<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/report_helpers.php';

$user = rptAuthUser($pdo);

if (in_array($user['role'], ['player', 'parent'], true)) {
    jsonOut(['error' => 'Forbidden'], 403);
}

$ctx      = requireClubPermission($pdo, $user, 'assessments.read');
$clubId   = $ctx['club_id'];
$teamName = trim($_GET['team_name'] ?? '');

// Optional custom date range (?from=YYYY-MM-DD&to=YYYY-MM-DD) — when given,
// every figure below (completion rate, avg hooper/RPE, training load, pain
// reports) is computed over that same range instead of the default 30d/7d
// windows.
$dateRe = '/^\d{4}-\d{2}-\d{2}$/';
$rangeFrom = (isset($_GET['from']) && preg_match($dateRe, $_GET['from'])) ? $_GET['from'] : null;
$rangeTo   = (isset($_GET['to'])   && preg_match($dateRe, $_GET['to']))   ? $_GET['to']   : null;
if ($rangeFrom !== null && $rangeTo !== null && $rangeFrom > $rangeTo) {
    [$rangeFrom, $rangeTo] = [$rangeTo, $rangeFrom];
}
if ($rangeFrom === null || $rangeTo === null) { $rangeFrom = null; $rangeTo = null; }

// Fetch scoped players — never show independent players
if ($teamName !== '') {
    $stmt = $pdo->prepare(
        "SELECT id, name, position, team_name, player_type, linked_user_id
         FROM club_players
         WHERE club_id = ? AND is_active = 1 AND team_name = ?
           AND (player_type IS NULL OR player_type != 'independent')
         ORDER BY name ASC"
    );
    $stmt->execute([$clubId, $teamName]);
} else {
    $stmt = $pdo->prepare(
        "SELECT id, name, position, team_name, player_type, linked_user_id
         FROM club_players
         WHERE club_id = ? AND is_active = 1
           AND (player_type IS NULL OR player_type != 'independent')
         ORDER BY name ASC"
    );
    $stmt->execute([$clubId]);
}
$clubPlayers = $stmt->fetchAll(PDO::FETCH_ASSOC);

$players        = [];
$topPerformers  = [];
$atRiskPlayers  = [];

// Aggregation accumulators
$hSum = 0; $hCount = 0;
$rSum = 0; $rCount = 0;
$cSum = 0; $cCount = 0;
$lSum = 0;

foreach ($clubPlayers as $cp) {
    $summary = rptPlayerSummary($pdo, $cp['id'], $cp['id'], $clubId, $rangeFrom, $rangeTo);

    // At-risk logic per spec
    $avgHooper = $summary['average_hooper_30d'];
    $avgRpe    = $summary['average_post_rpe_30d'];
    $pain      = $summary['pain_reports_30d'];
    $isAtRisk  = (
        ($avgHooper !== null && $avgHooper > 14) ||
        ($pain > 0)                              ||
        ($avgRpe    !== null && $avgRpe    >= 8)
    );

    // Assessment scores are the "Assessments" report's job (report_tile
    // Assessments / TeamPerformanceReportScreen) — deliberately not repeated
    // here to avoid two reports showing the same scores.
    $row = [
        'player_id'             => $cp['id'],
        'name'                  => $cp['name'],
        'position'              => $cp['position'] ?? null,
        'avg_hooper'            => $avgHooper,
        'avg_post_rpe'          => $avgRpe,
        'completion_rate'       => $summary['completion_rate_30d'],
        'training_load_7d'      => $summary['training_load_7d'],
        'training_load_period'  => $summary['training_load_period'],
        'training_load_period_days' => $summary['training_load_period_days'],
        'status'                => $isAtRisk ? 'at_risk' : 'ready',
    ];
    $players[] = $row;

    if ($isAtRisk) $atRiskPlayers[] = $row;

    // Accumulate for team averages
    if ($avgHooper !== null) { $hSum += $avgHooper; $hCount++; }
    if ($avgRpe    !== null) { $rSum += $avgRpe;    $rCount++; }
    $cSum += $summary['completion_rate_30d'];
    $cCount++;
    $lSum += $summary['training_load_7d'];
}

$squadSize = count($players);
$teamAverages = [
    'avg_hooper'          => $hCount > 0 ? round($hSum / $hCount, 1) : null,
    'avg_post_rpe'        => $rCount > 0 ? round($rSum / $rCount, 1) : null,
    'completion_rate'     => $cCount > 0 ? round($cSum / $cCount)   : 0,
    'training_load_7d'    => $rangeFrom !== null
        ? null
        : ($squadSize > 0 ? (int)round($lSum / $squadSize) : 0),
    'training_load_period' => $squadSize > 0
        ? (int)round(array_sum(array_column($players, 'training_load_period')) / $squadSize)
        : 0,
    'training_load_period_days' => $clubPlayers
        ? (int)($players[0]['training_load_period_days'] ?? 7)
        : 7,
    'squad_size'          => $squadSize,
];

jsonOut([
    'success'         => true,
    'team_name'       => $teamName !== '' ? $teamName : null,
    'players'         => $players,
    'team_averages'   => $teamAverages,
    'top_performers'  => $topPerformers,
    'at_risk_players' => $atRiskPlayers,
    'range'           => ($rangeFrom !== null) ? ['from' => $rangeFrom, 'to' => $rangeTo] : null,
]);
