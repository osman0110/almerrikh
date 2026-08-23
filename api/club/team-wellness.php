<?php
require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/player/training-load/TrainingLoadCalculator.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';
require_once dirname(__DIR__) . '/includes/fitness/EligiblePlayerRepository.php';
require_once dirname(__DIR__) . '/includes/fitness/FitnessConfig.php';
require_once dirname(__DIR__) . '/includes/fitness/SchemaInspector.php';
require_once dirname(__DIR__) . '/includes/fitness/TrainingLoadWindowService.php';
require_once dirname(__DIR__) . '/includes/fitness/ActiveSeasonResolver.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

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
        'SELECT u.id, u.role FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);

// Role check: only club/coach/academy may view team wellness
if (in_array($user['role'], ['player', 'parent'], true)) {
    jsonOut(['error' => 'Forbidden — coaches only'], 403);
}

$ctx = requireClubPermission($pdo, $user, 'fitness.training_load.view');

// Optional custom date range (?from=YYYY-MM-DD&to=YYYY-MM-DD) — readiness,
// RPE, recovery, and the period-load KPI share this exact window. The weekly
// training-load table and ACWR retain their explicit calendar-week/trailing-
// 28-day definitions. Defaults to "today" (a single day) when not provided.
$dateRe = '/^\d{4}-\d{2}-\d{2}$/';
$from = (isset($_GET['from']) && preg_match($dateRe, $_GET['from'])) ? $_GET['from'] : FitnessConfig::today();
$to   = (isset($_GET['to'])   && preg_match($dateRe, $_GET['to']))   ? $_GET['to']   : FitnessConfig::today();
if ($from > $to) { [$from, $to] = [$to, $from]; }
$rangeStart = (new DateTimeImmutable($from . ' 00:00:00', FitnessConfig::timezone()))
    ->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');
$rangeEnd = (new DateTimeImmutable($to . ' 23:59:59', FitnessConfig::timezone()))
    ->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');

// One official population for Hooper, RPE, load and completeness. A player
// login is optional; linked_player_id is the reporting identity.
$trainingLoadRoster = EligiblePlayerRepository::activeForScope(
    $pdo,
    (int)$ctx['club_id'],
    $ctx['team_id'] ?? null
);
$linkedUserIds = array_values(array_filter(array_column($trainingLoadRoster, 'linked_user_id')));
$linkedPlayerIds = array_values(array_filter(array_column($trainingLoadRoster, 'id')));

// Training-load table stays week-based (Mon-Sun) — anchored to the end of
// the chosen range so it shows the week containing it.
$referenceDate = $to;
$playersTrainingLoad = [];
foreach ($trainingLoadRoster as $p) {
    $r = TrainingLoadCalculator::getPlayerWeeklyReport(
        $pdo, (int)($p['linked_user_id'] ?? 0), $p['id'], $referenceDate,
        TrainingLoadCalculator::DEFAULT_TIMEZONE, false
    );
    $window = TrainingLoadWindowService::build(
        $pdo,
        (int)($p['linked_user_id'] ?? 0),
        (string)$p['id'],
        $referenceDate,
        $from
    );
    $last7 = $window['last_7_days'];
    $last28 = $window['last_28_days'];
    $selectedRange = $window['selected_range'];
    $acwr = $window['acwr_details'];
    $playersTrainingLoad[] = [
        'player_id'           => $p['id'],
        'player_name'         => $p['name'],
        'position'            => $p['position'],
        'team_name'           => $p['team_name'],
        'player_photo_url'    => $p['photo_url'] ?? null,
        'weekly_load'         => $r['weekly_load'],
        'daily_mean'          => $r['daily_mean'],
        'standard_deviation'  => $r['standard_deviation'],
        'monotony'            => $r['monotony'],
        'strain'              => $r['strain'],
        'monotony_display'    => $r['monotony_display'],
        'calculation_status'  => $r['calculation_status'],
        'completeness_status' => $r['completeness_status'],
        'days'                => $r['days'], // Mon-Sun breakdown for the team training-load table
        'days_28'             => $window['days'],
        'days_range'          => $window['days_range'],
        'sessions_count_7d'   => $last7['sessions_count'],
        'total_minutes_7d'    => $last7['total_minutes'],
        'average_rpe_7d'      => $last7['average_rpe'],
        'load_7d_preliminary' => $last7['preliminary_load'],
        'load_28d_preliminary'=> $last28['preliminary_load'],
        'period_load_preliminary' => $selectedRange['preliminary_load'],
        'period_data_completeness' => $selectedRange['data_completeness'],
        'missing_rpe_count'   => $last28['missing_rpe_count'],
        'missing_duration_count' => $last28['missing_duration_count'],
        'data_completeness'   => $last28['data_completeness'],
        'acwr'                => $acwr['acwr'],
        'acwr_classification' => $acwr['classification'],
        'acwr_details'        => $acwr,
    ];
}

$activeSeason = ActiveSeasonResolver::resolve(
    $pdo,
    (int)$ctx['club_id'],
    $ctx['team_id'] ?? null
);

$emptyResponse = [
    'team_readiness_score'      => null,
    'team_readiness_preliminary'=> null,
    'injury_risk_count'         => 0,
    'average_rpe'               => null,
    'weekly_load'               => null,
    'weekly_load_preliminary'   => null,
    'period_load'               => null,
    'period_load_preliminary'   => null,
    'recovery_score'            => null,
    'players_needing_attention' => 0,
    'total_checked_in'          => 0,
    'highest_fatigue_players'   => [],
    'players_training_load'     => $playersTrainingLoad,
    'range'                     => ['from' => $from, 'to' => $to],
    'population'                => EligiblePlayerRepository::populationSummary($trainingLoadRoster, []),
    'active_season'             => $activeSeason,
];

if (empty($linkedPlayerIds)) {
    jsonOut($emptyResponse);
}

$playerIn = implode(',', array_fill(0, count($linkedPlayerIds), '?'));
$userIn = $linkedUserIds ? implode(',', array_fill(0, count($linkedUserIds), '?')) : '';
$populationScope = "(linked_player_id IN ($playerIn)";
$populationParams = $linkedPlayerIds;
if ($linkedUserIds) {
    $populationScope .= " OR (linked_player_id IS NULL AND user_id IN ($userIn))";
    $populationParams = [...$populationParams, ...$linkedUserIds];
}
$populationScope .= ')';
$activeRpeFilter = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
    ? ' AND is_active_record = 1'
    : '';

// ─ Team Readiness % (avg hooper within range, scoped to team) ───────────────
$stmt = $pdo->prepare(
    "SELECT AVG(hooper_score) as avg_hooper
     FROM player_hooper_index
     WHERE submitted_at BETWEEN ? AND ?
       AND $populationScope"
);
$stmt->execute([$rangeStart, $rangeEnd, ...$populationParams]);
$avgHooperRaw = $stmt->fetch()['avg_hooper'] ?? null;
$avgHooper = $avgHooperRaw !== null ? (float)$avgHooperRaw : null;

$teamReadiness = null;
if ($avgHooper !== null) {
    $teamReadiness = 100;
    if ($avgHooper <= 10) {
        // Normal
    } elseif ($avgHooper <= 16) {
        $teamReadiness -= 20;
    } else {
        $teamReadiness -= 40;
    }
}
if ($teamReadiness !== null) $teamReadiness = max(0, min(100, (int)$teamReadiness));

// ─ Injury Risk Count (within range, scoped to team) ─────────────────────────
$stmt = $pdo->prepare(
    "SELECT COUNT(DISTINCT user_id) as count
     FROM player_hooper_index
     WHERE hooper_score >= 17
       AND submitted_at BETWEEN ? AND ?
       AND $populationScope"
);
$stmt->execute([$rangeStart, $rangeEnd, ...$populationParams]);
$injuryRiskCount = (int)($stmt->fetch()['count'] ?? 0);

// ─ Average RPE (within range, scoped to team) ───────────────────────────────
$stmt = $pdo->prepare(
    "SELECT AVG(rpe_score) as avg_rpe FROM player_rpe
     WHERE submitted_at BETWEEN ? AND ? AND $populationScope$activeRpeFilter"
);
$stmt->execute([$rangeStart, $rangeEnd, ...$populationParams]);
$avgRpeRaw = $stmt->fetch()['avg_rpe'] ?? null;
$avgRpe = $avgRpeRaw !== null ? (float)$avgRpeRaw : null;

// ─ Total Load (within range, scoped to team) ────────────────────────────────
$weeklyLoadPreliminary = array_sum(array_map(
    fn(array $row) => (float)$row['weekly_load'],
    $playersTrainingLoad
));
$teamLoadApprovable = !empty($playersTrainingLoad)
    && count(array_filter(
        $playersTrainingLoad,
        fn(array $row) => $row['completeness_status'] === 'COMPLETE'
    )) === count($playersTrainingLoad);
$weeklyLoad = $teamLoadApprovable ? $weeklyLoadPreliminary : null;

// The KPI follows the selected range. `weekly_load` above remains the
// calendar-week (Mon-Sun) value used by the weekly training-load table.
$periodLoadPreliminary = array_sum(array_map(
    fn(array $row) => (float)$row['period_load_preliminary'],
    $playersTrainingLoad
));
$periodLoadApprovable = !empty($playersTrainingLoad)
    && count(array_filter(
        $playersTrainingLoad,
        fn(array $row) => $row['period_data_completeness'] === 1.0
    )) === count($playersTrainingLoad);
$periodLoad = $periodLoadApprovable ? $periodLoadPreliminary : null;

// ─ Recovery Score (% of team with good hooper, within range) ───────────────
$stmt = $pdo->prepare(
    "SELECT COUNT(DISTINCT user_id) as total
     FROM player_hooper_index
     WHERE submitted_at BETWEEN ? AND ?
       AND $populationScope"
);
$stmt->execute([$rangeStart, $rangeEnd, ...$populationParams]);
$totalCheckedIn = (int)($stmt->fetch()['total'] ?? 0);

$stmt = $pdo->prepare(
    "SELECT COUNT(DISTINCT user_id) as recovered
     FROM player_hooper_index
     WHERE submitted_at BETWEEN ? AND ?
       AND hooper_score <= 10
       AND $populationScope"
);
$stmt->execute([$rangeStart, $rangeEnd, ...$populationParams]);
$recoveredCount = (int)($stmt->fetch()['recovered'] ?? 0);

$recoveryScore = $totalCheckedIn > 0 ? round(($recoveredCount / $totalCheckedIn) * 100) : null;

// ─ Players Needing Attention (within range, scoped to team) ─────────────────
$stmt = $pdo->prepare(
    "SELECT COUNT(DISTINCT user_id) as cnt
     FROM player_hooper_index
     WHERE submitted_at BETWEEN ? AND ?
       AND (hooper_score >= 17 OR fatigue >= 6 OR sleep_quality <= 2)
       AND $populationScope"
);
$stmt->execute([$rangeStart, $rangeEnd, ...$populationParams]);
$playersNeedingAttention = (int)($stmt->fetch()['cnt'] ?? 0);

// ─ Highest Fatigue (within range, scoped to team) ───────────────────────────
$stmt = $pdo->prepare(
    "SELECT user_id, linked_player_id, fatigue
     FROM player_hooper_index
     WHERE submitted_at BETWEEN ? AND ?
       AND $populationScope
     ORDER BY fatigue DESC LIMIT 5"
);
$stmt->execute([$rangeStart, $rangeEnd, ...$populationParams]);
$highestFatigue = $stmt->fetchAll();

$submittedStmt = $pdo->prepare(
    "SELECT DISTINCT linked_player_id, user_id
     FROM player_hooper_index
     WHERE submitted_at BETWEEN ? AND ? AND $populationScope"
);
$submittedStmt->execute([$rangeStart, $rangeEnd, ...$populationParams]);
$userToPlayer = [];
foreach ($trainingLoadRoster as $player) {
    if (!empty($player['linked_user_id'])) $userToPlayer[(int)$player['linked_user_id']] = $player['id'];
}
$submittedPlayerIds = [];
foreach ($submittedStmt->fetchAll() as $submitted) {
    $submittedPlayerIds[] = $submitted['linked_player_id']
        ?: ($userToPlayer[(int)$submitted['user_id']] ?? null);
}
$population = EligiblePlayerRepository::populationSummary($trainingLoadRoster, $submittedPlayerIds);
$teamReadinessPreliminary = $teamReadiness;
if ($population['missing_players'] > 0) {
    $teamReadiness = null;
}

// $playersTrainingLoad was already computed above (broader roster, not
// gated by linked_user_id) — reused here as-is.

jsonOut([
    'team_readiness_score'      => $teamReadiness,
    'team_readiness_preliminary'=> $teamReadinessPreliminary,
    'injury_risk_count'         => $injuryRiskCount,
    'average_rpe'               => $avgRpe !== null ? round($avgRpe, 2) : null,
    'weekly_load'               => $weeklyLoad,
    'weekly_load_preliminary'   => $weeklyLoadPreliminary,
    'period_load'               => $periodLoad,
    'period_load_preliminary'   => $periodLoadPreliminary,
    'recovery_score'            => $recoveryScore !== null ? (int)$recoveryScore : null,
    'players_needing_attention' => $playersNeedingAttention,
    'total_checked_in'          => $totalCheckedIn,
    'highest_fatigue_players'   => $highestFatigue,
    'players_training_load'     => $playersTrainingLoad,
    'range'                     => ['from' => $from, 'to' => $to],
    'population'                => $population,
    'active_season'             => $activeSeason,
]);
