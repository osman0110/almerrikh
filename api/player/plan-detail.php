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
        'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);

$planId = trim($_GET['id'] ?? '');
if (!$planId) jsonOut(['error' => 'id is required'], 400);

$userId = (int)$user['id'];

// Security: plan must belong to this player
$plan = $pdo->prepare(
    'SELECT id, plan_type, title, goal, status, num_weeks,
            recovery_notes, progression_rules, created_at
     FROM training_plans WHERE id = ? AND player_user_id = ? AND status != \'archived\''
);
$plan->execute([$planId, $userId]);
$planRow = $plan->fetch();
if (!$planRow) jsonOut(['error' => 'Plan not found'], 404);

$planRow['num_weeks'] = $planRow['num_weeks'] !== null ? (int)$planRow['num_weeks'] : null;

// Sessions with player status, grouped for week display
$sessStmt = $pdo->prepare("
    SELECT ts.id, ts.title, ts.session_date, ts.duration_minutes,
           ts.objective, ts.status AS session_status,
           ts.week_number, ts.intensity,
           sp.status AS player_status,
           sp.pre_check_completed_at, sp.completed_at,
           (SELECT COUNT(*) FROM session_exercises WHERE session_id = ts.id) AS exercise_count
    FROM training_sessions ts
    LEFT JOIN session_players sp ON sp.session_id = ts.id AND sp.player_user_id = ?
    WHERE ts.plan_id = ?
    ORDER BY ts.session_date, ts.created_at
");
$sessStmt->execute([$userId, $planId]);
$sessions = $sessStmt->fetchAll();

// Group by week
$weeks = [];
foreach ($sessions as $s) {
    $s['duration_minutes'] = (int)$s['duration_minutes'];
    $s['exercise_count']   = (int)$s['exercise_count'];
    $s['week_number']      = $s['week_number'] !== null ? (int)$s['week_number'] : 1;
    $wk = $s['week_number'];
    if (!isset($weeks[$wk])) $weeks[$wk] = ['week' => $wk, 'sessions' => []];
    $weeks[$wk]['sessions'][] = $s;
}
ksort($weeks);

jsonOut([
    'plan'  => $planRow,
    'weeks' => array_values($weeks),
    'total_sessions' => count($sessions),
]);
