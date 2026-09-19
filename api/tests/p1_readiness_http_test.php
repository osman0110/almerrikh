<?php
// End-to-end HTTP regression test for the 2026-09-19 production-readiness
// closure. Runs the REAL endpoints through PHP's built-in web server against
// an isolated test database, with its own fixtures (two clubs, owner, admin,
// two coaches, doctor, analyst, players) that are deleted afterwards.
//
//   APP_ENV=test TEST_DB_NAME=smart_sport_test php api/tests/p1_readiness_http_test.php
//
// Refuses to run outside an explicitly configured test database (same
// convention as p0_attendance_scope_test.php). Never touches production.
//
// Covers: player "My Assessments", assessment ownership + cross-player /
// cross-club isolation, session ownership (coach owns, club = boundary,
// owner/admin override), unauthorized-role session writes via raw API,
// session exercises/assessments/attendance/clock, duplicate-safe retries,
// medical-detail redaction + no silent wipe, staff account creation,
// admin password reset + session revocation, staff suspension revocation,
// notification failure not failing a committed save, account deletion.

if (getenv('APP_ENV') !== 'test' || getenv('TEST_DB_NAME') === false) {
    fwrite(STDERR, "Refusing to run: set APP_ENV=test and TEST_DB_NAME.\n");
    exit(2);
}

$dbName = getenv('TEST_DB_NAME');
$dbHost = getenv('TEST_DB_HOST') ?: '127.0.0.1';
$dbUser = getenv('TEST_DB_USER') ?: 'root';
$dbPass = getenv('TEST_DB_PASS') ?: '';
$port   = (int)(getenv('TEST_HTTP_PORT') ?: 8099);
// TEST_API_DIR lets the same suite run against another checkout (e.g. the
// pre-fix code) to prove the tests catch the regressions.
$apiDir = getenv('TEST_API_DIR') ?: dirname(__DIR__);

$pdo = new PDO("mysql:host=$dbHost;dbname=$dbName;charset=utf8mb4", $dbUser, $dbPass, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);

// ── Built-in server with the test DB and an isolated temp dir ────────────────
$tmpDir = sys_get_temp_dir() . '/merr_p1_http_' . getmypid();
@mkdir($tmpDir, 0777, true);
$fakeKey = "$tmpDir/fcm-key.json";
file_put_contents($fakeKey, '{}');
$env = array_merge(getenv(), [
    'DB_NAME' => $dbName,
    'DB_HOST' => $dbHost,
    'DB_USER' => $dbUser,
    'DB_PASS' => $dbPass,
    'TMP' => $tmpDir,
    'TEMP' => $tmpDir,
    'TMPDIR' => $tmpDir,
    'FCM_SERVICE_ACCOUNT_PATH' => $fakeKey,
]);
$serverLog = "$tmpDir/server.log";
$proc = proc_open(
    [PHP_BINARY, '-d', 'display_errors=0', '-d', "error_log=$serverLog", '-S', "127.0.0.1:$port", '-t', $apiDir],
    [0 => ['pipe', 'r'], 1 => ['file', "$tmpDir/stdout.log", 'a'], 2 => ['file', "$tmpDir/stderr.log", 'a']],
    $pipes, $apiDir, $env
);
if (!is_resource($proc)) { fwrite(STDERR, "Could not start php -S\n"); exit(2); }
$up = false;
for ($i = 0; $i < 50 && !$up; $i++) {
    $sock = @fsockopen('127.0.0.1', $port, $errno, $errstr, 0.2);
    if ($sock) { fclose($sock); $up = true; } else { usleep(100000); }
}
if (!$up) { proc_terminate($proc); fwrite(STDERR, "php -S did not come up on $port\n"); exit(2); }

function api(string $method, string $path, ?string $token = null, ?array $body = null): array {
    global $port;
    $ch = curl_init("http://127.0.0.1:$port/$path");
    $headers = ['Content-Type: application/json'];
    if ($token) $headers[] = "Authorization: Bearer $token";
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST  => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_TIMEOUT        => 30,
    ]);
    if ($body !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
    $raw = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    $json = json_decode((string)$raw, true);
    return [$code, is_array($json) ? $json : ['_raw' => $raw]];
}

$results = [];
function check(string $name, bool $ok, $detail = null): void {
    global $results;
    $results[] = [$name, $ok, $ok ? null : $detail];
}

// ── Fixtures ─────────────────────────────────────────────────────────────────
$seed  = random_int(100000, 899999);
$clubA = 1900000000 + $seed;
$clubB = 1950000000 + $seed;
$userIds = [];
$tokens  = [];
$password = 'Test-' . $seed;

$mkUser = function (string $key, string $role, ?int $clubId, array $extra = []) use ($pdo, $seed, $password, &$userIds, &$tokens) {
    $email = "p1_{$key}_{$seed}@test.invalid";
    $pdo->prepare(
        'INSERT INTO users (name, email, password_hash, role, account_type, player_type, club_id, linked_player_id, is_active, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, "active")'
    )->execute([
        "P1 $key", $email, password_hash($password, PASSWORD_BCRYPT, ['cost' => 4]),
        $role, $role, $extra['player_type'] ?? null, $clubId, $extra['linked_player_id'] ?? null,
    ]);
    $id = (int)$pdo->lastInsertId();
    $userIds[$key] = $id;
    $token = bin2hex(random_bytes(32));
    $pdo->prepare('INSERT INTO user_tokens (token, user_id, expires_at) VALUES (?, ?, NOW() + INTERVAL 1 DAY)')
        ->execute([$token, $id]);
    $tokens[$key] = $token;
    return $id;
};
$mkStaff = function (string $key, int $clubId, string $staffRole) use ($pdo, $mkUser) {
    $id = $mkUser($key, $staffRole === 'owner' ? 'club' : 'staff', $clubId);
    $pdo->prepare('INSERT INTO club_staff (club_id, user_id, staff_role, status) VALUES (?, ?, ?, "active")')
        ->execute([$clubId, $id, $staffRole]);
    return $id;
};
$mkPlayer = function (string $key, int $clubId, int $ownerId, bool $withLogin) use ($pdo, $seed, $mkUser) {
    $pid = "p1-$key-$seed";
    $pdo->prepare(
        'INSERT INTO club_players (id, user_id, club_id, name, player_type, is_active, status)
         VALUES (?, ?, ?, ?, "club", 1, "active")'
    )->execute([$pid, $ownerId, $clubId, "Player $key"]);
    if ($withLogin) {
        $uid = $mkUser($key, 'player', null, ['player_type' => 'club', 'linked_player_id' => $pid]);
        $pdo->prepare('UPDATE club_players SET linked_user_id = ? WHERE id = ?')->execute([$uid, $pid]);
    }
    return $pid;
};

$exitCode = 1;
// The login rate limiter counts failures per IP; this test deliberately
// fails logins (D9, E3), so start and end with a clean slate for 127.0.0.1
// in the TEST database.
$pdo->exec("DELETE FROM auth_rate_limit WHERE ip = '127.0.0.1'");
try {
    $ownerA = $mkStaff('ownerA', $clubA, 'owner');
    $ownerB = $mkStaff('ownerB', $clubB, 'owner');
    $pdo->prepare('INSERT INTO clubs (id, owner_user_id, name, status) VALUES (?, ?, ?, "active"), (?, ?, ?, "active")')
        ->execute([$clubA, $ownerA, "P1 Club A $seed", $clubB, $ownerB, "P1 Club B $seed"]);
    $mkStaff('adminA', $clubA, 'admin');
    $mkStaff('coachA', $clubA, 'coach');
    $mkStaff('coachB', $clubA, 'coach');
    $mkStaff('doctorA', $clubA, 'doctor');
    $mkStaff('analystA', $clubA, 'analyst');
    $mkStaff('pmA', $clubA, 'performance_manager');
    $mkStaff('coachC', $clubB, 'coach');
    $p1 = $mkPlayer('player1', $clubA, $ownerA, true);
    $p2 = $mkPlayer('player2', $clubA, $ownerA, true);
    $p3 = $mkPlayer('player3', $clubA, $ownerA, true);
    $pB = $mkPlayer('playerB', $clubB, $ownerB, false);

    // ── A. Assessments ───────────────────────────────────────────────────────
    $asmId = "p1-asm-$seed";
    $asmBody = ['id' => $asmId, 'player_id' => $p1, 'player_name' => 'Player player1', 'type' => 'squat',
                'overall_score' => 72, 'movement_quality_score' => 70, 'stability_score' => 71,
                'symmetry_score' => 73, 'control_score' => 74, 'quality_score' => 80];
    [$c, $r] = api('POST', 'assessments.php', $tokens['coachA'], $asmBody);
    check('A1 coach A records assessment for player 1', $c === 200 && ($r['success'] ?? false), [$c, $r]);

    // Visibility rule 2026-09-19: players see only coach-approved results.
    [$c, $r] = api('GET', 'player/assessments.php', $tokens['player1']);
    $ids = array_column($r['assessments'] ?? [], 'id');
    check('A1b pending (unapproved) assessment is NOT shown to the player', $c === 200 && !in_array($asmId, $ids, true), [$c, $ids]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['coachA'], ['action' => 'approve', 'id' => $asmId]);
    check('A1c recording coach approves the assessment', $c === 200 && ($r['status'] ?? '') === 'approved', [$c, $r]);

    [$c, $r] = api('GET', 'player/assessments.php', $tokens['player1']);
    $ids = array_column($r['assessments'] ?? [], 'id');
    check('A2 player 1 sees coach-recorded assessment (player/assessments.php)', $c === 200 && in_array($asmId, $ids, true), [$c, $ids]);

    [$c, $r] = api('GET', 'assessments.php', $tokens['player1']);
    $ids = array_column($r['assessments'] ?? [], 'id');
    check('A3 player 1 sees it via assessments.php too', $c === 200 && in_array($asmId, $ids, true), [$c, $ids]);

    [$c, $r] = api('GET', 'player/assessments.php', $tokens['player2']);
    $ids = array_column($r['assessments'] ?? [], 'id');
    check('A4 player 2 does NOT see player 1 assessment', $c === 200 && !in_array($asmId, $ids, true), [$c, $ids]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['coachB'], ['action' => 'override', 'id' => $asmId, 'override_score' => 10, 'override_reason' => 'x']);
    check('A5 coach B cannot override coach A assessment (403)', $c === 403 && ($r['code'] ?? '') === 'not_assessment_owner', [$c, $r]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['coachB'], ['action' => 'approve', 'id' => $asmId]);
    check('A6 coach B cannot approve coach A assessment (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['coachB'], array_merge($asmBody, ['overall_score' => 5]));
    check('A7 coach B cannot overwrite coach A assessment via upsert (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['coachA'], $asmBody);
    $rows = (int)$pdo->query('SELECT COUNT(*) FROM assessments WHERE id = ' . $pdo->quote($asmId))->fetchColumn();
    check('A8 coach A retry of same assessment is idempotent (no duplicate)', $c === 200 && ($r['updated'] ?? null) === true && $rows === 1, [$c, $r, $rows]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['adminA'], ['action' => 'override', 'id' => $asmId, 'override_score' => 75, 'override_reason' => 'admin review']);
    check('A9 club admin override is allowed', $c === 200, [$c, $r]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['player1'], ['id' => "p1-asm-self-$seed", 'player_id' => $p2, 'type' => 'squat', 'overall_score' => 99]);
    check('A10 player cannot save an assessment for another player (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('GET', 'assessments.php?player_id=' . urlencode($p1), $tokens['coachC']);
    $ids = array_column($r['assessments'] ?? [], 'id');
    check('A11 club B coach cannot read club A assessment', $c === 200 && !in_array($asmId, $ids, true), [$c, $ids]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['coachC'], ['action' => 'override', 'id' => $asmId, 'override_score' => 1, 'override_reason' => 'x']);
    check('A12 club B coach override → 404 (no cross-club confirmation)', $c === 404, [$c, $r]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['coachA'], ['id' => "p1-asm-x-$seed", 'player_id' => $pB, 'type' => 'squat', 'overall_score' => 50]);
    check('A13 coach A cannot assess a club B player (403)', $c === 403, [$c, $r]);

    // ── B. Sessions ──────────────────────────────────────────────────────────
    $sid = "p1-sess-$seed";
    $sessBody = ['id' => $sid, 'title' => 'P1 Session', 'date' => date('Y-m-d'), 'startTime' => '09:00',
                 'durationMin' => 60, 'player_ids' => [$p1, $p2], 'attendanceRequired' => true, 'rpeRequired' => true];
    [$c, $r] = api('POST', 'sessions.php', $tokens['coachA'], $sessBody);
    check('B1 coach A creates session', $c === 200 && ($r['created'] ?? null) === true, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['coachA'], $sessBody);
    $rows = (int)$pdo->query('SELECT COUNT(*) FROM club_sessions WHERE id = ' . $pdo->quote($sid))->fetchColumn();
    check('B2 retry of the same session is idempotent (no duplicate)', $c === 200 && ($r['created'] ?? null) === false && $rows === 1, [$c, $r, $rows]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['coachB'], array_merge($sessBody, ['title' => 'Hijacked']));
    check('B3 coach B cannot edit coach A session (403 not 404)', $c === 403 && ($r['code'] ?? '') === 'not_session_owner', [$c, $r]);

    [$c, $r] = api('GET', 'sessions.php?id=' . urlencode($sid), $tokens['coachB']);
    check('B4 coach B can view it, flagged can_manage=false', $c === 200 && ($r['session']['can_manage'] ?? null) === false, [$c, $r['session']['can_manage'] ?? $r]);

    [$c, $r] = api('GET', 'sessions.php?id=' . urlencode($sid), $tokens['coachA']);
    check('B5 coach A view flagged can_manage=true', $c === 200 && ($r['session']['can_manage'] ?? null) === true, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['coachB'], ['action' => 'attendance', 'session_id' => $sid, 'attendance' => [$p1 => 'present']]);
    check('B6 coach B cannot take attendance in coach A session (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['coachA'], ['action' => 'attendance', 'session_id' => $sid, 'attendance' => [$p1 => 'present', $p2 => 'absent']]);
    check('B7 coach A takes attendance', $c === 200 && ($r['present_count'] ?? null) === 1, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['coachA'], ['action' => 'attendance', 'session_id' => $sid, 'attendance' => [$p3 => 'present']]);
    check('B8 attendance for a player not in the session → 422', $c === 422, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['coachB'], ['action' => 'session_clock', 'session_id' => $sid, 'operation' => 'start_session']);
    check('B9 coach B cannot run coach A session clock (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['coachA'], ['action' => 'session_clock', 'session_id' => $sid, 'operation' => 'start_session']);
    check('B10 coach A starts the session clock', $c === 200, [$c, $r]);

    $exBody = ['session_id' => $sid, 'exercises' => [['exercise_name' => 'Warm-up', 'sets' => 1]]];
    [$c, $r] = api('POST', 'sessions/exercises.php', $tokens['coachA'], $exBody);
    check('B11 coach A saves session exercises', $c === 200 && ($r['count'] ?? 0) === 1, [$c, $r]);

    [$c, $r] = api('GET', 'sessions/exercises.php?session_id=' . urlencode($sid), $tokens['coachB']);
    check('B12 coach B can READ exercises of coach A session (was "Session not found")', $c === 200 && count($r['exercises'] ?? []) === 1, [$c, $r]);

    [$c, $r] = api('POST', 'sessions/exercises.php', $tokens['coachB'], $exBody);
    check('B13 coach B cannot change exercises (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('GET', 'sessions/exercises.php?session_id=' . urlencode($sid), $tokens['coachC']);
    check('B14 club B coach cannot read club A session exercises (404)', $c === 404, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['doctorA'], array_merge($sessBody, ['id' => "p1-sess-doc-$seed"]));
    check('B15 doctor cannot create a session via raw API (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['analystA'], array_merge($sessBody, ['id' => "p1-sess-an-$seed"]));
    check('B16 analyst cannot create a session via raw API (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['player1'], array_merge($sessBody, ['id' => "p1-sess-pl-$seed"]));
    check('B17 player cannot create a session (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['coachA'], array_merge($sessBody, ['id' => "p1-sess-x-$seed", 'player_ids' => [$p1, $pB]]));
    check('B18 session with a club B player → 422', $c === 422, [$c, $r]);

    [$c, $r] = api('GET', 'sessions.php?id=' . urlencode($sid), $tokens['coachC']);
    check('B19 club B coach cannot read club A session (404)', $c === 404, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['coachC'], $sessBody);
    check('B20 club B coach cannot overwrite club A session id (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('POST', 'sessions.php', $tokens['adminA'], array_merge($sessBody, ['title' => 'Admin edit']));
    $owner = (int)$pdo->query('SELECT user_id FROM club_sessions WHERE id = ' . $pdo->quote($sid))->fetchColumn();
    check('B21 club admin override can edit; owner unchanged', $c === 200 && $owner === $userIds['coachA'], [$c, $r, $owner]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['coachA'], array_merge($asmBody, ['id' => "p1-asm-s-$seed", 'player_id' => $p2, 'session_id' => $sid]));
    check('B22 coach A records assessment inside own session', $c === 200, [$c, $r]);

    [$c, $r] = api('GET', 'club/session_assessments.php?session_id=' . urlencode($sid), $tokens['coachB']);
    $ids = array_column($r['assessments'] ?? [], 'id');
    check('B23 session assessments are listed club-wide (not only caller rows)', $c === 200 && in_array("p1-asm-s-$seed", $ids, true), [$c, $ids]);

    [$c, $r] = api('POST', 'assessments.php', $tokens['coachB'], array_merge($asmBody, ['id' => "p1-asm-sb-$seed", 'player_id' => $p2, 'session_id' => $sid]));
    check('B24 coach B cannot record assessments into coach A session (403)', $c === 403, [$c, $r]);

    // Notification failure after a committed save: FCM "credentials" usable
    // (fake cached token) but device_tokens unusable → push layer throws.
    file_put_contents("$tmpDir/merr_fcm_access_token.json", json_encode([
        'access_token' => 'fake', 'project_id' => 'fake', 'expires_at' => time() + 3600,
    ]));
    // Reproduce a prod DB where migration 0012 (device_tokens) never ran:
    // the push layer then throws after the session is already committed.
    $hasDeviceTokens = (bool)$pdo->query("SHOW TABLES LIKE 'device_tokens'")->fetchColumn();
    if ($hasDeviceTokens) { $pdo->exec('RENAME TABLE device_tokens TO device_tokens_p1_hidden'); }
    $nid = "p1-sess-n-$seed";
    [$c, $r] = api('POST', 'sessions.php', $tokens['coachA'], array_merge($sessBody, ['id' => $nid]));
    $saved = (int)$pdo->query('SELECT COUNT(*) FROM club_sessions WHERE id = ' . $pdo->quote($nid))->fetchColumn();
    check('B25 save succeeds even when notification delivery fails', $c === 200 && ($r['success'] ?? false) && $saved === 1, [$c, $r, $saved]);
    check('B26 response flags notifications_sent=false (warning, not an error)', ($r['notifications_sent'] ?? null) === false, $r);
    [$c, $r] = api('POST', 'sessions.php', $tokens['coachA'], array_merge($sessBody, ['id' => $nid]));
    $saved = (int)$pdo->query('SELECT COUNT(*) FROM club_sessions WHERE id = ' . $pdo->quote($nid))->fetchColumn();
    check('B27 user retry after the warning does not duplicate', $c === 200 && $saved === 1, [$c, $r, $saved]);
    if ($hasDeviceTokens) { $pdo->exec('RENAME TABLE device_tokens_p1_hidden TO device_tokens'); }
    @unlink("$tmpDir/merr_fcm_access_token.json");

    [$c, $r] = api('DELETE', 'sessions.php?id=' . urlencode($nid), $tokens['coachB']);
    check('B28 coach B cannot delete coach A session (403)', $c === 403, [$c, $r]);
    [$c, $r] = api('DELETE', 'sessions.php?id=' . urlencode($nid), $tokens['coachA']);
    $left = (int)$pdo->query('SELECT COUNT(*) FROM session_players WHERE session_id = ' . $pdo->quote($nid) . " AND status = 'assigned'")->fetchColumn();
    check('B29 coach A deletes own session; players no longer assigned', $c === 200 && ($r['deleted'] ?? false) === true && $left === 0, [$c, $r, $left]);

    // ── C. Medical information ───────────────────────────────────────────────
    $pdo->prepare('UPDATE club_players SET medical_notes = ?, injury_notes = ?, status = "injured", unavailable_reason = ? WHERE id = ?')
        ->execute(['Grade 2 hamstring strain, MRI 12/09', 'Left hamstring', 'No sprinting this week', $p1]);

    [$c, $r] = api('GET', 'players.php?id=' . urlencode($p1), $tokens['coachA']);
    $pl = $r['players'][0] ?? [];
    check('C1 coach does NOT receive medical/injury note text', $c === 200 && $pl['medical_notes'] === null && $pl['injury_notes'] === null
        && ($pl['medical_detail_hidden'] ?? null) === true && ($pl['has_injury_notes'] ?? null) === true, [$c, $pl]);
    check('C2 coach still gets availability (status, unavailable_reason)', ($pl['status'] ?? '') === 'injured' && ($pl['unavailable_reason'] ?? '') === 'No sprinting this week', $pl);

    [$c, $r] = api('GET', 'players.php', $tokens['coachA']);
    $leak = array_filter($r['players'] ?? [], fn($x) => ($x['medical_notes'] ?? null) !== null || ($x['injury_notes'] ?? null) !== null);
    check('C3 coach roster listing leaks no medical text', $c === 200 && !$leak, [$c, count($leak)]);

    [$c, $r] = api('GET', 'club/player.php?id=' . urlencode($p1), $tokens['coachA']);
    $pl = $r['player'] ?? $r['data']['player'] ?? $r;
    check('C4 club/player.php leaks no medical text to coach', $c === 200 && !str_contains(json_encode($r), 'hamstring strain'), [$c]);

    [$c, $r] = api('GET', 'coach/players.php', $tokens['coachA']);
    check('C5 coach/players.php leaks no injury text', $c === 200 && !str_contains(json_encode($r), 'Left hamstring'), [$c]);

    [$c, $r] = api('GET', 'players.php?id=' . urlencode($p1), $tokens['doctorA']);
    $pl = $r['players'][0] ?? [];
    check('C6 doctor receives full medical notes', $c === 200 && ($pl['medical_notes'] ?? '') === 'Grade 2 hamstring strain, MRI 12/09', [$c, $pl]);

    [$c, $r] = api('POST', 'players.php', $tokens['coachA'], [
        'id' => $p1, 'name' => 'Player player1', 'position' => 'MID', 'status' => 'injured',
        'unavailable_reason' => 'No sprinting this week', 'medical_notes' => null, 'injury_notes' => null, 'physical_notes' => 'coach note',
    ]);
    $row = $pdo->query('SELECT medical_notes, injury_notes, physical_notes FROM club_players WHERE id = ' . $pdo->quote($p1))->fetch();
    check('C7 coach editing the player does not wipe the doctor notes', $c === 200 && $row['medical_notes'] === 'Grade 2 hamstring strain, MRI 12/09'
        && $row['injury_notes'] === 'Left hamstring' && $row['physical_notes'] === 'coach note', [$c, $r, $row]);

    [$c, $r] = api('POST', 'players.php', $tokens['doctorA'], ['id' => $p1, 'name' => 'ignored', 'status' => 'injured', 'medical_notes' => 'Cleared for jogging', 'injury_notes' => 'Left hamstring']);
    $row = $pdo->query('SELECT medical_notes, name FROM club_players WHERE id = ' . $pdo->quote($p1))->fetch();
    check('C8 doctor can update medical notes (identity fields untouched)', $c === 200 && $row['medical_notes'] === 'Cleared for jogging' && $row['name'] === 'Player player1', [$c, $r, $row]);

    // Rule 2026-09-19: owner/admin and performance manager do NOT get full
    // medical text from the API (no wildcard medical access).
    foreach (['adminA' => 'C9 admin', 'ownerA' => 'C10 owner', 'pmA' => 'C11 performance manager'] as $who => $label) {
        [$c, $r] = api('GET', 'players.php?id=' . urlencode($p1), $tokens[$who]);
        check("$label does NOT receive medical/injury note text", $c === 200 && !str_contains(json_encode($r), 'Cleared for jogging') && !str_contains(json_encode($r), 'Left hamstring'), [$c]);
    }
    [$c, $r] = api('GET', 'club/injuries.php?player_id=' . urlencode($p1), $tokens['adminA']);
    check('C12 admin cannot open the clinical injury file (403)', $c === 403, [$c, $r]);
    [$c, $r] = api('POST', 'players.php', $tokens['adminA'], ['id' => $p1, 'name' => 'Player player1', 'status' => 'injured', 'medical_notes' => 'admin overwrite', 'injury_notes' => null]);
    $row = $pdo->query('SELECT medical_notes, injury_notes FROM club_players WHERE id = ' . $pdo->quote($p1))->fetch();
    check('C13 admin player edit cannot overwrite or wipe medical notes', $c === 200 && $row['medical_notes'] === 'Cleared for jogging' && $row['injury_notes'] === 'Left hamstring', [$c, $r, $row]);

    // ── D. Staff accounts, password reset, suspension ────────────────────────
    $newEmail = "p1_newcoach_{$seed}@test.invalid";
    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['action' => 'create_account', 'name' => 'New Coach', 'email' => $newEmail, 'password' => 'Start-123', 'staff_role' => 'coach']);
    $newUserId = (int)($r['user_id'] ?? 0);
    if ($newUserId) $userIds['newcoach'] = $newUserId;
    check('D1 admin creates a coach account', $c === 200 && $newUserId > 0, [$c, $r]);

    [$c, $r] = api('POST', 'auth.php?action=login', null, ['email' => $newEmail, 'password' => 'Start-123']);
    $newToken = $r['token'] ?? null;
    check('D2 new coach can log in', $c === 200 && $newToken, [$c, $r]);

    [$c, $r] = api('GET', 'sessions.php', $newToken);
    check('D3 new coach is linked to club A (can list club A sessions)', $c === 200 && in_array($sid, array_column($r['sessions'] ?? [], 'id'), true), [$c]);

    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['action' => 'create_account', 'name' => 'Dup', 'email' => $newEmail, 'password' => 'Start-123', 'staff_role' => 'coach']);
    check('D4 duplicate email rejected (409)', $c === 409, [$c, $r]);

    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['action' => 'create_account', 'name' => 'Bad', 'email' => "p1_bad_{$seed}@test.invalid", 'password' => 'Start-123', 'staff_role' => 'owner']);
    check('D5 cannot create an owner account (400)', $c === 400, [$c, $r]);

    [$c, $r] = api('POST', 'club/staff.php', $tokens['coachA'], ['action' => 'create_account', 'name' => 'X', 'email' => "p1_x_{$seed}@test.invalid", 'password' => 'Start-123', 'staff_role' => 'coach']);
    check('D6 coach cannot create staff accounts (403)', $c === 403, [$c, $r]);

    // Privilege escalation: only the owner creates admins (account or invite).
    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['action' => 'create_account', 'name' => 'Adm', 'email' => "p1_adm_{$seed}@test.invalid", 'password' => 'Start-123', 'staff_role' => 'admin']);
    check('D6a admin cannot create an admin account (403)', $c === 403 && ($r['code'] ?? '') === 'owner_only', [$c, $r]);
    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['account_type' => 'admin']);
    check('D6b admin cannot create an admin invite code (403)', $c === 403, [$c, $r]);
    [$c, $r] = api('POST', 'club/staff.php', $tokens['ownerA'], ['account_type' => 'admin']);
    $adminCode = $r['code'] ?? '';
    check('D6c owner can create an admin invite code', $c === 200 && $adminCode !== '', [$c, $r]);
    api('POST', 'club/staff.php', $tokens['ownerA'], ['action' => 'toggle_code', 'code' => $adminCode, 'is_active' => false]);
    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['action' => 'toggle_code', 'code' => $adminCode, 'is_active' => true]);
    check('D6d admin cannot re-activate an admin invite (403)', $c === 403, [$c, $r]);
    [$c, $r] = api('POST', 'club/staff.php', $tokens['ownerA'], ['action' => 'create_account', 'name' => 'Adm2', 'email' => "p1_adm2_{$seed}@test.invalid", 'password' => 'Start-123', 'staff_role' => 'admin']);
    if (!empty($r['user_id'])) $userIds['admin2'] = (int)$r['user_id'];
    check('D6e owner can create an admin account', $c === 200 && !empty($r['user_id']), [$c, $r]);
    $admin2Row = (int)$pdo->query('SELECT id FROM club_staff WHERE user_id = ' . (int)($userIds['admin2'] ?? 0))->fetchColumn();
    [$c, $r] = api('DELETE', 'club/staff.php?id=' . $admin2Row, $tokens['adminA']);
    check('D6f admin cannot suspend another admin (403)', $c === 403, [$c, $r]);
    $selfRow = (int)$pdo->query('SELECT id FROM club_staff WHERE user_id = ' . (int)$userIds['adminA'])->fetchColumn();
    $roleBefore = $pdo->query('SELECT staff_role FROM club_staff WHERE id = ' . $selfRow)->fetchColumn();
    check('D6g no endpoint path changed the admin role (no self-promotion)', $roleBefore === 'admin', $roleBefore);

    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['action' => 'reset_password', 'user_id' => $newUserId, 'new_password' => 'Reset-456']);
    check('D7 admin resets the new coach password', $c === 200, [$c, $r]);
    [$c, $r] = api('GET', 'sessions.php', $newToken);
    check('D8 reset revokes the old session (401)', $c === 401, [$c]);
    [$c, $r] = api('POST', 'auth.php?action=login', null, ['email' => $newEmail, 'password' => 'Start-123']);
    check('D9 old password no longer works', $c === 401, [$c]);
    [$c, $r] = api('POST', 'auth.php?action=login', null, ['email' => $newEmail, 'password' => 'Reset-456']);
    check('D10 temporary password works', $c === 200 && !empty($r['token']), [$c]);

    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['action' => 'reset_password', 'user_id' => $userIds['player1'], 'new_password' => 'Reset-789']);
    check('D11 admin resets a player login password', $c === 200, [$c, $r]);
    $pdo->prepare('INSERT INTO user_tokens (token, user_id, expires_at) VALUES (?, ?, NOW() + INTERVAL 1 DAY)')
        ->execute([$tokens['player1'] = bin2hex(random_bytes(32)), $userIds['player1']]);

    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['action' => 'reset_password', 'user_id' => $userIds['coachC'], 'new_password' => 'Reset-000']);
    check('D12 admin cannot reset a club B user (404)', $c === 404, [$c, $r]);

    [$c, $r] = api('POST', 'club/staff.php', $tokens['adminA'], ['action' => 'reset_password', 'user_id' => $ownerA, 'new_password' => 'Reset-000']);
    check('D13 admin cannot reset the owner (403)', $c === 403, [$c, $r]);

    [$c, $r] = api('POST', 'club/staff.php', $tokens['coachA'], ['action' => 'reset_password', 'user_id' => $userIds['player2'], 'new_password' => 'Reset-000']);
    check('D14 coach cannot reset passwords (403)', $c === 403, [$c, $r]);

    $audit = (int)$pdo->query("SELECT COUNT(*) FROM audit_logs WHERE entity_type = 'users' AND field_name = 'password_reset' AND entity_id = '" . $newUserId . "'")->fetchColumn();
    $pwLeak = (int)$pdo->query("SELECT COUNT(*) FROM audit_logs WHERE new_value LIKE '%Reset-456%' OR old_value LIKE '%Reset-456%'")->fetchColumn();
    check('D15 password reset audited without the password', $audit === 1 && $pwLeak === 0, [$audit, $pwLeak]);

    $staffRowId = (int)$pdo->query('SELECT id FROM club_staff WHERE user_id = ' . (int)$userIds['coachB'])->fetchColumn();
    [$c, $r] = api('DELETE', 'club/staff.php?id=' . $staffRowId, $tokens['adminA']);
    [$c2, $r2] = api('GET', 'sessions.php', $tokens['coachB']);
    check('D16 suspending a staff member revokes their sessions', $c === 200 && $c2 === 401, [$c, $c2]);

    // ── E. Account deletion (Apple 5.1.1(v)) ────────────────────────────────
    [$c, $r] = api('POST', 'assessments.php', $tokens['coachA'], array_merge($asmBody, ['id' => "p1-asm-p3-$seed", 'player_id' => $p3]));
    [$c, $r] = api('POST', 'auth.php?action=delete_account', $tokens['player3'], ['password' => 'wrong']);
    check('E1 deletion with wrong password refused', $c === 403, [$c, $r]);
    [$c, $r] = api('POST', 'auth.php?action=delete_account', $tokens['player3'], ['password' => $password]);
    check('E2 player deletes own account', $c === 200 && ($r['deleted'] ?? false) === true, [$c, $r]);
    [$c, $r] = api('POST', 'auth.php?action=login', null, ['email' => "p1_player3_{$seed}@test.invalid", 'password' => $password]);
    check('E3 deleted account cannot log in', $c === 401, [$c]);
    $kept = (int)$pdo->query('SELECT COUNT(*) FROM assessments WHERE id = ' . $pdo->quote("p1-asm-p3-$seed"))->fetchColumn();
    check('E4 coach-recorded assessment history is retained by the club', $kept === 1, $kept);

    $exitCode = 0;
} catch (Throwable $e) {
    check('harness', false, get_class($e) . ': ' . $e->getMessage() . ' @' . $e->getLine());
} finally {
    try { if ((bool)$pdo->query("SHOW TABLES LIKE 'device_tokens_p1_hidden'")->fetchColumn()) $pdo->exec('RENAME TABLE device_tokens_p1_hidden TO device_tokens'); } catch (Throwable $e) {}
    // ── Cleanup: everything created under the two fixture clubs / users ──────
    $clubList = "$clubA,$clubB";
    $extra = $pdo->query("SELECT id FROM users WHERE club_id IN ($clubList)")->fetchAll(PDO::FETCH_COLUMN);
    $uids = implode(',', array_map('intval', array_unique(array_merge(array_values($userIds), $extra, [0]))));
    $sessIds = $pdo->query("SELECT id FROM club_sessions WHERE club_id IN ($clubList)")->fetchAll(PDO::FETCH_COLUMN);
    $sessList = $sessIds ? implode(',', array_map([$pdo, 'quote'], $sessIds)) : "''";
    $stmts = [
        "DELETE FROM club_session_exercises WHERE session_id IN ($sessList)",
        "DELETE FROM session_attendance WHERE session_id IN ($sessList)",
        "DELETE FROM session_players WHERE session_id IN ($sessList)",
        "DELETE FROM training_sessions WHERE club_id IN ($clubList)",
        "DELETE FROM club_sessions WHERE club_id IN ($clubList)",
        "DELETE FROM assessments WHERE club_id IN ($clubList) OR player_id LIKE 'p1-%-$seed'",
        "DELETE FROM notifications WHERE club_id IN ($clubList)",
        "DELETE FROM audit_logs WHERE changed_by_user_id IN ($uids)",
        "DELETE FROM player_status_history WHERE player_id LIKE 'p1-%-$seed'",
        "DELETE FROM club_players WHERE club_id IN ($clubList) OR id LIKE 'p1-%-$seed'",
        "DELETE FROM club_staff WHERE club_id IN ($clubList)",
        "DELETE FROM user_tokens WHERE user_id IN ($uids)",
        "DELETE FROM account_deletions WHERE user_id IN ($uids)",
        "DELETE FROM users WHERE id IN ($uids)",
        "DELETE FROM club_access_codes WHERE club_id IN ($clubList)",
        "DELETE FROM clubs WHERE id IN ($clubList)",
        "DELETE FROM auth_rate_limit WHERE ip = '127.0.0.1'",
    ];
    foreach ($stmts as $sql) {
        try { $pdo->exec($sql); } catch (Throwable $e) { fwrite(STDERR, "cleanup: $sql → {$e->getMessage()}\n"); }
    }
    proc_terminate($proc);
    proc_close($proc);
}

$failed = array_filter($results, fn($r) => !$r[1]);
foreach ($results as [$name, $ok, $detail]) {
    echo ($ok ? '  PASS  ' : '  FAIL  ') . $name . ($ok ? '' : '  → ' . json_encode($detail, JSON_UNESCAPED_UNICODE)) . "\n";
}
echo "\np1_readiness_http_test: " . (count($results) - count($failed)) . ' passed, ' . count($failed) . " failed\n";
if (is_file($serverLog) && $failed) echo "server log: $serverLog\n";
exit($failed || $exitCode ? 1 : 0);
