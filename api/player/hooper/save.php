<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/audit_log.php';
require_once dirname(__DIR__, 2) . '/includes/club_auth.php';

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

// A coach (any non-player/parent role) may log a Hooper check-in on behalf
// of a roster player — most club players never sign in themselves.
$isCoach = !in_array($user['role'], ['player', 'parent'], true);
$recordedBy = 'self';
$coachTargetPlayerId = null;

if ($isCoach) {
    $coachTargetPlayerId = trim((string)($body['player_id'] ?? ''));
    if (!$coachTargetPlayerId) jsonOut(['error' => 'player_id is required'], 400);
    // Scoped by club_id — a roster player belongs to the whole club, shared
    // across every coach/staff member, not to whichever coach is logged in.
    $ctx = requireClubPermission($pdo, $user, 'players.read');
    $pStmt = $pdo->prepare(
        'SELECT id FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1 LIMIT 1'
    );
    $pStmt->execute([$coachTargetPlayerId, $ctx['club_id']]);
    if (!$pStmt->fetch()) jsonOut(['error' => 'Player not found in your roster'], 404);
    $recordedBy = 'coach';
} elseif ($user['role'] !== 'player') {
    jsonOut(['error' => 'Forbidden'], 403);
}

// Validate Hooper fields 1–7
$fields = ['sleep_quality', 'fatigue', 'stress', 'muscle_soreness'];
foreach ($fields as $f) {
    if (!isset($body[$f])) jsonOut(['error' => "$f is required"], 400);
    $v = (int)$body[$f];
    if ($v < 1 || $v > 7) jsonOut(['error' => "$f must be 1–7"], 400);
}

$sleepQ   = (int)$body['sleep_quality'];
$fatigue  = (int)$body['fatigue'];
$stress   = (int)$body['stress'];
$soreness = (int)$body['muscle_soreness'];
$hooper   = $sleepQ + $fatigue + $stress + $soreness;

$sleepHours = isset($body['sleep_hours']) ? (float)$body['sleep_hours'] : null;
if ($sleepHours !== null && ($sleepHours < 0 || $sleepHours > 24))
    jsonOut(['error' => 'sleep_hours must be 0–24'], 400);

// pre_rpe 1–10 (optional)
$preRpe = null;
if (isset($body['pre_rpe'])) {
    $preRpe = (int)$body['pre_rpe'];
    if ($preRpe < 1 || $preRpe > 10) jsonOut(['error' => 'pre_rpe must be 1–10'], 400);
}

$painToday    = isset($body['pain_today']) ? (int)(bool)$body['pain_today'] : 0;
$painLocation = ($painToday && isset($body['pain_location']))
    ? substr((string)$body['pain_location'], 0, 100) : null;

// mood 1–7 (optional) — same scale as the other Hooper items
$mood = null;
if (isset($body['mood'])) {
    $mood = (int)$body['mood'];
    if ($mood < 1 || $mood > 7) jsonOut(['error' => 'mood must be 1–7'], 400);
}

$notes        = isset($body['notes']) ? substr((string)$body['notes'], 0, 500) : null;
$assessmentId = isset($body['assessment_id']) ? (string)$body['assessment_id'] : null;

// Accept session_id (preferred for new flow) OR training_session_id (backwards compat)
$sessionId = null;
if (!empty($body['session_id']))            $sessionId = (string)$body['session_id'];
elseif (!empty($body['training_session_id'])) $sessionId = (string)$body['training_session_id'];

// Scoping — never trust client-supplied IDs for the self-report path;
// for the coach path, the roster ownership check above already verified it.
$linkedPlayerId = $isCoach ? $coachTargetPlayerId : ($user['linked_player_id'] ?? null);
$clubId         = $isCoach ? $ctx['club_id']      : ($user['club_user_id']     ?? null);

// Duplicate prevention: one Hooper entry per player per session (if the
// check-in is tied to a session), otherwise one per calendar day.
// The coach path dedupes on linked_player_id (the roster player), never on
// user_id — user_id there is the coach's own account, shared across every
// player they log for, so keying on it would collide across players. Coaches
// may still correct a mistake (update in place); a player's own self-report
// for a real session is a ONE-TIME submission — once in, it's locked, so a
// resubmit is rejected outright instead of silently overwriting it.
if ($isCoach) {
    if ($sessionId) {
        $dupStmt = $pdo->prepare(
            'SELECT id FROM player_hooper_index WHERE linked_player_id = ? AND session_id = ? LIMIT 1'
        );
        $dupStmt->execute([$linkedPlayerId, $sessionId]);
    } else {
        $dupStmt = $pdo->prepare(
            'SELECT id FROM player_hooper_index
             WHERE linked_player_id = ? AND session_id IS NULL AND DATE(submitted_at) = CURDATE()
             LIMIT 1'
        );
        $dupStmt->execute([$linkedPlayerId]);
    }
} elseif ($sessionId) {
    $dupStmt = $pdo->prepare(
        'SELECT id FROM player_hooper_index WHERE user_id = ? AND session_id = ? LIMIT 1'
    );
    $dupStmt->execute([$user['id'], $sessionId]);
    if ($dupStmt->fetchColumn()) {
        jsonOut(['error' => 'already_submitted', 'message' => 'Hooper already submitted for this session'], 409);
    }
    $existingId = null;
} else {
    $dupStmt = $pdo->prepare(
        'SELECT id FROM player_hooper_index
         WHERE user_id = ? AND session_id IS NULL AND DATE(submitted_at) = CURDATE()
         LIMIT 1'
    );
    $dupStmt->execute([$user['id']]);
}
$existingId ??= $dupStmt->fetchColumn();

if ($existingId) {
    $prevStmt = $pdo->prepare('SELECT pain_today, pain_location FROM player_hooper_index WHERE id = ?');
    $prevStmt->execute([$existingId]);
    $prevRow = $prevStmt->fetch(PDO::FETCH_ASSOC) ?: null;

    $stmt = $pdo->prepare(
        'UPDATE player_hooper_index
         SET sleep_quality = ?, fatigue = ?, stress = ?, muscle_soreness = ?, sleep_hours = ?,
             hooper_score = ?, pre_rpe = ?, pain_today = ?, pain_location = ?, mood = ?,
             notes = ?, assessment_id = ?, recorded_by = ?, submitted_at = NOW()
         WHERE id = ?'
    );
    $stmt->execute([
        $sleepQ, $fatigue, $stress, $soreness, $sleepHours,
        $hooper, $preRpe, $painToday, $painLocation, $mood,
        $notes, $assessmentId, $recordedBy,
        $existingId,
    ]);
    $id = (int)$existingId;

    logAuditDiff($pdo, 'player_hooper_index', (string)$existingId, $prevRow, [
        'pain_today'    => $painToday,
        'pain_location' => $painLocation,
    ], (int)$user['id']);
} else {
    $stmt = $pdo->prepare(
        'INSERT INTO player_hooper_index
         (user_id, linked_player_id, club_id,
          session_id, training_session_id, assessment_id,
          sleep_quality, fatigue, stress, muscle_soreness, sleep_hours,
          hooper_score, pre_rpe, pain_today, pain_location, mood, notes, recorded_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $stmt->execute([
        $user['id'], $linkedPlayerId, $clubId,
        $sessionId, $sessionId, $assessmentId,   // store in both columns
        $sleepQ, $fatigue, $stress, $soreness, $sleepHours,
        $hooper, $preRpe, $painToday, $painLocation, $mood, $notes, $recordedBy
    ]);
    $id = (int)$pdo->lastInsertId();
}

$status = $hooper <= 10 ? 'normal' : ($hooper <= 16 ? 'moderate' : 'high_risk');

// Readiness alert — notify coach/doctor/performance_manager staff on a new
// (not re-edited) high-risk Hooper score. Best-effort: never let a
// notification failure break the actual Hooper save this endpoint exists for.
if ($status === 'high_risk' && !$existingId && $linkedPlayerId) {
    try {
        require_once dirname(__DIR__, 2) . '/includes/notifications.php';
        $clubRowStmt = $pdo->prepare('SELECT id FROM clubs WHERE owner_user_id = ?');
        $clubRowStmt->execute([$clubId]);
        $formalClubId = $clubRowStmt->fetchColumn();

        if ($formalClubId) {
            $nameStmt = $pdo->prepare('SELECT name FROM club_players WHERE id = ?');
            $nameStmt->execute([$linkedPlayerId]);
            $playerName = $nameStmt->fetchColumn() ?: '';

            $staffStmt = $pdo->prepare(
                "SELECT user_id FROM club_staff
                 WHERE club_id = ? AND status = 'active'
                   AND staff_role IN ('coach', 'doctor', 'performance_manager')"
            );
            $staffStmt->execute([$formalClubId]);
            foreach ($staffStmt->fetchAll(PDO::FETCH_COLUMN) as $staffUserId) {
                createNotification(
                    $pdo, (int)$formalClubId, (int)$staffUserId,
                    'readiness_alert',
                    'جاهزية منخفضة: ' . $playerName,
                    "مؤشر Hooper: $hooper",
                    '/club/players/' . $linkedPlayerId
                );
            }
        }
    } catch (Throwable $e) {
        // Notification is a nice-to-have here — swallow and move on.
    }
}

// Transition session_players: assigned → pre_checked
if ($sessionId) {
    $pdo->prepare(
        'UPDATE session_players
         SET status = \'pre_checked\', pre_check_completed_at = NOW()
         WHERE session_id = ? AND player_user_id = ? AND status = \'assigned\''
    )->execute([$sessionId, $user['id']]);
}

jsonOut(['success' => true, 'id' => $id, 'hooper_score' => $hooper, 'status' => $status]);
