<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/audit_log.php';
require_once __DIR__ . '/_helpers.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonError('Method not allowed', 405);

$user = getAuthUser($pdo);
$body = json_decode(file_get_contents('php://input'), true) ?? [];

$id = trim((string)($body['id'] ?? ''));
if (!$id) jsonOut(['error' => 'id is required'], 400);

// Coaches only — a player should never be able to erase their own history.
if (in_array($user['role'], ['player', 'parent'], true)) jsonOut(['error' => 'Forbidden'], 403);
$ctx = requireClubPermission($pdo, $user, 'fitness.body_composition.update');

$rowStmt = $pdo->prepare('SELECT * FROM player_body_composition_assessments WHERE id = ? AND deleted_at IS NULL');
$rowStmt->execute([$id]);
$existing = $rowStmt->fetch(PDO::FETCH_ASSOC);
if (!$existing) jsonOut(['error' => 'Assessment not found'], 404);
if ((int)$existing['club_id'] !== (int)$ctx['club_id']) jsonOut(['error' => 'Forbidden'], 403);
if (($existing['approval_status'] ?? null) === 'approved') {
    jsonOut(['error' => 'Cancel approval before archiving this assessment'], 409);
}
if (($ctx['team_id'] ?? null) !== null) {
    $teamStmt = $pdo->prepare('SELECT team_id FROM club_players WHERE id = ? AND club_id = ?');
    $teamStmt->execute([$existing['linked_player_id'], $ctx['club_id']]);
    if ((int)$teamStmt->fetchColumn() !== (int)$ctx['team_id']) jsonOut(['error' => 'Forbidden'], 403);
}

$pdo->prepare('UPDATE player_body_composition_assessments SET deleted_at = NOW(), updated_by = ? WHERE id = ?')
    ->execute([(int)$user['id'], $id]);

logAuditDiff($pdo, 'player_body_composition_assessments', $id, $existing, ['deleted_at' => date('Y-m-d H:i:s')], (int)$user['id']);

jsonOut(['success' => true, 'id' => $id]);
