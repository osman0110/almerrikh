<?php
/**
 * GET /api/coach/plans/list.php
 * Optional query params: status (draft|published), type (ai|manual)
 * Allowed roles: club, coach, academy
 */
require_once dirname(__DIR__, 2) . '/db.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') { http_response_code(405); echo '{"error":"Method not allowed"}'; exit; }

function jsonOut(array $d, int $c = 200): never {
    http_response_code($c);
    echo json_encode($d, JSON_UNESCAPED_UNICODE);
    exit;
}
function bearerToken(): string {
    $a = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? $_SERVER['Authorization'] ?? '';
    if (!$a && function_exists('apache_request_headers')) { $h = apache_request_headers(); $a = $h['Authorization'] ?? $h['authorization'] ?? ''; }
    return stripos($a, 'Bearer ') === 0 ? trim(substr($a, 7)) : trim($a);
}
function getAuthUser(PDO $pdo): array {
    $tok = bearerToken();
    if (!$tok) jsonOut(['error' => 'Unauthorized'], 401);
    $s = $pdo->prepare('SELECT u.id,u.role FROM users u JOIN user_tokens t ON u.id=t.user_id WHERE t.token=?');
    $s->execute([$tok]); $u = $s->fetch();
    if (!$u) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $u;
}

$user = getAuthUser($pdo);
if (!in_array($user['role'], ['club','coach','academy'], true)) jsonOut(['error' => 'Forbidden'], 403);
$coachId = (int)$user['id'];

$statusFilter = trim((string)($_GET['status'] ?? ''));
$typeFilter   = trim((string)($_GET['type']   ?? ''));

$where  = ['tp.coach_user_id = :cid'];
$params = [':cid' => $coachId];

if ($statusFilter && in_array($statusFilter, ['draft','published'], true)) {
    $where[] = 'tp.status = :status';
    $params[':status'] = $statusFilter;
}
if ($typeFilter && in_array($typeFilter, ['ai','manual'], true)) {
    $where[] = 'tp.plan_type = :ptype';
    $params[':ptype'] = $typeFilter;
}

$whereSQL = implode(' AND ', $where);
$stmt = $pdo->prepare(
    "SELECT tp.id, tp.plan_type, tp.title, tp.goal, tp.status, tp.target_type,
            tp.num_weeks, tp.plan_summary, tp.recovery_notes, tp.created_at,
            COUNT(DISTINCT ts.id) AS session_count
     FROM training_plans tp
     LEFT JOIN training_sessions ts ON ts.plan_id = tp.id
     WHERE {$whereSQL}
     GROUP BY tp.id
     ORDER BY tp.created_at DESC
     LIMIT 100"
);
$stmt->execute($params);
$rows = $stmt->fetchAll();

$plans = [];
foreach ($rows as $r) {
    $plans[] = [
        'id'           => $r['id'],
        'plan_type'    => $r['plan_type'],
        'title'        => $r['title'],
        'goal'         => $r['goal'],
        'status'       => $r['status'],
        'target_type'  => $r['target_type'],
        'num_weeks'    => (int)$r['num_weeks'],
        'summary'      => $r['plan_summary'],
        'session_count'=> (int)$r['session_count'],
        'created_at'   => $r['created_at'],
    ];
}

jsonOut(['success' => true, 'plans' => $plans]);
