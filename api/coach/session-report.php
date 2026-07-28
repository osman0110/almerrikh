<?php
require_once dirname(__DIR__, 1) . '/db.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') jsonError('Method not allowed', 405);

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
    jsonOut(['error' => 'Forbidden'], 403);
}

$sessionId = trim($_GET['id'] ?? '');
if (!$sessionId) jsonOut(['error' => 'id is required'], 400);

// Security: session must belong to this coach
$sess = $pdo->prepare(
    'SELECT id, plan_id, title, description, session_date, duration_minutes,
            objective, source, status, wellness_required, rpe_required, created_at
     FROM training_sessions WHERE id = ? AND coach_user_id = ?'
);
$sess->execute([$sessionId, $user['id']]);
$session = $sess->fetch();
if (!$session) jsonOut(['error' => 'Session not found or access denied'], 404);

$session['duration_minutes']  = (int)$session['duration_minutes'];
$session['wellness_required'] = (bool)$session['wellness_required'];
$session['rpe_required']      = (bool)$session['rpe_required'];

// Exercises
$exStmt = $pdo->prepare(
    'SELECT id, exercise_name, category, sets, reps, duration_seconds,
            rest_seconds, intensity, instructions, requires_pose_detection,
            assessment_type, sort_order
     FROM session_exercises WHERE session_id = ? ORDER BY sort_order'
);
$exStmt->execute([$sessionId]);
$exercises = $exStmt->fetchAll();
foreach ($exercises as &$e) {
    $e['requires_pose_detection'] = (bool)$e['requires_pose_detection'];
}
unset($e);

// Players with completion data
$playerStmt = $pdo->prepare("
    SELECT
        sp.player_user_id,
        sp.linked_player_id,
        sp.status      AS player_status,
        sp.pre_check_completed_at,
        sp.started_at,
        sp.completed_at,
        COALESCE(cp.name, u.name, 'Unknown')    AS player_name,
        COALESCE(cp.position, '')               AS position,
        COALESCE(cp.team_name, '')              AS team_name,
        ptf.post_rpe,
        ptf.pain_reported,
        ptf.difficulty,
        ptf.mood_after,
        phi.hooper_score,
        phi.pre_rpe
    FROM session_players sp
    LEFT JOIN club_players cp ON cp.id = sp.linked_player_id
    LEFT JOIN users        u  ON u.id  = sp.player_user_id
    LEFT JOIN post_training_feedback ptf ON ptf.id = (
        SELECT id FROM post_training_feedback
        WHERE session_id = sp.session_id AND player_user_id = sp.player_user_id
        ORDER BY created_at DESC LIMIT 1
    )
    LEFT JOIN player_hooper_index phi ON phi.id = (
        SELECT id FROM player_hooper_index
        WHERE session_id = sp.session_id AND user_id = sp.player_user_id
        ORDER BY created_at DESC LIMIT 1
    )
    WHERE sp.session_id = ?
    ORDER BY player_name
");
$playerStmt->execute([$sessionId]);
$players = $playerStmt->fetchAll();

$totalPlayers    = count($players);
$completedCount  = 0;
$painAlerts      = 0;

foreach ($players as &$p) {
    $p['post_rpe']      = $p['post_rpe']      !== null ? (float)$p['post_rpe']    : null;
    $p['pain_reported'] = (bool)$p['pain_reported'];
    $p['mood_after']    = $p['mood_after']    !== null ? (int)$p['mood_after']    : null;
    $p['hooper_score']  = $p['hooper_score']  !== null ? (int)$p['hooper_score']  : null;
    $p['pre_rpe']       = $p['pre_rpe']       !== null ? (float)$p['pre_rpe']     : null;
    if ($p['player_status'] === 'completed') $completedCount++;
    if ($p['pain_reported']) $painAlerts++;
}
unset($p);

jsonOut([
    'session'          => $session,
    'exercises'        => $exercises,
    'players'          => $players,
    'total_players'    => $totalPlayers,
    'completed_count'  => $completedCount,
    'pain_alerts'      => $painAlerts,
]);
