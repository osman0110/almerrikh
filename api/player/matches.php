<?php
/**
 * GET /api/player/matches.php
 * Read-only list of club matches the authenticated player is part of.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
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

if (!$player) jsonOut(['matches' => [], 'count' => 0]);

$limit = min((int)($_GET['limit'] ?? 50), 200);

// Scoped by club_id — a match belongs to the whole club (any coach/staff
// member may have created it), not just to whichever coach happens to match
// this player's own roster-row owner.
$stmt = $pdo->prepare(
    "SELECT m.*, c.name AS competition_name,
            (SELECT COUNT(*) FROM match_cards mc WHERE mc.match_id = m.id AND mc.player_id = ? AND mc.card_type = 'yellow') AS my_yellow_cards,
            (SELECT COUNT(*) FROM match_cards mc WHERE mc.match_id = m.id AND mc.player_id = ? AND mc.card_type = 'red') AS my_red_cards
     FROM matches m LEFT JOIN club_competitions c ON c.id = m.competition_id
     WHERE (m.club_id = ? OR (m.club_id IS NULL AND m.user_id = ?)) AND JSON_CONTAINS(m.player_ids, JSON_QUOTE(?))
     ORDER BY m.match_date DESC, m.match_time DESC LIMIT " . $limit
);
$stmt->execute([(string)$player['id'], (string)$player['id'], $player['club_id'], $player['user_id'], (string)$player['id']]);
$rows = $stmt->fetchAll();

// Has this player already submitted Hooper/RPE for this match? Used to hide
// the entry button and lock the one-time submission client-side.
$hooperStmt = $pdo->prepare('SELECT hooper_score FROM player_hooper_index WHERE user_id = ? AND session_id = ? LIMIT 1');
$rpeStmt    = $pdo->prepare('SELECT rpe_score FROM player_rpe WHERE user_id = ? AND session_id = ? AND rpe_type = \'post\' LIMIT 1');

foreach ($rows as &$r) {
    $r['wellness_required'] = (bool)$r['wellness_required'];
    $r['rpe_required']      = (bool)$r['rpe_required'];
    $r['player_ids']        = $r['player_ids'] && $r['player_ids'] !== 'null'
        ? json_decode($r['player_ids'], true) ?? [] : [];
    $r['player_minutes']    = $r['player_minutes'] && $r['player_minutes'] !== 'null'
        ? json_decode($r['player_minutes'], true) ?? [] : [];
    $r['my_minutes']        = $r['player_minutes'][(string)$player['id']] ?? null;

    $hooperStmt->execute([$user['id'], $r['id']]);
    $hooperScore = $hooperStmt->fetchColumn();
    $r['wellness_done'] = $hooperScore !== false;
    $r['hooper_score'] = $hooperScore !== false ? (int)$hooperScore : null;

    $rpeStmt->execute([$user['id'], $r['id']]);
    $rpeScore = $rpeStmt->fetchColumn();
    $r['rpe_done'] = $rpeScore !== false;
    $r['rpe_score'] = $rpeScore !== false ? (int)$rpeScore : null;
}
unset($r);

jsonOut(['matches' => $rows, 'count' => count($rows)]);
