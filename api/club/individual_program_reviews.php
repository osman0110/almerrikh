<?php
/**
 * Individual program weekly reviews — sits on top of the EXISTING
 * training_plans/training_sessions/session_exercises infrastructure
 * (see api/coach/plans/create-manual.php for how a plan gets created).
 * This endpoint does not create plans; it only lists a player's plans
 * (scoped by the modern club_id, not the legacy coach_user_id ownership
 * those older endpoints use) and manages the weekly review layer.
 *
 * GET  ?player_id=X           — list this player's individual training plans
 * GET  ?plan_id=X              — list weekly reviews for a plan
 * POST action=create_review    — add a weekly review
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';

function jsonOut(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function bearerToken(): string {
    $auth = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? $_SERVER['Authorization'] ?? '';
    if (!$auth && function_exists('apache_request_headers')) {
        $h = apache_request_headers();
        $auth = $h['Authorization'] ?? $h['authorization'] ?? '';
    }
    if (stripos($auth, 'Bearer ') === 0) return trim(substr($auth, 7));
    return trim($auth);
}

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['success' => false, 'message' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

function planOut(array $p): array {
    return [
        'id'          => $p['id'],
        'title'       => $p['title'],
        'goal'        => $p['goal'],
        'status'      => $p['status'],
        'num_weeks'   => $p['num_weeks'] !== null ? (int)$p['num_weeks'] : null,
        'created_at'  => $p['created_at'],
    ];
}

function reviewOut(array $r): array {
    return [
        'id'                 => (string)$r['id'],
        'week_number'        => (int)$r['week_number'],
        'review_date'        => $r['review_date'],
        'completion_percent' => (int)$r['completion_percent'],
        'coach_notes'        => $r['coach_notes'],
        'player_feedback'    => $r['player_feedback'],
        'reviewed_by_name'   => $r['reviewed_by_name'] ?? null,
        'created_at'         => $r['created_at'],
    ];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

if ($method === 'GET') {
    $ctx = requireClubPermission($pdo, $user, 'players.read');

    $planId = trim($_GET['plan_id'] ?? '');
    if ($planId) {
        $planStmt = $pdo->prepare('SELECT id FROM training_plans WHERE id = ? AND club_id = ?');
        $planStmt->execute([$planId, $ctx['club_id']]);
        if (!$planStmt->fetchColumn()) jsonOut(['success' => false, 'message' => 'Not found'], 404);

        $stmt = $pdo->prepare(
            'SELECT r.*, u.name AS reviewed_by_name
             FROM individual_program_reviews r
             JOIN users u ON u.id = r.reviewed_by_user_id
             WHERE r.plan_id = ?
             ORDER BY r.week_number ASC'
        );
        $stmt->execute([$planId]);
        jsonOut(['success' => true, 'reviews' => array_map('reviewOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
    }

    $playerId = trim($_GET['player_id'] ?? '');
    if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id or plan_id is required'], 400);

    // Plans use two different assignment paths: the legacy linked_player_id,
    // AI plans use plan_players, and manual plans use session_players.
    $stmt = $pdo->prepare(
        'SELECT DISTINCT tp.*
         FROM training_plans tp
         LEFT JOIN plan_players pp
           ON pp.plan_id = tp.id AND pp.club_player_id = ?
         LEFT JOIN training_sessions ts ON ts.plan_id = tp.id
         LEFT JOIN session_players sp
           ON sp.session_id = ts.id AND sp.linked_player_id = ?
         WHERE tp.club_id = ?
           AND (tp.linked_player_id = ? OR pp.plan_id IS NOT NULL OR sp.session_id IS NOT NULL)
         ORDER BY tp.created_at DESC'
    );
    $stmt->execute([$playerId, $playerId, $ctx['club_id'], $playerId]);
    jsonOut(['success' => true, 'plans' => array_map('planOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
}

if ($method === 'POST') {
    $ctx  = requireClubPermission($pdo, $user, 'players.write');
    $body = json_decode(file_get_contents('php://input'), true) ?? [];

    if (($body['action'] ?? '') !== 'create_review') {
        jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
    }

    $planId = trim($body['plan_id'] ?? '');
    if (!$planId) jsonOut(['success' => false, 'message' => 'plan_id is required'], 400);

    $planStmt = $pdo->prepare('SELECT id FROM training_plans WHERE id = ? AND club_id = ?');
    $planStmt->execute([$planId, $ctx['club_id']]);
    if (!$planStmt->fetchColumn()) jsonOut(['success' => false, 'message' => 'Plan not found'], 404);

    $weekNumber = (int)($body['week_number'] ?? 1);
    if ($weekNumber < 1 || $weekNumber > 52) jsonOut(['success' => false, 'message' => 'week_number must be 1-52'], 400);

    $completion = (int)($body['completion_percent'] ?? 0);
    if ($completion < 0 || $completion > 100) jsonOut(['success' => false, 'message' => 'completion_percent must be 0-100'], 400);

    $stmt = $pdo->prepare(
        'INSERT INTO individual_program_reviews
             (plan_id, week_number, review_date, completion_percent, coach_notes, player_feedback, reviewed_by_user_id)
         VALUES (?, ?, ?, ?, ?, ?, ?)'
    );
    $stmt->execute([
        $planId, $weekNumber, date('Y-m-d'), $completion,
        trim($body['coach_notes'] ?? '') ?: null,
        trim($body['player_feedback'] ?? '') ?: null,
        $user['id'],
    ]);
    jsonOut(['success' => true, 'id' => (string)$pdo->lastInsertId()]);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
