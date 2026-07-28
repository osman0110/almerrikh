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
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);

$sessionId = isset($_GET['id']) ? trim($_GET['id']) : '';
if (!$sessionId) jsonOut(['error' => 'id is required'], 400);

// Security: player must be assigned to this session
$sp = $pdo->prepare(
    'SELECT sp.status AS player_status, sp.pre_check_completed_at, sp.started_at, sp.completed_at,
            ts.id, ts.title, ts.description, ts.duration_minutes,
            ts.objective, ts.status AS session_status,
            ts.wellness_required, ts.rpe_required, ts.session_date
     FROM session_players sp
     JOIN training_sessions ts ON ts.id = sp.session_id
     WHERE sp.session_id = ? AND sp.player_user_id = ?'
);
$sp->execute([$sessionId, $user['id']]);
$row = $sp->fetch();

if (!$row) jsonOut(['error' => 'Session not found or not assigned to you'], 404);

$exStmt = $pdo->prepare(
    'SELECT id, exercise_name, category, sets, reps, duration_seconds,
            rest_seconds, intensity, instructions, video_url,
            requires_pose_detection, assessment_type, sort_order
     FROM session_exercises WHERE session_id = ? ORDER BY sort_order'
);
$exStmt->execute([$sessionId]);
$exercises = $exStmt->fetchAll();

$row['wellness_required']    = (bool)$row['wellness_required'];
$row['rpe_required']         = (bool)$row['rpe_required'];
$row['exercise_count']       = count($exercises);
$row['exercises']            = array_map(static function(array $e): array {
    $e['requires_pose_detection'] = (bool)$e['requires_pose_detection'];
    return $e;
}, $exercises);

jsonOut(['session' => $row]);
