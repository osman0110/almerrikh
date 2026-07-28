<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once 'db.php';
require_once 'includes/club_auth.php';

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
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

function requireCoachRole(array $user): void {
    if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
        jsonOut(['error' => 'Forbidden — coaches only'], 403);
    }
}

function scopedTeamPlayerIds(PDO $pdo, array $ctx): array {
    if ($ctx['team_id'] === null) return [];
    $teamStmt = $pdo->prepare(
        'SELECT name FROM club_teams WHERE id = ? AND club_id = ? AND is_active = 1'
    );
    $teamStmt->execute([(int)$ctx['team_id'], (int)$ctx['club_id']]);
    $teamName = $teamStmt->fetchColumn() ?: '';
    $stmt = $pdo->prepare(
        'SELECT id FROM club_players
         WHERE club_id = ? AND is_active = 1
           AND (team_id = ? OR (team_id IS NULL AND team_name = ?))'
    );
    $stmt->execute([
        (int)$ctx['club_id'],
        (int)$ctx['team_id'],
        $teamName,
    ]);
    return array_values(array_unique(array_map(
        'strval',
        $stmt->fetchAll(PDO::FETCH_COLUMN)
    )));
}

function matchInTeamScope(array $match, array $ctx, array $teamPlayerIds): bool {
    if ($ctx['team_id'] === null) return true;
    $matchPlayerIds = $match['player_ids'] ?? [];
    return is_array($matchPlayerIds)
        && (bool)array_intersect($matchPlayerIds, $teamPlayerIds);
}

function normalizeMatch(array &$r): void {
    $r['wellness_required'] = (bool)$r['wellness_required'];
    $r['rpe_required']      = (bool)$r['rpe_required'];
    $r['player_ids']      = $r['player_ids'] && $r['player_ids'] !== 'null'
        ? json_decode($r['player_ids'], true) ?? [] : [];
    $r['player_minutes']  = $r['player_minutes'] && $r['player_minutes'] !== 'null'
        ? json_decode($r['player_minutes'], true) ?? [] : [];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

// ── GET ────────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $singleId = $_GET['id'] ?? null;

    $ctx = requireClubPermission($pdo, $user, 'sessions.read');
    $teamPlayerIds = scopedTeamPlayerIds($pdo, $ctx);

    if ($singleId) {
        $stmt = $pdo->prepare('SELECT * FROM matches WHERE id = ? AND club_id = ?');
        $stmt->execute([$singleId, $ctx['club_id']]);
        $row = $stmt->fetch();
        if (!$row) jsonOut(['error' => 'Match not found'], 404);

        normalizeMatch($row);
        if (!matchInTeamScope($row, $ctx, $teamPlayerIds)) {
            jsonOut(['error' => 'Match not found'], 404);
        }

        // Include evaluations
        $ev = $pdo->prepare('SELECT * FROM coach_evaluations WHERE match_id = ?');
        $ev->execute([$singleId]);
        $row['evaluations'] = $ev->fetchAll();

        // Include survey responses count
        $sr = $pdo->prepare(
            "SELECT response_type, COUNT(*) as cnt FROM survey_responses WHERE match_id = ? GROUP BY response_type"
        );
        $sr->execute([$singleId]);
        $row['survey_counts'] = $sr->fetchAll();

        // Include cards (yellow/red) for this match
        $cardsStmt = $pdo->prepare(
            'SELECT id, match_id, player_id, card_type, minute, reason, created_at
             FROM match_cards WHERE match_id = ? ORDER BY minute ASC, created_at ASC'
        );
        $cardsStmt->execute([$singleId]);
        $row['cards'] = $cardsStmt->fetchAll();

        // Include per-player participation (starter/sub, minutes, position, goals/assists)
        $partStmt = $pdo->prepare(
            'SELECT id, match_id, player_id, starter, played, minute_in, minute_out,
                    minutes_played, position, goals, assists, not_played_reason
             FROM match_participations WHERE match_id = ? ORDER BY starter DESC, minute_in ASC'
        );
        $partStmt->execute([$singleId]);
        $row['participations'] = $partStmt->fetchAll();

        jsonOut(['match' => $row]);
    }

    $status = $_GET['status'] ?? null;
    $limit  = min((int)($_GET['limit'] ?? 50), 200);

    $where  = ['club_id = ?'];
    $params = [$ctx['club_id']];
    if ($status) { $where[] = 'status = ?'; $params[] = $status; }

    $sql = 'SELECT * FROM matches WHERE ' . implode(' AND ', $where)
         . ' ORDER BY match_date DESC, match_time DESC LIMIT ' . $limit;

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();

    foreach ($rows as &$r) { normalizeMatch($r); }
    unset($r);
    if ($ctx['team_id'] !== null) {
        $rows = array_values(array_filter(
            $rows,
            static fn(array $row): bool =>
                matchInTeamScope($row, $ctx, $teamPlayerIds)
        ));
    }

    jsonOut(['matches' => $rows, 'count' => count($rows)]);
}

// ── POST: create / update match ────────────────────────────────────────────────
if ($method === 'POST') {
    requireCoachRole($user);
    $body     = json_decode(file_get_contents('php://input'), true) ?? [];
    $action   = trim($body['action'] ?? '');

    // ── Cards: record yellow/red cards for a match (replaces the full set) ──────
    if ($action === 'cards') {
        $matchId = trim($body['match_id'] ?? '');
        if (!$matchId) jsonOut(['error' => 'match_id is required'], 400);

        $ownerStmt = $pdo->prepare('SELECT club_id FROM matches WHERE id = ?');
        $ownerStmt->execute([$matchId]);
        $match = $ownerStmt->fetch();
        if (!$match) jsonOut(['error' => 'Match not found'], 404);

        $ctx = requireClubPermission($pdo, $user, 'matches.update');
        if ((int)$match['club_id'] !== (int)$ctx['club_id']) jsonOut(['error' => 'Forbidden'], 403);

        $cards = $body['cards'] ?? [];
        if (!is_array($cards)) jsonOut(['error' => 'cards must be an array'], 422);

        $pdo->prepare('DELETE FROM match_cards WHERE match_id = ?')->execute([$matchId]);

        $insert = $pdo->prepare(
            'INSERT INTO match_cards (match_id, player_id, card_type, minute, reason, created_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        foreach ($cards as $c) {
            if (!is_array($c)) continue;
            $playerId = trim($c['player_id'] ?? '');
            $cardType = in_array($c['card_type'] ?? '', ['yellow', 'red'], true) ? $c['card_type'] : null;
            if (!$playerId || !$cardType) continue;
            $insert->execute([
                $matchId,
                $playerId,
                $cardType,
                isset($c['minute']) && $c['minute'] !== '' ? (int)$c['minute'] : null,
                $c['reason'] ?? null,
                (int)$user['id'],
            ]);
        }

        jsonOut(['success' => true]);
    }

    // ── Participations: record per-player match participation (replaces the
    // full set for this match) — starter/sub, minute in/out, position,
    // goals/assists, not-played reason. ───────────────────────────────────────
    if ($action === 'participations') {
        $matchId = trim($body['match_id'] ?? '');
        if (!$matchId) jsonOut(['error' => 'match_id is required'], 400);

        $ownerStmt = $pdo->prepare('SELECT club_id FROM matches WHERE id = ?');
        $ownerStmt->execute([$matchId]);
        $match = $ownerStmt->fetch();
        if (!$match) jsonOut(['error' => 'Match not found'], 404);

        $ctx = requireClubPermission($pdo, $user, 'matches.update');
        if ((int)$match['club_id'] !== (int)$ctx['club_id']) jsonOut(['error' => 'Forbidden'], 403);

        $participations = $body['participations'] ?? [];
        if (!is_array($participations)) jsonOut(['error' => 'participations must be an array'], 422);

        $pdo->prepare('DELETE FROM match_participations WHERE match_id = ?')->execute([$matchId]);

        $insert = $pdo->prepare(
            'INSERT INTO match_participations
                 (match_id, player_id, starter, played, minute_in, minute_out,
                  minutes_played, position, goals, assists, not_played_reason, created_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        foreach ($participations as $p) {
            if (!is_array($p)) continue;
            $playerId = trim($p['player_id'] ?? '');
            if (!$playerId) continue;
            $insert->execute([
                $matchId,
                $playerId,
                (int)(bool)($p['starter'] ?? false),
                (int)(bool)($p['played']  ?? true),
                isset($p['minute_in'])  && $p['minute_in']  !== '' ? (int)$p['minute_in']  : null,
                isset($p['minute_out']) && $p['minute_out'] !== '' ? (int)$p['minute_out'] : null,
                (int)($p['minutes_played'] ?? 0),
                $p['position'] ?? null,
                (int)($p['goals']   ?? 0),
                (int)($p['assists'] ?? 0),
                $p['not_played_reason'] ?? null,
                (int)$user['id'],
            ]);
        }

        jsonOut(['success' => true]);
    }

    $id       = trim($body['id'] ?? '');
    $opponent = trim($body['opponent'] ?? '');
    $date     = trim($body['match_date'] ?? $body['date'] ?? '');

    if (!$id)       jsonOut(['error' => 'id is required'], 400);
    if (!$opponent) jsonOut(['error' => 'opponent is required'], 400);
    if (!$date)     jsonOut(['error' => 'match_date is required'], 400);

    // Ownership check for updates
    $existStmt = $pdo->prepare('SELECT club_id FROM matches WHERE id = ?');
    $existStmt->execute([$id]);
    $existing = $existStmt->fetch();
    $ctx = requireClubPermission(
        $pdo,
        $user,
        $existing ? 'matches.update' : 'matches.create'
    );
    if ($existing && (int)$existing['club_id'] !== (int)$ctx['club_id']) {
        jsonOut(['error' => 'Forbidden'], 403);
    }

    $playerIds    = $body['player_ids'] ?? [];
    $playerMinutes = $body['player_minutes'] ?? [];
    if (is_string($playerIds)) $playerIds = json_decode($playerIds, true) ?? [];
    $playerIds = is_array($playerIds)
        ? array_values(array_unique(array_map('strval', $playerIds)))
        : [];
    if ($ctx['team_id'] !== null) {
        $allowedPlayerIds = scopedTeamPlayerIds($pdo, $ctx);
    } else {
        $allowedStmt = $pdo->prepare(
            'SELECT id FROM club_players WHERE club_id = ? AND is_active = 1'
        );
        $allowedStmt->execute([$ctx['club_id']]);
        $allowedPlayerIds = array_values(array_unique(array_map(
            'strval',
            $allowedStmt->fetchAll(PDO::FETCH_COLUMN)
        )));
    }
    $playerIds = array_values(array_intersect($playerIds, $allowedPlayerIds));
    if (is_string($playerMinutes)) {
        $playerMinutes = json_decode($playerMinutes, true) ?? [];
    }
    $playerMinutes = is_array($playerMinutes)
        ? array_intersect_key($playerMinutes, array_fill_keys($playerIds, true))
        : [];
    $competitionId = isset($body['competition_id']) && $body['competition_id'] !== ''
        ? (int)$body['competition_id'] : null;

    $stmt = $pdo->prepare(
        'INSERT INTO matches
             (id, user_id, club_id, opponent, match_date, match_time, location, status,
              player_ids, player_minutes, competition_id, wellness_required, rpe_required, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
             club_id           = COALESCE(VALUES(club_id), club_id),
             opponent          = VALUES(opponent),
             match_date        = VALUES(match_date),
             match_time        = VALUES(match_time),
             location          = VALUES(location),
             status            = VALUES(status),
             player_ids        = VALUES(player_ids),
             player_minutes    = VALUES(player_minutes),
             competition_id    = VALUES(competition_id),
             wellness_required = VALUES(wellness_required),
             rpe_required      = VALUES(rpe_required),
             notes             = VALUES(notes)'
    );

    $stmt->execute([
        $id,
        $user['id'],
        $ctx['club_id'],
        $opponent,
        $date,
        $body['match_time'] ?? $body['time'] ?? '16:00',
        $body['location']   ?? null,
        $body['status']     ?? 'scheduled',
        is_array($playerIds)     ? json_encode($playerIds)     : ($playerIds     ?: '[]'),
        is_array($playerMinutes) ? json_encode($playerMinutes) : ($playerMinutes ?: '{}'),
        $competitionId,
        (int)(bool)($body['wellness_required'] ?? false),
        (int)(bool)($body['rpe_required']      ?? false),
        $body['notes'] ?? null,
    ]);

    jsonOut(['success' => true, 'id' => $id]);
}

// ── DELETE ─────────────────────────────────────────────────────────────────────
if ($method === 'DELETE') {
    requireCoachRole($user);
    $ctx = requireClubPermission($pdo, $user, 'matches.delete');
    $id = $_GET['id'] ?? (json_decode(file_get_contents('php://input'), true)['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id is required'], 400);

    $stmt = $pdo->prepare('DELETE FROM matches WHERE id = ? AND club_id = ?');
    $stmt->execute([$id, $ctx['club_id']]);
    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
