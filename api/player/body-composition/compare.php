<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once __DIR__ . '/_helpers.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$user = getAuthUser($pdo);
$fromId = trim((string)($_GET['from_id'] ?? ''));
$toId   = trim((string)($_GET['to_id'] ?? ''));
if (!$fromId || !$toId) jsonOut(['error' => 'from_id and to_id are required'], 400);

$stmt = $pdo->prepare('SELECT * FROM player_body_composition_assessments WHERE id IN (?, ?) AND deleted_at IS NULL');
$stmt->execute([$fromId, $toId]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
$byId = [];
foreach ($rows as $r) $byId[$r['id']] = $r;
if (!isset($byId[$fromId]) || !isset($byId[$toId])) jsonOut(['error' => 'One or both assessments not found'], 404);

$from = $byId[$fromId];
$to = $byId[$toId];

$isCoach = !in_array($user['role'], ['player', 'parent'], true);
if ($isCoach) {
    $ctx = requireClubPermission($pdo, $user, 'fitness.body_composition.view');
    if ((int)$from['club_id'] !== (int)$ctx['club_id'] || (int)$to['club_id'] !== (int)$ctx['club_id']) {
        jsonOut(['error' => 'Forbidden'], 403);
    }
    if (($ctx['team_id'] ?? null) !== null) {
        $teamStmt = $pdo->prepare(
            'SELECT COUNT(*) FROM club_players
             WHERE id IN (?, ?) AND club_id = ? AND team_id = ?'
        );
        $teamStmt->execute([
            $from['linked_player_id'],
            $to['linked_player_id'],
            $ctx['club_id'],
            $ctx['team_id'],
        ]);
        $expectedPlayers = count(array_unique([
            $from['linked_player_id'],
            $to['linked_player_id'],
        ]));
        if ((int)$teamStmt->fetchColumn() !== $expectedPlayers) jsonOut(['error' => 'Forbidden'], 403);
    }
    if (in_array($ctx['staff_role'], ['performance_manager', 'nutritionist', 'doctor'], true)) {
        if (($from['approval_status'] ?? null) !== 'approved' || ($to['approval_status'] ?? null) !== 'approved') {
            jsonOut(['error' => 'Approved assessments not found'], 404);
        }
    }
} else {
    $ownLinkedId = $user['linked_player_id'] ?? null;
    if (!$ownLinkedId || $from['linked_player_id'] !== $ownLinkedId || $to['linked_player_id'] !== $ownLinkedId) {
        jsonOut(['error' => 'Forbidden'], 403);
    }
}

function bcCompareRow(string $label, ?float $start, ?float $end): array {
    $diff = ($start !== null && $end !== null) ? round($end - $start, 2) : null;
    $pctChange = ($diff !== null && $start != 0) ? round(($diff / $start) * 100, 1) : null;
    return ['label' => $label, 'start' => $start, 'end' => $end, 'diff' => $diff, 'pct_change' => $pctChange];
}

$f = fn($k) => $from[$k] !== null ? (float)$from[$k] : null;
$t = fn($k) => $to[$k] !== null ? (float)$to[$k] : null;

$table = [
    bcCompareRow('weight_kg', $f('weight_kg'), $t('weight_kg')),
    bcCompareRow('bmi', $f('bmi'), $t('bmi')),
    bcCompareRow('body_fat_percentage', $f('body_fat_percentage'), $t('body_fat_percentage')),
    bcCompareRow('fat_mass_kg', $f('fat_mass_kg'), $t('fat_mass_kg')),
    bcCompareRow('fat_free_mass_kg', $f('fat_free_mass_kg'), $t('fat_free_mass_kg')),
    bcCompareRow('biceps_mm', $f('biceps_mm'), $t('biceps_mm')),
    bcCompareRow('triceps_mm', $f('triceps_mm'), $t('triceps_mm')),
    bcCompareRow('subscapular_mm', $f('subscapular_mm'), $t('subscapular_mm')),
    bcCompareRow('suprailiac_mm', $f('suprailiac_mm'), $t('suprailiac_mm')),
    bcCompareRow('skinfold_sum_mm', $f('skinfold_sum_mm'), $t('skinfold_sum_mm')),
];

jsonOut(['from' => $from, 'to' => $to, 'comparison' => $table]);
