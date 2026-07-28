<?php
require_once dirname(__DIR__, 3) . '/db.php';
require_once dirname(__DIR__, 3) . '/includes/club_auth.php';
require_once __DIR__ . '/../_helpers.php';

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
$ctx = requireClubPermission($pdo, $user, 'fitness.body_composition.update');

$body = json_decode(file_get_contents('php://input'), true) ?? [];
$playerId = trim((string)($body['player_id'] ?? ''));
if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);

$pStmt = $pdo->prepare(
    'SELECT id FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1' .
    (($ctx['team_id'] ?? null) !== null ? ' AND team_id = ?' : '') .
    ' LIMIT 1'
);
$playerParams = [$playerId, $ctx['club_id']];
if (($ctx['team_id'] ?? null) !== null) $playerParams[] = $ctx['team_id'];
$pStmt->execute($playerParams);
if (!$pStmt->fetch()) jsonOut(['error' => 'Player not found in your roster'], 404);

$num = fn($k) => isset($body[$k]) && $body[$k] !== '' ? (float)$body[$k] : null;
$targetWeight = $num('target_weight_kg');
$targetBodyFat = $num('target_body_fat_percentage');
$targetFatMass = $num('target_fat_mass_kg');
$minAcceptable = $num('min_acceptable_body_fat');
$maxAcceptable = $num('max_acceptable_body_fat');
$targetDate = !empty($body['target_date']) ? (string)$body['target_date'] : null;
$notes = isset($body['notes']) ? substr((string)$body['notes'], 0, 1000) : null;

if ($minAcceptable !== null && $maxAcceptable !== null && $minAcceptable > $maxAcceptable) {
    jsonOut(['error' => 'min_acceptable_body_fat cannot exceed max_acceptable_body_fat'], 400);
}

$existingStmt = $pdo->prepare('SELECT id FROM player_body_composition_goals WHERE linked_player_id = ?');
$existingStmt->execute([$playerId]);
$existingId = $existingStmt->fetchColumn();

if ($existingId) {
    $pdo->prepare(
        'UPDATE player_body_composition_goals SET
         target_weight_kg = ?, target_body_fat_percentage = ?, target_fat_mass_kg = ?,
         min_acceptable_body_fat = ?, max_acceptable_body_fat = ?, target_date = ?, notes = ?, updated_by = ?
         WHERE id = ?'
    )->execute([
        $targetWeight, $targetBodyFat, $targetFatMass, $minAcceptable, $maxAcceptable, $targetDate, $notes,
        (int)$user['id'], $existingId,
    ]);
    $id = $existingId;
} else {
    $id = bin2hex(random_bytes(16));
    $pdo->prepare(
        'INSERT INTO player_body_composition_goals
         (id, linked_player_id, club_id, target_weight_kg, target_body_fat_percentage, target_fat_mass_kg,
          min_acceptable_body_fat, max_acceptable_body_fat, target_date, notes, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    )->execute([
        $id, $playerId, $ctx['club_id'], $targetWeight, $targetBodyFat, $targetFatMass,
        $minAcceptable, $maxAcceptable, $targetDate, $notes, (int)$user['id'],
    ]);
}

jsonOut(['success' => true, 'id' => $id]);
