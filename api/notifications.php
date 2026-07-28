<?php
/**
 * In-app notification center — per-user list + read state.
 * Rows are written by createNotification() (api/includes/notifications.php)
 * from other endpoints (tasks.php task_assigned/task_comment, injuries.php
 * injury_created, readiness-alert logic) — this endpoint only reads/updates.
 *
 * GET  ?unread_only=1          — list notifications for the caller
 * GET  ?count=1                — just the unread count
 * POST action=mark_read, id=X  — mark one notification read
 * POST action=mark_all_read    — mark all of the caller's notifications read
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db.php';

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
    if (!$token) jsonOut(['success' => false, 'message' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

function notificationOut(array $n): array {
    return [
        'id'           => (string)$n['id'],
        'type'         => $n['type'],
        'title'        => $n['title'],
        'body'         => $n['body'],
        'linked_route' => $n['linked_route'],
        'is_read'      => (bool)$n['is_read'],
        'created_at'   => $n['created_at'],
    ];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if ($method === 'GET') {
    if (($_GET['count'] ?? '') === '1') {
        $stmt = $pdo->prepare('SELECT COUNT(*) FROM notifications WHERE user_id = ? AND is_read = 0');
        $stmt->execute([$user['id']]);
        jsonOut(['success' => true, 'unread_count' => (int)$stmt->fetchColumn()]);
    }

    $where = 'user_id = ?';
    $params = [$user['id']];
    if (($_GET['unread_only'] ?? '') === '1') {
        $where .= ' AND is_read = 0';
    }

    $stmt = $pdo->prepare(
        "SELECT * FROM notifications WHERE $where ORDER BY created_at DESC LIMIT 100"
    );
    $stmt->execute($params);
    jsonOut([
        'success' => true,
        'notifications' => array_map('notificationOut', $stmt->fetchAll(PDO::FETCH_ASSOC)),
    ]);
}

if ($method === 'POST') {
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? '');

    if ($action === 'mark_read') {
        $id = trim($body['id'] ?? '');
        if (!$id) jsonOut(['success' => false, 'message' => 'id is required'], 400);
        $pdo->prepare('UPDATE notifications SET is_read = 1 WHERE id = ? AND user_id = ?')
            ->execute([$id, $user['id']]);
        jsonOut(['success' => true]);
    }

    if ($action === 'mark_all_read') {
        $pdo->prepare('UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0')
            ->execute([$user['id']]);
        jsonOut(['success' => true]);
    }

    jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
