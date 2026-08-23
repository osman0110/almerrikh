<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once 'db.php';
require_once 'includes/club_auth.php';
require_once 'includes/notifications.php';

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

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

// ── GET: list or single session ───────────────────────────────────────────────
if ($method === 'GET') {
    $singleId = $_GET['id'] ?? null;
    $ctx = requireClubPermission($pdo, $user, 'sessions.read');

    if ($singleId) {
        $stmt = $pdo->prepare(
            'SELECT cs.*,
                    CASE WHEN cs.actual_started_at IS NULL THEN 0
                         ELSE TIMESTAMPDIFF(SECOND, cs.actual_started_at,
                              COALESCE(cs.actual_ended_at, UTC_TIMESTAMP())) END AS elapsed_seconds,
                    (cs.actual_started_at IS NOT NULL AND cs.actual_ended_at IS NULL
                     AND cs.status = "active") AS clock_running
             FROM club_sessions cs WHERE cs.id = ? AND cs.club_id = ?'
        );
        $stmt->execute([$singleId, $ctx['club_id']]);
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
                     WHERE id IN ($placeholders) AND club_id = ?"
                );
                $pStmt->execute([...$playerIds, $ctx['club_id']]);
                $players = $pStmt->fetchAll(PDO::FETCH_ASSOC);

                $aStmt = $pdo->prepare(
                    'SELECT player_id, status, timer_started_at IS NOT NULL AS clock_running,
                            elapsed_seconds + CASE WHEN timer_started_at IS NULL THEN 0
                                ELSE TIMESTAMPDIFF(SECOND, timer_started_at, UTC_TIMESTAMP()) END AS elapsed_seconds
                     FROM session_attendance WHERE session_id = ? AND club_id = ?'
                );
                $aStmt->execute([$singleId, $ctx['club_id']]);
                $attendanceByPlayer = [];
                foreach ($aStmt->fetchAll(PDO::FETCH_ASSOC) as $a) {
                    $attendanceByPlayer[$a['player_id']] = $a;
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
                        'attendance_status' => $attendanceByPlayer[$p['id']]['status'] ?? 'pending',
                        'clock_running'      => (bool)($attendanceByPlayer[$p['id']]['clock_running'] ?? false),
                        'elapsed_seconds'    => max(0, (int)($attendanceByPlayer[$p['id']]['elapsed_seconds'] ?? 0)),
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

    $where = ['club_id = ?'];
    $params = [$ctx['club_id']];

    if ($date)   { $where[] = 'date = ?';   $params[] = $date; }
    if ($status) { $where[] = 'status = ?'; $params[] = $status; }

    $sql = 'SELECT club_sessions.*,
                   CASE WHEN actual_started_at IS NULL THEN 0
                        ELSE TIMESTAMPDIFF(SECOND, actual_started_at,
                             COALESCE(actual_ended_at, UTC_TIMESTAMP())) END AS elapsed_seconds,
                   (actual_started_at IS NOT NULL AND actual_ended_at IS NULL
                    AND status = "active") AS clock_running
            FROM club_sessions WHERE ' . implode(' AND ', $where)
         . ' ORDER BY date DESC, start_time ASC LIMIT ' . $limit;

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
    $r['ai_enabled']          = (bool)$r['ai_enabled'];
    $r['attendance_required'] = (bool)$r['attendance_required'];
    $r['rpe_required']        = (bool)$r['rpe_required'];
    $r['wellness_required']   = (bool)$r['wellness_required'];
    $r['clock_running']       = (bool)($r['clock_running'] ?? false);
    $r['elapsed_seconds']     = max(0, (int)($r['elapsed_seconds'] ?? 0));
    // Decode JSON arrays
    $r['player_ids']           = $r['player_ids'] && $r['player_ids'] !== 'null'
        ? json_decode($r['player_ids'], true) ?? [] : [];
    $r['completed_player_ids'] = $r['completed_player_ids'] && $r['completed_player_ids'] !== 'null'
        ? json_decode($r['completed_player_ids'], true) ?? [] : [];
    $r['assessment_types'] = isset($r['assessment_types']) && $r['assessment_types'] && $r['assessment_types'] !== 'null'
        ? json_decode($r['assessment_types'], true) ?? [] : [];
}

// ── POST: create / update / sub-actions ──────────────────────────────────────
if ($method === 'POST') {
    requireCoachRole($user);
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? '');

    if ($action === 'session_clock') {
        $ctx = requireClubPermission($pdo, $user, 'sessions.write');
        $sessionId = trim($body['session_id'] ?? '');
        $operation = trim($body['operation'] ?? '');
        $playerId = trim($body['player_id'] ?? '');
        if (!$sessionId) jsonOut(['error' => 'session_id required'], 400);

        $sessionStmt = $pdo->prepare('SELECT * FROM club_sessions WHERE id = ? AND club_id = ?');
        $sessionStmt->execute([$sessionId, $ctx['club_id']]);
        $session = $sessionStmt->fetch(PDO::FETCH_ASSOC);
        if (!$session) jsonOut(['error' => 'Session not found'], 404);

        $playerIds = $session['player_ids'] && $session['player_ids'] !== 'null'
            ? json_decode($session['player_ids'], true) ?? [] : [];
        $playerIds = array_map('strval', $playerIds);
        if ($playerId !== '' && !in_array($playerId, $playerIds, true)) {
            jsonOut(['error' => 'Player is not assigned to this session'], 422);
        }

        $ensureTimer = $pdo->prepare(
            "INSERT INTO session_attendance
                 (session_id, player_id, user_id, club_id, status, marked_at, elapsed_seconds)
             VALUES (?, ?, ?, ?, 'pending', NULL, 0)
             ON DUPLICATE KEY UPDATE club_id = VALUES(club_id)"
        );

        $pdo->beginTransaction();
        try {
            if ($operation === 'start_session') {
                foreach ($playerIds as $assignedId) {
                    $ensureTimer->execute([$sessionId, $assignedId, (int)$user['id'], $ctx['club_id']]);
                }
                $pdo->prepare(
                    "UPDATE club_sessions SET actual_started_at = COALESCE(actual_started_at, UTC_TIMESTAMP()),
                     actual_ended_at = NULL, status = 'active' WHERE id = ?"
                )->execute([$sessionId]);
                $pdo->prepare(
                    "UPDATE session_attendance SET timer_started_at = COALESCE(timer_started_at, UTC_TIMESTAMP()),
                     timer_ended_at = NULL WHERE session_id = ? AND status <> 'absent'"
                )->execute([$sessionId]);
                if (!empty($session['linked_training_session_id'])) {
                    $pdo->prepare(
                        "UPDATE session_players SET started_at = COALESCE(started_at, UTC_TIMESTAMP()),
                         completed_at = NULL, status = 'started'
                         WHERE session_id = ? AND status IN ('assigned', 'pre_checked', 'started')"
                    )->execute([$session['linked_training_session_id']]);
                }
            } elseif ($operation === 'finish_session') {
                $pdo->prepare(
                    'UPDATE session_attendance
                     SET elapsed_seconds = elapsed_seconds + CASE WHEN timer_started_at IS NULL THEN 0
                             ELSE GREATEST(0, TIMESTAMPDIFF(SECOND, timer_started_at, UTC_TIMESTAMP())) END,
                         timer_ended_at = CASE WHEN timer_started_at IS NULL THEN timer_ended_at ELSE UTC_TIMESTAMP() END,
                         timer_started_at = NULL WHERE session_id = ?'
                )->execute([$sessionId]);
                $pdo->prepare(
                    "UPDATE club_sessions SET actual_ended_at = UTC_TIMESTAMP(), status = 'completed' WHERE id = ?"
                )->execute([$sessionId]);
                if (!empty($session['linked_training_session_id'])) {
                    $pdo->prepare(
                        "UPDATE session_players SET completed_at = COALESCE(completed_at, UTC_TIMESTAMP()), status = 'completed'
                         WHERE session_id = ? AND started_at IS NOT NULL AND status <> 'missed'"
                    )->execute([$session['linked_training_session_id']]);
                }
            } elseif (in_array($operation, ['start_player', 'stop_player'], true)) {
                if (!$playerId) {
                    $pdo->rollBack();
                    jsonOut(['error' => 'player_id required'], 400);
                }
                $ensureTimer->execute([$sessionId, $playerId, (int)$user['id'], $ctx['club_id']]);
                if ($operation === 'start_player') {
                    $pdo->prepare(
                        "UPDATE club_sessions SET actual_started_at = COALESCE(actual_started_at, UTC_TIMESTAMP()),
                         actual_ended_at = NULL, status = 'active' WHERE id = ?"
                    )->execute([$sessionId]);
                    $pdo->prepare(
                        'UPDATE session_attendance SET timer_started_at = COALESCE(timer_started_at, UTC_TIMESTAMP()),
                         timer_ended_at = NULL WHERE session_id = ? AND player_id = ?'
                    )->execute([$sessionId, $playerId]);
                    if (!empty($session['linked_training_session_id'])) {
                        $pdo->prepare(
                            "UPDATE session_players SET started_at = COALESCE(started_at, UTC_TIMESTAMP()),
                             completed_at = NULL, status = 'started'
                             WHERE session_id = ? AND linked_player_id = ?
                                   AND status IN ('assigned', 'pre_checked', 'started')"
                        )->execute([$session['linked_training_session_id'], $playerId]);
                    }
                } else {
                    $pdo->prepare(
                        'UPDATE session_attendance
                         SET elapsed_seconds = elapsed_seconds +
                                 GREATEST(0, TIMESTAMPDIFF(SECOND, timer_started_at, UTC_TIMESTAMP())),
                             timer_ended_at = UTC_TIMESTAMP(), timer_started_at = NULL
                         WHERE session_id = ? AND player_id = ? AND timer_started_at IS NOT NULL'
                    )->execute([$sessionId, $playerId]);
                    if (!empty($session['linked_training_session_id'])) {
                        $pdo->prepare(
                            "UPDATE session_players SET completed_at = COALESCE(completed_at, UTC_TIMESTAMP()), status = 'completed'
                             WHERE session_id = ? AND linked_player_id = ? AND started_at IS NOT NULL"
                        )->execute([$session['linked_training_session_id'], $playerId]);
                    }
                }
            } else {
                $pdo->rollBack();
                jsonOut(['error' => 'Unsupported clock operation'], 422);
            }
            $pdo->commit();
            jsonOut(['success' => true]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            jsonOut(['error' => 'Unable to update session clock'], 500);
        }
    }

    // ── Attendance: mark which players were present/absent/late ──────────────
    if ($action === 'attendance') {
        $sessionId  = trim($body['session_id'] ?? '');
        $attendance = $body['attendance'] ?? []; // {player_id: 'present'|'absent'|'late'}

        if (!$sessionId) jsonOut(['error' => 'session_id required'], 400);

        $ctx = requireClubPermission($pdo, $user, 'sessions.write');
        $ownerStmt = $pdo->prepare('SELECT id, linked_training_session_id FROM club_sessions WHERE id = ? AND club_id = ?');
        $ownerStmt->execute([$sessionId, $ctx['club_id']]);
        $ownerRow = $ownerStmt->fetch(PDO::FETCH_ASSOC);
        if (!$ownerRow) jsonOut(['error' => 'Session not found'], 404);
        $linkedTrainingSessionId = $ownerRow['linked_training_session_id'] ?? null;

        $validStatuses = ['present', 'absent', 'late'];
        $attStmt = $pdo->prepare(
            'INSERT INTO session_attendance (session_id, player_id, user_id, club_id, status, marked_at)
             VALUES (?, ?, ?, ?, ?, NOW())
             ON DUPLICATE KEY UPDATE status = VALUES(status), marked_at = VALUES(marked_at), club_id = VALUES(club_id)'
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
            if (!in_array($status, $validStatuses, true)) continue;
            $attStmt->execute([$sessionId, $playerId, $user['id'], $ctx['club_id'], $status]);
            if ($status === 'absent') {
                $pdo->prepare(
                    'UPDATE session_attendance
                     SET elapsed_seconds = elapsed_seconds + CASE WHEN timer_started_at IS NULL THEN 0
                             ELSE GREATEST(0, TIMESTAMPDIFF(SECOND, timer_started_at, UTC_TIMESTAMP())) END,
                         timer_ended_at = CASE WHEN timer_started_at IS NULL THEN timer_ended_at ELSE UTC_TIMESTAMP() END,
                         timer_started_at = NULL WHERE session_id = ? AND player_id = ?'
                )->execute([$sessionId, $playerId]);
            }
            if ($status === 'absent' && $missedStmt) {
                $missedStmt->execute([$linkedTrainingSessionId, $playerId]);
            }
        }

        $present = array_values(array_filter(
            array_keys($attendance),
            fn($pid) => in_array($attendance[$pid] ?? '', ['present', 'late'], true)
        ));

        // Keep the legacy JSON summary in sync for existing report widgets
        $stmt = $pdo->prepare(
            'UPDATE club_sessions SET completed_player_ids = ?, player_count = ? WHERE id = ? AND club_id = ?'
        );
        $stmt->execute([json_encode($present), count($present), $sessionId, $ctx['club_id']]);

        jsonOut(['success' => true, 'present_count' => count($present)]);
    }

    // ── Add exercise to a session ─────────────────────────────────────────────
    if ($action === 'add_exercise') {
        $sessionId = trim($body['session_id'] ?? '');
        if (!$sessionId) jsonOut(['error' => 'session_id required'], 400);

        $ownerStmt = $pdo->prepare('SELECT id FROM club_sessions WHERE id = ? AND user_id = ?');
        $ownerStmt->execute([$sessionId, $user['id']]);
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
    $sessionCtx = resolveClubContext($pdo, $user);
    $sessionClubId = $sessionCtx['club_id'];

    // Ownership check for updates
    $existing = false;
    if ($id) {
        $existStmt = $pdo->prepare('SELECT user_id, club_id FROM club_sessions WHERE id = ?');
        $existStmt->execute([$id]);
        $existing = $existStmt->fetch();
        if ($existing) {
            $sameClub = $sessionClubId !== null && (int)($existing['club_id'] ?? 0) === (int)$sessionClubId;
            $sameCreator = (int)$existing['user_id'] === (int)$user['id'];
            if (!$sameClub && !$sameCreator) jsonOut(['error' => 'Forbidden'], 403);
        }
    }
    $isNewSession = !$existing;

    $stmt = $pdo->prepare(
        'INSERT INTO club_sessions
             (id, user_id, club_id, title, type, scope, status, date, start_time, end_time,
              duration_min, location, team_name, player_count, intensity, ai_enabled,
              attendance_required, rpe_required, wellness_required, coach_name, notes,
              player_ids, completed_player_ids, assessment_count, assessment_types, position_filter,
              linked_training_session_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
             club_id                = VALUES(club_id),
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
    $playerIdsJson = is_array($playerIds) ? json_encode($playerIds) : $playerIds;
    $completedIdsJson = is_array($completedIds) ? json_encode($completedIds) : $completedIds;
    $assessmentTypesJson = is_array($assessmentTypes) ? json_encode($assessmentTypes) : $assessmentTypes;

    try {
        $pdo->beginTransaction();
        $stmt->execute([
            $id,
            $user['id'],
            $sessionClubId,
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

        // Bridge into the session_players system — this is what the player's
        // own "Today's Session" card reads. The legacy and active session rows
        // must commit together so the player can never receive a partial save.
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
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('sessions.php: session_players bridge failed: ' . $e->getMessage());
        jsonOut(['error' => 'Unable to save the session and player assignments'], 500);
    }

    // Newly scheduled session — alert the assigned players and the physical
    // coach. Updates to an existing session stay silent to avoid
    // re-notifying on every minor edit. Runs AFTER the commit above and in
    // its own try/catch: the session is already saved at this point, so a
    // notification failure must never be reported back as a save failure.
    if ($isNewSession && $clubId) {
        try {
            $startTime = $body['startTime'] ?? $body['start_time'] ?? '';
            $when = "$date $startTime";
            foreach ($linkedRows ?? [] as $cp) {
                createNotification(
                    $pdo, (int)$clubId, (int)$cp['linked_user_id'], 'session_scheduled',
                    ['title' => $title, 'when' => $when], '/session/' . $id
                );
            }
            notifyClubRole($pdo, (int)$clubId, 'coach', 'session_scheduled_coach', ['title' => $title, 'when' => $when], ['linked_route' => '/session/' . $id]);
        } catch (Throwable $e) {
            error_log('sessions.php: session_scheduled notification failed: ' . $e->getMessage());
        }
    }

    jsonOut(['success' => true, 'id' => $id]);
}

// ── DELETE: delete session ────────────────────────────────────────────────────
if ($method === 'DELETE') {
    requireCoachRole($user);
    $id = $_GET['id'] ?? (json_decode(file_get_contents('php://input'), true)['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id is required'], 400);

    $stmt = $pdo->prepare('DELETE FROM club_sessions WHERE id = ? AND user_id = ?');
    $stmt->execute([$id, $user['id']]);
    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
