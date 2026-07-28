<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once __DIR__ . '/_helpers.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$user = getAuthUser($pdo);
$id = trim((string)($_GET['id'] ?? ''));
if (!$id) jsonOut(['error' => 'id is required'], 400);

$stmt = $pdo->prepare('SELECT * FROM player_body_composition_assessments WHERE id = ? AND deleted_at IS NULL');
$stmt->execute([$id]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$row) jsonOut(['error' => 'Assessment not found'], 404);

// Scope check: same access rule as everywhere else — a player may only see
// their own record, a coach only records belonging to their own account.
$isCoach = !in_array($user['role'], ['player', 'parent'], true);
if ($isCoach) {
    $ctx = requireClubPermission($pdo, $user, 'fitness.body_composition.view');
    if ((int)$row['club_id'] !== (int)$ctx['club_id']) jsonOut(['error' => 'Forbidden'], 403);
    if (($ctx['team_id'] ?? null) !== null) {
        $teamStmt = $pdo->prepare('SELECT team_id FROM club_players WHERE id = ? AND club_id = ?');
        $teamStmt->execute([$row['linked_player_id'], $ctx['club_id']]);
        if ((int)$teamStmt->fetchColumn() !== (int)$ctx['team_id']) jsonOut(['error' => 'Forbidden'], 403);
    }
    if (
        in_array($ctx['staff_role'], ['performance_manager', 'nutritionist', 'doctor'], true)
        && ($row['approval_status'] ?? null) !== 'approved'
    ) {
        jsonOut(['error' => 'Approved assessment not found'], 404);
    }
} else {
    $ownLinkedId = $user['linked_player_id'] ?? null;
    if (!$ownLinkedId || $row['linked_player_id'] !== $ownLinkedId) jsonOut(['error' => 'Forbidden'], 403);
}

$prevStmt = $pdo->prepare(
    'SELECT * FROM player_body_composition_assessments
     WHERE deleted_at IS NULL AND id != ? AND ' . ($row['linked_player_id'] ? 'linked_player_id = ?' : 'user_id = ?') . '
       AND (assessment_date < ? OR (assessment_date = ? AND created_at < ?))
     ORDER BY assessment_date DESC, created_at DESC LIMIT 1'
);
$prevStmt->execute([
    $id, $row['linked_player_id'] ?: $row['user_id'],
    $row['assessment_date'], $row['assessment_date'], $row['created_at'],
]);
$prev = $prevStmt->fetch(PDO::FETCH_ASSOC) ?: null;

$delta = null;
if ($prev) {
    $mk = fn($cur, $prevVal) => ($cur === null || $prevVal === null) ? null : round((float)$cur - (float)$prevVal, 2);
    $delta = [
        'weight_kg'           => $mk($row['weight_kg'], $prev['weight_kg']),
        'body_fat_percentage' => $mk($row['body_fat_percentage'], $prev['body_fat_percentage']),
        'fat_mass_kg'         => $mk($row['fat_mass_kg'], $prev['fat_mass_kg']),
        'fat_free_mass_kg'    => $mk($row['fat_free_mass_kg'], $prev['fat_free_mass_kg']),
        'skinfold_sum_mm'     => $mk($row['skinfold_sum_mm'], $prev['skinfold_sum_mm']),
        'previous_date'       => $prev['assessment_date'],
    ];
}

$goalStatus = null;
if ($row['linked_player_id']) {
    $goalStmt = $pdo->prepare('SELECT * FROM player_body_composition_goals WHERE linked_player_id = ? LIMIT 1');
    $goalStmt->execute([$row['linked_player_id']]);
    $goal = $goalStmt->fetch(PDO::FETCH_ASSOC) ?: null;
    $goalStatus = bcGoalStatus($goal, $row['body_fat_percentage'] !== null ? (float)$row['body_fat_percentage'] : null, $row['assessment_date']);
}

jsonOut(['assessment' => $row, 'delta' => $delta, 'goal_status' => $goalStatus]);
