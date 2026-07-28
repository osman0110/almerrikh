<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once 'db.php';
require_once 'includes/club_auth.php';
require_once 'includes/audit_log.php';

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

function sessionTeamScope(PDO $pdo, array $ctx, string $alias = ''): array {
    if ($ctx['team_id'] === null) return ['', []];
    $teamStmt = $pdo->prepare(
        'SELECT name FROM club_teams WHERE id = ? AND club_id = ? AND is_active = 1'
    );
    $teamStmt->execute([(int)$ctx['team_id'], (int)$ctx['club_id']]);
    $teamName = $teamStmt->fetchColumn() ?: '';
    $prefix = $alias !== '' ? $alias . '.' : '';
    return [
        " AND ({$prefix}team_id = ? OR ({$prefix}team_id IS NULL AND {$prefix}team_name = ?))",
        [(int)$ctx['team_id'], $teamName],
    ];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

// ── GET: list or single session ───────────────────────────────────────────────
if ($method === 'GET') {
    $singleId = $_GET['id'] ?? null;
    $ctx = requireClubPermission($pdo, $user, 'sessions.read');
    [$teamSql, $teamParams] = sessionTeamScope($pdo, $ctx, 'cs');

    if ($singleId) {
        $stmt = $pdo->prepare(
            "SELECT cs.*,
                    (SELECT COUNT(*)
                     FROM session_attendance sa
                     WHERE sa.session_id = cs.id
                       AND sa.status IN ('present', 'late')) AS attendance_present_count
             FROM club_sessions cs
             WHERE cs.id = ? AND cs.club_id = ?$teamSql"
        );
        $stmt->execute([$singleId, $ctx['club_id'], ...$teamParams]);
        $row = $stmt->fetch();
        if (!$row) jsonOut(['error' => 'Session not found'], 404);
        normalizeSession($row);

        // ── Roster + real attendance + wellness snapshot ──────────────────────
        if (($_GET['roster'] ?? '') === '1') {
            $playerIds = $row['player_ids'];
            $participants = [];

            if (!empty($playerIds)) {
                $placeholders = implode(',', array_fill(0, count($playerIds), '?'));
                $pStmt = $pdo->prepare(
                    "SELECT id, name, position, number, linked_user_id, status AS player_status
                     FROM club_players
                     WHERE id IN ($placeholders) AND club_id = ?" .
                     ($ctx['team_id'] !== null
                        ? ' AND (team_id = ? OR (team_id IS NULL AND team_name = ?))'
                        : '') . "
                     ORDER BY CASE WHEN number IS NULL OR number = 0 THEN 1 ELSE 0 END,
                              number ASC, name ASC"
                );
                $pStmt->execute([
                    ...$playerIds,
                    $ctx['club_id'],
                    ...($ctx['team_id'] !== null ? $teamParams : []),
                ]);
                $players = $pStmt->fetchAll(PDO::FETCH_ASSOC);

                $aStmt = $pdo->prepare(
                    'SELECT player_id, status FROM session_attendance WHERE session_id = ?'
                );
                $aStmt->execute([$singleId]);
                $attendanceByPlayer = [];
                foreach ($aStmt->fetchAll(PDO::FETCH_ASSOC) as $a) {
                    $attendanceByPlayer[$a['player_id']] = $a['status'];
                }

                foreach ($players as $p) {
                    $hooperScore = null;
                    if (!empty($p['linked_user_id'])) {
                        $hStmt = $pdo->prepare(
                            'SELECT hooper_score FROM player_hooper_index
                             WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 1'
                        );
                        $hStmt->execute([(int)$p['linked_user_id']]);
                        $hRow = $hStmt->fetch(PDO::FETCH_ASSOC);
                        $hooperScore = $hRow ? (int)$hRow['hooper_score'] : null;
                    }

                    $playerStatus = $p['player_status'] ?? 'active';
                    $wellnessLabel = 'ready';
                    if ($playerStatus !== 'active') {
                        $wellnessLabel = 'injured';
                    } elseif ($hooperScore !== null && $hooperScore > 16) {
                        $wellnessLabel = 'high_risk';
                    } elseif ($hooperScore !== null && $hooperScore > 10) {
                        $wellnessLabel = 'fatigue';
                    }

                    $participants[] = [
                        'id'                => $p['id'],
                        'number'            => (int)($p['number'] ?? 0),
                        'name'              => $p['name'],
                        'position'          => $p['position'] ?? '',
                        'attendance_status' => $attendanceByPlayer[$p['id']] ?? 'pending',
                        'player_status'     => $wellnessLabel,
                        'hooper_score'      => $hooperScore,
                    ];
                }
            }

            jsonOut(['session' => $row, 'participants' => $participants]);
        }

        jsonOut(['session' => $row]);
    }

    $date   = $_GET['date']   ?? null;
    $status = $_GET['status'] ?? null;
    $limit  = min((int)($_GET['limit'] ?? 50), 200);

    $where = ['cs.club_id = ?'];
    $params = [$ctx['club_id']];
    if ($teamSql !== '') {
        $where[] = substr($teamSql, 5);
        $params = [...$params, ...$teamParams];
    }

    if ($date)   { $where[] = 'cs.date = ?';   $params[] = $date; }
    if ($status) { $where[] = 'cs.status = ?'; $params[] = $status; }

    $sql = "SELECT cs.*,
                   (SELECT COUNT(*)
                    FROM session_attendance sa
                    WHERE sa.session_id = cs.id
                      AND sa.status IN ('present', 'late')) AS attendance_present_count
            FROM club_sessions cs WHERE " . implode(' AND ', $where)
         . ' ORDER BY cs.date DESC, cs.start_time ASC LIMIT ' . $limit;

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();

    foreach ($rows as &$r) { normalizeSession($r); }
    unset($r);

    jsonOut(['sessions' => $rows, 'count' => count($rows)]);
}

function normalizeSession(array &$r): void {
    $r['duration_min']        = (int)$r['duration_min'];
    $r['player_count']        = (int)$r['player_count'];
    $r['assessment_count']    = (int)($r['assessment_count'] ?? 0);
    $r['attendance_present_count'] = (int)($r['attendance_present_count'] ?? 0);
    $r['ai_enabled']          = (bool)$r['ai_enabled'];
    $r['attendance_required'] = (bool)$r['attendance_required'];
    $r['rpe_required']        = (bool)$r['rpe_required'];
    $r['wellness_required']   = (bool)$r['wellness_required'];
    // Decode JSON arrays
    $r['player_ids']           = $r['player_ids'] && $r['player_ids'] !== 'null'
        ? json_decode($r['player_ids'], true) ?? [] : [];
    $r['completed_player_ids'] = $r['completed_player_ids'] && $r['completed_player_ids'] !== 'null'
        ? json_decode($r['completed_player_ids'], true) ?? [] : [];
    $r['player_ids'] = array_values(array_unique(array_map('strval', $r['player_ids'])));
    $r['completed_player_ids'] = array_values(array_unique(array_map(
        'strval',
        $r['completed_player_ids']
    )));
    $r['assessment_types'] = isset($r['assessment_types']) && $r['assessment_types'] && $r['assessment_types'] !== 'null'
        ? json_decode($r['assessment_types'], true) ?? [] : [];
}

// ── POST: create / update / sub-actions ──────────────────────────────────────
if ($method === 'POST') {
    requireCoachRole($user);
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? '');

    // ── Attendance: mark which players were present/absent/late ──────────────
    if ($action === 'attendance') {
        $sessionId  = trim($body['session_id'] ?? '');
        $attendance = $body['attendance'] ?? []; // {player_id: 'present'|'absent'|'late'}

        if (!$sessionId) jsonOut(['error' => 'session_id required'], 400);

        $ctx = requireClubPermission($pdo, $user, 'sessions.write');
        [$teamSql, $teamParams] = sessionTeamScope($pdo, $ctx);
        $ownerStmt = $pdo->prepare(
            'SELECT id, player_ids, linked_training_session_id
             FROM club_sessions WHERE id = ? AND club_id = ?' . $teamSql
        );
        $ownerStmt->execute([$sessionId, $ctx['club_id'], ...$teamParams]);
        $ownerRow = $ownerStmt->fetch(PDO::FETCH_ASSOC);
        if (!$ownerRow) jsonOut(['error' => 'Session not found'], 404);
        $linkedTrainingSessionId = $ownerRow['linked_training_session_id'] ?? null;
        $rosterIds = json_decode($ownerRow['player_ids'] ?? '[]', true);
        $rosterIds = is_array($rosterIds)
            ? array_values(array_unique(array_map('strval', $rosterIds)))
            : [];
        $existingAttendanceStmt = $pdo->prepare(
            'SELECT player_id, status FROM session_attendance WHERE session_id = ?'
        );
        $existingAttendanceStmt->execute([$sessionId]);
        $existingAttendance = [];
        foreach ($existingAttendanceStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $existingAttendance[(string)$row['player_id']] = (string)$row['status'];
        }

        $validStatuses = ['present', 'absent', 'late'];
        $attStmt = $pdo->prepare(
            'INSERT INTO session_attendance (session_id, player_id, user_id, status, marked_at)
             VALUES (?, ?, ?, ?, NOW())
             ON DUPLICATE KEY UPDATE status = VALUES(status), marked_at = VALUES(marked_at)'
        );
        // Only fires when this club_sessions row is explicitly linked to a
        // training_sessions row (linked_training_session_id) — bridges real
        // coach-taken attendance into the wellness workflow's own session
        // state, so an absence actually reaches session_players.status
        // ('missed' was previously defined in the schema but never written
        // anywhere). Never overwrites a player who already progressed
        // further (pre_checked/started/completed) in that workflow.
        $missedStmt = $linkedTrainingSessionId ? $pdo->prepare(
            "UPDATE session_players sp
             JOIN club_players cp ON cp.linked_user_id = sp.player_user_id
             SET sp.status = 'missed'
             WHERE sp.session_id = ? AND cp.id = ? AND sp.status = 'assigned'"
        ) : null;

        foreach ($attendance as $playerId => $status) {
            $playerId = (string)$playerId;
            if (!in_array($playerId, $rosterIds, true)) continue;
            if (!in_array($status, $validStatuses, true)) continue;
            $attStmt->execute([$sessionId, $playerId, $user['id'], $status]);
            if (($existingAttendance[$playerId] ?? null) !== $status) {
                logFitnessAudit(
                    $pdo,
                    'session_attendance',
                    $sessionId . ':' . $playerId,
                    'attendance.update',
                    (int)$user['id'],
                    (int)$ctx['club_id'],
                    $playerId,
                    ['status' => $existingAttendance[$playerId] ?? null],
                    ['status' => $status, 'session_id' => $sessionId],
                    null,
                    isset($body['operation_id']) ? (string)$body['operation_id'] : null
                );
            }
            if ($status === 'absent' && $missedStmt) {
                $missedStmt->execute([$linkedTrainingSessionId, $playerId]);
            }
        }

        $present = array_values(array_filter(
            $rosterIds,
            fn($pid) => in_array($attendance[$pid] ?? '', ['present', 'late'], true)
        ));

        // Keep only the roster count in sync. completed_player_ids belongs to
        // physical assessments and must never be overwritten by attendance.
        $stmt = $pdo->prepare(
            'UPDATE club_sessions SET player_count = ? WHERE id = ? AND club_id = ?'
        );
        $stmt->execute([
            count($rosterIds),
            $sessionId,
            $ctx['club_id'],
        ]);

        jsonOut(['success' => true, 'present_count' => count($present)]);
    }

    // ── Add exercise to a session ─────────────────────────────────────────────
    if ($action === 'add_exercise') {
        $sessionId = trim($body['session_id'] ?? '');
        if (!$sessionId) jsonOut(['error' => 'session_id required'], 400);

        $ctx = requireClubPermission($pdo, $user, 'sessions.write');
        [$teamSql, $teamParams] = sessionTeamScope($pdo, $ctx);
        $ownerStmt = $pdo->prepare(
            'SELECT id FROM club_sessions WHERE id = ? AND club_id = ?' . $teamSql
        );
        $ownerStmt->execute([$sessionId, $ctx['club_id'], ...$teamParams]);
        if (!$ownerStmt->fetch()) jsonOut(['error' => 'Session not found'], 404);

        $name = trim($body['exercise_name'] ?? $body['name'] ?? '');
        if (!$name) jsonOut(['error' => 'exercise_name required'], 400);

        $maxStmt = $pdo->prepare(
            'SELECT COALESCE(MAX(sort_order), -1) FROM club_session_exercises WHERE session_id = ?'
        );
        $maxStmt->execute([$sessionId]);
        $nextOrder = (int)$maxStmt->fetchColumn() + 1;

        $stmt = $pdo->prepare(
            'INSERT INTO club_session_exercises
                 (session_id, exercise_type, exercise_name, category, sets, reps,
                  duration_seconds, rest_seconds, intensity, assessment_type, notes, sort_order)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $sessionId,
            $body['exercise_type']   ?? 'manual',
            $name,
            $body['category']        ?? null,
            isset($body['sets'])              ? (int)$body['sets']             : null,
            isset($body['reps'])              ? (int)$body['reps']             : null,
            isset($body['duration_seconds'])  ? (int)$body['duration_seconds'] : null,
            isset($body['rest_seconds'])      ? (int)$body['rest_seconds']     : null,
            $body['intensity']       ?? 'medium',
            $body['assessment_type'] ?? null,
            $body['notes']           ?? null,
            isset($body['sort_order']) ? (int)$body['sort_order'] : $nextOrder,
        ]);

        jsonOut(['success' => true, 'id' => (int)$pdo->lastInsertId()]);
    }

    // ── Upsert session (default action) ──────────────────────────────────────
    $id    = trim($body['id'] ?? '');
    $title = trim($body['title'] ?? '');
    $date  = trim($body['date'] ?? '');

    if (!$id)    jsonOut(['error' => 'id is required'], 400);
    if (!$title) jsonOut(['error' => 'title is required'], 400);
    if (!$date)  jsonOut(['error' => 'date is required'], 400);

    // Sessions belong to the whole club (shared across every coach/staff
    // member), not to whichever coach created them — resolve the real club
    // and gate/scope on that instead of a strict creator-id match.
    $sessionCtx = requireClubPermission($pdo, $user, 'sessions.write');
    $sessionClubId = $sessionCtx['club_id'];
    [, $writeTeamParams] = sessionTeamScope($pdo, $sessionCtx);
    $sessionTeamId = $sessionCtx['team_id'] !== null
        ? (int)$sessionCtx['team_id']
        : (
            isset($body['team_id']) && $body['team_id'] !== ''
                ? (int)$body['team_id']
                : null
        );

    // Ownership check for updates
    if ($id) {
        $existStmt = $pdo->prepare(
            'SELECT user_id, club_id, team_id, team_name FROM club_sessions WHERE id = ?'
        );
        $existStmt->execute([$id]);
        $existing = $existStmt->fetch();
        if ($existing) {
            $sameClub = $sessionClubId !== null && (int)($existing['club_id'] ?? 0) === (int)$sessionClubId;
            $sameCreator = (int)$existing['user_id'] === (int)$user['id'];
            $sameTeam = $sessionCtx['team_id'] === null
                || (int)($existing['team_id'] ?? 0) === (int)$sessionCtx['team_id']
                || (
                    $existing['team_id'] === null
                    && (string)($existing['team_name'] ?? '') === (string)($writeTeamParams[1] ?? '')
                );
            if ((!$sameClub && !$sameCreator) || !$sameTeam) {
                jsonOut(['error' => 'Forbidden'], 403);
            }
        }
    }

    $stmt = $pdo->prepare(
        'INSERT INTO club_sessions
             (id, user_id, club_id, team_id, title, type, scope, status, date, start_time, end_time,
              duration_min, location, team_name, player_count, intensity, ai_enabled,
              attendance_required, rpe_required, wellness_required, coach_name, notes,
              player_ids, completed_player_ids, assessment_count, assessment_types, position_filter,
              linked_training_session_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
             club_id                = VALUES(club_id),
             team_id                = VALUES(team_id),
             title                  = VALUES(title),
             type                   = VALUES(type),
             scope                  = VALUES(scope),
             status                 = VALUES(status),
             date                   = VALUES(date),
             start_time             = VALUES(start_time),
             end_time               = VALUES(end_time),
             duration_min           = VALUES(duration_min),
             location               = VALUES(location),
             team_name              = VALUES(team_name),
             player_count           = VALUES(player_count),
             intensity              = VALUES(intensity),
             ai_enabled             = VALUES(ai_enabled),
             attendance_required    = VALUES(attendance_required),
             rpe_required           = VALUES(rpe_required),
             wellness_required      = VALUES(wellness_required),
             coach_name             = VALUES(coach_name),
             notes                  = VALUES(notes),
             player_ids             = VALUES(player_ids),
             completed_player_ids   = VALUES(completed_player_ids),
             assessment_count       = VALUES(assessment_count),
             assessment_types       = VALUES(assessment_types),
             position_filter        = VALUES(position_filter),
             linked_training_session_id = VALUES(linked_training_session_id)'
    );

    // Normalize player_ids / completed_player_ids / assessment_types to JSON strings
    $playerIds = $body['player_ids'] ?? $body['playerIds'] ?? [];
    $completedIds = $body['completed_player_ids'] ?? $body['completedPlayerIds'] ?? [];
    $assessmentTypes = $body['assessment_types'] ?? $body['assessmentTypes'] ?? [];
    if (is_string($playerIds)) $playerIds = json_decode($playerIds, true) ?? [];
    if (is_string($completedIds)) $completedIds = json_decode($completedIds, true) ?? [];
    $playerIds = is_array($playerIds)
        ? array_values(array_unique(array_map('strval', $playerIds)))
        : [];
    $completedIds = is_array($completedIds)
        ? array_values(array_unique(array_map('strval', $completedIds)))
        : [];
    if ($playerIds) {
        $placeholders = implode(',', array_fill(0, count($playerIds), '?'));
        [$playerTeamSql, $playerTeamParams] = sessionTeamScope(
            $pdo,
            $sessionCtx,
            'cp'
        );
        $playerCheck = $pdo->prepare(
            "SELECT cp.id FROM club_players cp
             WHERE cp.id IN ($placeholders) AND cp.club_id = ?$playerTeamSql"
        );
        $playerCheck->execute([
            ...$playerIds,
            $sessionClubId,
            ...$playerTeamParams,
        ]);
        $playerIds = array_values(array_unique(array_map(
            'strval',
            $playerCheck->fetchAll(PDO::FETCH_COLUMN)
        )));
    }
    $completedIds = array_values(array_intersect($completedIds, $playerIds));
    $playerIdsJson = json_encode($playerIds);
    $completedIdsJson = json_encode($completedIds);
    $assessmentTypesJson = is_array($assessmentTypes) ? json_encode($assessmentTypes) : $assessmentTypes;

    $stmt->execute([
        $id,
        $user['id'],
        $sessionClubId,
        $sessionTeamId,
        $title,
        $body['type']                ?? 'physicalAssessment',
        $body['scope']               ?? 'team',
        $body['status']              ?? 'scheduled',
        $date,
        $body['startTime']           ?? $body['start_time'] ?? '08:00',
        $body['endTime']             ?? $body['end_time']   ?? null,
        (int)($body['durationMin']   ?? $body['duration_min'] ?? 90),
        $body['location']            ?? '',
        $body['teamName']            ?? $body['team_name']  ?? null,
        (int)($body['playerCount']   ?? $body['player_count'] ?? count($playerIds)),
        $body['intensity']           ?? 'medium',
        (int)(bool)($body['aiEnabled']          ?? $body['ai_enabled'] ?? false),
        (int)(bool)($body['attendanceRequired'] ?? $body['attendance_required'] ?? false),
        (int)(bool)($body['rpeRequired']        ?? $body['rpe_required'] ?? false),
        (int)(bool)($body['wellnessRequired']   ?? $body['wellness_required'] ?? false),
        $body['coachName']           ?? $body['coach_name'] ?? null,
        $body['notes']               ?? null,
        $playerIdsJson,
        $completedIdsJson,
        (int)($body['assessmentCount'] ?? $body['assessment_count'] ?? 0),
        $assessmentTypesJson,
        $body['position_filter']     ?? $body['positionFilter'] ?? null,
        // Reuse the same id for the bridged training_sessions row below —
        // always known, no separate lookup ever needed.
        $id,
    ]);

    // Bridge into the session_players system — this is what the player's own
    // "Today's Session" card (api/player/today-session.php) actually reads.
    // Without this, a coach could select every player here and the session
    // would still never show up for any of them, since that endpoint queries
    // session_players/training_sessions, which this club_sessions row never
    // touched before.
    try {
        $clubId = $sessionClubId;

        $pdo->prepare(
            'INSERT INTO training_sessions
                 (id, club_id, coach_user_id, title, session_date, duration_minutes, wellness_required, rpe_required)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
                 club_id = VALUES(club_id), title = VALUES(title), session_date = VALUES(session_date),
                 duration_minutes = VALUES(duration_minutes),
                 wellness_required = VALUES(wellness_required), rpe_required = VALUES(rpe_required)'
        )->execute([
            $id, $clubId, (int)$user['id'], $title, $date,
            (int)($body['durationMin'] ?? $body['duration_min'] ?? 90),
            (int)(bool)($body['wellnessRequired'] ?? $body['wellness_required'] ?? false),
            (int)(bool)($body['rpeRequired']      ?? $body['rpe_required']      ?? false),
        ]);

        if ($playerIds) {
            $placeholders = implode(',', array_fill(0, count($playerIds), '?'));
            $linkedStmt = $pdo->prepare(
                "SELECT id, linked_user_id FROM club_players WHERE id IN ($placeholders) AND linked_user_id IS NOT NULL"
            );
            $linkedStmt->execute($playerIds);
            $linkedRows = $linkedStmt->fetchAll(PDO::FETCH_ASSOC);

            $spStmt = $pdo->prepare(
                'INSERT INTO session_players (session_id, club_id, player_user_id, linked_player_id, status)
                 VALUES (?, ?, ?, ?, \'assigned\')
                 ON DUPLICATE KEY UPDATE linked_player_id = VALUES(linked_player_id)'
            );
            foreach ($linkedRows as $cp) {
                $spStmt->execute([$id, $clubId, (int)$cp['linked_user_id'], $cp['id']]);
            }

            // Drop players who were unassigned on this edit — only ever
            // touches rows still in 'assigned' (never a player who already
            // pre-checked/started/completed).
            $keepUserIds = array_column($linkedRows, 'linked_user_id');
            if ($keepUserIds) {
                $keepPlaceholders = implode(',', array_fill(0, count($keepUserIds), '?'));
                $pdo->prepare(
                    "DELETE FROM session_players
                     WHERE session_id = ? AND status = 'assigned' AND player_user_id NOT IN ($keepPlaceholders)"
                )->execute([$id, ...$keepUserIds]);
            } else {
                $pdo->prepare("DELETE FROM session_players WHERE session_id = ? AND status = 'assigned'")
                    ->execute([$id]);
            }
        } else {
            $pdo->prepare("DELETE FROM session_players WHERE session_id = ? AND status = 'assigned'")
                ->execute([$id]);
        }
    } catch (Throwable $e) {
        // Never let the bridge break the actual session save — the coach's
        // club_sessions write above already succeeded.
        error_log('sessions.php: session_players bridge failed: ' . $e->getMessage());
    }

    jsonOut(['success' => true, 'id' => $id]);
}

// ── DELETE: delete session ────────────────────────────────────────────────────
if ($method === 'DELETE') {
    requireCoachRole($user);
    $ctx = requireClubPermission($pdo, $user, 'sessions.write');
    [$teamSql, $teamParams] = sessionTeamScope($pdo, $ctx);
    $id = $_GET['id'] ?? (json_decode(file_get_contents('php://input'), true)['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id is required'], 400);

    $stmt = $pdo->prepare(
        'DELETE FROM club_sessions WHERE id = ? AND club_id = ?' . $teamSql
    );
    $stmt->execute([$id, $ctx['club_id'], ...$teamParams]);
    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
