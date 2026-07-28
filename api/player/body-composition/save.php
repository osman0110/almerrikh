<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/audit_log.php';
require_once dirname(__DIR__, 2) . '/includes/body_composition_calculator.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/FitnessConfig.php';
require_once __DIR__ . '/_helpers.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonError('Method not allowed', 405);

$user = getAuthUser($pdo);
$body = json_decode(file_get_contents('php://input'), true) ?? [];

$scope = resolvePlayerScope(
    $pdo,
    $user,
    $body,
    true,
    'fitness.body_composition.create'
);
$linkedPlayerId = $scope['linkedPlayerId'];
$clubId         = $scope['clubId'];
$recordedBy     = $scope['recordedBy'];
$player         = $scope['player'];

$weight = isset($body['weight_kg']) ? (float)$body['weight_kg'] : null;
$height = isset($body['height_cm']) ? (float)$body['height_cm']
    : (($player['height_cm'] ?? null) !== null ? (float)$player['height_cm'] : null);

if ($weight === null) jsonOut(['error' => 'weight_kg is required'], 400);
if ($height === null) jsonOut(['error' => 'height_cm is required (no height on file for this player)'], 400);
if ($weight < 20 || $weight > 250) jsonOut(['error' => 'weight_kg must be 20–250'], 400);
if ($height < 100 || $height > 230) jsonOut(['error' => 'height_cm must be 100–230'], 400);

$assessmentDate = isset($body['assessment_date']) ? (string)$body['assessment_date'] : FitnessConfig::today();
if (!bcValidDate($assessmentDate)) jsonOut(['error' => 'assessment_date must be YYYY-MM-DD'], 400);
$assessmentTime = isset($body['assessment_time']) ? substr((string)$body['assessment_time'], 0, 5) : null;

$allowedTypes = ['periodic', 'season_start', 'season_end', 'camp_start', 'camp_end', 'pre_injury', 'post_injury'];
$assessmentType = isset($body['assessment_type']) && in_array($body['assessment_type'], $allowedTypes, true)
    ? $body['assessment_type'] : 'periodic';

// ── Skinfolds: up to 3 attempts per site, averaged server-side ──────────────
function bcReadSite(array $body, string $site): array {
    $get = fn($k) => isset($body[$k]) ? (float)$body[$k] : null;
    $a1 = $get("{$site}_attempt_1_mm");
    $a2 = $get("{$site}_attempt_2_mm");
    $a3 = $get("{$site}_attempt_3_mm");
    foreach ([$a1, $a2, $a3] as $v) {
        if (!bc_attempt_valid($v)) jsonOut(['error' => "$site attempts must be 2–60mm"], 400);
    }
    return [$a1, $a2, $a3];
}

$sites = ['biceps', 'triceps', 'subscapular', 'suprailiac'];
$siteValues = [];
$warnings = [];
$skinfoldSum = 0.0;
$anySite = false;

foreach ($sites as $site) {
    [$a1, $a2, $a3] = bcReadSite($body, $site);
    $avg = bc_average_attempts($a1, $a2, $a3);
    if ($avg !== null) {
        $anySite = true;
        $skinfoldSum += $avg;
        if (bc_attempt_spread_flag($a1, $a2, $a3)) {
            $warnings[] = "$site attempts differ by more than " . BC_ATTEMPT_SPREAD_LIMIT_MM . "mm — consider re-measuring";
        }
    }
    $siteValues[$site] = ['a1' => $a1, 'a2' => $a2, 'a3' => $a3, 'avg' => $avg];
}

$skinfoldSum = $anySite ? round($skinfoldSum, 1) : null;

// ── Age + formula selection ─────────────────────────────────────────────────
$age = null;
if (!empty($player['date_of_birth'])) {
    $age = bc_calc_age($player['date_of_birth'], $assessmentDate);
}
if ($age === null && isset($body['age_years'])) $age = (int)$body['age_years'];

$measurementMethod = strtolower(trim((string)($body['measurement_method'] ?? 'skinfold')));
$isExternalMeasurement = $measurementMethod !== 'skinfold';
$deviceName = isset($body['device_name']) ? substr(trim((string)$body['device_name']), 0, 100) : null;

$bodyFatPercentage = null;
$formulaCode = null;
$ageGroup = null;
$formulaVersion = null;
$calculationStatus = BC_CALC_INCOMPLETE_SKINFOLD;
$measurementCompleteness = 0.0;
$missingSites = BC_DEFAULT_REQUIRED_SITES;

if ($isExternalMeasurement) {
    if (!isset($body['body_fat_percentage'])) {
        jsonOut(['error' => 'body_fat_percentage is required for an external measurement'], 400);
    }
    if (!$deviceName) {
        jsonOut(['error' => 'device_name is required for an external measurement'], 400);
    }
    $bodyFatPercentage = (float)$body['body_fat_percentage'];
    if ($bodyFatPercentage < 1 || $bodyFatPercentage > 70) {
        jsonOut(['error' => 'body_fat_percentage must be 1–70'], 400);
    }
    $calculationStatus = BC_CALC_COMPLETE;
    $measurementCompleteness = 1.0;
    $missingSites = [];
} elseif ($age !== null) {
    $formula = bc_select_formula($pdo, $age, 'male');
    $siteAverages = [];
    foreach ($siteValues as $site => $values) $siteAverages[$site] = $values['avg'];
    $completeness = bc_skinfold_completeness($siteAverages, $formula);
    $calculationStatus = $completeness['status'];
    $measurementCompleteness = $completeness['measurement_completeness'];
    $missingSites = $completeness['missing_sites'];

    if ($calculationStatus === BC_CALC_COMPLETE) {
        $skinfoldSum = round(array_sum(array_map(
            fn(string $site) => (float)$siteAverages[$site],
            $completeness['required_sites']
        )), 1);
        $calc = bc_calculate_body_fat($pdo, $skinfoldSum, $age, 'male');
        if (isset($calc['error'])) {
            $calculationStatus = 'UNSUPPORTED_FORMULA';
            $warnings[] = $calc['error'];
        } else {
            $bodyFatPercentage = $calc['body_fat_percentage'];
            $formulaCode = $calc['formula_code'];
            $ageGroup = $calc['age_group'];
            $formulaVersion = $calc['formula_version'];
        }
    } else {
        $skinfoldSum = null;
    }
} elseif ($skinfoldSum !== null) {
    if ($age === null) {
        $warnings[] = 'Age unknown — cannot calculate body fat % (missing date of birth)';
        $calculationStatus = 'AGE_REQUIRED';
    }
}

if ($missingSites) {
    $warnings[] = 'Incomplete skinfold: ' . implode(', ', $missingSites);
}

// The coach is the one taking the measurement, so there is no separate
// reviewer to approve it against — a coach-recorded assessment is final
// the moment it's saved. Only a player's own self-entry (no coach in the
// loop) still lands as a draft pending someone else's review.
$approvalStatus = $scope['isCoach'] ? 'approved' : 'draft';
$approvedBy = $approvalStatus === 'approved' ? (int)$user['id'] : null;
$approvedAt = $approvalStatus === 'approved'
    ? (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format('Y-m-d H:i:s')
    : null;

$bmi = bc_bmi($weight, $height);
$fatMassKg = $bodyFatPercentage !== null ? bc_fat_mass_kg($weight, $bodyFatPercentage) : null;
$fatFreeMassKg = $fatMassKg !== null ? bc_fat_free_mass_kg($weight, $fatMassKg) : null;

$notes = isset($body['notes']) ? substr((string)$body['notes'], 0, 1000) : null;
$assessedBy = isset($body['assessed_by']) ? substr((string)$body['assessed_by'], 0, 255) : ($scope['isCoach'] ? $user['name'] : null);

$id = bin2hex(random_bytes(16));

$stmt = $pdo->prepare(
    'INSERT INTO player_body_composition_assessments
     (id, user_id, club_id, linked_player_id, recorded_by, team_name, position,
      assessment_date, assessment_time, assessment_type, height_cm, weight_kg, age_at_assessment,
      biceps_attempt_1_mm, biceps_attempt_2_mm, biceps_attempt_3_mm, biceps_mm,
      triceps_attempt_1_mm, triceps_attempt_2_mm, triceps_attempt_3_mm, triceps_mm,
      subscapular_attempt_1_mm, subscapular_attempt_2_mm, subscapular_attempt_3_mm, subscapular_mm,
      suprailiac_attempt_1_mm, suprailiac_attempt_2_mm, suprailiac_attempt_3_mm, suprailiac_mm,
      skinfold_sum_mm, calculation_formula_code, calculation_age_group,
      body_fat_percentage, fat_mass_kg, fat_free_mass_kg, bmi,
      measurement_method, device_name, approval_status, approved_by, approved_at,
      calculation_status, measurement_completeness, missing_sites_json, formula_version,
      notes, assessed_by, created_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
);
$stmt->execute([
    $id, $user['id'], $clubId, $linkedPlayerId, $recordedBy,
    $player['team_name'] ?? null, $player['position'] ?? null,
    $assessmentDate, $assessmentTime, $assessmentType, $height, $weight, $age,
    $siteValues['biceps']['a1'], $siteValues['biceps']['a2'], $siteValues['biceps']['a3'], $siteValues['biceps']['avg'],
    $siteValues['triceps']['a1'], $siteValues['triceps']['a2'], $siteValues['triceps']['a3'], $siteValues['triceps']['avg'],
    $siteValues['subscapular']['a1'], $siteValues['subscapular']['a2'], $siteValues['subscapular']['a3'], $siteValues['subscapular']['avg'],
    $siteValues['suprailiac']['a1'], $siteValues['suprailiac']['a2'], $siteValues['suprailiac']['a3'], $siteValues['suprailiac']['avg'],
    $skinfoldSum, $formulaCode, $ageGroup,
    $bodyFatPercentage, $fatMassKg, $fatFreeMassKg, $bmi,
    $measurementMethod, $deviceName, $approvalStatus, $approvedBy, $approvedAt,
    $calculationStatus, $measurementCompleteness, json_encode($missingSites),
    $formulaVersion, $notes, $assessedBy, (int)$user['id'],
]);

logAuditDiff($pdo, 'player_body_composition_assessments', $id, null, [
    'weight_kg' => $weight, 'body_fat_percentage' => $bodyFatPercentage,
], (int)$user['id']);
logFitnessAudit(
    $pdo,
    'player_body_composition_assessments',
    $id,
    'body_composition.created',
    (int)$user['id'],
    $clubId !== null ? (int)$clubId : null,
    $linkedPlayerId,
    null,
    [
        'approval_status' => $approvalStatus,
        'calculation_status' => $calculationStatus,
        'measurement_method' => $measurementMethod,
    ],
    isset($body['reason']) ? substr((string)$body['reason'], 0, 500) : null
);

// Deltas vs. the previous assessment (if any) for this player
$prevStmt = $pdo->prepare(
    'SELECT weight_kg, body_fat_percentage, fat_mass_kg, fat_free_mass_kg, skinfold_sum_mm, assessment_date
     FROM player_body_composition_assessments
     WHERE deleted_at IS NULL AND id != ? AND ' . ($linkedPlayerId ? 'linked_player_id = ?' : 'user_id = ?') . '
     ORDER BY assessment_date DESC, created_at DESC LIMIT 1'
);
$prevStmt->execute([$id, $linkedPlayerId ?: $user['id']]);
$prev = $prevStmt->fetch(PDO::FETCH_ASSOC) ?: null;

$deltas = null;
if ($prev) {
    $mk = fn($cur, $prevVal) => ($cur === null || $prevVal === null) ? null : round($cur - (float)$prevVal, 2);
    $deltas = [
        'weight_kg'            => $mk($weight, $prev['weight_kg']),
        'body_fat_percentage'  => $mk($bodyFatPercentage, $prev['body_fat_percentage']),
        'fat_mass_kg'          => $mk($fatMassKg, $prev['fat_mass_kg']),
        'fat_free_mass_kg'     => $mk($fatFreeMassKg, $prev['fat_free_mass_kg']),
        'skinfold_sum_mm'      => $mk($skinfoldSum, $prev['skinfold_sum_mm']),
        'previous_date'        => $prev['assessment_date'],
    ];
}

// Goal comparison
$goalStmt = $pdo->prepare('SELECT * FROM player_body_composition_goals WHERE linked_player_id = ? LIMIT 1');
$goalStmt->execute([$linkedPlayerId]);
$goal = $goalStmt->fetch(PDO::FETCH_ASSOC) ?: null;
$goalStatus = $linkedPlayerId ? bcGoalStatus($goal, $bodyFatPercentage, $assessmentDate) : null;

jsonOut([
    'success' => true,
    'id' => $id,
    'assessment_date' => $assessmentDate,
    'age_at_assessment' => $age,
    'skinfold_sum_mm' => $skinfoldSum,
    'calculation_formula_code' => $formulaCode,
    'calculation_age_group' => $ageGroup,
    'formula_version' => $formulaVersion,
    'calculation_status' => $calculationStatus,
    'measurement_completeness' => $measurementCompleteness,
    'missing_sites' => $missingSites,
    'approval_status' => $approvalStatus,
    'measurement_method' => $measurementMethod,
    'body_fat_percentage' => $bodyFatPercentage,
    'fat_mass_kg' => $fatMassKg,
    'fat_free_mass_kg' => $fatFreeMassKg,
    'bmi' => $bmi,
    'warnings' => $warnings,
    'deltas' => $deltas,
    'goal_status' => $goalStatus,
]);
