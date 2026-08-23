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

$ctx = requireClubPermission($pdo, $user, 'players.read');
$cid = (int)$ctx['club_id'];

$playerId = trim($_GET['player_id'] ?? '');
if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);

$to   = trim($_GET['to']   ?? '') ?: date('Y-m-d');
$from = trim($_GET['from'] ?? '') ?: date('Y-m-d', strtotime('-365 days', strtotime($to)));
$competitionId = isset($_GET['competition_id']) && $_GET['competition_id'] !== ''
    ? (int)$_GET['competition_id']
    : null;

// ── Participation rollup per competition ────────────────────────────────────
$competitionFilter = $competitionId !== null ? ' AND m.competition_id = ?' : '';
$partParams = [$cid, $playerId, $from, $to];
if ($competitionId !== null) $partParams[] = $competitionId;
$partStmt = $pdo->prepare(
    'SELECT COALESCE(c.id, 0) AS competition_id, COALESCE(c.name, "أخرى") AS competition_name,
            mp.starter, mp.played, mp.minutes_played, mp.goals, mp.assists
     FROM match_participations mp
     JOIN matches m ON m.id = mp.match_id
     LEFT JOIN club_competitions c ON c.id = m.competition_id
     WHERE m.club_id = ? AND mp.player_id = ? AND m.match_date BETWEEN ? AND ?' . $competitionFilter
);
$partStmt->execute($partParams);

$byCompetition = [];
$ensure = function (int $id, string $name) use (&$byCompetition) {
    if (!isset($byCompetition[$id])) {
        $byCompetition[$id] = [
            'competition_id'   => $id,
            'competition_name' => $name,
            'appearances'      => 0,
            'starts'           => 0,
            'sub_appearances'  => 0,
            'total_minutes'    => 0,
            'goals'            => 0,
            'assists'          => 0,
            'yellow_cards'     => 0,
            'red_cards'        => 0,
            'active_suspensions' => 0,
            'matches_remaining' => 0,
        ];
    }
};

foreach ($partStmt->fetchAll() as $r) {
    $id = (int)$r['competition_id'];
    $ensure($id, $r['competition_name']);
    if ((int)$r['played'] === 1) {
        $byCompetition[$id]['appearances']++;
        if ((int)$r['starter'] === 1) $byCompetition[$id]['starts']++;
        else $byCompetition[$id]['sub_appearances']++;
    }
    $byCompetition[$id]['total_minutes'] += (int)$r['minutes_played'];
    $byCompetition[$id]['goals']         += (int)$r['goals'];
    $byCompetition[$id]['assists']       += (int)$r['assists'];
}

// ── Cards per competition ────────────────────────────────────────────────────
$cardParams = [$cid, $playerId, $from, $to];
if ($competitionId !== null) $cardParams[] = $competitionId;
$cardStmt = $pdo->prepare(
    'SELECT COALESCE(c.id, 0) AS competition_id, COALESCE(c.name, "أخرى") AS competition_name,
            mc.card_type, COUNT(*) AS cnt
     FROM match_cards mc
     JOIN matches m ON m.id = mc.match_id
     LEFT JOIN club_competitions c ON c.id = m.competition_id
     WHERE m.club_id = ? AND mc.player_id = ? AND m.match_date BETWEEN ? AND ?' . $competitionFilter . '
     GROUP BY competition_id, competition_name, mc.card_type'
);
$cardStmt->execute($cardParams);

foreach ($cardStmt->fetchAll() as $r) {
    $id = (int)$r['competition_id'];
    $ensure($id, $r['competition_name']);
    if ($r['card_type'] === 'yellow') $byCompetition[$id]['yellow_cards'] = (int)$r['cnt'];
    if ($r['card_type'] === 'red')    $byCompetition[$id]['red_cards']    = (int)$r['cnt'];
}

$suspensionParams = [$cid, $playerId];
$suspensionFilter = '';
if ($competitionId !== null) {
    $suspensionFilter = ' AND ps.competition_id = ?';
    $suspensionParams[] = $competitionId;
}
$suspensionStmt = $pdo->prepare(
    "SELECT ps.competition_id, COUNT(*) AS active_suspensions,
            COALESCE(SUM(ps.matches_remaining), 0) AS matches_remaining,
            c.name AS competition_name
     FROM player_suspensions ps
     JOIN club_competitions c ON c.id = ps.competition_id
     WHERE ps.club_id = ? AND ps.player_id = ? AND ps.status = 'active'" . $suspensionFilter . '
     GROUP BY ps.competition_id, c.name'
);
$suspensionStmt->execute($suspensionParams);
foreach ($suspensionStmt->fetchAll() as $r) {
    $id = (int)$r['competition_id'];
    $ensure($id, $r['competition_name']);
    $byCompetition[$id]['active_suspensions'] = (int)$r['active_suspensions'];
    $byCompetition[$id]['matches_remaining'] = (int)$r['matches_remaining'];
}

$result = array_values($byCompetition);
usort($result, fn($a, $b) => $b['total_minutes'] <=> $a['total_minutes']);

jsonOut([
    'player_id'     => $playerId,
    'range'         => ['from' => $from, 'to' => $to],
    'competitions'  => $result,
]);
