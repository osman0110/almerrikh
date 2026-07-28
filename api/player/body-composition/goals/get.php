<?php
require_once dirname(__DIR__, 3) . '/db.php';
require_once __DIR__ . '/../_helpers.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$user = getAuthUser($pdo);
$scope = resolvePlayerScope($pdo, $user, $_GET, true);
$playerId = $scope['linkedPlayerId'];
if (!$playerId) jsonOut(['goal' => null]);

$stmt = $pdo->prepare('SELECT * FROM player_body_composition_goals WHERE linked_player_id = ? LIMIT 1');
$stmt->execute([$playerId]);
$goal = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;

$latestStmt = $pdo->prepare(
    'SELECT body_fat_percentage, weight_kg, fat_mass_kg FROM player_body_composition_assessments
     WHERE linked_player_id = ? AND deleted_at IS NULL ORDER BY assessment_date DESC, created_at DESC LIMIT 1'
);
$latestStmt->execute([$playerId]);
$latest = $latestStmt->fetch(PDO::FETCH_ASSOC) ?: null;

$currentBodyFat = $latest && $latest['body_fat_percentage'] !== null ? (float)$latest['body_fat_percentage'] : null;
$status = bcGoalStatus($goal, $currentBodyFat);

jsonOut(['goal' => $goal, 'current' => $latest, 'status' => $status]);
