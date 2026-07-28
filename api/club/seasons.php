<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';
require_once '../includes/club_auth.php';

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

$token = bearerToken();
if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['error' => 'Invalid token'], 401);
if (in_array($user['role'], ['player', 'parent'])) jsonOut(['error' => 'Forbidden'], 403);

$method = $_SERVER['REQUEST_METHOD'];
$ctx    = requireClubPermission($pdo, $user, 'seasons.read');
$cid    = (int)$ctx['club_id'];

// ── GET — list seasons for this club (optionally scoped to a team) ────────────

if ($method === 'GET') {
    $teamId = isset($_GET['team_id']) && $_GET['team_id'] !== '' ? (int)$_GET['team_id'] : null;

    $where  = ['club_id = ?'];
    $params = [$cid];
    if ($teamId !== null) {
        $where[] = 'team_id = ?';
        $params[] = $teamId;
    }

    $stmt = $pdo->prepare(
        'SELECT id, club_id, team_id, name, starts_on, ends_on, status, created_at, updated_at
         FROM club_seasons WHERE ' . implode(' AND ', $where) . '
         ORDER BY starts_on DESC'
    );
    $stmt->execute($params);
    jsonOut(['seasons' => $stmt->fetchAll()]);
}

// ── POST — create/update a season, or activate one ─────────────────────────────

if ($method === 'POST') {
    requireClubPermission($pdo, $user, 'seasons.write');

    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? '');

    // ── Activate: demote any other active season in the same (club, team)
    // scope first, so the generated active_scope_key unique constraint on
    // club_seasons never collides.
    if ($action === 'activate') {
        $id = $body['id'] ?? null;
        if (!$id) jsonOut(['error' => 'id required'], 422);

        $stmt = $pdo->prepare('SELECT id, team_id FROM club_seasons WHERE id = ? AND club_id = ?');
        $stmt->execute([$id, $cid]);
        $season = $stmt->fetch();
        if (!$season) jsonOut(['error' => 'Season not found'], 404);

        $pdo->beginTransaction();
        try {
            $demote = $pdo->prepare(
                "UPDATE club_seasons SET status = 'draft'
                 WHERE club_id = ? AND team_id <=> ? AND status = 'active'"
            );
            $demote->execute([$cid, $season['team_id']]);

            $activate = $pdo->prepare("UPDATE club_seasons SET status = 'active' WHERE id = ? AND club_id = ?");
            $activate->execute([$id, $cid]);

            $pdo->commit();
        } catch (Exception $e) {
            $pdo->rollBack();
            jsonOut(['error' => 'Could not activate season'], 500);
        }

        jsonOut(['success' => true]);
    }

    // ── Create/update ──────────────────────────────────────────────────────────
    $name     = trim($body['name'] ?? '');
    $startsOn = trim($body['starts_on'] ?? '');
    $endsOn   = trim($body['ends_on'] ?? '');
    if (!$name || !$startsOn || !$endsOn) {
        jsonOut(['error' => 'name, starts_on and ends_on are required'], 422);
    }

    $teamId = isset($body['team_id']) && $body['team_id'] !== '' && $body['team_id'] !== null
        ? (int)$body['team_id'] : null;
    $requestedStatus = $body['status'] ?? 'draft';
    $status = in_array($requestedStatus, ['draft', 'active', 'archived'], true)
        ? $requestedStatus : 'draft';

    $id = $body['id'] ?? null;

    if ($id) {
        $stmt = $pdo->prepare('SELECT id FROM club_seasons WHERE id = ? AND club_id = ?');
        $stmt->execute([$id, $cid]);
        if (!$stmt->fetch()) jsonOut(['error' => 'Season not found'], 404);

        // Updating status to 'active' directly here would collide with an
        // existing active row in the same scope — require the dedicated
        // 'activate' action for that transition instead.
        if ($status === 'active') jsonOut(['error' => 'Use action=activate to set a season active'], 422);

        $pdo->prepare(
            'UPDATE club_seasons SET team_id = ?, name = ?, starts_on = ?, ends_on = ?, status = ?
             WHERE id = ? AND club_id = ?'
        )->execute([$teamId, $name, $startsOn, $endsOn, $status, $id, $cid]);

        jsonOut(['success' => true, 'id' => $id]);
    }

    if ($status === 'active') jsonOut(['error' => 'Use action=activate to set a season active'], 422);

    $stmt = $pdo->prepare(
        'INSERT INTO club_seasons (club_id, team_id, name, starts_on, ends_on, status, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?)'
    );
    $stmt->execute([$cid, $teamId, $name, $startsOn, $endsOn, $status, (int)$user['id']]);

    jsonOut(['success' => true, 'id' => (int)$pdo->lastInsertId()]);
}

// ── DELETE — only when not the active season ────────────────────────────────

if ($method === 'DELETE') {
    requireClubPermission($pdo, $user, 'seasons.write');

    $id = $_GET['id'] ?? (json_decode(file_get_contents('php://input'), true)['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id required'], 422);

    $stmt = $pdo->prepare("SELECT status FROM club_seasons WHERE id = ? AND club_id = ?");
    $stmt->execute([$id, $cid]);
    $row = $stmt->fetch();
    if (!$row) jsonOut(['error' => 'Season not found'], 404);
    if ($row['status'] === 'active') jsonOut(['error' => 'Cannot delete the active season'], 409);

    $pdo->prepare('DELETE FROM club_seasons WHERE id = ? AND club_id = ?')->execute([$id, $cid]);

    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
