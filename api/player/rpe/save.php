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

function resolvePlayerParticipationMinutes(
    PDO $pdo,
    string $sessionId,
    int $userId,
    ?string $linkedPlayerId
): ?int {
    if ($linkedPlayerId && SchemaInspector::hasTable($pdo, 'match_participations')) {
        $stmt = $pdo->prepare(
            'SELECT minutes_played FROM match_participations
             WHERE match_id = ? AND player_id = ? LIMIT 1'
        );
        $stmt->execute([$sessionId, $linkedPlayerId]);
        $minutes = $stmt->fetchColumn();
        if ($minutes !== false && (int)$minutes >= 0) return (int)$minutes;
    }

    if ($linkedPlayerId && SchemaInspector::hasTable($pdo, 'matches')) {
        $stmt = $pdo->prepare('SELECT player_minutes FROM matches WHERE id = ? LIMIT 1');
        $stmt->execute([$sessionId]);
        $rawMinutes = $stmt->fetchColumn();
        if ($rawMinutes !== false && $rawMinutes !== null) {
            $minutesByPlayer = json_decode((string)$rawMinutes, true);
            if (is_array($minutesByPlayer) && isset($minutesByPlayer[$linkedPlayerId])) {
                return max(0, (int)$minutesByPlayer[$linkedPlayerId]);
            }
        }
    }

    if (SchemaInspector::hasTable($pdo, 'session_players')) {
        $stmt = $pdo->prepare(
            'SELECT started_at, completed_at FROM session_players
             WHERE session_id = ? AND player_user_id = ? LIMIT 1'
        );
        $stmt->execute([$sessionId, $userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row && $row['started_at']) {
            $end = $row['completed_at'] ?: date('Y-m-d H:i:s');
            $seconds = strtotime($end) - strtotime($row['started_at']);
            if ($seconds > 0) return min(480, max(1, (int)round($seconds / 60)));
        }
    }

    // A full-participation session starts with its planned duration. The coach
    // can replace it with the player's actual exposure from the load report.
    if (SchemaInspector::hasTable($pdo, 'club_sessions')) {
        $stmt = $pdo->prepare('SELECT duration_min FROM club_sessions WHERE id = ? LIMIT 1');
        $stmt->execute([$sessionId]);
        $minutes = $stmt->fetchColumn();
        if ($minutes !== false && (int)$minutes > 0) return (int)$minutes;
    }
    if (SchemaInspector::hasTable($pdo, 'training_sessions')) {
        $stmt = $pdo->prepare('SELECT duration_minutes FROM training_sessions WHERE id = ? LIMIT 1');
        $stmt->execute([$sessionId]);
        $minutes = $stmt->fetchColumn();
        if ($minutes !== false && (int)$minutes > 0) return (int)$minutes;
    }

    return null;
}

$user = getAuthUser($pdo);
$body = $GLOBALS['sessionRpeRequestBody']
    ?? json_decode(file_get_contents('php://input'), true)
    ?? [];

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

if (!isset($body['rpe_score'])) jsonOut(['error' => 'rpe_score is required'], 400);

$rpe = (float)$body['rpe_score'];
if ($rpe < 0 || $rpe > 10 || floor($rpe) !== $rpe) {
    jsonOut(['error' => 'rpe_score must be an integer from 0 to 10'], 400);
}

$notes = null;
$sessionType = isset($body['session_type']) ? substr((string)$body['session_type'], 0, 50) : null;
$assessmentId = isset($body['assessment_id']) ? (string)$body['assessment_id'] : null;

// Accept session_id (preferred) OR training_session_id (backwards compat)
$sessionId = null;
if (!empty($body['session_id']))             $sessionId = (string)$body['session_id'];
elseif (!empty($body['training_session_id'])) $sessionId = (string)$body['training_session_id'];

// Scoping — never trust client-supplied IDs for the self-report path;
// for the coach path, the roster ownership check above already verified it.
$linkedPlayerId = $isCoach ? $coachTargetPlayerId : ($user['linked_player_id'] ?? null);
$clubId         = $isCoach ? $ctx['club_id']      : ($user['club_user_id']     ?? null);

if (!$isCoach && !$sessionId) {
    jsonOut(['error' => 'session_id is required for Session RPE'], 400);
}

$allowedRpeTypes = ['pre', 'post'];
$rpeType = isset($body['rpe_type']) && in_array($body['rpe_type'], $allowedRpeTypes, true)
    ? $body['rpe_type'] : 'post';

// Hooper/wellness answers are intentionally excluded from Session RPE.
$painReported = 0;
$difficulty = null;
$moodAfter = null;
$completedFullSession = 1;

$submittedDuration = isset($body['actual_duration_minutes'])
    ? (int)$body['actual_duration_minutes']
    : (isset($body['duration_minutes']) ? (int)$body['duration_minutes'] : null);
if ($submittedDuration !== null && ($submittedDuration < 0 || $submittedDuration > 480)) {
    jsonOut(['error' => 'actual_duration_minutes must be 0–480'], 400);
}

$actualDuration = $isCoach
    ? $submittedDuration
    : resolvePlayerParticipationMinutes(
        $pdo,
        (string)$sessionId,
        (int)$user['id'],
        $linkedPlayerId ? (string)$linkedPlayerId : null
    );
if ($actualDuration === null) {
    jsonOut([
        'error' => 'participation_minutes_missing',
        'message' => 'Actual participation minutes must be recorded by the coach first',
    ], 409);
}
$duration = $actualDuration;

$incompleteReason = null;

// Session Load always uses the player's actual participation exposure.
$effectiveDuration = $actualDuration;
$load = $rpe * $effectiveDuration;

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

$existingLogical = null;
if (SchemaInspector::hasColumn($pdo, 'player_rpe', 'logical_key')) {
    $logicalStmt = $pdo->prepare(
        'SELECT *, TIMESTAMPDIFF(MINUTE, submitted_at, NOW()) AS minutes_since_submission
         FROM player_rpe
         WHERE logical_key = ? AND is_active_record = 1 LIMIT 1'
    );
    $logicalStmt->execute([$logicalKey]);
    $existingLogical = $logicalStmt->fetch(PDO::FETCH_ASSOC) ?: null;
}

if ($existingLogical) {
    if ($isCoach) {
        requireClubPermission($pdo, $user, 'fitness.rpe.update');
    }
    if (!$isCoach) {
        $minutesSinceSubmission = max(0, (int)$existingLogical['minutes_since_submission']);
        if ($minutesSinceSubmission > FitnessConfig::RPE_PLAYER_EDIT_WINDOW_MINUTES) {
            jsonOut([
                'error' => 'edit_window_expired',
                'message' => 'The 50-minute RPE edit window has expired',
            ], 409);
        }
        // A player's correction changes only the perceived effort. Any
        // player-specific duration already approved by the coach stays fixed.
        $actualDuration = $existingLogical['actual_duration_minutes']
            ?? $existingLogical['duration_minutes'];
        $duration = (int)$actualDuration;
        $effectiveDuration = $duration;
        $load = $rpe * $effectiveDuration;
    }
    $reason = trim(substr((string)($body['reason'] ?? ''), 0, 500));
    if ($isCoach && $reason === '') {
        jsonOut(['error' => 'reason is required when approving a new RPE'], 400);
    }
    if (!$isCoach) $reason = 'Player correction within 50-minute window';

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
             idempotency_key = ?, revision_number = revision_number + 1,
             last_edited_at = NOW(), last_edited_by_user_id = ?
             WHERE id = ?'
        )->execute([
            $rpe, $duration, $load,
            $painReported, $difficulty, $moodAfter, $notes,
            $completedFullSession, $actualDuration, $incompleteReason,
            $idempotencyKey !== '' ? $idempotencyKey : null,
            (int)$user['id'],
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
    if (!$isCoach && $sessionId && SchemaInspector::hasTable($pdo, 'session_players')) {
        $pdo->prepare(
            "UPDATE session_players
             SET status = 'completed', completed_at = COALESCE(completed_at, NOW())
             WHERE session_id = ? AND player_user_id = ? AND status <> 'missed'"
        )->execute([$sessionId, $user['id']]);
    }
    jsonOut([
        'success' => true,
        'id' => (int)$existingLogical['id'],
        'training_load' => $load,
        'updated' => true,
        'record_status' => 'edited',
        'edit_window_minutes' => FitnessConfig::RPE_PLAYER_EDIT_WINDOW_MINUTES,
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

if (!$isCoach && $sessionId && SchemaInspector::hasTable($pdo, 'session_players')) {
    $pdo->prepare(
        "UPDATE session_players
         SET status = 'completed', completed_at = COALESCE(completed_at, NOW())
         WHERE session_id = ? AND player_user_id = ? AND status <> 'missed'"
    )->execute([$sessionId, $user['id']]);
}

jsonOut([
    'success' => true,
    'id' => $id,
    'training_load' => $load,
    'record_status' => 'original',
    'edit_window_minutes' => FitnessConfig::RPE_PLAYER_EDIT_WINDOW_MINUTES,
]);
