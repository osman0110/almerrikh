<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/SchemaInspector.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

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

$user  = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);
$limit = min(30, max(1, (int)($_GET['limit'] ?? 14)));

$activeFilter = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
    ? ' AND is_active_record = 1'
    : '';
$stmt = $pdo->prepare(
    'SELECT id, session_type, rpe_score, duration_minutes, training_load, notes, submitted_at,
            completed_full_session, actual_duration_minutes, incomplete_reason
     FROM player_rpe
     WHERE user_id = ?' . $activeFilter . '
     ORDER BY submitted_at DESC LIMIT ?'
);
$stmt->execute([$user['id'], $limit]);
$history = $stmt->fetchAll();

// rpe_score/training_load are DECIMAL columns — PDO returns them as strings,
// which would serialize as JSON strings instead of numbers. Cast explicitly
// so Dart's RpeEntry.fromJson keeps parsing them as numeric.
foreach ($history as &$row) {
    if (isset($row['rpe_score']))     $row['rpe_score']     = (float)$row['rpe_score'];
    if (isset($row['training_load'])) $row['training_load'] = (float)$row['training_load'];
}
unset($row);

jsonOut(['history' => $history, 'count' => count($history)]);
