<?php
/**
 * GET /api/player/sessions.php
 * Read-only list of club training sessions the authenticated player is part of.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';
require_once '../includes/club_auth.php';
require_once '../includes/fitness/FitnessConfig.php';
require_once '../includes/fitness/SchemaInspector.php';

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

if ($_SERVER['REQUEST_METHOD'] !== 'GET') jsonOut(['error' => 'Method not allowed'], 405);

$user = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);

// Resolve the player's club_players record (never trust client-supplied ids).
$cpStmt = $pdo->prepare(
    'SELECT id, user_id, club_id FROM club_players
     WHERE (linked_user_id = ? OR (user_id = ? AND player_type = "independent"))
       AND is_active = 1
     ORDER BY created_at DESC LIMIT 1'
);
$cpStmt->execute([$user['id'], $user['id']]);
$player = $cpStmt->fetch();

if (!$player) jsonOut(['sessions' => [], 'count' => 0]);

$limit = min((int)($_GET['limit'] ?? 50), 200);

// Scoped by club_id — a session belongs to the whole club (any coach/staff
// member may have created it), not just to whichever coach happens to match
// this player's own roster-row owner. Falls back to the legacy owner-id
// match too, so sessions saved before club_id was backfilled still show.
$stmt = $pdo->prepare(
    'SELECT * FROM club_sessions
     WHERE (club_id = ? OR (club_id IS NULL AND user_id = ?)) AND JSON_CONTAINS(player_ids, JSON_QUOTE(?))
     ORDER BY date DESC LIMIT ' . $limit
);
$stmt->execute([$player['club_id'], $player['user_id'], (string)$player['id']]);
$rows = $stmt->fetchAll();

// Has this player already submitted Hooper/RPE for this session? Used to
// hide the entry button and lock the one-time submission client-side.
$hooperStmt = $pdo->prepare('SELECT id FROM player_hooper_index WHERE user_id = ? AND session_id = ? LIMIT 1');
$activeRpeFilter = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
    ? ' AND is_active_record = 1'
    : '';
$rpeStmt = $pdo->prepare(
    'SELECT id, TIMESTAMPDIFF(MINUTE, submitted_at, NOW()) <= '
        . FitnessConfig::RPE_PLAYER_EDIT_WINDOW_MINUTES . ' AS editable
     FROM player_rpe
     WHERE (user_id = ? OR linked_player_id = ?)
       AND session_id = ? AND rpe_type = \'post\''
       . $activeRpeFilter . '
     ORDER BY submitted_at DESC LIMIT 1'
);

foreach ($rows as &$r) {
    $r['player_ids']           = $r['player_ids'] && $r['player_ids'] !== 'null'
        ? json_decode($r['player_ids'], true) ?? [] : [];
    $r['completed_player_ids'] = $r['completed_player_ids'] && $r['completed_player_ids'] !== 'null'
        ? json_decode($r['completed_player_ids'], true) ?? [] : [];
    $r['my_completed'] = in_array((string)$player['id'], $r['completed_player_ids'], true);

    $hooperStmt->execute([$user['id'], $r['id']]);
    $r['wellness_done'] = (bool)$hooperStmt->fetchColumn();
    $rpeStmt->execute([$user['id'], $player['id'], $r['id']]);
    $rpeRow = $rpeStmt->fetch(PDO::FETCH_ASSOC);
    $r['rpe_done'] = (bool)$rpeRow;
    $r['rpe_editable'] = $rpeRow ? (bool)$rpeRow['editable'] : false;
}
unset($r);

jsonOut(['sessions' => $rows, 'count' => count($rows)]);
