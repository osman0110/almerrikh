<?php
/**
 * POST /api/coach/plans/publish.php
 * Publishes a draft plan:
 *   1. Sets training_plans.status = 'published'
 *   2. Sets each training_session.status = 'assigned'
 *   3. Creates session_players for every plan_player × every session
 * Allowed roles: club, coach, academy
 */
require_once dirname(__DIR__, 2) . '/db.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); echo '{"error":"Method not allowed"}'; exit; }

function jsonOut(array $d, int $c = 200): never {
    http_response_code($c);
    echo json_encode($d, JSON_UNESCAPED_UNICODE);
    exit;
}
function bearerToken(): string {
    $a = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? $_SERVER['Authorization'] ?? '';
    if (!$a && function_exists('apache_request_headers')) { $h = apache_request_headers(); $a = $h['Authorization'] ?? $h['authorization'] ?? ''; }
    return stripos($a, 'Bearer ') === 0 ? trim(substr($a, 7)) : trim($a);
}
function getAuthUser(PDO $pdo): array {
    $tok = bearerToken();
    if (!$tok) jsonOut(['error' => 'Unauthorized'], 401);
    $s = $pdo->prepare('SELECT u.id,u.role FROM users u JOIN user_tokens t ON u.id=t.user_id WHERE t.token=?');
    $s->execute([$tok]); $u = $s->fetch();
    if (!$u) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $u;
}

$user = getAuthUser($pdo);
if (!in_array($user['role'], ['club','coach','academy'], true)) jsonOut(['error' => 'Forbidden'], 403);
$coachId = (int)$user['id'];

$body   = json_decode(file_get_contents('php://input'), true) ?? [];
$planId = trim((string)($body['plan_id'] ?? ''));
if (!$planId) jsonOut(['error' => 'plan_id is required'], 400);

// Verify ownership
$stmt = $pdo->prepare('SELECT id,status,club_id FROM training_plans WHERE id=? AND coach_user_id=?');
$stmt->execute([$planId, $coachId]);
$plan = $stmt->fetch();
if (!$plan) jsonOut(['error' => 'Plan not found or not yours'], 403);
if ($plan['status'] === 'published') jsonOut(['error' => 'Plan already published'], 400);
if ($plan['status'] !== 'draft') jsonOut(['error' => 'Only draft plans can be published'], 400);

// Fetch sessions
$sessStmt = $pdo->prepare('SELECT id FROM training_sessions WHERE plan_id=?');
$sessStmt->execute([$planId]);
$sessions = array_column($sessStmt->fetchAll(), 'id');
if (empty($sessions)) jsonOut(['error' => 'Plan has no sessions'], 400);

// Fetch intended players
$ppStmt = $pdo->prepare('SELECT club_player_id, player_user_id FROM plan_players WHERE plan_id=?');
$ppStmt->execute([$planId]);
$planPlayers = $ppStmt->fetchAll();
if (empty($planPlayers)) jsonOut(['error' => 'Plan has no assigned players'], 400);

$pdo->beginTransaction();
try {
    // 1. Publish plan
    $pdo->prepare('UPDATE training_plans SET status=\'published\',updated_at=NOW() WHERE id=?')->execute([$planId]);

    // 2. Activate sessions
    $pdo->prepare('UPDATE training_sessions SET status=\'assigned\' WHERE plan_id=?')->execute([$planId]);

    // 3. Create session_players
    $spStmt = $pdo->prepare(
        'INSERT IGNORE INTO session_players
         (session_id,club_id,player_user_id,linked_player_id,status)
         VALUES (?,?,?,?,\'assigned\')'
    );
    $published = 0;
    foreach ($sessions as $sid) {
        foreach ($planPlayers as $pp) {
            $spStmt->execute([
                $sid,
                $coachId,
                $pp['player_user_id'],
                $pp['club_player_id'],
            ]);
            $published++;
        }
    }

    $pdo->commit();
} catch (Exception $e) {
    $pdo->rollBack();
    jsonOut(['error' => 'Publish failed: ' . $e->getMessage()], 500);
}

jsonOut([
    'success'              => true,
    'plan_id'              => $planId,
    'published_sessions'   => count($sessions),
    'assigned_players'     => count($planPlayers),
    'session_player_rows'  => $published,
]);
