<?php
require_once dirname(__DIR__, 2) . '/db.php';

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
        'SELECT u.id, u.role FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
if (!in_array($user['role'], ['club', 'coach', 'academy'], true)) {
    jsonOut(['error' => 'Forbidden — coach/club/academy only'], 403);
}

$body = json_decode(file_get_contents('php://input'), true) ?? [];

// ── Validate required fields ──────────────────────────────────────────────────
$title = trim((string)($body['title'] ?? ''));
if (!$title) jsonOut(['error' => 'title is required'], 400);
if (mb_strlen($title) > 255) $title = mb_substr($title, 0, 255);

$sessionDateRaw = trim((string)($body['session_date'] ?? ''));
$dateObj = DateTime::createFromFormat('Y-m-d', $sessionDateRaw);
if (!$dateObj) jsonOut(['error' => 'session_date must be YYYY-MM-DD'], 400);
$sessionDate = $dateObj->format('Y-m-d');

$durationMinutes = (int)($body['duration_minutes'] ?? 60);
if ($durationMinutes < 5 || $durationMinutes > 480)
    jsonOut(['error' => 'duration_minutes must be 5–480'], 400);

$allowedObjectives = ['fitness', 'football', 'recovery', 'assessment', 'mixed'];
$objective = in_array($body['objective'] ?? '', $allowedObjectives, true)
    ? (string)$body['objective'] : 'mixed';

$wellnessRequired = isset($body['wellness_required']) ? (int)(bool)$body['wellness_required'] : 1;
$rpeRequired      = isset($body['rpe_required'])      ? (int)(bool)$body['rpe_required']      : 1;
$description = isset($body['description']) ? substr(trim((string)$body['description']), 0, 1000) : null;
$notes       = isset($body['notes'])       ? substr(trim((string)$body['notes']), 0, 1000)       : null;

$exercises = is_array($body['exercises'] ?? null) ? $body['exercises'] : [];
$playerIds = is_array($body['player_ids'] ?? null) ? $body['player_ids'] : [];

if (empty($playerIds)) jsonOut(['error' => 'At least one player_id is required'], 400);

// ── IDs ───────────────────────────────────────────────────────────────────────
$planId    = bin2hex(random_bytes(16));
$sessionId = bin2hex(random_bytes(16));
$coachId   = (int)$user['id'];

// ── Transaction ───────────────────────────────────────────────────────────────
$pdo->beginTransaction();
try {
    // 1. training_plan
    $pdo->prepare(
        'INSERT INTO training_plans
         (id, plan_type, owner_type, club_id, coach_user_id, title, goal, status)
         VALUES (?, \'manual\', ?, ?, ?, ?, ?, \'published\')'
    )->execute([$planId, $user['role'], $coachId, $coachId, $title, $objective]);

    // 2. training_session
    $pdo->prepare(
        'INSERT INTO training_sessions
         (id, plan_id, club_id, coach_user_id, title, description,
          session_date, duration_minutes, objective, source, status,
          wellness_required, rpe_required)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, \'manual\', \'assigned\', ?, ?)'
    )->execute([
        $sessionId, $planId, $coachId, $coachId, $title, $description,
        $sessionDate, $durationMinutes, $objective,
        $wellnessRequired, $rpeRequired
    ]);

    // 3. Exercises
    $exStmt = $pdo->prepare(
        'INSERT INTO session_exercises
         (session_id, exercise_name, category, sets, reps,
          duration_seconds, rest_seconds, intensity,
          instructions, video_url, requires_pose_detection, assessment_type, sort_order)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    foreach ($exercises as $i => $ex) {
        $exName = trim((string)($ex['exercise_name'] ?? ''));
        if (!$exName) continue;
        $category  = in_array($ex['category'] ?? '', ['football','fitness','mobility','recovery','assessment'], true)
            ? (string)$ex['category'] : 'fitness';
        $intensity = in_array($ex['intensity'] ?? '', ['low','medium','high'], true)
            ? (string)$ex['intensity'] : 'medium';
        $exStmt->execute([
            $sessionId,
            substr($exName, 0, 255),
            $category,
            isset($ex['sets'])             ? (int)$ex['sets']             : null,
            isset($ex['reps'])             ? (int)$ex['reps']             : null,
            isset($ex['duration_seconds']) ? (int)$ex['duration_seconds'] : null,
            isset($ex['rest_seconds'])     ? (int)$ex['rest_seconds']     : null,
            $intensity,
            isset($ex['instructions'])     ? substr(trim((string)$ex['instructions']), 0, 1000) : null,
            isset($ex['video_url'])        ? substr(trim((string)$ex['video_url']), 0, 500)     : null,
            empty($ex['requires_pose_detection']) ? 0 : 1,
            isset($ex['assessment_type'])  ? (string)$ex['assessment_type'] : null,
            (int)$i,
        ]);
    }

    // 4. Assign players (security: must belong to this coach)
    $assigned = 0;
    $skipped  = 0;
    $cpStmt = $pdo->prepare(
        'SELECT linked_user_id FROM club_players WHERE id = ? AND user_id = ?'
    );
    foreach ($playerIds as $pid) {
        $pid = (string)$pid;
        $cpStmt->execute([$pid, $coachId]);
        $cp = $cpStmt->fetch();
        if (!$cp || !$cp['linked_user_id']) { $skipped++; continue; }
        $pdo->prepare(
            'INSERT IGNORE INTO session_players
             (session_id, club_id, player_user_id, linked_player_id, status)
             VALUES (?, ?, ?, ?, \'assigned\')'
        )->execute([$sessionId, $coachId, (int)$cp['linked_user_id'], $pid]);
        $assigned++;
    }

    $pdo->commit();
} catch (Exception $e) {
    $pdo->rollBack();
    jsonOut(['error' => 'Failed to create plan: ' . $e->getMessage()], 500);
}

jsonOut([
    'success'        => true,
    'plan_id'        => $planId,
    'session_id'     => $sessionId,
    'assigned_count' => $assigned,
    'skipped_count'  => $skipped,
]);
