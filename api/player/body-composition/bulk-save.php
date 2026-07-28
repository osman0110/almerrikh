<?php
// Commits rows already parsed and player-matched client-side (see
// lib/screens/club/body_composition_bulk_import_page.dart) — this endpoint
// re-validates everything server-side (never trusts the client's math) and
// applies the same calculation core as save.php so a bulk-imported row and
// a manually-entered row are indistinguishable in the database.
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/audit_log.php';
require_once dirname(__DIR__, 2) . '/includes/body_composition_calculator.php';
require_once dirname(__DIR__, 2) . '/includes/club_auth.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/FitnessConfig.php';
require_once __DIR__ . '/_helpers.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonError('Method not allowed', 405);

$user = getAuthUser($pdo);
if (in_array($user['role'], ['player', 'parent'], true)) jsonOut(['error' => 'Forbidden — coaches only'], 403);
// Scoped by club_id — a roster player belongs to the whole club, shared
// across every coach/staff member, not to whichever coach is logged in.
$ctx = requireClubPermission($pdo, $user, 'fitness.body_composition.import');

$body = json_decode(file_get_contents('php://input'), true) ?? [];
$rows = $body['rows'] ?? [];
if (!is_array($rows) || !$rows) jsonOut(['error' => 'rows must be a non-empty array'], 400);

$batchId = bin2hex(random_bytes(16));
$results = [];
$pdo->beginTransaction();
try {
foreach ($rows as $i => $r) {
    if (!is_array($r)) { $results[] = ['row' => $i, 'success' => false, 'error' => 'Invalid row']; continue; }

    $playerId = trim((string)($r['player_id'] ?? ''));
    if (!$playerId) { $results[] = ['row' => $i, 'success' => false, 'error' => 'player_id is required']; continue; }

    $pStmt = $pdo->prepare(
        'SELECT id, name, position, team_name, team_id, date_of_birth, height_cm
         FROM club_players
         WHERE id = ? AND club_id = ? AND is_active = 1' .
         (($ctx['team_id'] ?? null) !== null ? ' AND team_id = ?' : '') .
         ' LIMIT 1'
    );
    $playerParams = [$playerId, $ctx['club_id']];
    if (($ctx['team_id'] ?? null) !== null) $playerParams[] = $ctx['team_id'];
    $pStmt->execute($playerParams);
    $player = $pStmt->fetch(PDO::FETCH_ASSOC);
    if (!$player) { $results[] = ['row' => $i, 'success' => false, 'error' => 'Player not found in your roster']; continue; }

    $weight = isset($r['weight_kg']) ? (float)$r['weight_kg'] : null;
    $height = isset($r['height_cm']) ? (float)$r['height_cm'] : (($player['height_cm'] ?? null) !== null ? (float)$player['height_cm'] : null);
    $assessmentDate = !empty($r['assessment_date']) ? (string)$r['assessment_date'] : FitnessConfig::today();
    if (!bcValidDate($assessmentDate)) {
        $results[] = ['row' => $i, 'player_id' => $playerId, 'success' => false, 'error' => 'assessment_date must be YYYY-MM-DD'];
        continue;
    }

    if ($weight === null || $weight < 20 || $weight > 250) { $results[] = ['row' => $i, 'player_id' => $playerId, 'success' => false, 'error' => 'weight_kg must be 20–250']; continue; }
    if ($height === null || $height < 100 || $height > 230) { $results[] = ['row' => $i, 'player_id' => $playerId, 'success' => false, 'error' => 'height_cm must be 100–230 (no height on file)']; continue; }

    // Duplicate guard: same player + date already recorded, unless overwrite requested
    $dupStmt = $pdo->prepare('SELECT * FROM player_body_composition_assessments WHERE linked_player_id = ? AND assessment_date = ? AND deleted_at IS NULL');
    $dupStmt->execute([$playerId, $assessmentDate]);
    $dupRow = $dupStmt->fetch(PDO::FETCH_ASSOC) ?: null;
    $dupId = $dupRow['id'] ?? null;
    if ($dupId && empty($r['overwrite'])) {
        $results[] = ['row' => $i, 'player_id' => $playerId, 'success' => false, 'error' => 'Duplicate — an assessment already exists for this player on this date', 'existing_id' => $dupId];
        continue;
    }

    $sites = ['biceps', 'triceps', 'subscapular', 'suprailiac'];
    $siteValues = [];
    $skinfoldSum = 0.0;
    $anySite = false;
    $rowError = null;
    foreach ($sites as $site) {
        $get = fn($k) => isset($r[$k]) && $r[$k] !== '' ? (float)$r[$k] : null;
        $a1 = $get("{$site}_attempt_1_mm"); $a2 = $get("{$site}_attempt_2_mm"); $a3 = $get("{$site}_attempt_3_mm");
        foreach ([$a1, $a2, $a3] as $v) {
            if (!bc_attempt_valid($v)) $rowError = "$site attempts must be 2–60mm";
        }
        $avg = bc_average_attempts($a1, $a2, $a3);
        if ($avg !== null) { $anySite = true; $skinfoldSum += $avg; }
        $siteValues[$site] = ['a1' => $a1, 'a2' => $a2, 'a3' => $a3, 'avg' => $avg];
    }
    if ($rowError) { $results[] = ['row' => $i, 'player_id' => $playerId, 'success' => false, 'error' => $rowError]; continue; }
    $skinfoldSum = $anySite ? round($skinfoldSum, 1) : null;

    $age = !empty($player['date_of_birth']) ? bc_calc_age($player['date_of_birth'], $assessmentDate) : null;
    $bodyFatPercentage = null; $formulaCode = null; $ageGroup = null; $formulaVersion = null;
    $calculationStatus = BC_CALC_INCOMPLETE_SKINFOLD;
    $measurementCompleteness = 0.0;
    $missingSites = BC_DEFAULT_REQUIRED_SITES;
    if ($age !== null) {
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
            if (!isset($calc['error'])) {
                $bodyFatPercentage = $calc['body_fat_percentage'];
                $formulaCode = $calc['formula_code'];
                $ageGroup = $calc['age_group'];
                $formulaVersion = $calc['formula_version'];
            } else {
                $calculationStatus = 'UNSUPPORTED_FORMULA';
            }
        } else {
            $skinfoldSum = null;
        }
    } else {
        $calculationStatus = 'AGE_REQUIRED';
        $skinfoldSum = null;
    }

    $bmi = bc_bmi($weight, $height);
    $fatMassKg = $bodyFatPercentage !== null ? bc_fat_mass_kg($weight, $bodyFatPercentage) : null;
    $fatFreeMassKg = $fatMassKg !== null ? bc_fat_free_mass_kg($weight, $fatMassKg) : null;
    $notes = isset($r['notes']) ? substr((string)$r['notes'], 0, 1000) : null;

    if ($dupId && !empty($r['overwrite'])) {
        $overwriteReason = trim(substr((string)($r['overwrite_reason'] ?? ''), 0, 500));
        if ($overwriteReason === '') {
            $results[] = [
                'row' => $i,
                'player_id' => $playerId,
                'success' => false,
                'error' => 'overwrite_reason is required',
                'existing_id' => $dupId,
            ];
            continue;
        }
        $pdo->prepare(
            'INSERT INTO body_composition_revisions
             (assessment_id, revision_number, old_values_json, new_values_json, reason, changed_by)
             SELECT ?, COALESCE(MAX(revision_number), 0) + 1, ?, ?, ?, ?
             FROM body_composition_revisions WHERE assessment_id = ?'
        )->execute([
            $dupId,
            json_encode($dupRow, JSON_UNESCAPED_UNICODE),
            json_encode([
                'weight_kg' => $weight,
                'body_fat_percentage' => $bodyFatPercentage,
                'calculation_status' => $calculationStatus,
            ], JSON_UNESCAPED_UNICODE),
            $overwriteReason,
            (int)$user['id'],
            $dupId,
        ]);
        $pdo->prepare(
            'UPDATE player_body_composition_assessments SET
             weight_kg=?, height_cm=?, age_at_assessment=?,
             biceps_attempt_1_mm=?, biceps_attempt_2_mm=?, biceps_attempt_3_mm=?, biceps_mm=?,
             triceps_attempt_1_mm=?, triceps_attempt_2_mm=?, triceps_attempt_3_mm=?, triceps_mm=?,
             subscapular_attempt_1_mm=?, subscapular_attempt_2_mm=?, subscapular_attempt_3_mm=?, subscapular_mm=?,
             suprailiac_attempt_1_mm=?, suprailiac_attempt_2_mm=?, suprailiac_attempt_3_mm=?, suprailiac_mm=?,
             skinfold_sum_mm=?, calculation_formula_code=?, calculation_age_group=?,
             body_fat_percentage=?, fat_mass_kg=?, fat_free_mass_kg=?, bmi=?,
             approval_status=?, calculation_status=?, measurement_completeness=?,
             missing_sites_json=?, formula_version=?, import_batch_id=?, notes=?, updated_by=?
             WHERE id=?'
        )->execute([
            $weight, $height, $age,
            $siteValues['biceps']['a1'], $siteValues['biceps']['a2'], $siteValues['biceps']['a3'], $siteValues['biceps']['avg'],
            $siteValues['triceps']['a1'], $siteValues['triceps']['a2'], $siteValues['triceps']['a3'], $siteValues['triceps']['avg'],
            $siteValues['subscapular']['a1'], $siteValues['subscapular']['a2'], $siteValues['subscapular']['a3'], $siteValues['subscapular']['avg'],
            $siteValues['suprailiac']['a1'], $siteValues['suprailiac']['a2'], $siteValues['suprailiac']['a3'], $siteValues['suprailiac']['avg'],
            $skinfoldSum, $formulaCode, $ageGroup, $bodyFatPercentage, $fatMassKg, $fatFreeMassKg, $bmi,
            'approved',
            $calculationStatus, $measurementCompleteness, json_encode($missingSites),
            $formulaVersion, $batchId, $notes,
            (int)$user['id'], $dupId,
        ]);
        logFitnessAudit(
            $pdo,
            'player_body_composition_assessments',
            $dupId,
            'body_composition.bulk_overwrite',
            (int)$user['id'],
            (int)$ctx['club_id'],
            $playerId,
            $dupRow,
            [
                'weight_kg' => $weight,
                'body_fat_percentage' => $bodyFatPercentage,
                'calculation_status' => $calculationStatus,
            ],
            $overwriteReason,
            $batchId
        );
        $results[] = [
            'row' => $i,
            'player_id' => $playerId,
            'success' => true,
            'id' => $dupId,
            'overwritten' => true,
            'calculation_status' => $calculationStatus,
            'missing_sites' => $missingSites,
        ];
        continue;
    }

    $id = bin2hex(random_bytes(16));
    $pdo->prepare(
        'INSERT INTO player_body_composition_assessments
         (id, user_id, club_id, linked_player_id, recorded_by, team_name, position,
          assessment_date, assessment_type, height_cm, weight_kg, age_at_assessment,
          biceps_attempt_1_mm, biceps_attempt_2_mm, biceps_attempt_3_mm, biceps_mm,
          triceps_attempt_1_mm, triceps_attempt_2_mm, triceps_attempt_3_mm, triceps_mm,
          subscapular_attempt_1_mm, subscapular_attempt_2_mm, subscapular_attempt_3_mm, subscapular_mm,
          suprailiac_attempt_1_mm, suprailiac_attempt_2_mm, suprailiac_attempt_3_mm, suprailiac_mm,
          skinfold_sum_mm, calculation_formula_code, calculation_age_group,
          body_fat_percentage, fat_mass_kg, fat_free_mass_kg, bmi,
          approval_status, approved_by, approved_at, calculation_status,
          measurement_completeness, missing_sites_json, formula_version, import_batch_id,
          measurement_method, notes, assessed_by, created_by)
         VALUES (?, ?, ?, ?, \'coach\', ?, ?, ?, \'periodic\', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    )->execute([
        $id, $user['id'], (int)$ctx['club_id'], $playerId,
        $player['team_name'] ?? null, $player['position'] ?? null,
        $assessmentDate, $height, $weight, $age,
        $siteValues['biceps']['a1'], $siteValues['biceps']['a2'], $siteValues['biceps']['a3'], $siteValues['biceps']['avg'],
        $siteValues['triceps']['a1'], $siteValues['triceps']['a2'], $siteValues['triceps']['a3'], $siteValues['triceps']['avg'],
        $siteValues['subscapular']['a1'], $siteValues['subscapular']['a2'], $siteValues['subscapular']['a3'], $siteValues['subscapular']['avg'],
        $siteValues['suprailiac']['a1'], $siteValues['suprailiac']['a2'], $siteValues['suprailiac']['a3'], $siteValues['suprailiac']['avg'],
        $skinfoldSum, $formulaCode, $ageGroup, $bodyFatPercentage, $fatMassKg, $fatFreeMassKg, $bmi,
        'approved',
        (int)$user['id'],
        (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format('Y-m-d H:i:s'),
        $calculationStatus, $measurementCompleteness, json_encode($missingSites),
        $formulaVersion, $batchId, 'skinfold', $notes,
        $user['name'], (int)$user['id'],
    ]);
    logFitnessAudit(
        $pdo,
        'player_body_composition_assessments',
        $id,
        'body_composition.bulk_created',
        (int)$user['id'],
        (int)$ctx['club_id'],
        $playerId,
        null,
        [
            'weight_kg' => $weight,
            'body_fat_percentage' => $bodyFatPercentage,
            'calculation_status' => $calculationStatus,
        ],
        null,
        $batchId
    );
    $results[] = [
        'row' => $i,
        'player_id' => $playerId,
        'success' => true,
        'id' => $id,
        'calculation_status' => $calculationStatus,
        'missing_sites' => $missingSites,
    ];
}
    $successCountForBatch = count(array_filter($results, fn($result) => $result['success']));
    $pdo->prepare(
        'INSERT INTO body_composition_import_batches
         (id, club_id, created_by, import_policy, received_count, imported_count, rejected_count, status, result_json)
         VALUES (?, ?, ?, \'PARTIAL_IMPORT\', ?, ?, ?, \'completed\', ?)'
    )->execute([
        $batchId,
        (int)$ctx['club_id'],
        (int)$user['id'],
        count($rows),
        $successCountForBatch,
        count($results) - $successCountForBatch,
        json_encode($results, JSON_UNESCAPED_UNICODE),
    ]);
    logFitnessAudit(
        $pdo,
        'body_composition_import',
        $batchId,
        'body_composition.imported',
        (int)$user['id'],
        (int)$ctx['club_id'],
        null,
        null,
        ['received' => count($rows), 'results' => $results],
        isset($body['reason']) ? substr((string)$body['reason'], 0, 500) : null,
        $batchId
    );
    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    jsonOut([
        'error' => 'Bulk import failed before commit',
        'import_batch_id' => $batchId,
    ], 500);
}

$successCount = count(array_filter($results, fn($r) => $r['success']));
jsonOut([
    'success' => true,
    'policy' => 'PARTIAL_IMPORT',
    'import_batch_id' => $batchId,
    'received' => count($rows),
    'imported' => $successCount,
    'rejected' => count($results) - $successCount,
    'failed' => count($results) - $successCount,
    'results' => $results,
]);
