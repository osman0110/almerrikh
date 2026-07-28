<?php
/**
 * POST /api/mobile/player/join-club.php
 * Player uses an invite code to join a club.
 * Body: { "invite_code": "ABCD1234", "share_history": true }
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';

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
        'SELECT u.id, u.name, u.role, u.player_type, u.linked_player_id, u.club_user_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ?'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid token'], 401);
    return $user;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonOut(['error' => 'POST only'], 405);

$user        = getAuthUser($pdo);
$body        = json_decode(file_get_contents('php://input'), true) ?? [];
$inviteCode  = trim($body['invite_code']   ?? '');
$shareHistory= (bool)($body['share_history'] ?? true);

// Role checks before touching invite
if ($user['role'] !== 'player') {
    jsonOut(['error' => 'Forbidden — players only'], 403);
}
if ($user['club_user_id']) {
    jsonOut(['error' => 'Already linked to a club'], 409);
}

if (!$inviteCode) jsonOut(['error' => 'invite_code required'], 400);

// Validate access code — unified, reusable, never single-use.
$stmt = $pdo->prepare(
    'SELECT cac.*, c.name AS club_name
     FROM club_access_codes cac
     JOIN clubs c ON c.id = cac.club_id
     WHERE cac.code = ? AND cac.is_active = 1 AND cac.account_type = "player"'
);
$stmt->execute([$inviteCode]);
$invite = $stmt->fetch();
if (!$invite) jsonOut(['error' => 'Invalid or inactive invite code'], 400);

$clubUserId      = (int)$invite['club_user_id'];
$currentPlayerId = $user['linked_player_id'];

// ── Decide which club_players record becomes the canonical one ────────────────

if ($currentPlayerId) {
    // Player had an existing record — promote it instead of creating a new one
    $linkedPlayerId = $currentPlayerId;

    if ($shareHistory) {
        // Convert existing indie record into a club record visible to coach
        $pdo->prepare(
            'UPDATE club_players
             SET player_type = "club", user_id = ?, linked_user_id = ?
             WHERE id = ?'
        )->execute([$clubUserId, $user['id'], $linkedPlayerId]);
    } else {
        // Deactivate old record, create a fresh club record with no prior history
        $pdo->prepare('UPDATE club_players SET is_active = 0 WHERE id = ?')
            ->execute([$currentPlayerId]);

        $linkedPlayerId = 'cp-' . $user['id'] . '-' . time();
        $pdo->prepare(
            'INSERT INTO club_players (id, user_id, name, player_type, linked_user_id, is_active)
             VALUES (?, ?, ?, "club", ?, 1)'
        )->execute([$linkedPlayerId, $clubUserId, $user['name'], $user['id']]);
    }
} else {
    // No existing player record — create a fresh one under the coach
    $linkedPlayerId = 'cp-' . $user['id'] . '-' . time();
    $pdo->prepare(
        'INSERT INTO club_players (id, user_id, name, player_type, linked_user_id, is_active)
         VALUES (?, ?, ?, "club", ?, 1)'
    )->execute([$linkedPlayerId, $clubUserId, $user['name'], $user['id']]);
}

// Update user record
$pdo->prepare(
    'UPDATE users SET club_user_id = ?, linked_player_id = ?, player_type = "club" WHERE id = ?'
)->execute([$clubUserId, $linkedPlayerId, $user['id']]);

// Usage stats only — the code stays active and reusable for the next player.
$pdo->prepare(
    'UPDATE club_access_codes SET use_count = use_count + 1, last_used_at = NOW() WHERE code = ?'
)->execute([$inviteCode]);

jsonOut([
    'success'          => true,
    'club_name'        => $invite['club_name'],
    'linked_player_id' => $linkedPlayerId,
    'club_user_id'     => $clubUserId,
    'share_history'    => $shareHistory,
    'message'          => 'تم انضمامك إلى ' . $invite['club_name'] . ' بنجاح.',
]);
