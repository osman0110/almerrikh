<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once __DIR__ . '/_helpers.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/SchemaInspector.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/BodyCompositionRepository.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$user = getAuthUser($pdo);
$scope = resolvePlayerScope($pdo, $user, $_GET, true);
$linkedPlayerId = $scope['linkedPlayerId'];
// Approval gating removed — a coach-recorded measurement is usable in
// reports the moment it's saved, no separate approval step.
$approvalFilter = '';

$limit = min(100, max(1, (int)($_GET['limit'] ?? 30)));

if ($linkedPlayerId) {
    $stmt = $pdo->prepare(
        'SELECT * FROM player_body_composition_assessments
         WHERE linked_player_id = ? AND deleted_at IS NULL' . $approvalFilter . '
         ORDER BY assessment_date DESC, created_at DESC LIMIT ?'
    );
    $stmt->execute([$linkedPlayerId, $limit]);
} else {
    $stmt = $pdo->prepare(
        'SELECT * FROM player_body_composition_assessments
         WHERE user_id = ? AND recorded_by = \'self\' AND deleted_at IS NULL' . $approvalFilter . '
         ORDER BY assessment_date DESC, created_at DESC LIMIT ?'
    );
    $stmt->execute([$user['id'], $limit]);
}
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

// No row in the new skinfold-based system yet — most club players only ever
// get weighed/measured through the older self-service body-metrics flow, so
// fall back to that record rather than showing "no data" when one exists
// (it already surfaces in the club-wide list.php via the same repository).
if (!$rows) {
    $legacy = BodyCompositionRepository::latestForPlayer(
        $pdo,
        $linkedPlayerId,
        $linkedPlayerId ? null : (int)$user['id'],
        false
    );
    if ($legacy && $legacy['source_system'] === 'LEGACY_SYSTEM') {
        $measuredAt = (string)($legacy['measured_at'] ?? '');
        $rows[] = [
            'id' => 'legacy:' . $legacy['id'],
            'linked_player_id' => $legacy['linked_player_id'] ?? $linkedPlayerId,
            'assessment_date' => substr($measuredAt, 0, 10),
            'assessment_time' => strlen($measuredAt) > 11 ? substr($measuredAt, 11, 5) : null,
            'assessment_type' => 'legacy',
            'height_cm' => $legacy['height_cm'],
            'weight_kg' => $legacy['weight_kg'],
            'body_fat_percentage' => $legacy['body_fat_percentage'],
            'fat_mass_kg' => $legacy['fat_mass_kg'],
            'fat_free_mass_kg' => $legacy['fat_free_mass_kg'],
            'bmi' => $legacy['raw']['bmi'] ?? null,
            'skinfold_sum_mm' => null,
            'notes' => $legacy['raw']['specialist_notes'] ?? null,
            'assessed_by' => $legacy['raw']['measured_by'] ?? null,
            'source_system' => 'LEGACY_SYSTEM',
            'is_legacy' => true,
            'read_only' => true,
            'approval_status' => 'legacy_unreviewed',
        ];
    }
}

// Precompute deltas vs the chronologically-previous entry (rows are DESC, so
// "previous" is the next element in this array) for the profile-tab charts.
foreach ($rows as $i => &$row) {
    $prev = $rows[$i + 1] ?? null;
    $mk = fn($cur, $prevVal) => ($cur === null || $prevVal === null) ? null : round((float)$cur - (float)$prevVal, 2);
    $row['delta'] = $prev ? [
        'weight_kg'           => $mk($row['weight_kg'], $prev['weight_kg']),
        'body_fat_percentage' => $mk($row['body_fat_percentage'], $prev['body_fat_percentage']),
        'fat_mass_kg'         => $mk($row['fat_mass_kg'], $prev['fat_mass_kg']),
        'fat_free_mass_kg'    => $mk($row['fat_free_mass_kg'], $prev['fat_free_mass_kg']),
        'skinfold_sum_mm'     => $mk($row['skinfold_sum_mm'], $prev['skinfold_sum_mm']),
    ] : null;
}
unset($row);

jsonOut(['history' => $rows, 'count' => count($rows)]);
