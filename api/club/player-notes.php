<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';

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
        'SELECT u.id, u.role, u.name FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden — coaches only'], 403);
}

// ── GET: list notes for a player ────────────────────────────────────────────
if ($method === 'GET') {
    $playerId = trim($_GET['player_id'] ?? '');
    if (!$playerId) jsonOut(['success' => false, 'message' => 'Missing player_id'], 400);

    $ctx = requireClubPermission($pdo, $user, 'notes.read');
    $stmt = $pdo->prepare(
        'SELECT n.id, n.player_id, n.author_name, n.note_text, n.created_at
         FROM player_notes n
         JOIN club_players p ON p.id = n.player_id
         WHERE n.player_id = ? AND p.club_id = ?
         ORDER BY n.created_at DESC'
    );
    $stmt->execute([$playerId, $ctx['club_id']]);
    $notes = array_map(function ($row) {
        return [
            'id'         => (string)$row['id'],
            'playerId'   => $row['player_id'],
            'authorName' => $row['author_name'],
            'text'       => $row['note_text'],
            'date'       => $row['created_at'],
        ];
    }, $stmt->fetchAll());

    jsonOut(['success' => true, 'notes' => $notes]);
}

// ── POST: add a note ────────────────────────────────────────────────────────
if ($method === 'POST') {
    $data = json_decode(file_get_contents('php://input'), true) ?? [];
    $playerId = trim($data['player_id'] ?? '');
    $text     = trim($data['text'] ?? '');
    if (!$playerId || !$text) jsonOut(['success' => false, 'message' => 'Missing player_id or text'], 400);

    $ctx = requireClubPermission($pdo, $user, 'notes.write');

    // Confirm the player actually belongs to this staff member's club.
    $ownStmt = $pdo->prepare('SELECT 1 FROM club_players WHERE id = ? AND club_id = ?');
    $ownStmt->execute([$playerId, $ctx['club_id']]);
    if (!$ownStmt->fetchColumn()) jsonOut(['success' => false, 'message' => 'Player not found'], 404);

    $authorName = trim($data['author_name'] ?? '') ?: ($user['name'] ?? 'Coach');

    $stmt = $pdo->prepare(
        'INSERT INTO player_notes (player_id, coach_user_id, author_name, note_text) VALUES (?, ?, ?, ?)'
    );
    $stmt->execute([$playerId, $user['id'], $authorName, $text]);

    jsonOut(['success' => true, 'id' => (string)$pdo->lastInsertId()]);
}

// ── DELETE: remove a note ───────────────────────────────────────────────────
if ($method === 'DELETE') {
    $id = trim($_GET['id'] ?? '');
    if (!$id) jsonOut(['success' => false, 'message' => 'Missing id'], 400);

    requireClubPermission($pdo, $user, 'notes.write');

    $stmt = $pdo->prepare('DELETE FROM player_notes WHERE id = ? AND coach_user_id = ?');
    $stmt->execute([$id, $user['id']]);

    jsonOut(['success' => true]);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
