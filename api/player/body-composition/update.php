<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/audit_log.php';
require_once dirname(__DIR__, 2) . '/includes/body_composition_calculator.php';
require_once __DIR__ . '/_helpers.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonError('Method not allowed', 405);

$user = getAuthUser($pdo);
$body = json_decode(file_get_contents('php://input'), true) ?? [];
$ctx = requireClubPermission($pdo, $user, 'fitness.body_composition.update');

$id = trim((string)($body['id'] ?? ''));
if (!$id) jsonOut(['error' => 'id is required'], 400);

$rowStmt = $pdo->prepare('SELECT * FROM player_body_composition_assessments WHERE id = ? AND deleted_at IS NULL');
$rowStmt->execute([$id]);
$existing = $rowStmt->fetch(PDO::FETCH_ASSOC);
if (!$existing) jsonOut(['error' => 'Assessment not found'], 404);
if ((int)$existing['club_id'] !== (int)$ctx['club_id']) jsonOut(['error' => 'Forbidden'], 403);
if (($ctx['team_id'] ?? null) !== null) {
    $teamStmt = $pdo->prepare('SELECT team_id FROM club_players WHERE id = ? AND club_id = ?');
    $teamStmt->execute([$existing['linked_player_id'], $ctx['club_id']]);
    if ((int)$teamStmt->fetchColumn() !== (int)$ctx['team_id']) jsonOut(['error' => 'Forbidden'], 403);
}
// No separate approval workflow — this endpoint already requires
// fitness.body_composition.update, i.e. only a coach/staff member can
// reach it, so an edit doesn't need to be re-approved by anyone else.
$reason = isset($body['reason']) ? trim(substr((string)$body['reason'], 0, 500)) : '';

$weight = isset($body['weight_kg']) ? (float)$body['weight_kg'] : (float)$existing['weight_kg'];
$height = isset($body['height_cm']) ? (float)$body['height_cm'] : (float)$existing['height_cm'];
if ($weight < 20 || $weight > 250) jsonOut(['error' => 'weight_kg must be 20–250'], 400);
if ($height < 100 || $height > 230) jsonOut(['error' => 'height_cm must be 100–230'], 400);

$assessmentDate = isset($body['assessment_date']) ? (string)$body['assessment_date'] : $existing['assessment_date'];
if (!bcValidDate($assessmentDate)) jsonOut(['error' => 'assessment_date must be YYYY-MM-DD'], 400);
$assessmentTime = array_key_exists('assessment_time', $body) ? substr((string)$body['assessment_time'], 0, 5) : $existing['assessment_time'];

$allowedTypes = ['periodic', 'season_start', 'season_end', 'camp_start', 'camp_end', 'pre_injury', 'post_injury'];
$assessmentType = isset($body['assessment_type']) && in_array($body['assessment_type'], $allowedTypes, true)
    ? $body['assessment_type'] : $existing['assessment_type'];

$sites = ['biceps', 'triceps', 'subscapular', 'suprailiac'];
$siteValues = [];
$warnings = [];
$skinfoldSum = 0.0;
$anySite = false;

foreach ($sites as $site) {
    $get = function (string $key, $fallback) use ($body) {
        return array_key_exists($key, $body) ? (($body[$key] === null) ? null : (float)$body[$key]) : $fallback;
    };
    $a1 = $get("{$site}_attempt_1_mm", $existing["{$site}_attempt_1_mm"] !== null ? (float)$existing["{$site}_attempt_1_mm"] : null);
    $a2 = $get("{$site}_attempt_2_mm", $existing["{$site}_attempt_2_mm"] !== null ? (float)$existing["{$site}_attempt_2_mm"] : null);
    $a3 = $get("{$site}_attempt_3_mm", $existing["{$site}_attempt_3_mm"] !== null ? (float)$existing["{$site}_attempt_3_mm"] : null);
    foreach ([$a1, $a2, $a3] as $v) {
        if (!bc_attempt_valid($v)) jsonOut(['error' => "$site attempts must be 2–60mm"], 400);
    }
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

$age = isset($body['age_years']) ? (int)$body['age_years'] : ($existing['age_at_assessment'] !== null ? (int)$existing['age_at_assessment'] : null);
if ($age === null && !empty($existing['linked_player_id'])) {
    $pStmt = $pdo->prepare('SELECT date_of_birth FROM club_players WHERE id = ?');
    $pStmt->execute([$existing['linked_player_id']]);
    $dob = $pStmt->fetchColumn();
    if ($dob) $age = bc_calc_age($dob, $assessmentDate);
}

$measurementMethod = strtolower(trim((string)(
    $body['measurement_method']
    ?? $existing['measurement_method']
    ?? 'skinfold'
)));
$deviceName = array_key_exists('device_name', $body)
    ? substr(trim((string)$body['device_name']), 0, 100)
    : ($existing['device_name'] ?? null);
$isExternalMeasurement = $measurementMethod !== 'skinfold';

$bodyFatPercentage = null; $formulaCode = null; $ageGroup = null; $formulaVersion = null;
$calculationStatus = BC_CALC_INCOMPLETE_SKINFOLD;
$measurementCompleteness = 0.0;
$missingSites = BC_DEFAULT_REQUIRED_SITES;
if ($isExternalMeasurement) {
    $bodyFatPercentage = isset($body['body_fat_percentage'])
        ? (float)$body['body_fat_percentage']
        : ($existing['body_fat_percentage'] !== null ? (float)$existing['body_fat_percentage'] : null);
    if ($bodyFatPercentage === null || $bodyFatPercentage < 1 || $bodyFatPercentage > 70) {
        jsonOut(['error' => 'body_fat_percentage must be 1–70 for an external measurement'], 400);
    }
    if (!$deviceName) jsonOut(['error' => 'device_name is required for an external measurement'], 400);
    $skinfoldSum = null;
    $calculationStatus = BC_CALC_COMPLETE;
    $measurementCompleteness = 1.0;
    $missingSites = [];
} elseif ($age !== null) {
    $formula = bc_select_formula($pdo, $age, 'male');
    $averages = [];
    foreach ($siteValues as $site => $values) $averages[$site] = $values['avg'];
    $completeness = bc_skinfold_completeness($averages, $formula);
    $calculationStatus = $completeness['status'];
    $measurementCompleteness = $completeness['measurement_completeness'];
    $missingSites = $completeness['missing_sites'];
    if ($calculationStatus === BC_CALC_COMPLETE) {
        $skinfoldSum = round(array_sum(array_map(
            fn(string $site) => (float)$averages[$site],
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
} else {
    $calculationStatus = 'AGE_REQUIRED';
    $skinfoldSum = null;
    $warnings[] = 'Age unknown — cannot calculate body fat % (missing date of birth)';
}

$bmi = bc_bmi($weight, $height);
$fatMassKg = $bodyFatPercentage !== null ? bc_fat_mass_kg($weight, $bodyFatPercentage) : null;
$fatFreeMassKg = $fatMassKg !== null ? bc_fat_free_mass_kg($weight, $fatMassKg) : null;

$notes = array_key_exists('notes', $body) ? substr((string)$body['notes'], 0, 1000) : $existing['notes'];

$pdo->prepare(
    'INSERT INTO body_composition_revisions
     (assessment_id, revision_number, old_values_json, new_values_json, reason, changed_by)
     SELECT ?, COALESCE(MAX(revision_number), 0) + 1, ?, ?, ?, ?
     FROM body_composition_revisions WHERE assessment_id = ?'
)->execute([
    $id,
    json_encode($existing, JSON_UNESCAPED_UNICODE),
    json_encode([
        'weight_kg' => $weight,
        'body_fat_percentage' => $bodyFatPercentage,
        'calculation_status' => $calculationStatus,
        'approval_status' => 'approved',
    ], JSON_UNESCAPED_UNICODE),
    $reason ?: null,
    (int)$user['id'],
    $id,
]);

$pdo->prepare(
    'UPDATE player_body_composition_assessments SET
     assessment_date = ?, assessment_time = ?, assessment_type = ?, height_cm = ?, weight_kg = ?, age_at_assessment = ?,
     biceps_attempt_1_mm = ?, biceps_attempt_2_mm = ?, biceps_attempt_3_mm = ?, biceps_mm = ?,
     triceps_attempt_1_mm = ?, triceps_attempt_2_mm = ?, triceps_attempt_3_mm = ?, triceps_mm = ?,
     subscapular_attempt_1_mm = ?, subscapular_attempt_2_mm = ?, subscapular_attempt_3_mm = ?, subscapular_mm = ?,
     suprailiac_attempt_1_mm = ?, suprailiac_attempt_2_mm = ?, suprailiac_attempt_3_mm = ?, suprailiac_mm = ?,
     skinfold_sum_mm = ?, calculation_formula_code = ?, calculation_age_group = ?,
     body_fat_percentage = ?, fat_mass_kg = ?, fat_free_mass_kg = ?, bmi = ?,
     approval_status = \'approved\', approved_by = ?, approved_at = ?,
     calculation_status = ?, measurement_completeness = ?, missing_sites_json = ?,
     formula_version = ?, measurement_method = ?, device_name = ?, notes = ?, updated_by = ?
     WHERE id = ?'
)->execute([
    $assessmentDate, $assessmentTime, $assessmentType, $height, $weight, $age,
    $siteValues['biceps']['a1'], $siteValues['biceps']['a2'], $siteValues['biceps']['a3'], $siteValues['biceps']['avg'],
    $siteValues['triceps']['a1'], $siteValues['triceps']['a2'], $siteValues['triceps']['a3'], $siteValues['triceps']['avg'],
    $siteValues['subscapular']['a1'], $siteValues['subscapular']['a2'], $siteValues['subscapular']['a3'], $siteValues['subscapular']['avg'],
    $siteValues['suprailiac']['a1'], $siteValues['suprailiac']['a2'], $siteValues['suprailiac']['a3'], $siteValues['suprailiac']['avg'],
    $skinfoldSum, $formulaCode, $ageGroup,
    $bodyFatPercentage, $fatMassKg, $fatFreeMassKg, $bmi,
    (int)$user['id'], (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format('Y-m-d H:i:s'),
    $calculationStatus, $measurementCompleteness, json_encode($missingSites), $formulaVersion,
    $measurementMethod, $deviceName, $notes, (int)$user['id'],
    $id,
]);

logAuditDiff($pdo, 'player_body_composition_assessments', $id, $existing, [
    'weight_kg' => $weight, 'body_fat_percentage' => $bodyFatPercentage, 'notes' => $notes,
], (int)$user['id']);
logFitnessAudit(
    $pdo,
    'player_body_composition_assessments',
    $id,
    'body_composition.updated',
    (int)$user['id'],
    (int)$ctx['club_id'],
    $existing['linked_player_id'],
    $existing,
    [
        'weight_kg' => $weight,
        'body_fat_percentage' => $bodyFatPercentage,
        'calculation_status' => $calculationStatus,
        'approval_status' => 'approved',
        'measurement_method' => $measurementMethod,
    ],
    $reason ?: null
);

jsonOut([
    'success' => true, 'id' => $id,
    'skinfold_sum_mm' => $skinfoldSum,
    'body_fat_percentage' => $bodyFatPercentage,
    'calculation_status' => $calculationStatus,
    'measurement_completeness' => $measurementCompleteness,
    'missing_sites' => $missingSites,
    'approval_status' => 'approved',
    'measurement_method' => $measurementMethod,
    'fat_mass_kg' => $fatMassKg,
    'fat_free_mass_kg' => $fatFreeMassKg,
    'bmi' => $bmi,
    'warnings' => $warnings,
]);
