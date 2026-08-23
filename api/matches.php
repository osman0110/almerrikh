<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once 'db.php';
require_once 'includes/club_auth.php';
require_once 'includes/notifications.php';
require_once 'includes/discipline.php';

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

function normalizeMatch(array &$r): void {
    $r['wellness_required'] = (bool)$r['wellness_required'];
    $r['rpe_required']      = (bool)$r['rpe_required'];
    $r['player_ids']      = $r['player_ids'] && $r['player_ids'] !== 'null'
        ? json_decode($r['player_ids'], true) ?? [] : [];
    $r['player_minutes']  = $r['player_minutes'] && $r['player_minutes'] !== 'null'
        ? json_decode($r['player_minutes'], true) ?? [] : [];
    $r['clock_running'] = (bool)($r['clock_running'] ?? false);
    $r['elapsed_seconds'] = max(0, (int)($r['elapsed_seconds'] ?? 0));
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

// ── GET ────────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $singleId = $_GET['id'] ?? null;

    $ctx = requireClubPermission($pdo, $user, 'sessions.read');

    if ($singleId) {
        $stmt = $pdo->prepare(
            'SELECT m.*, cc.name AS competition_name,
                    CASE WHEN m.actual_started_at IS NULL THEN 0
                         ELSE TIMESTAMPDIFF(SECOND, m.actual_started_at,
                              COALESCE(m.actual_ended_at, UTC_TIMESTAMP())) END AS elapsed_seconds,
                    (m.actual_started_at IS NOT NULL AND m.actual_ended_at IS NULL
                     AND m.status = "active") AS clock_running
             FROM matches m
             LEFT JOIN club_competitions cc ON cc.id = m.competition_id
             WHERE m.id = ? AND m.club_id = ?'
        );
        $stmt->execute([$singleId, $ctx['club_id']]);
        $row = $stmt->fetch();
        if (!$row) jsonOut(['error' => 'Match not found'], 404);

        normalizeMatch($row);

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
                    minutes_played, position, goals, assists, not_played_reason, rating, injured,
                    timer_started_at IS NOT NULL AS clock_running,
                    accumulated_seconds + CASE WHEN timer_started_at IS NULL THEN 0
                        ELSE TIMESTAMPDIFF(SECOND, timer_started_at, UTC_TIMESTAMP()) END AS elapsed_seconds
             FROM match_participations WHERE match_id = ? ORDER BY starter DESC, minute_in ASC'
        );
        $partStmt->execute([$singleId]);
        $row['participations'] = $partStmt->fetchAll();

        jsonOut(['match' => $row]);
    }

    $status = $_GET['status'] ?? null;
    $limit  = min((int)($_GET['limit'] ?? 50), 200);

    $where  = ['m.club_id = ?'];
    $params = [$ctx['club_id']];
    if ($status) { $where[] = 'm.status = ?'; $params[] = $status; }

    $sql = 'SELECT m.*, cc.name AS competition_name,
                   CASE WHEN m.actual_started_at IS NULL THEN 0
                        ELSE TIMESTAMPDIFF(SECOND, m.actual_started_at,
                             COALESCE(m.actual_ended_at, UTC_TIMESTAMP())) END AS elapsed_seconds,
                   (m.actual_started_at IS NOT NULL AND m.actual_ended_at IS NULL
                    AND m.status = "active") AS clock_running
            FROM matches m
            LEFT JOIN club_competitions cc ON cc.id = m.competition_id
            WHERE ' . implode(' AND ', $where)
         . ' ORDER BY m.match_date DESC, m.match_time DESC LIMIT ' . $limit;

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();

    foreach ($rows as &$r) { normalizeMatch($r); }
    unset($r);

    jsonOut(['matches' => $rows, 'count' => count($rows)]);
}

// ── POST: create / update match ────────────────────────────────────────────────
if ($method === 'POST') {
    requireCoachRole($user);
    $body     = json_decode(file_get_contents('php://input'), true) ?? [];
    $action   = trim($body['action'] ?? '');

    if (in_array($action, ['clock', 'starter', 'stat'], true)) {
        $matchId = trim($body['match_id'] ?? '');
        if (!$matchId) jsonOut(['error' => 'match_id is required'], 400);

        $ownerStmt = $pdo->prepare('SELECT * FROM matches WHERE id = ?');
        $ownerStmt->execute([$matchId]);
        $match = $ownerStmt->fetch(PDO::FETCH_ASSOC);
        if (!$match) jsonOut(['error' => 'Match not found'], 404);

        $ctx = requireClubPermission($pdo, $user, 'matches.live');
        if ((int)$match['club_id'] !== (int)$ctx['club_id']) {
            jsonOut(['error' => 'Forbidden'], 403);
        }

        $playerIds = $match['player_ids'] && $match['player_ids'] !== 'null'
            ? json_decode($match['player_ids'], true) ?? [] : [];
        $playerIds = array_map('strval', $playerIds);
        $playerId = trim($body['player_id'] ?? '');
        if ($playerId !== '' && !in_array($playerId, $playerIds, true)) {
            jsonOut(['error' => 'Player is not assigned to this match'], 422);
        }

        $ensureParticipation = $pdo->prepare(
            'INSERT IGNORE INTO match_participations
                 (match_id, player_id, starter, played, minutes_played, goals, assists, created_by_user_id)
             VALUES (?, ?, 0, 1, 0, 0, 0, ?)'
        );

        if ($action === 'starter') {
            if ($match['actual_started_at'] !== null) {
                jsonOut(['error' => 'Starting lineup cannot be changed after the match starts'], 409);
            }
            if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);
            $ensureParticipation->execute([$matchId, $playerId, (int)$user['id']]);
            $pdo->prepare(
                'UPDATE match_participations SET starter = ?, played = ?
                 WHERE match_id = ? AND player_id = ?'
            )->execute([(int)(bool)($body['starter'] ?? false), (int)(bool)($body['starter'] ?? false), $matchId, $playerId]);
            jsonOut(['success' => true]);
        }

        if ($action === 'stat') {
            if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);
            $stat = $body['stat'] ?? '';
            if (!in_array($stat, ['goals', 'assists'], true)) {
                jsonOut(['error' => 'Unsupported stat'], 422);
            }
            $ensureParticipation->execute([$matchId, $playerId, (int)$user['id']]);
            $pdo->prepare("UPDATE match_participations SET {$stat} = {$stat} + 1 WHERE match_id = ? AND player_id = ?")
                ->execute([$matchId, $playerId]);
            jsonOut(['success' => true]);
        }

        $operation = trim($body['operation'] ?? '');
        $pdo->beginTransaction();
        try {
            if ($operation === 'start_match') {
                $starterCount = $pdo->prepare('SELECT COUNT(*) FROM match_participations WHERE match_id = ? AND starter = 1');
                $starterCount->execute([$matchId]);
                if ((int)$starterCount->fetchColumn() === 0) {
                    $pdo->rollBack();
                    jsonOut(['error' => 'Select the starting players first'], 422);
                }
                $pdo->prepare(
                    "UPDATE matches SET actual_started_at = COALESCE(actual_started_at, UTC_TIMESTAMP()),
                     actual_ended_at = NULL, status = 'active' WHERE id = ?"
                )->execute([$matchId]);
                $pdo->prepare(
                    'UPDATE match_participations
                     SET timer_started_at = COALESCE(timer_started_at, UTC_TIMESTAMP()),
                         played = 1, minute_in = COALESCE(minute_in, 0)
                     WHERE match_id = ? AND starter = 1'
                )->execute([$matchId]);
            } elseif ($operation === 'finish_match') {
                $elapsedStmt = $pdo->prepare(
                    'SELECT GREATEST(0, TIMESTAMPDIFF(SECOND, actual_started_at, UTC_TIMESTAMP()))
                     FROM matches WHERE id = ?'
                );
                $elapsedStmt->execute([$matchId]);
                $matchSeconds = (int)$elapsedStmt->fetchColumn();
                $pdo->prepare(
                    'UPDATE match_participations
                     SET minutes_played = ROUND((accumulated_seconds + CASE WHEN timer_started_at IS NULL THEN 0
                             ELSE GREATEST(0, TIMESTAMPDIFF(SECOND, timer_started_at, UTC_TIMESTAMP())) END) / 60),
                         accumulated_seconds = accumulated_seconds + CASE WHEN timer_started_at IS NULL THEN 0
                             ELSE GREATEST(0, TIMESTAMPDIFF(SECOND, timer_started_at, UTC_TIMESTAMP())) END,
                         minute_out = CASE WHEN timer_started_at IS NULL THEN minute_out ELSE ? END,
                         timer_started_at = NULL
                     WHERE match_id = ?'
                )->execute([(int)floor($matchSeconds / 60), $matchId]);
                $pdo->prepare(
                    "UPDATE matches SET actual_ended_at = UTC_TIMESTAMP(), status = 'completed' WHERE id = ?"
                )->execute([$matchId]);
            } elseif ($operation === 'start_player') {
                if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);
                $ensureParticipation->execute([$matchId, $playerId, (int)$user['id']]);
                $pdo->prepare(
                    'UPDATE match_participations mp JOIN matches m ON m.id = mp.match_id
                     SET mp.timer_started_at = COALESCE(mp.timer_started_at, UTC_TIMESTAMP()), mp.played = 1,
                         mp.minute_in = COALESCE(mp.minute_in,
                             FLOOR(TIMESTAMPDIFF(SECOND, m.actual_started_at, UTC_TIMESTAMP()) / 60))
                     WHERE mp.match_id = ? AND mp.player_id = ? AND m.actual_started_at IS NOT NULL
                           AND m.actual_ended_at IS NULL'
                )->execute([$matchId, $playerId]);
            } elseif ($operation === 'stop_player') {
                if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);
                $pdo->prepare(
                    'UPDATE match_participations mp JOIN matches m ON m.id = mp.match_id
                     SET mp.minutes_played = ROUND((mp.accumulated_seconds +
                             GREATEST(0, TIMESTAMPDIFF(SECOND, mp.timer_started_at, UTC_TIMESTAMP()))) / 60),
                         mp.accumulated_seconds = mp.accumulated_seconds +
                             GREATEST(0, TIMESTAMPDIFF(SECOND, mp.timer_started_at, UTC_TIMESTAMP())),
                         mp.minute_out = FLOOR(TIMESTAMPDIFF(SECOND, m.actual_started_at, UTC_TIMESTAMP()) / 60),
                         mp.timer_started_at = NULL
                     WHERE mp.match_id = ? AND mp.player_id = ? AND mp.timer_started_at IS NOT NULL'
                )->execute([$matchId, $playerId]);
            } else {
                $pdo->rollBack();
                jsonOut(['error' => 'Unsupported clock operation'], 422);
            }
            $pdo->commit();
            jsonOut(['success' => true]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            jsonOut(['error' => 'Unable to update match clock'], 500);
        }
    }

    // ── Cards: record yellow/red cards for a match (replaces the full set) ──────
    if ($action === 'cards') {
        $matchId = trim($body['match_id'] ?? '');
        if (!$matchId) jsonOut(['error' => 'match_id is required'], 400);

        $ownerStmt = $pdo->prepare('SELECT id, club_id, competition_id, match_date, status FROM matches WHERE id = ?');
        $ownerStmt->execute([$matchId]);
        $match = $ownerStmt->fetch();
        if (!$match) jsonOut(['error' => 'Match not found'], 404);

        $ctx = requireClubPermission($pdo, $user, 'matches.live');
        if ((int)$match['club_id'] !== (int)$ctx['club_id']) jsonOut(['error' => 'Forbidden'], 403);

        $cards = $body['cards'] ?? [];
        if (!is_array($cards)) jsonOut(['error' => 'cards must be an array'], 422);

        $insert = $pdo->prepare(
            'INSERT INTO match_cards (match_id, player_id, card_type, minute, reason, created_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        $newCardIds = [];
        foreach ($cards as $c) {
            if (!is_array($c)) continue;
            $playerId = trim($c['player_id'] ?? '');
            $cardType = in_array($c['card_type'] ?? '', ['yellow', 'red'], true) ? $c['card_type'] : null;
            if (!$playerId || !$cardType) continue;
            $duplicate = $pdo->prepare(
                'SELECT id FROM match_cards WHERE match_id = ? AND player_id = ? AND card_type = ?
                 AND COALESCE(minute, -1) = COALESCE(?, -1) AND COALESCE(reason, "") = COALESCE(?, "") LIMIT 1'
            );
            $duplicate->execute([$matchId, $playerId, $cardType, $c['minute'] ?? null, $c['reason'] ?? null]);
            if ($duplicate->fetchColumn()) continue;
            $insert->execute([
                $matchId,
                $playerId,
                $cardType,
                isset($c['minute']) && $c['minute'] !== '' ? (int)$c['minute'] : null,
                $c['reason'] ?? null,
                (int)$user['id'],
            ]);
            $newCardIds[] = (int)$pdo->lastInsertId();
        }

        $match['_new_card_ids'] = $newCardIds;
        disciplineProcessCards($pdo, $match, (int)$user['id']);

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
                  minutes_played, position, goals, assists, not_played_reason, created_by_user_id,
                  rating, injured)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
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
                isset($p['rating']) && $p['rating'] !== '' ? (float)$p['rating'] : null,
                (int)(bool)($p['injured'] ?? false),
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
    $competitionId = isset($body['competition_id']) && $body['competition_id'] !== ''
        ? (int)$body['competition_id'] : null;

    if (($body['status'] ?? 'scheduled') !== 'cancelled') {
        try {
            disciplineAssertPlayersEligible(
                $pdo,
                (int)$ctx['club_id'],
                $competitionId,
                is_array($playerIds) ? array_values(array_filter(array_map('strval', $playerIds))) : []
            );
        } catch (RuntimeException $e) {
            jsonOut(['error' => $e->getMessage()], 422);
        }
    }

    $stage      = $body['stage']       ?? null;
    $roundLabel = $body['round_label'] ?? null;
    $groupName  = $body['group_name']  ?? null;
    $ourScore      = isset($body['our_score'])      && $body['our_score']      !== '' ? (int)$body['our_score']      : null;
    $opponentScore = isset($body['opponent_score']) && $body['opponent_score'] !== '' ? (int)$body['opponent_score'] : null;

    $stmt = $pdo->prepare(
        'INSERT INTO matches
             (id, user_id, club_id, opponent, match_date, match_time, location, status,
              player_ids, player_minutes, competition_id, wellness_required, rpe_required, notes,
              stage, round_label, group_name, our_score, opponent_score)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
             notes             = VALUES(notes),
             stage             = VALUES(stage),
             round_label       = VALUES(round_label),
             group_name        = VALUES(group_name),
             our_score         = VALUES(our_score),
             opponent_score    = VALUES(opponent_score)'
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
        $stage,
        $roundLabel,
        $groupName,
        $ourScore,
        $opponentScore,
    ]);

    disciplineAdvanceForCompletedMatch($pdo, [
        'id' => $id,
        'club_id' => $ctx['club_id'],
        'competition_id' => $competitionId,
        'match_date' => $date,
        'status' => $body['status'] ?? 'scheduled',
    ]);

    // Newly scheduled match — alert the selected players and the coaching
    // staff. Updates to an existing match stay silent.
    if (!$existing && is_array($playerIds) && $playerIds) {
        $placeholders = implode(',', array_fill(0, count($playerIds), '?'));
        $linkedStmt = $pdo->prepare(
            "SELECT linked_user_id FROM club_players WHERE id IN ($placeholders) AND linked_user_id IS NOT NULL"
        );
        $linkedStmt->execute($playerIds);
        $when = "$date " . ($body['match_time'] ?? $body['time'] ?? '');
        foreach ($linkedStmt->fetchAll(PDO::FETCH_COLUMN) as $linkedUserId) {
            createNotification(
                $pdo, (int)$ctx['club_id'], (int)$linkedUserId, 'match_scheduled',
                ['opponent' => $opponent, 'when' => $when], '/match/' . $id
            );
        }
        notifyClubRole($pdo, (int)$ctx['club_id'], 'coach', 'match_scheduled_coach', ['opponent' => $opponent, 'when' => $when], ['linked_route' => '/match/' . $id]);
    }

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
