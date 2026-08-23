<?php
/**
 * POST /api/alerts/send.php
 * Admin/coach broadcasts a free-text alert to a player, a team, or the whole
 * club. Writes one `notifications` row (+ push) per recipient via the shared
 * createNotification() choke point — 'coach_alert' has no i18n template, so
 * notification_i18n.php's default case renders $title/$message verbatim.
 *
 * Body: { title, message, target: 'individual'|'team'|'club',
 *         player_ids?: [club_players.id, ...], team_name?: string }
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';
require_once dirname(__DIR__) . '/includes/notifications.php';

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
        'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);

$user = getAuthUser($pdo);
$ctx  = requireClubPermission($pdo, $user, 'alerts.send');
$clubId = $ctx['club_id'];

$body    = json_decode(file_get_contents('php://input'), true) ?? [];
$title   = trim((string)($body['title'] ?? ''));
$message = trim((string)($body['message'] ?? ''));
$target  = trim((string)($body['target'] ?? 'individual'));

if ($title === '' || $message === '') {
    jsonOut(['success' => false, 'message' => 'title and message are required'], 400);
}

$sql = 'SELECT linked_user_id FROM club_players WHERE club_id = ? AND is_active = 1 AND linked_user_id IS NOT NULL';
$params = [$clubId];

if ($target === 'individual') {
    $playerIds = array_filter(array_map('intval', (array)($body['player_ids'] ?? [])));
    if (!$playerIds) jsonOut(['success' => false, 'message' => 'player_ids is required'], 400);
    $placeholders = implode(',', array_fill(0, count($playerIds), '?'));
    $sql .= " AND id IN ($placeholders)";
    $params = array_merge($params, $playerIds);
} elseif ($target === 'team') {
    $teamName = trim((string)($body['team_name'] ?? ''));
    if ($teamName === '') jsonOut(['success' => false, 'message' => 'team_name is required'], 400);
    $sql .= ' AND team_name = ?';
    $params[] = $teamName;
} elseif ($target !== 'club') {
    jsonOut(['success' => false, 'message' => 'Invalid target'], 400);
}

$stmt = $pdo->prepare($sql);
$stmt->execute($params);
$recipientIds = array_unique(array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN)));

foreach ($recipientIds as $recipientUserId) {
    createNotification($pdo, $clubId, $recipientUserId, 'coach_alert', [
        'title'    => $title,
        'raw_body' => $message,
    ], '/club/notifications');
}

jsonOut(['success' => true, 'sent_count' => count($recipientIds)]);
