<?php
/**
 * GET /api/player/my-notes.php
 * Read-only: coach/staff notes written about the authenticated player on
 * their profile page (player_notes table, written via
 * api/club/player-notes.php). Scoped to the caller's own club_players.id.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';

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
        'SELECT u.id, u.role FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);

$user = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['success' => false, 'message' => 'Forbidden — players only'], 403);

$stmt = $pdo->prepare(
    "SELECT id FROM club_players
     WHERE linked_user_id = ? AND is_active = 1 AND player_type = 'club'
     ORDER BY created_at DESC LIMIT 1"
);
$stmt->execute([$user['id']]);
$playerId = $stmt->fetchColumn();

if (!$playerId) jsonOut(['success' => true, 'notes' => []]);

$stmt = $pdo->prepare(
    'SELECT id, author_name, note_text, created_at
     FROM player_notes WHERE player_id = ? ORDER BY created_at DESC LIMIT 20'
);
$stmt->execute([$playerId]);
$notes = array_map(function ($row) {
    return [
        'id'         => (string)$row['id'],
        'authorName' => $row['author_name'],
        'text'       => $row['note_text'],
        'date'       => $row['created_at'],
    ];
}, $stmt->fetchAll());

jsonOut(['success' => true, 'notes' => $notes]);
