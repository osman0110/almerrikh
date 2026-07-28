<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

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
        ?? $_SERVER['Authorization']
        ?? '';
    if (!$auth && function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    }
    if (stripos($auth, 'Bearer ') === 0) return trim(substr($auth, 7));
    return trim($auth);
}

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.name, u.email FROM users u
         JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$method = $_SERVER['REQUEST_METHOD'];

// ── GET: list assessments ─────────────────────────────────────────────────────
if ($method === 'GET') {
    $user  = getAuthUser($pdo);
    $limit = min((int)($_GET['limit'] ?? 50), 200);

    // Load caller's player_type and linked_player_id from DB
    $callerStmt = $pdo->prepare('SELECT player_type, linked_player_id FROM users WHERE id = ?');
    $callerStmt->execute([$user['id']]);
    $callerInfo = $callerStmt->fetch();
    $isPlayer   = !empty($callerInfo['player_type']);

    // ── Attempt group: all captures of one test-taking session + best/average ──
    $attemptGroupId = trim($_GET['attempt_group_id'] ?? '');
    if ($attemptGroupId) {
        $stmt = $pdo->prepare(
            'SELECT * FROM assessments WHERE user_id = ? AND attempt_group_id = ?
             ORDER BY attempt_number ASC'
        );
        $stmt->execute([$user['id'], $attemptGroupId]);
        $attempts = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $validScores = [];
        foreach ($attempts as &$a) {
            $a['overall_score'] = (int)$a['overall_score'];
            $a['attempt_number'] = (int)($a['attempt_number'] ?? 1);
            $a['is_valid'] = (bool)($a['is_valid'] ?? 1);
            if ($a['is_valid']) $validScores[] = $a['overall_score'];
        }
        unset($a);

        $best = $validScores ? max($validScores) : null;
        $average = $validScores ? round(array_sum($validScores) / count($validScores), 1) : null;

        jsonOut([
            'attempts'      => $attempts,
            'attempt_count' => count($attempts),
            'valid_count'   => count($validScores),
            'best_score'    => $best,
            'average_score' => $average,
        ]);
    }

    if ($isPlayer) {
        // SECURITY: players always query their OWN player_id from DB, never from request
        $linkedPlayerId = $callerInfo['linked_player_id'] ?? null;
        if (!$linkedPlayerId) {
            jsonOut([
                'error'       => 'player_profile_missing',
                'message'     => 'Player profile not linked. Please log in again.',
                'assessments' => [],
            ], 404);
        }
        $stmt = $pdo->prepare(
            'SELECT * FROM assessments WHERE user_id = ? AND player_id = ?
             ORDER BY created_at DESC LIMIT ' . $limit
        );
        $stmt->execute([$user['id'], $linkedPlayerId]);
    } else {
        // Club staff (coach/doctor/analyst/physio/...): scoped to the whole club,
        // not just the account that happens to be logged in.
        $ctx = requireClubPermission($pdo, $user, 'assessments.read');
        $teamFilter = $ctx['team_id'] !== null
            ? ' AND COALESCE(cp.team_id, ct.id) = ?'
            : '';
        $teamParams = $ctx['team_id'] !== null ? [(int)$ctx['team_id']] : [];
        $playerId = $_GET['player_id'] ?? null;
        if ($playerId) {
            $stmt = $pdo->prepare(
                'SELECT a.* FROM assessments a
                 JOIN club_players cp ON cp.id = a.player_id AND cp.club_id = a.club_id
                 LEFT JOIN club_teams ct
                   ON ct.club_id = cp.club_id AND ct.name = cp.team_name AND ct.is_active = 1
                 WHERE a.club_id = ? AND a.player_id = ?' . $teamFilter . '
                 ORDER BY a.created_at DESC LIMIT ' . $limit
            );
            $stmt->execute([$ctx['club_id'], $playerId, ...$teamParams]);
        } else {
            $stmt = $pdo->prepare(
                'SELECT a.* FROM assessments a
                 JOIN club_players cp ON cp.id = a.player_id AND cp.club_id = a.club_id
                 LEFT JOIN club_teams ct
                   ON ct.club_id = cp.club_id AND ct.name = cp.team_name AND ct.is_active = 1
                 WHERE a.club_id = ?' . $teamFilter . '
                 ORDER BY a.created_at DESC LIMIT ' . $limit
            );
            $stmt->execute([$ctx['club_id'], ...$teamParams]);
        }
    }

    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($rows as &$row) {
        $row['issues']  = json_decode($row['issues_json']  ?? '[]', true) ?? [];
        $row['tips']    = json_decode($row['tips_json']    ?? '[]', true) ?? [];
        $row['drills']  = json_decode($row['drills_json']  ?? '[]', true) ?? [];
        // Decode without assoc flag so empty {} stays stdClass → serialises as {} not []
        // A [] (JSON array) from Flutter would also survive as an object-like structure
        $rawMetrics = json_decode($row['angle_metrics_json'] ?? '{}');
        $row['metrics'] = ($rawMetrics instanceof stdClass) ? $rawMetrics : new stdClass();
        $row['overall_score']          = (int) $row['overall_score'];
        $row['movement_quality_score'] = (int) ($row['movement_quality_score'] ?? 0);
        $row['stability_score']        = (int) ($row['stability_score'] ?? 0);
        $row['symmetry_score']         = (int) ($row['symmetry_score'] ?? 0);
        $row['control_score']          = (int) ($row['control_score'] ?? 0);
        $row['quality_score']          = (int) ($row['quality_score'] ?? 0);
        $row['pre_hooper_index']       = isset($row['pre_hooper_index']) ? (int)$row['pre_hooper_index'] : null;
        $row['pre_rpe']                = isset($row['pre_rpe'])          ? (int)$row['pre_rpe']          : null;
        $row['post_rpe']               = isset($row['post_rpe'])         ? (int)$row['post_rpe']         : null;
        $row['pain_reported']          = (bool)($row['pain_reported']    ?? false);
        $row['mood_after']             = isset($row['mood_after'])        ? (int)$row['mood_after']       : null;
        $row['session_id']             = $row['session_id'] ?? null;
        $row['attempt_group_id']       = $row['attempt_group_id'] ?? null;
        $row['attempt_number']         = (int)($row['attempt_number'] ?? 1);
        $row['is_valid']               = (bool)($row['is_valid'] ?? 1);
        $row['invalid_reason']         = $row['invalid_reason'] ?? null;
        $row['override_score']         = isset($row['override_score']) ? (int)$row['override_score'] : null;
        $row['override_reason']        = $row['override_reason'] ?? null;
        $row['status']                 = $row['status'] ?? 'pending_review';
        $row['approved_by_user_id']    = isset($row['approved_by_user_id']) ? (int)$row['approved_by_user_id'] : null;
        $row['approved_at']            = $row['approved_at'] ?? null;
        unset($row['issues_json'], $row['tips_json'], $row['drills_json'], $row['angle_metrics_json']);
    }
    unset($row);

    jsonOut(['assessments' => $rows, 'count' => count($rows)]);

// ── POST: save / upsert assessment ───────────────────────────────────────────
} elseif ($method === 'POST') {
    $user = getAuthUser($pdo);
    $body = json_decode(file_get_contents('php://input'), true) ?? [];

    // ── Coach manual override of a test score, with a required reason ────────
    if (($body['action'] ?? '') === 'override') {
        require_once 'includes/audit_log.php';

        $id = trim($body['id'] ?? '');
        if (!$id) jsonOut(['error' => 'id is required'], 400);

        // Only coaches/clubs may override (never a player overriding their own score)
        $roleCheck = $pdo->prepare('SELECT player_type FROM users WHERE id = ?');
        $roleCheck->execute([$user['id']]);
        if (!empty($roleCheck->fetch()['player_type'])) {
            jsonOut(['error' => 'Forbidden — coaches only'], 403);
        }

        $ctxOverride = requireClubPermission($pdo, $user, 'assessments.write');
        $existStmt = $pdo->prepare('SELECT * FROM assessments WHERE id = ? AND club_id = ?');
        $existStmt->execute([$id, $ctxOverride['club_id']]);
        $existing = $existStmt->fetch(PDO::FETCH_ASSOC);
        if (!$existing) jsonOut(['error' => 'Assessment not found'], 404);

        if (!isset($body['override_score'])) jsonOut(['error' => 'override_score is required'], 400);
        $overrideScore = (int)$body['override_score'];
        if ($overrideScore < 0 || $overrideScore > 100) jsonOut(['error' => 'override_score must be 0–100'], 400);

        $overrideReason = trim((string)($body['override_reason'] ?? ''));
        if ($overrideReason === '') jsonOut(['error' => 'override_reason is required'], 400);
        $overrideReason = substr($overrideReason, 0, 255);

        $upd = $pdo->prepare(
            'UPDATE assessments
             SET override_score = ?, override_reason = ?, overridden_by_user_id = ?, overridden_at = NOW()
             WHERE id = ? AND club_id = ?'
        );
        $upd->execute([$overrideScore, $overrideReason, $user['id'], $id, $ctxOverride['club_id']]);

        $oldValue = $existing['override_score'] ?? $existing['overall_score'];
        logAudit(
            $pdo, 'assessments', $id, 'override_score',
            $oldValue !== null ? (string)$oldValue : null,
            (string)$overrideScore, (int)$user['id']
        );

        jsonOut(['success' => true, 'id' => $id, 'override_score' => $overrideScore]);
    }

    // ── Coach certifies the (possibly edited) result — flips status to
    // 'approved'. Only after this does the app delete the on-device video. ──
    if (($body['action'] ?? '') === 'approve') {
        require_once 'includes/audit_log.php';

        $id = trim($body['id'] ?? '');
        if (!$id) jsonOut(['error' => 'id is required'], 400);

        $roleCheckA = $pdo->prepare('SELECT player_type FROM users WHERE id = ?');
        $roleCheckA->execute([$user['id']]);
        if (!empty($roleCheckA->fetch()['player_type'])) {
            jsonOut(['error' => 'Forbidden — coaches only'], 403);
        }

        $ctxApprove = requireClubPermission($pdo, $user, 'assessments.write');
        $existStmtA = $pdo->prepare('SELECT id, status FROM assessments WHERE id = ? AND club_id = ?');
        $existStmtA->execute([$id, $ctxApprove['club_id']]);
        $existingA = $existStmtA->fetch(PDO::FETCH_ASSOC);
        if (!$existingA) jsonOut(['error' => 'Assessment not found'], 404);

        $updA = $pdo->prepare(
            "UPDATE assessments
             SET status = 'approved', approved_by_user_id = ?, approved_at = NOW()
             WHERE id = ? AND club_id = ?"
        );
        $updA->execute([$user['id'], $id, $ctxApprove['club_id']]);

        logAudit(
            $pdo, 'assessments', $id, 'status',
            $existingA['status'] ?? 'pending_review', 'approved', (int)$user['id']
        );

        jsonOut(['success' => true, 'id' => $id, 'status' => 'approved']);
    }

    $id         = trim($body['id'] ?? '');
    $playerId   = trim($body['player_id'] ?? '');
    $playerName = trim($body['player_name'] ?? '');
    $type       = trim($body['type'] ?? '');
    $sessionId  = trim($body['session_id'] ?? '') ?: null;
    $overall    = (int)($body['overall_score'] ?? 0);
    $movement   = (int)($body['movement_quality_score'] ?? 0);
    $stability  = (int)($body['stability_score'] ?? 0);
    $symmetry   = (int)($body['symmetry_score'] ?? 0);
    $control    = (int)($body['control_score'] ?? 0);
    $quality    = (int)($body['quality_score'] ?? 0);
    $issues     = json_encode($body['issues'] ?? [], JSON_UNESCAPED_UNICODE);
    $tips       = json_encode($body['correction_tips'] ?? [], JSON_UNESCAPED_UNICODE);
    $drills     = json_encode($body['recommended_drills'] ?? [], JSON_UNESCAPED_UNICODE);
    $metrics    = json_encode($body['angle_metrics'] ?? [], JSON_UNESCAPED_UNICODE);
    $notes       = $body['coach_notes']     ?? null;
    $preHooper   = isset($body['pre_hooper_index']) ? (int)$body['pre_hooper_index'] : null;
    $preRpe      = isset($body['pre_rpe'])           ? (int)$body['pre_rpe']          : null;
    $postRpe     = isset($body['post_rpe'])          ? (int)$body['post_rpe']         : null;
    $painReport  = (int)(bool)($body['pain_reported'] ?? false);
    $difficulty  = $body['difficulty']    ?? null;
    $moodAfter   = isset($body['mood_after'])        ? (int)$body['mood_after']       : null;

    $attemptGroupId = isset($body['attempt_group_id']) ? (string)$body['attempt_group_id'] : null;
    $attemptNumber  = isset($body['attempt_number'])   ? (int)$body['attempt_number']      : 1;
    $invalidReason  = isset($body['invalid_reason'])   ? substr((string)$body['invalid_reason'], 0, 50) : null;
    $isValid        = $invalidReason === null ? 1 : 0;

    if (!$id || !$playerId || !$type) {
        jsonOut(['error' => 'id, player_id and type are required'], 400);
    }

    $existingAssessmentStmt = $pdo->prepare(
        'SELECT overall_score, status, session_id, type
         FROM assessments WHERE id = ?'
    );
    $existingAssessmentStmt->execute([$id]);
    $existingAssessment = $existingAssessmentStmt->fetch(PDO::FETCH_ASSOC) ?: null;

    // Coaches: verify player belongs to their club (players: player_id comes from DB in GET, skip check)
    $callerInfo2 = $pdo->prepare('SELECT player_type FROM users WHERE id = ?');
    $callerInfo2->execute([$user['id']]);
    $isPlayer2 = !empty($callerInfo2->fetch()['player_type']);
    $playerClubId = null;
    $playerTeamId = null;
    if (!$isPlayer2) {
        $ctxWrite = requireClubPermission($pdo, $user, 'assessments.write');
        $ownerCheck = $pdo->prepare(
            'SELECT cp.club_id, COALESCE(cp.team_id, ct.id) AS resolved_team_id
             FROM club_players cp
             LEFT JOIN club_teams ct
               ON ct.club_id = cp.club_id AND ct.name = cp.team_name AND ct.is_active = 1
             WHERE cp.id = ? AND cp.club_id = ?'
        );
        $ownerCheck->execute([$playerId, $ctxWrite['club_id']]);
        $ownerRow = $ownerCheck->fetch();
        if (
            !$ownerRow
            || (
                $ctxWrite['team_id'] !== null
                && (int)($ownerRow['resolved_team_id'] ?? 0) !== (int)$ctxWrite['team_id']
            )
        ) {
            jsonOut(['error' => 'Forbidden — player not in your club'], 403);
        }
        $playerClubId = $ownerRow['club_id'];
        $playerTeamId = $ownerRow['resolved_team_id'] !== null
            ? (int)$ownerRow['resolved_team_id']
            : null;
    } else {
        $pcStmt = $pdo->prepare('SELECT club_id, team_id FROM club_players WHERE id = ?');
        $pcStmt->execute([$playerId]);
        $playerRow = $pcStmt->fetch(PDO::FETCH_ASSOC);
        $playerClubId = $playerRow['club_id'] ?? null;
        $playerTeamId = isset($playerRow['team_id']) ? (int)$playerRow['team_id'] : null;
    }

    if ($sessionId !== null && $playerClubId !== null) {
        $sessionCheck = $pdo->prepare(
            'SELECT 1 FROM club_sessions cs
             LEFT JOIN club_teams ct
               ON ct.club_id = cs.club_id AND ct.name = cs.team_name AND ct.is_active = 1
             WHERE cs.id = ? AND cs.club_id = ?' .
             ($playerTeamId !== null ? ' AND COALESCE(cs.team_id, ct.id) = ?' : '')
        );
        $sessionCheck->execute([
            $sessionId,
            $playerClubId,
            ...($playerTeamId !== null ? [$playerTeamId] : []),
        ]);
        if (!$sessionCheck->fetchColumn()) {
            jsonOut(['error' => 'Session not found for player team'], 404);
        }
    }

    $stmt = $pdo->prepare(
        'INSERT INTO assessments
             (id, user_id, club_id, team_id, player_id, player_name, type, session_id,
              overall_score, movement_quality_score, stability_score,
              symmetry_score, control_score, quality_score,
              issues_json, tips_json, drills_json, angle_metrics_json, notes,
              pre_hooper_index, pre_rpe, post_rpe, pain_reported, difficulty, mood_after,
              attempt_group_id, attempt_number, is_valid, invalid_reason)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
             club_id                = COALESCE(VALUES(club_id),          club_id),
             team_id                = COALESCE(VALUES(team_id),          team_id),
             session_id             = COALESCE(VALUES(session_id),       session_id),
             overall_score          = VALUES(overall_score),
             movement_quality_score = VALUES(movement_quality_score),
             stability_score        = VALUES(stability_score),
             symmetry_score         = VALUES(symmetry_score),
             control_score          = VALUES(control_score),
             quality_score          = VALUES(quality_score),
             issues_json            = VALUES(issues_json),
             tips_json              = VALUES(tips_json),
             drills_json            = VALUES(drills_json),
             angle_metrics_json     = VALUES(angle_metrics_json),
             notes                  = VALUES(notes),
             pre_hooper_index       = COALESCE(VALUES(pre_hooper_index), pre_hooper_index),
             pre_rpe                = COALESCE(VALUES(pre_rpe),          pre_rpe),
             post_rpe               = COALESCE(VALUES(post_rpe),         post_rpe),
             pain_reported          = COALESCE(VALUES(pain_reported),    pain_reported),
             difficulty             = COALESCE(VALUES(difficulty),       difficulty),
             mood_after             = COALESCE(VALUES(mood_after),       mood_after),
             attempt_group_id       = COALESCE(VALUES(attempt_group_id), attempt_group_id),
             attempt_number         = VALUES(attempt_number),
             is_valid               = VALUES(is_valid),
             invalid_reason         = VALUES(invalid_reason)'
    );
    $stmt->execute([
        $id, $user['id'], $playerClubId, $playerTeamId,
        $playerId, $playerName, $type, $sessionId,
        $overall, $movement, $stability, $symmetry, $control, $quality,
        $issues, $tips, $drills, $metrics, $notes,
        $preHooper, $preRpe, $postRpe, $painReport, $difficulty, $moodAfter,
        $attemptGroupId, $attemptNumber, $isValid, $invalidReason,
    ]);

    logFitnessAudit(
        $pdo,
        'assessments',
        $id,
        $existingAssessment ? 'assessment.update' : 'assessment.create',
        (int)$user['id'],
        $playerClubId !== null ? (int)$playerClubId : null,
        $playerId,
        $existingAssessment ? [
            'overall_score' => (int)$existingAssessment['overall_score'],
            'status' => $existingAssessment['status'] ?? 'pending_review',
            'session_id' => $existingAssessment['session_id'] ?? null,
            'type' => $existingAssessment['type'] ?? $type,
        ] : null,
        [
            'overall_score' => $overall,
            'status' => $existingAssessment['status'] ?? 'pending_review',
            'session_id' => $sessionId,
            'type' => $type,
        ],
        null,
        isset($body['operation_id']) ? (string)$body['operation_id'] : null
    );

    // Stamp the player's last_assessment_at so dashboard KPI stays fresh
    if ($playerId && $playerClubId) {
        $tsStmt = $pdo->prepare(
            'UPDATE club_players SET last_assessment_at = NOW()
             WHERE id = ? AND club_id = ?'
        );
        $tsStmt->execute([$playerId, $playerClubId]);
    }

    jsonOut(['success' => true, 'id' => $id]);

} else {
    jsonOut(['error' => 'Method not allowed'], 405);
}
