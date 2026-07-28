<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/club_auth.php';
require_once dirname(__DIR__, 2) . '/includes/audit_log.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/FitnessConfig.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/SchemaInspector.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/RpeIdentity.php';

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
$body = json_decode(file_get_contents('php://input'), true) ?? [];

// A coach (any non-player/parent role) may log RPE on behalf of a roster
// player — most club players never sign in themselves.
$isCoach = !in_array($user['role'], ['player', 'parent'], true);
$recordedBy = 'self';
$coachTargetPlayerId = null;

if ($isCoach) {
    $coachTargetPlayerId = trim((string)($body['player_id'] ?? ''));
    if (!$coachTargetPlayerId) jsonOut(['error' => 'player_id is required'], 400);
    // Scoped by club_id — a roster player belongs to the whole club, shared
    // across every coach/staff member, not to whichever coach is logged in.
    $ctx = requireClubPermission($pdo, $user, 'fitness.rpe.create_for_player');
    $pStmt = $pdo->prepare(
        'SELECT id FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1 LIMIT 1'
    );
    $pStmt->execute([$coachTargetPlayerId, $ctx['club_id']]);
    if (!$pStmt->fetch()) jsonOut(['error' => 'Player not found in your roster'], 404);
    $recordedBy = 'coach';
} elseif ($user['role'] !== 'player') {
    jsonOut(['error' => 'Forbidden'], 403);
} elseif (!clubStaffCan('player', 'fitness.rpe.create_for_self')) {
    jsonOut(['error' => 'Forbidden'], 403);
}

if (!isset($body['rpe_score']))       jsonOut(['error' => 'rpe_score is required'], 400);
if (!isset($body['duration_minutes'])) jsonOut(['error' => 'duration_minutes is required'], 400);

// RPE accepts decimals (e.g. 5.5) per the RPE APR Rwanda reference sheet.
$rpe      = (float)$body['rpe_score'];
$duration = (int)$body['duration_minutes'];

if ($rpe < 1 || $rpe > 10)          jsonOut(['error' => 'rpe_score must be 1–10'], 400);
if ($duration < 1 || $duration > 480) jsonOut(['error' => 'duration_minutes must be 1–480'], 400);

$notes       = isset($body['notes']) ? substr((string)$body['notes'], 0, 500) : null;
$sessionType = isset($body['session_type']) ? substr((string)$body['session_type'], 0, 50) : null;
$assessmentId = isset($body['assessment_id']) ? (string)$body['assessment_id'] : null;

// Accept session_id (preferred) OR training_session_id (backwards compat)
$sessionId = null;
if (!empty($body['session_id']))             $sessionId = (string)$body['session_id'];
elseif (!empty($body['training_session_id'])) $sessionId = (string)$body['training_session_id'];

$allowedRpeTypes = ['pre', 'post'];
$rpeType = isset($body['rpe_type']) && in_array($body['rpe_type'], $allowedRpeTypes, true)
    ? $body['rpe_type'] : 'post';

$painReported = isset($body['pain_reported']) ? (int)(bool)$body['pain_reported'] : 0;

$allowedDiff = ['easy', 'good', 'hard', 'too_hard'];
$difficulty  = isset($body['difficulty']) && in_array($body['difficulty'], $allowedDiff, true)
    ? $body['difficulty'] : null;

$moodAfter = null;
if (isset($body['mood_after'])) {
    $moodAfter = (int)$body['mood_after'];
    if ($moodAfter < 1 || $moodAfter > 5) jsonOut(['error' => 'mood_after must be 1–5'], 400);
}

// Partial participation — did the player complete the full planned session?
$completedFullSession = isset($body['completed_full_session'])
    ? (int)(bool)$body['completed_full_session'] : 1;

$actualDuration = null;
if (isset($body['actual_duration_minutes'])) {
    $actualDuration = (int)$body['actual_duration_minutes'];
    if ($actualDuration < 0 || $actualDuration > 480)
        jsonOut(['error' => 'actual_duration_minutes must be 0–480'], 400);
}

$incompleteReason = null;
if (!$completedFullSession) {
    $incompleteReason = isset($body['incomplete_reason'])
        ? substr((string)$body['incomplete_reason'], 0, 255) : null;
    if (!$incompleteReason) jsonOut(['error' => 'incomplete_reason is required when the session was not completed in full'], 400);
    if ($actualDuration === null) {
        jsonOut(['error' => 'actual_duration_minutes is required for partial participation'], 400);
    }
}

// Session Load uses the player's ACTUAL participation time when the session
// wasn't completed in full — using the planned/reported duration for a
// partial session would overstate their training load.
$effectiveDuration = (!$completedFullSession && $actualDuration !== null) ? $actualDuration : $duration;
$load = $rpe * $effectiveDuration;

// Scoping — never trust client-supplied IDs for the self-report path;
// for the coach path, the roster ownership check above already verified it.
$linkedPlayerId = $isCoach ? $coachTargetPlayerId : ($user['linked_player_id'] ?? null);
$clubId         = $isCoach ? $ctx['club_id']      : ($user['club_user_id']     ?? null);

$idempotencyKey = trim((string)(
    $_SERVER['HTTP_IDEMPOTENCY_KEY']
    ?? $body['idempotency_key']
    ?? ''
));
if (strlen($idempotencyKey) > 100) jsonOut(['error' => 'idempotency_key is too long'], 400);

$activityDate = isset($body['activity_date'])
    ? (string)$body['activity_date']
    : FitnessConfig::today();
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $activityDate)) {
    jsonOut(['error' => 'activity_date must be YYYY-MM-DD'], 400);
}
$externalReference = substr(trim((string)($body['external_reference'] ?? 'default')), 0, 80);
$logicalKey = RpeIdentity::logicalKey(
    $linkedPlayerId,
    (int)$user['id'],
    $sessionId,
    $rpeType,
    $activityDate,
    $sessionType,
    $externalReference
);

if ($idempotencyKey !== '' && SchemaInspector::hasColumn($pdo, 'player_rpe', 'idempotency_key')) {
    $idemStmt = $pdo->prepare(
        'SELECT id, training_load FROM player_rpe
         WHERE club_id <=> ? AND idempotency_key = ? LIMIT 1'
    );
    $idemStmt->execute([$clubId, $idempotencyKey]);
    $existingIdempotent = $idemStmt->fetch(PDO::FETCH_ASSOC);
    if ($existingIdempotent) {
        jsonOut([
            'success' => true,
            'id' => (int)$existingIdempotent['id'],
            'training_load' => (float)$existingIdempotent['training_load'],
            'idempotent_replay' => true,
        ]);
    }
}

// One-time submission per session: a player's own self-report for a real
// session locks after the first submission — a coach may still log again to
// correct a mistake, but the player's own RpeScreen can't be resubmitted.
if (!$isCoach && $sessionId) {
    $selfActiveFilter = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
        ? ' AND is_active_record = 1'
        : '';
    $dupStmt = $pdo->prepare(
        'SELECT id FROM player_rpe
         WHERE user_id = ? AND session_id = ? AND rpe_type = ?' . $selfActiveFilter . '
         LIMIT 1'
    );
    $dupStmt->execute([$user['id'], $sessionId, $rpeType]);
    if ($dupStmt->fetchColumn()) {
        jsonOut(['error' => 'already_submitted', 'message' => 'RPE already submitted for this session'], 409);
    }
}

$existingLogical = null;
if (SchemaInspector::hasColumn($pdo, 'player_rpe', 'logical_key')) {
    $logicalStmt = $pdo->prepare(
        'SELECT * FROM player_rpe
         WHERE logical_key = ? AND is_active_record = 1 LIMIT 1'
    );
    $logicalStmt->execute([$logicalKey]);
    $existingLogical = $logicalStmt->fetch(PDO::FETCH_ASSOC) ?: null;
}

if ($existingLogical) {
    if (!$isCoach) {
        jsonOut(['error' => 'already_submitted', 'message' => 'RPE already submitted for this activity'], 409);
    }
    $reason = trim(substr((string)($body['reason'] ?? ''), 0, 500));
    if ($reason === '') jsonOut(['error' => 'reason is required when updating RPE'], 400);

    $pdo->beginTransaction();
    try {
        $pdo->prepare(
            'INSERT INTO player_rpe_revisions
             (player_rpe_id, revision_number, old_values_json, changed_by_user_id, reason)
             VALUES (?, ?, ?, ?, ?)'
        )->execute([
            $existingLogical['id'],
            ((int)($existingLogical['revision_number'] ?? 1)) + 1,
            json_encode($existingLogical, JSON_UNESCAPED_UNICODE),
            (int)$user['id'],
            $reason,
        ]);
        $pdo->prepare(
            'UPDATE player_rpe SET
             rpe_score = ?, duration_minutes = ?, training_load = ?,
             pain_reported = ?, difficulty = ?, mood_after = ?, notes = ?,
             completed_full_session = ?, actual_duration_minutes = ?, incomplete_reason = ?,
             idempotency_key = ?, revision_number = revision_number + 1
             WHERE id = ?'
        )->execute([
            $rpe, $duration, $load,
            $painReported, $difficulty, $moodAfter, $notes,
            $completedFullSession, $actualDuration, $incompleteReason,
            $idempotencyKey !== '' ? $idempotencyKey : null,
            $existingLogical['id'],
        ]);
        logFitnessAudit(
            $pdo,
            'player_rpe',
            (string)$existingLogical['id'],
            'rpe.updated',
            (int)$user['id'],
            $clubId !== null ? (int)$clubId : null,
            $linkedPlayerId,
            $existingLogical,
            ['rpe_score' => $rpe, 'duration_minutes' => $duration, 'training_load' => $load],
            $reason,
            $idempotencyKey ?: null
        );
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        jsonOut(['error' => 'Unable to update RPE'], 500);
    }
    jsonOut([
        'success' => true,
        'id' => (int)$existingLogical['id'],
        'training_load' => $load,
        'updated' => true,
    ]);
}

$stmt = $pdo->prepare(
    'INSERT INTO player_rpe
     (user_id, linked_player_id, club_id,
      session_id, training_session_id, assessment_id,
      session_type, rpe_type, rpe_score, duration_minutes, training_load,
      pain_reported, difficulty, mood_after, notes,
      completed_full_session, actual_duration_minutes, incomplete_reason, recorded_by,
      logical_key, idempotency_key, source_type, revision_number, is_active_record)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)'
);
$stmt->execute([
    $user['id'], $linkedPlayerId, $clubId,
    $sessionId, $sessionId, $assessmentId,   // store in both columns
    $sessionType, $rpeType, $rpe, $duration, $load,
    $painReported, $difficulty, $moodAfter, $notes,
    $completedFullSession, $actualDuration, $incompleteReason, $recordedBy,
    $logicalKey, $idempotencyKey !== '' ? $idempotencyKey : null, $rpeType,
]);
$id = (int)$pdo->lastInsertId();

logFitnessAudit(
    $pdo,
    'player_rpe',
    (string)$id,
    'rpe.created',
    (int)$user['id'],
    $clubId !== null ? (int)$clubId : null,
    $linkedPlayerId,
    null,
    ['rpe_score' => $rpe, 'duration_minutes' => $duration, 'training_load' => $load],
    null,
    $idempotencyKey ?: null
);

// NOTE: session_players completion is handled exclusively by post-feedback.php
// This endpoint is for standalone RPE logging (monitoring dashboard, ACWR)

jsonOut(['success' => true, 'id' => $id, 'training_load' => $load]);
