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

$limit  = min((int)($_GET['limit'] ?? 30), 100);
$offset = max((int)($_GET['offset'] ?? 0), 0);

$stmt = $pdo->prepare("
    SELECT ts.id, ts.plan_id, ts.title, ts.description,
           ts.session_date, ts.duration_minutes, ts.objective,
           ts.source, ts.status, ts.wellness_required, ts.rpe_required,
           ts.created_at,
           (SELECT COUNT(*) FROM session_exercises WHERE session_id = ts.id)                               AS exercise_count,
           (SELECT COUNT(*) FROM session_players   WHERE session_id = ts.id)                               AS player_count,
           (SELECT COUNT(*) FROM session_players   WHERE session_id = ts.id AND status = 'assigned')       AS assigned_count,
           (SELECT COUNT(*) FROM session_players   WHERE session_id = ts.id AND status = 'pre_checked')    AS pre_checked_count,
           (SELECT COUNT(*) FROM session_players   WHERE session_id = ts.id AND status = 'started')        AS started_count,
           (SELECT COUNT(*) FROM session_players   WHERE session_id = ts.id AND status = 'completed')      AS completed_count,
           (SELECT COUNT(*) FROM session_players   WHERE session_id = ts.id AND status = 'missed')         AS missed_count
    FROM training_sessions ts
    WHERE ts.coach_user_id = ?
    ORDER BY ts.session_date DESC, ts.created_at DESC
    LIMIT ? OFFSET ?
");
$stmt->execute([$user['id'], $limit, $offset]);
$sessions = $stmt->fetchAll();

// Cast numeric fields
foreach ($sessions as &$s) {
    $s['duration_minutes']  = (int)$s['duration_minutes'];
    $s['exercise_count']    = (int)$s['exercise_count'];
    $s['player_count']      = (int)$s['player_count'];
    $s['assigned_count']    = (int)$s['assigned_count'];
    $s['pre_checked_count'] = (int)$s['pre_checked_count'];
    $s['started_count']     = (int)$s['started_count'];
    $s['completed_count']   = (int)$s['completed_count'];
    $s['missed_count']      = (int)$s['missed_count'];
    $s['wellness_required'] = (bool)$s['wellness_required'];
    $s['rpe_required']      = (bool)$s['rpe_required'];
}
unset($s);

jsonOut(['sessions' => $sessions, 'count' => count($sessions)]);
