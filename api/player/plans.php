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

$userId = (int)$user['id'];
$limit  = min((int)($_GET['limit'] ?? 10), 50);

$stmt = $pdo->prepare("
    SELECT tp.id, tp.plan_type, tp.title, tp.goal, tp.status,
           tp.num_weeks, tp.recovery_notes, tp.progression_rules, tp.created_at,
           (SELECT COUNT(*) FROM training_sessions WHERE plan_id = tp.id) AS session_count,
           (SELECT COUNT(*) FROM training_sessions ts
            JOIN session_players sp ON sp.session_id = ts.id
            WHERE ts.plan_id = tp.id AND sp.player_user_id = ? AND sp.status = 'completed') AS completed_count,
           (SELECT MIN(session_date) FROM training_sessions WHERE plan_id = tp.id) AS start_date,
           (SELECT MAX(session_date) FROM training_sessions WHERE plan_id = tp.id) AS end_date
    FROM training_plans tp
    WHERE tp.player_user_id = ? AND tp.status != 'archived'
    ORDER BY tp.created_at DESC
    LIMIT ?
");
$stmt->execute([$userId, $userId, $limit]);
$plans = $stmt->fetchAll();

foreach ($plans as &$p) {
    $p['session_count']   = (int)$p['session_count'];
    $p['completed_count'] = (int)$p['completed_count'];
    $p['num_weeks']       = $p['num_weeks'] !== null ? (int)$p['num_weeks'] : null;
}
unset($p);

jsonOut(['plans' => $plans, 'count' => count($plans)]);
