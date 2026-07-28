<?php
/**
 * Match-level, per-player breakdown behind the admin dashboard's stat
 * tiles (minutes / goals / assists / cards / matches count) —
 * filterable by season, competition, and date range so every number on
 * the admin panel can be drilled into instead of shown as a flat total.
 *
 * GET ?season_id=&competition_id=&from=&to=
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
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

$token = bearerToken();
if (!$token) jsonOut(['success' => false, 'message' => 'Unauthorized'], 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id
     WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

$ctx = requireClubPermission($pdo, $user, 'admin_dashboard.read');
$cid = (int)$ctx['club_id'];

$seasonId      = isset($_GET['season_id']) && $_GET['season_id'] !== '' ? (int)$_GET['season_id'] : null;
$competitionId = isset($_GET['competition_id']) && $_GET['competition_id'] !== '' ? (int)$_GET['competition_id'] : null;
$to   = trim($_GET['to']   ?? '') ?: date('Y-m-d');
$from = trim($_GET['from'] ?? '') ?: '2000-01-01';
foreach (['from' => $from, 'to' => $to] as $label => $value) {
    $parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $value);
    if (!$parsed || $parsed->format('Y-m-d') !== $value) {
        jsonOut(['success' => false, 'message' => "Invalid $label date"], 400);
    }
}
if ($from > $to) {
    jsonOut(['success' => false, 'message' => 'Invalid date range'], 400);
}

// Historical reports must keep players who later left the active roster.
$rosterStmt = $pdo->prepare('SELECT id, name FROM club_players WHERE club_id = ?');
$rosterStmt->execute([$cid]);
$roster = [];
foreach ($rosterStmt->fetchAll() as $p) {
    $roster[(string)$p['id']] = $p['name'];
}

// ── Matches in range, optionally scoped to one competition or one season ────
$sql = 'SELECT m.id, m.opponent, m.match_date, m.competition_id, m.player_minutes,
               c.name AS competition_name
        FROM matches m
        LEFT JOIN club_competitions c ON c.id = m.competition_id
        WHERE m.club_id = ? AND m.match_date BETWEEN ? AND ?';
$params = [$cid, $from, $to];
if ($competitionId !== null) {
    $sql .= ' AND m.competition_id = ?';
    $params[] = $competitionId;
} elseif ($seasonId !== null) {
    $sql .= ' AND c.season_id = ?';
    $params[] = $seasonId;
}
$sql .= ' ORDER BY m.match_date DESC';

$mStmt = $pdo->prepare($sql);
$mStmt->execute($params);
$matchRows = $mStmt->fetchAll();

$matchIds = array_column($matchRows, 'id');

// ── Cards for those matches, grouped by match+player+type ───────────────────
$cardsByMatchPlayer = []; // [match_id][player_id] = ['yellow'=>n,'red'=>n]
if ($matchIds) {
    $inList = implode(',', array_fill(0, count($matchIds), '?'));
    $cStmt = $pdo->prepare(
        "SELECT match_id, player_id, card_type, COUNT(*) AS cnt
         FROM match_cards
         WHERE match_id IN ($inList)
         GROUP BY match_id, player_id, card_type"
    );
    $cStmt->execute($matchIds);
    foreach ($cStmt->fetchAll() as $row) {
        $mid = $row['match_id'];
        $pid = (string)$row['player_id'];
        if (!isset($cardsByMatchPlayer[$mid][$pid])) {
            $cardsByMatchPlayer[$mid][$pid] = ['yellow' => 0, 'red' => 0];
        }
        if (in_array($row['card_type'], ['yellow', 'red'], true)) {
            $cardsByMatchPlayer[$mid][$pid][$row['card_type']] = (int)$row['cnt'];
        }
    }
}

$participationsByMatchPlayer = []; // [match_id][player_id] = ['goals'=>n,'assists'=>n]
if ($matchIds) {
    $inList = implode(',', array_fill(0, count($matchIds), '?'));
    $pStmt = $pdo->prepare(
        "SELECT match_id, player_id, goals, assists
         FROM match_participations
         WHERE match_id IN ($inList)"
    );
    $pStmt->execute($matchIds);
    foreach ($pStmt->fetchAll() as $row) {
        $participationsByMatchPlayer[$row['match_id']][(string)$row['player_id']] = [
            'goals'   => (int)$row['goals'],
            'assists' => (int)$row['assists'],
        ];
    }
}

// ── Assemble matches[] + roll up by_player / by_competition / totals ────────
$matches = [];
$byPlayer = [];
$byCompetition = []; // competition_id (or 0 for none) => rollup
$totals = [
    'matches' => 0, 'total_minutes' => 0, 'goals' => 0, 'assists' => 0,
    'yellow_cards' => 0, 'red_cards' => 0, 'matches_with_player_data' => 0,
];

foreach ($matchRows as $m) {
    $minutesJson = $m['player_minutes'] && $m['player_minutes'] !== 'null'
        ? (json_decode($m['player_minutes'], true) ?? []) : [];
    $cardsForMatch = $cardsByMatchPlayer[$m['id']] ?? [];
    $participationsForMatch = $participationsByMatchPlayer[$m['id']] ?? [];

    $playerIds = array_unique(array_merge(
        array_map('strval', array_keys($minutesJson)),
        array_keys($cardsForMatch),
        array_keys($participationsForMatch)
    ));

    $playersOut = [];
    foreach ($playerIds as $pid) {
        if (!isset($roster[$pid])) continue;
        $minutes = (int)($minutesJson[$pid] ?? 0);
        $yellow  = (int)($cardsForMatch[$pid]['yellow'] ?? 0);
        $red     = (int)($cardsForMatch[$pid]['red'] ?? 0);
        $goals   = (int)($participationsForMatch[$pid]['goals'] ?? 0);
        $assists = (int)($participationsForMatch[$pid]['assists'] ?? 0);
        if ($minutes <= 0 && $yellow === 0 && $red === 0 && $goals === 0 && $assists === 0) continue;

        $playersOut[$pid] = [
            'minutes' => $minutes, 'goals' => $goals, 'assists' => $assists,
            'yellow' => $yellow, 'red' => $red,
        ];

        if (!isset($byPlayer[$pid])) {
            $byPlayer[$pid] = [
                'player_id' => $pid, 'name' => $roster[$pid],
                'matches' => 0, 'total_minutes' => 0, 'goals' => 0, 'assists' => 0,
                'yellow_cards' => 0, 'red_cards' => 0,
            ];
        }
        $byPlayer[$pid]['matches']++;
        $byPlayer[$pid]['total_minutes'] += $minutes;
        $byPlayer[$pid]['goals']         += $goals;
        $byPlayer[$pid]['assists']       += $assists;
        $byPlayer[$pid]['yellow_cards']  += $yellow;
        $byPlayer[$pid]['red_cards']     += $red;

        $totals['total_minutes'] += $minutes;
        $totals['goals']         += $goals;
        $totals['assists']       += $assists;
        $totals['yellow_cards']  += $yellow;
        $totals['red_cards']     += $red;
    }

    $compId = $m['competition_id'] !== null ? (int)$m['competition_id'] : 0;
    if (!isset($byCompetition[$compId])) {
        $byCompetition[$compId] = [
            'competition_id'   => $m['competition_id'] !== null ? (int)$m['competition_id'] : null,
            'competition_name' => $m['competition_name'] ?? '',
            'matches' => 0, 'total_minutes' => 0, 'goals' => 0, 'assists' => 0,
            'yellow_cards' => 0, 'red_cards' => 0,
        ];
    }
    $byCompetition[$compId]['matches']++;
    foreach ($playersOut as $p) {
        $byCompetition[$compId]['total_minutes'] += $p['minutes'];
        $byCompetition[$compId]['goals']         += $p['goals'];
        $byCompetition[$compId]['assists']       += $p['assists'];
        $byCompetition[$compId]['yellow_cards']  += $p['yellow'];
        $byCompetition[$compId]['red_cards']     += $p['red'];
    }

    $totals['matches']++;
    if ($playersOut) {
        $totals['matches_with_player_data']++;
    }
    $matches[] = [
        'id'                => $m['id'],
        'opponent'          => $m['opponent'],
        'match_date'        => $m['match_date'],
        'competition_id'    => $m['competition_id'] !== null ? (int)$m['competition_id'] : null,
        'competition_name'  => $m['competition_name'] ?? '',
        'players'           => $playersOut,
    ];
}

jsonOut([
    'success'        => true,
    'generated_at'   => date(DATE_ATOM),
    'filters'        => [
        'season_id' => $seasonId, 'competition_id' => $competitionId,
        'from' => $from, 'to' => $to,
    ],
    'totals'         => $totals,
    'by_player'      => array_values($byPlayer),
    'by_competition' => array_values($byCompetition),
    'matches'        => $matches,
]);
