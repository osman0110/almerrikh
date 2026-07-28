<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';
require_once '../includes/club_auth.php';

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

$token = bearerToken();
if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['error' => 'Invalid token'], 401);

$ctx = requireClubPermission($pdo, $user, 'sessions.read');
$cid = (int)$ctx['club_id'];

$playerId = trim($_GET['player_id'] ?? '');
if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);

$to   = trim($_GET['to']   ?? '') ?: date('Y-m-d');
$from = trim($_GET['from'] ?? '') ?: date('Y-m-d', strtotime('-365 days', strtotime($to)));

// ── Participation rollup: appearances, starts, minutes, goals, assists ─────────
$partStmt = $pdo->prepare(
    'SELECT mp.starter, mp.played, mp.minutes_played, mp.goals, mp.assists
     FROM match_participations mp
     JOIN matches m ON m.id = mp.match_id
     WHERE m.club_id = ? AND mp.player_id = ? AND m.match_date BETWEEN ? AND ?'
);
$partStmt->execute([$cid, $playerId, $from, $to]);
$rows = $partStmt->fetchAll();

$appearances = 0;
$starts      = 0;
$subAppearances = 0;
$totalMinutes = 0;
$goals   = 0;
$assists = 0;
foreach ($rows as $r) {
    if ((int)$r['played'] === 1) {
        $appearances++;
        if ((int)$r['starter'] === 1) $starts++; else $subAppearances++;
    }
    $totalMinutes += (int)$r['minutes_played'];
    $goals   += (int)$r['goals'];
    $assists += (int)$r['assists'];
}

// ── Cards in range ──────────────────────────────────────────────────────────
$cardStmt = $pdo->prepare(
    'SELECT mc.card_type, COUNT(*) AS cnt
     FROM match_cards mc
     JOIN matches m ON m.id = mc.match_id
     WHERE m.club_id = ? AND mc.player_id = ? AND m.match_date BETWEEN ? AND ?
     GROUP BY mc.card_type'
);
$cardStmt->execute([$cid, $playerId, $from, $to]);
$yellow = 0;
$red    = 0;
foreach ($cardStmt->fetchAll() as $r) {
    if ($r['card_type'] === 'yellow') $yellow = (int)$r['cnt'];
    if ($r['card_type'] === 'red')    $red    = (int)$r['cnt'];
}

jsonOut([
    'player_id'        => $playerId,
    'range'            => ['from' => $from, 'to' => $to],
    'appearances'      => $appearances,
    'starts'           => $starts,
    'sub_appearances'  => $subAppearances,
    'total_minutes'    => $totalMinutes,
    'goals'            => $goals,
    'assists'          => $assists,
    'yellow_cards'     => $yellow,
    'red_cards'        => $red,
]);
