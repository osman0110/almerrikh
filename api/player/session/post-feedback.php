<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/notifications.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonError('Method not allowed', 405);

function jsonOut(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function bearerToken(): string {
    $auth = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? $_SERVER['Authorization'] ?? '';
    if (!$auth && function_exists('apache_request_headers')) {
        $h = apache_request_headers();
        $auth = $h['Authorization'] ?? $h['authorization'] ?? '';
    }
    if (stripos($auth, 'Bearer ') === 0) return trim(substr($auth, 7));
    return trim($auth);
}

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.role, u.linked_player_id, u.club_user_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);
$body = json_decode(file_get_contents('php://input'), true) ?? [];

// Required
if (!isset($body['post_rpe'])) jsonOut(['error' => 'post_rpe is required'], 400);
$postRpe = (int)$body['post_rpe'];
if ($postRpe < 0 || $postRpe > 10) jsonOut(['error' => 'post_rpe must be 0–10'], 400);

$sessionId    = isset($body['session_id'])    ? (string)$body['session_id']    : null;
$assessmentId = isset($body['assessment_id']) ? (string)$body['assessment_id'] : null;

if (!$sessionId && !$assessmentId) jsonOut(['error' => 'session_id or assessment_id is required'], 400);

// Optional fields
$painReported = isset($body['pain_reported']) ? (int)(bool)$body['pain_reported'] : 0;

$allowedDiff = ['easy', 'good', 'hard', 'too_hard'];
$difficulty  = isset($body['difficulty']) && in_array($body['difficulty'], $allowedDiff, true)
    ? $body['difficulty'] : null;

$moodAfter = null;
if (isset($body['mood_after'])) {
    $moodAfter = (int)$body['mood_after'];
    if ($moodAfter < 1 || $moodAfter > 5) jsonOut(['error' => 'mood_after must be 1–5'], 400);
}

$notes = isset($body['notes']) ? substr((string)$body['notes'], 0, 500) : null;

// Partial participation — did the player complete the full planned session?
$completedFullSession = isset($body['completed_full_session'])
    ? (int)(bool)$body['completed_full_session'] : 1;

$incompleteReason = null;
if (!$completedFullSession) {
    $incompleteReason = isset($body['incomplete_reason'])
        ? substr((string)$body['incomplete_reason'], 0, 255) : null;
    if (!$incompleteReason) jsonOut(['error' => 'incomplete_reason is required when the session was not completed in full'], 400);
}

// duration_minutes for training_load calculation (optional, default from session)
$durationMinutes = 0;
if (isset($body['duration_minutes'])) {
    $durationMinutes = (int)$body['duration_minutes'];
    if ($durationMinutes < 0 || $durationMinutes > 480)
        jsonOut(['error' => 'duration_minutes must be 0–480'], 400);
}

// If not provided, try to read from training_sessions
if (!$durationMinutes && $sessionId) {
    $ds = $pdo->prepare('SELECT duration_minutes FROM training_sessions WHERE id = ?');
    $ds->execute([$sessionId]);
    $dsRow = $ds->fetch();
    if ($dsRow) $durationMinutes = (int)$dsRow['duration_minutes'];
}

// actual_duration_minutes — how long the player actually participated.
// When the session wasn't completed in full, this (not the planned
// duration read above) is what the Session Load calculation should use.
$actualDuration = null;
if (isset($body['actual_duration_minutes'])) {
    $actualDuration = (int)$body['actual_duration_minutes'];
    if ($actualDuration < 0 || $actualDuration > 480)
        jsonOut(['error' => 'actual_duration_minutes must be 0–480'], 400);
}
$effectiveDuration = (!$completedFullSession && $actualDuration !== null) ? $actualDuration : $durationMinutes;

// Scoping from token — never trust client-supplied IDs
$linkedPlayerId = $user['linked_player_id'] ?? null;
$clubId         = $user['club_user_id']     ?? null;

// Validate session is assigned to this player
if ($sessionId) {
    $sp = $pdo->prepare(
        'SELECT id, status FROM session_players WHERE session_id = ? AND player_user_id = ?'
    );
    $sp->execute([$sessionId, $user['id']]);
    $spRow = $sp->fetch();
    if (!$spRow) jsonOut(['error' => 'Session not assigned to you'], 403);
    if ($spRow['status'] === 'completed') jsonOut(['error' => 'Post-feedback already submitted for this session'], 400);
}

// 1. Save to post_training_feedback
$stmt = $pdo->prepare(
    'INSERT INTO post_training_feedback
     (session_id, assessment_id, club_id, player_user_id, linked_player_id,
      post_rpe, pain_reported, difficulty, mood_after, notes,
      completed_full_session, actual_duration_minutes, incomplete_reason)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
);
$stmt->execute([
    $sessionId, $assessmentId, $clubId, $user['id'], $linkedPlayerId,
    $postRpe, $painReported, $difficulty, $moodAfter, $notes,
    $completedFullSession, $actualDuration, $incompleteReason
]);
$feedbackId = (int)$pdo->lastInsertId();

// 2. Also save to player_rpe for monitoring dashboard + ACWR calculations
// Uses effectiveDuration (actual participation time for a partial session)
// so a shortened session doesn't inflate the player's training load.
$trainingLoad = $effectiveDuration > 0 ? $postRpe * $effectiveDuration : 0;
$pdo->prepare(
    'INSERT INTO player_rpe
     (user_id, linked_player_id, club_id,
      session_id, training_session_id, assessment_id,
      rpe_type, rpe_score, duration_minutes, training_load,
      pain_reported, difficulty, mood_after, notes,
      completed_full_session, actual_duration_minutes, incomplete_reason)
     VALUES (?, ?, ?, ?, ?, ?, \'post\', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
)->execute([
    $user['id'], $linkedPlayerId, $clubId,
    $sessionId, $sessionId, $assessmentId,
    $postRpe, $durationMinutes, $trainingLoad,
    $painReported, $difficulty, $moodAfter, $notes,
    $completedFullSession, $actualDuration, $incompleteReason
]);

// 3. Transition session_players: started (or any non-completed) → completed
if ($sessionId) {
    $pdo->prepare(
        'UPDATE session_players
         SET status = \'completed\', completed_at = NOW()
         WHERE session_id = ? AND player_user_id = ? AND status NOT IN (\'completed\',\'missed\')'
    )->execute([$sessionId, $user['id']]);
}

$response = ['success' => true, 'id' => $feedbackId, 'training_load' => $trainingLoad];

if ($postRpe >= 8)  $response['coach_alert'] = 'high_rpe';
if ($painReported)  $response['coach_alert'] = 'pain_reported';

// Alert the physical coach when post-session feedback flags a concern.
// The feedback/RPE rows above are already saved — a notification failure
// here must never be reported back to the player as a save failure.
if (!empty($response['coach_alert']) && $clubId) {
    try {
        notifyClubRole(
            $pdo, (int)$clubId, 'coach', 'post_session_alert',
            ['pain_reported' => $painReported, 'rpe' => $postRpe],
            array_filter(['linked_route' => $sessionId ? '/session/' . $sessionId : null])
        );
    } catch (Throwable $e) {
        error_log('post-feedback.php: post_session_alert notification failed: ' . $e->getMessage());
    }
}

jsonOut($response);
