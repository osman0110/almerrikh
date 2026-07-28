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
if (in_array($user['role'], ['player', 'parent'], true)) jsonOut(['error' => 'Forbidden'], 403);
$ctx = requireClubPermission($pdo, $user, 'fitness.body_composition.approve');
$body = json_decode(file_get_contents('php://input'), true) ?? [];

$id = trim((string)($body['id'] ?? ''));
$action = strtolower(trim((string)($body['action'] ?? 'approve')));
$reason = trim(substr((string)($body['reason'] ?? ''), 0, 500));
if (!$id) jsonOut(['error' => 'id is required'], 400);
if (!in_array($action, ['approve', 'unapprove'], true)) {
    jsonOut(['error' => 'action must be approve or unapprove'], 400);
}
if ($action === 'unapprove' && !in_array($ctx['staff_role'], ['owner', 'admin'], true)) {
    jsonOut(['error' => 'Only an administrator can cancel approval'], 403);
}
if ($action === 'unapprove' && $reason === '') {
    jsonOut(['error' => 'reason is required when cancelling approval'], 400);
}

$stmt = $pdo->prepare(
    'SELECT a.*, cp.team_id
     FROM player_body_composition_assessments a
     LEFT JOIN club_players cp ON cp.id = a.linked_player_id
     WHERE a.id = ? AND a.deleted_at IS NULL'
);
$stmt->execute([$id]);
$existing = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$existing) jsonOut(['error' => 'Assessment not found'], 404);
if ((int)$existing['club_id'] !== (int)$ctx['club_id']) jsonOut(['error' => 'Forbidden'], 403);
if (($ctx['team_id'] ?? null) !== null && (int)$existing['team_id'] !== (int)$ctx['team_id']) {
    jsonOut(['error' => 'Forbidden'], 403);
}
if ($action === 'approve' && $existing['calculation_status'] !== BC_CALC_COMPLETE) {
    jsonOut([
        'error' => 'Incomplete assessment cannot be approved',
        'calculation_status' => $existing['calculation_status'],
    ], 409);
}

$newStatus = $action === 'approve' ? 'approved' : 'draft';
$pdo->beginTransaction();
try {
    $pdo->prepare(
        'INSERT INTO body_composition_revisions
         (assessment_id, revision_number, old_values_json, new_values_json, reason, changed_by)
         SELECT ?, COALESCE(MAX(revision_number), 0) + 1, ?, ?, ?, ?
         FROM body_composition_revisions WHERE assessment_id = ?'
    )->execute([
        $id,
        json_encode($existing, JSON_UNESCAPED_UNICODE),
        json_encode(['approval_status' => $newStatus], JSON_UNESCAPED_UNICODE),
        $reason ?: null,
        (int)$user['id'],
        $id,
    ]);
    $pdo->prepare(
        'UPDATE player_body_composition_assessments
         SET approval_status = ?, approved_by = ?, approved_at = ?
         WHERE id = ?'
    )->execute([
        $newStatus,
        $action === 'approve' ? (int)$user['id'] : null,
        $action === 'approve' ? gmdate('Y-m-d H:i:s') : null,
        $id,
    ]);
    logFitnessAudit(
        $pdo,
        'player_body_composition_assessments',
        $id,
        $action === 'approve' ? 'body_composition.approved' : 'body_composition.unapproved',
        (int)$user['id'],
        (int)$ctx['club_id'],
        $existing['linked_player_id'],
        ['approval_status' => $existing['approval_status']],
        ['approval_status' => $newStatus],
        $reason ?: null
    );
    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    jsonOut(['error' => 'Unable to change approval status'], 500);
}

jsonOut(['success' => true, 'id' => $id, 'approval_status' => $newStatus]);
