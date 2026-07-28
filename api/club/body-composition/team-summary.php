<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/club_auth.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/BodyCompositionRepository.php';
require_once dirname(__DIR__, 2) . '/player/body-composition/_helpers.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$user = getAuthUser($pdo);
if (in_array($user['role'], ['player', 'parent'], true)) jsonOut(['error' => 'Forbidden — coaches only'], 403);

// Scoped by club_id (a club has many staff/coaches sharing the same roster),
// not by the requesting coach's own user_id — a club_players/assessments row
// belongs to the club, never to a single coach.
$ctx = requireClubPermission($pdo, $user, 'fitness.body_composition.view');
$clubId = $ctx['club_id'];
$teamId = $ctx['team_id'] ?? null;

// Roster size (active players)
$rosterSql = 'SELECT COUNT(*) FROM club_players WHERE club_id = ? AND is_active = 1';
$rosterParams = [$clubId];
if ($teamId !== null) {
    $rosterSql .= ' AND team_id = ?';
    $rosterParams[] = $teamId;
}
$rosterStmt = $pdo->prepare($rosterSql);
$rosterStmt->execute($rosterParams);
$rosterSize = (int)$rosterStmt->fetchColumn();

// Unified source: approved new-system assessment first, legacy fallback only
// when the player has no approved new-system assessment.
$latestRows = BodyCompositionRepository::latestUnifiedForClub($pdo, $clubId, $teamId);

$measuredThisMonth = 0;
$monthStart = date('Y-m-01');
foreach ($latestRows as $row) {
    if (substr((string)$row['measured_at'], 0, 10) >= $monthStart) $measuredThisMonth++;
}

$overdueThresholdDays = 90; // "overdue" = no measurement in the last 90 days
$overdueCutoff = date('Y-m-d', strtotime("-$overdueThresholdDays days"));
$measuredPlayerIds = array_column($latestRows, 'linked_player_id');
$overdueCount = $rosterSize - count($measuredPlayerIds);
foreach ($latestRows as $row) {
    if (substr((string)$row['measured_at'], 0, 10) < $overdueCutoff) $overdueCount++;
}

$avg = fn(string $field) => (function () use ($latestRows, $field) {
    $vals = array_filter(array_map(fn($r) => $r[$field] !== null ? (float)$r[$field] : null, $latestRows), fn($v) => $v !== null);
    return $vals ? round(array_sum($vals) / count($vals), 2) : null;
})();

$avgWeight = $avg('weight_kg');
$avgBodyFat = $avg('body_fat_percentage');
$avgFatMass = $avg('fat_mass_kg');
$avgLeanMass = $avg('fat_free_mass_kg');
$avgMuscleMass = $avg('muscle_mass_kg');

// Goals + status per measured player
$linkedIds = array_values(array_unique(array_filter($measuredPlayerIds)));
$goalsByPlayer = [];
if ($linkedIds) {
    $in = implode(',', array_fill(0, count($linkedIds), '?'));
    $gStmt = $pdo->prepare("SELECT * FROM player_body_composition_goals WHERE linked_player_id IN ($in)");
    $gStmt->execute($linkedIds);
    foreach ($gStmt->fetchAll(PDO::FETCH_ASSOC) as $g) $goalsByPlayer[$g['linked_player_id']] = $g;
}

$inGoalCount = 0;
$needsFollowUpCount = 0;
foreach ($latestRows as $row) {
    $goal = $goalsByPlayer[$row['linked_player_id']] ?? null;
    if (!$goal) continue;
    $status = bcGoalStatus(
        $goal,
        $row['body_fat_percentage'] !== null ? (float)$row['body_fat_percentage'] : null,
        substr((string)$row['measured_at'], 0, 10)
    );
    if (($status['status'] ?? null) === 'on_track' || ($status['status'] ?? null) === 'achieved') $inGoalCount++;
    if (($status['status'] ?? null) === 'needs_follow_up') $needsFollowUpCount++;
}

// Biggest improvement / regression this period — compares each player's
// latest vs. their previous assessment's body fat %.
$biggestImprovement = null;
$biggestRegression = null;
// Approval gating removed — a coach-recorded measurement is usable in
// reports the moment it's saved, no separate approval step.
$approvedHistoryFilter = '';
foreach ($latestRows as $row) {
    if ($row['body_fat_percentage'] === null) continue;
    if ($row['source_system'] !== 'NEW_SYSTEM') continue;
    $prevStmt = $pdo->prepare(
        'SELECT body_fat_percentage FROM player_body_composition_assessments
         WHERE linked_player_id = ? AND deleted_at IS NULL AND id != ?' . $approvedHistoryFilter . '
         ORDER BY assessment_date DESC, created_at DESC LIMIT 1'
    );
    $prevStmt->execute([$row['linked_player_id'], $row['id']]);
    $prevBf = $prevStmt->fetchColumn();
    if ($prevBf === false || $prevBf === null) continue;

    $diff = round((float)$row['body_fat_percentage'] - (float)$prevBf, 2);
    $entry = ['linked_player_id' => $row['linked_player_id'], 'player_name' => $row['assessed_by'], 'diff' => $diff];

    if ($diff < 0 && ($biggestImprovement === null || $diff < $biggestImprovement['diff'])) $biggestImprovement = $entry;
    if ($diff > 0 && ($biggestRegression === null || $diff > $biggestRegression['diff'])) $biggestRegression = $entry;
}

// Attach player names for the biggest-change entries (assessed_by isn't the player name)
foreach ([&$biggestImprovement, &$biggestRegression] as &$entry) {
    if ($entry) {
        $nStmt = $pdo->prepare('SELECT name FROM club_players WHERE id = ?');
        $nStmt->execute([$entry['linked_player_id']]);
        $entry['player_name'] = $nStmt->fetchColumn() ?: null;
    }
}
unset($entry);

jsonOut([
    'roster_size' => $rosterSize,
    'measured_this_month' => $measuredThisMonth,
    'overdue_count' => max(0, $overdueCount),
    'avg_weight_kg' => $avgWeight,
    'avg_body_fat_percentage' => $avgBodyFat,
    'avg_fat_mass_kg' => $avgFatMass,
    'avg_fat_free_mass_kg' => $avgLeanMass,
    'avg_muscle_mass_kg' => $avgMuscleMass,
    'measurement_source_policy' => 'APPROVED_NEW_THEN_LEGACY_FALLBACK',
    'in_goal_count' => $inGoalCount,
    'needs_follow_up_count' => $needsFollowUpCount,
    'biggest_improvement' => $biggestImprovement,
    'biggest_regression' => $biggestRegression,
]);
