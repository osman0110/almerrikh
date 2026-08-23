<?php
// Integration test skeleton. It intentionally refuses to run outside an
// explicitly configured test database.
//
// Regression test for RB2: the attendance-summary sync in
// api/sessions.php (action=attendance) used to scope its final
// club_sessions UPDATE by `user_id = ?` (the session's creator) instead of
// `club_id = ?`. That meant any staff member other than the original
// creator marking attendance on a shared club session silently updated 0
// rows. This test exercises the exact SQL statement now in sessions.php
// against seeded fixtures and asserts all four required scenarios:
//   1. Session creator can update attendance.
//   2. A different authorized staff member in the SAME club can update it.
//   3. A staff member from a DIFFERENT club cannot touch it (0 rows, and
//      the endpoint's own ownership lookup would 404 before reaching here).
//   4. A role without 'sessions.write' is rejected by clubStaffCan() before
//      any SQL runs at all (see p0_sessions_write_permission_test.php for
//      the full role matrix — this test only spot-checks one such role in
//      context).
if (getenv('APP_ENV') !== 'test' || getenv('TEST_DB_NAME') === false) {
    fwrite(STDERR, "Refusing to run: set APP_ENV=test and TEST_DB_NAME.\n");
    exit(2);
}

require_once dirname(__DIR__) . '/includes/club_auth.php';

$pdo = new PDO(
    'mysql:host=' . (getenv('TEST_DB_HOST') ?: '127.0.0.1')
        . ';dbname=' . getenv('TEST_DB_NAME') . ';charset=utf8mb4',
    getenv('TEST_DB_USER') ?: 'root',
    getenv('TEST_DB_PASS') ?: '',
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
);

$pdo->beginTransaction();
try {
    $seed = random_int(100000, 900000);
    $clubA = 1000000000 + $seed;
    $clubB = 1100000000 + $seed;
    $creatorUserId = 1200000000 + $seed;   // club A, creates the session
    $coworkerUserId = 1300000000 + $seed;  // club A, different staff member
    $otherClubUserId = 1400000000 + $seed; // club B staff member
    $sessionId = 'p0_att_session_' . $seed;

    // Minimal club_staff rows so resolveClubContext()/clubStaffCan() reflect
    // real membership rather than the legacy users.club_id fallback.
    $staffInsert = $pdo->prepare(
        'INSERT INTO club_staff (club_id, user_id, staff_role, status) VALUES (?, ?, ?, "active")'
    );
    $staffInsert->execute([$clubA, $creatorUserId, 'coach']);
    $staffInsert->execute([$clubA, $coworkerUserId, 'performance_manager']);
    $staffInsert->execute([$clubB, $otherClubUserId, 'coach']);

    $pdo->prepare(
        "INSERT INTO club_sessions (id, user_id, club_id, title, date) VALUES (?, ?, ?, 'P0 Attendance Fixture', CURDATE())"
    )->execute([$sessionId, $creatorUserId, $clubA]);

    // Reproduces exactly the fixed statement from api/sessions.php.
    $updateAttendanceSummary = function (PDO $pdo, string $sessionId, int $actingClubId) {
        $stmt = $pdo->prepare(
            'UPDATE club_sessions SET completed_player_ids = ?, player_count = ? WHERE id = ? AND club_id = ?'
        );
        $stmt->execute([json_encode(['x']), 1, $sessionId, $actingClubId]);
        return $stmt->rowCount();
    };

    // 1) Session creator (resolves to club A) updates — must succeed.
    $creatorCtx = resolveClubContext($pdo, ['id' => $creatorUserId]);
    if ($creatorCtx['club_id'] !== $clubA) {
        throw new RuntimeException('Fixture error: creator did not resolve to club A');
    }
    $rows = $updateAttendanceSummary($pdo, $sessionId, $creatorCtx['club_id']);
    if ($rows !== 1) {
        throw new RuntimeException("Creator update affected $rows rows, expected 1");
    }

    // 2) A different staff member in the SAME club — this is the exact bug
    // that shipped: pre-fix, this scenario silently updated 0 rows because
    // the query filtered by the creator's user_id, not the club.
    if (!clubStaffCan('performance_manager', 'sessions.write')) {
        throw new RuntimeException('Fixture error: performance_manager should have sessions.write');
    }
    $coworkerCtx = resolveClubContext($pdo, ['id' => $coworkerUserId]);
    if ($coworkerCtx['club_id'] !== $clubA) {
        throw new RuntimeException('Fixture error: coworker did not resolve to club A');
    }
    $rows = $updateAttendanceSummary($pdo, $sessionId, $coworkerCtx['club_id']);
    if ($rows !== 1) {
        throw new RuntimeException("Same-club coworker update affected $rows rows, expected 1 (RB2 regression)");
    }

    // 3) A staff member from a DIFFERENT club must not be able to touch this
    // session's row, even if (hypothetically) they had the right action —
    // club isolation must hold regardless of role.
    $otherClubCtx = resolveClubContext($pdo, ['id' => $otherClubUserId]);
    if ($otherClubCtx['club_id'] !== $clubB) {
        throw new RuntimeException('Fixture error: other-club user did not resolve to club B');
    }
    $rows = $updateAttendanceSummary($pdo, $sessionId, $otherClubCtx['club_id']);
    if ($rows !== 0) {
        throw new RuntimeException("Cross-club update affected $rows rows, expected 0 (isolation breach)");
    }
    // The endpoint itself also guards this one step earlier via the
    // ownership lookup ('SELECT id FROM club_sessions WHERE id = ? AND
    // club_id = ?'), which would 404 before ever reaching the UPDATE — this
    // assertion is the belt to that endpoint's suspenders.
    $ownerStmt = $pdo->prepare('SELECT id FROM club_sessions WHERE id = ? AND club_id = ?');
    $ownerStmt->execute([$sessionId, $otherClubCtx['club_id']]);
    if ($ownerStmt->fetch()) {
        throw new RuntimeException('Cross-club ownership lookup unexpectedly found the session');
    }

    // 4) A role without sessions.write must be rejected before any SQL runs.
    if (clubStaffCan('analyst', 'sessions.write')) {
        throw new RuntimeException('analyst must not have sessions.write');
    }

    echo "p0_attendance_scope_test: OK\n";
} finally {
    $pdo->rollBack();
}
