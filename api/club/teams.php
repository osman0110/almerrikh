<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
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

$uid    = (int)$user['id'];
$method = $_SERVER['REQUEST_METHOD'];
$ctx    = requireClubPermission($pdo, $user, 'teams.read');
$cid    = $ctx['club_id'];

// ── GET — return all teams (from club_teams + implicit from players) ──────────

if ($method === 'GET') {
    // Teams from dedicated table
    $stmt = $pdo->prepare(
        'SELECT id, name, category, coach_name, physical_coach_name, season, notes, created_at
         FROM club_teams WHERE club_id = ? AND is_active = 1 ORDER BY created_at ASC'
    );
    $stmt->execute([$cid]);
    $rows = $stmt->fetchAll();

    // For each team, count players in club_players
    $teams = [];
    foreach ($rows as $r) {
        $cnt = $pdo->prepare(
            "SELECT COUNT(*) FROM club_players WHERE club_id = ? AND team_name = ? AND is_active = 1"
        );
        $cnt->execute([$cid, $r['name']]);
        $teams[] = [
            'id'                  => $r['id'],
            'name'                => $r['name'],
            'category'            => $r['category'],
            'coach_name'          => $r['coach_name'],
            'physical_coach_name' => $r['physical_coach_name'],
            'season'              => $r['season'],
            'notes'               => $r['notes'],
            'player_count'        => (int)$cnt->fetchColumn(),
        ];
    }

    // Also include implicit teams from players not in any club_teams row
    $namedTeams = array_column($teams, 'name');
    $implicit = $pdo->prepare(
        "SELECT DISTINCT team_name FROM club_players
         WHERE club_id = ? AND is_active = 1 AND team_name IS NOT NULL AND team_name != ''"
    );
    $implicit->execute([$cid]);
    foreach ($implicit->fetchAll() as $r) {
        if (!in_array($r['team_name'], $namedTeams, true)) {
            $cnt = $pdo->prepare(
                "SELECT COUNT(*) FROM club_players WHERE club_id = ? AND team_name = ? AND is_active = 1"
            );
            $cnt->execute([$cid, $r['team_name']]);
            $teams[] = [
                'id'                  => $r['team_name'],
                'name'                => $r['team_name'],
                'category'            => 'firstTeam',
                'coach_name'          => '',
                'physical_coach_name' => '',
                'season'              => date('Y') . '/' . (date('Y') + 1),
                'notes'               => null,
                'player_count'        => (int)$cnt->fetchColumn(),
            ];
        }
    }

    jsonOut(['teams' => $teams]);
}

// ── POST — create team ─────────────────────────────────────────────────────────

if ($method === 'POST') {
    requireClubPermission($pdo, $user, 'teams.write');

    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $name = trim($body['name'] ?? '');
    if (!$name) jsonOut(['error' => 'Team name is required'], 422);

    $id = $body['id'] ?? bin2hex(random_bytes(16));

    // Check for duplicates
    $dup = $pdo->prepare('SELECT id FROM club_teams WHERE club_id = ? AND name = ? AND is_active = 1');
    $dup->execute([$cid, $name]);
    if ($dup->fetch()) jsonOut(['error' => 'Team name already exists'], 409);

    $ownerStmt = $pdo->prepare('SELECT owner_user_id FROM clubs WHERE id = ?');
    $ownerStmt->execute([$cid]);
    $ownerUserId = (int)($ownerStmt->fetchColumn() ?: $uid);

    $stmt = $pdo->prepare(
        'INSERT INTO club_teams (id, user_id, club_id, name, category, coach_name, physical_coach_name, season, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $stmt->execute([
        $id,
        $ownerUserId,
        $cid,
        $name,
        $body['category']            ?? 'firstTeam',
        $body['coach_name']          ?? '',
        $body['physical_coach_name'] ?? '',
        $body['season']              ?? date('Y') . '/' . (date('Y') + 1),
        $body['notes']               ?? null,
    ]);

    jsonOut(['success' => true, 'id' => $id]);
}

// ── PUT — update team ─────────────────────────────────────────────────────────

if ($method === 'PUT') {
    requireClubPermission($pdo, $user, 'teams.write');

    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $id   = $body['id'] ?? ($_GET['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id required'], 422);

    $stmt = $pdo->prepare('SELECT id, name FROM club_teams WHERE id = ? AND club_id = ? AND is_active = 1');
    $stmt->execute([$id, $cid]);
    $existing = $stmt->fetch();

    // Legacy data may have a team name on players without a matching
    // club_teams row. Those teams are included by GET and must remain editable.
    $isImplicit = !$existing;
    if ($isImplicit) {
        $implicit = $pdo->prepare(
            "SELECT team_name FROM club_players
             WHERE club_id = ? AND team_name = ? AND is_active = 1 LIMIT 1"
        );
        $implicit->execute([$cid, $id]);
        $implicitName = $implicit->fetchColumn();
        if (!$implicitName) jsonOut(['error' => 'Team not found'], 404);
        $existing = ['id' => null, 'name' => $implicitName];
    }

    $newName = trim($body['name'] ?? $existing['name']);
    if (!$newName) jsonOut(['error' => 'Team name is required'], 422);

    $dup = $pdo->prepare(
        'SELECT id FROM club_teams WHERE club_id = ? AND name = ? AND is_active = 1'
    );
    $dup->execute([$cid, $newName]);
    $duplicateId = $dup->fetchColumn();
    if ($duplicateId && ($isImplicit || $duplicateId !== $id)) {
        jsonOut(['error' => 'Team name already exists'], 409);
    }

    $savedId = $id;
    $pdo->beginTransaction();
    try {
        if ($isImplicit) {
            $savedId = bin2hex(random_bytes(16));
            $ownerStmt = $pdo->prepare('SELECT owner_user_id FROM clubs WHERE id = ?');
            $ownerStmt->execute([$cid]);
            $ownerUserId = (int)($ownerStmt->fetchColumn() ?: $uid);

            $pdo->prepare(
                'INSERT INTO club_teams
                 (id, user_id, club_id, name, category, coach_name, physical_coach_name, season, notes)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
            )->execute([
                $savedId,
                $ownerUserId,
                $cid,
                $newName,
                $body['category']            ?? 'firstTeam',
                $body['coach_name']          ?? '',
                $body['physical_coach_name'] ?? '',
                $body['season']              ?? '',
                $body['notes']               ?? null,
            ]);
        } else {
            $pdo->prepare(
                'UPDATE club_teams SET name = ?, category = ?, coach_name = ?, physical_coach_name = ?,
                 season = ?, notes = ? WHERE id = ? AND club_id = ?'
            )->execute([
                $newName,
                $body['category']            ?? 'firstTeam',
                $body['coach_name']          ?? '',
                $body['physical_coach_name'] ?? '',
                $body['season']              ?? '',
                $body['notes']               ?? null,
                $id,
                $cid,
            ]);
        }

        // Keep the player roster attached when the team is renamed.
        if ($newName !== $existing['name']) {
            $pdo->prepare(
                'UPDATE club_players SET team_name = ? WHERE club_id = ? AND team_name = ?'
            )->execute([$newName, $cid, $existing['name']]);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }

    jsonOut(['success' => true, 'id' => $savedId]);
}

// ── DELETE — soft-delete team ─────────────────────────────────────────────────

if ($method === 'DELETE') {
    requireClubPermission($pdo, $user, 'teams.write');

    $id = $_GET['id'] ?? (json_decode(file_get_contents('php://input'), true)['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id required'], 422);

    $stmt = $pdo->prepare(
        'SELECT id, name FROM club_teams WHERE id = ? AND club_id = ? AND is_active = 1'
    );
    $stmt->execute([$id, $cid]);
    $team = $stmt->fetch();

    // An implicit legacy team uses its name as the temporary id returned by GET.
    $teamName = $team ? $team['name'] : $id;
    if (!$team) {
        $implicit = $pdo->prepare(
            "SELECT 1 FROM club_players
             WHERE club_id = ? AND team_name = ? AND is_active = 1 LIMIT 1"
        );
        $implicit->execute([$cid, $teamName]);
        if (!$implicit->fetchColumn()) jsonOut(['error' => 'Team not found'], 404);
    }

    $pdo->beginTransaction();
    try {
        if ($team) {
            $pdo->prepare(
                'UPDATE club_teams SET is_active = 0 WHERE id = ? AND club_id = ?'
            )->execute([$id, $cid]);
        }

        // Deleting a team never deletes its players. Detach them so GET does
        // not recreate the deleted team from their legacy team_name value.
        $detach = $pdo->prepare(
            'UPDATE club_players SET team_name = NULL WHERE club_id = ? AND team_name = ?'
        );
        $detach->execute([$cid, $teamName]);
        $detachedPlayers = $detach->rowCount();
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }

    jsonOut(['success' => true, 'detached_players' => $detachedPlayers]);
}

jsonOut(['error' => 'Method not allowed'], 405);
