<?php
/**
 * DB-integration tests for TrainingLoadCalculator — session resolver,
 * dedup across club_sessions/training_sessions, missing-data flags,
 * Hooper isolation and centralized ACWR integration.
 *
 * Run: php api/tests/training_load_calculator_db_test.php
 */
require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/player/training-load/TrainingLoadCalculator.php';

$pass = 0; $fail = 0;

function ok(string $label, bool $cond, string $detail = ''): void {
    global $pass, $fail;
    if ($cond) { echo "  PASS  $label\n"; $pass++; }
    else        { echo "  FAIL  $label" . ($detail ? " — $detail" : '') . "\n"; $fail++; }
}

function almostEqual($a, $b, float $eps = 1e-6): bool {
    if ($a === null || $b === null) return $a === $b;
    return abs($a - $b) < $eps;
}

echo "\n=== TrainingLoadCalculator — DB Integration Tests ===\n\n";

$ts = time();
$tz = 'Africa/Kigali';
// Fixed calendar week far from "today" so it can never overlap the rolling
// ACWR now consumes the calculator's quality-aware daily records.
$mon = '2026-07-06'; $tue = '2026-07-07'; $wed = '2026-07-08'; $thu = '2026-07-09';
$fri = '2026-07-10'; $sat = '2026-07-11'; $sun = '2026-07-12';

$userId = null; $csId = null; $tsId = null; $tsLinkedId = null; $hooperInserted = false;

try {
    $pdo->beginTransaction();

    $pdo->prepare("INSERT INTO users (name,email,password_hash,role,player_type) VALUES (?,?,?,'player','club')")
        ->execute(['TL Test Player', "tl_player_{$ts}@test.com", 'x']);
    $userId = (int)$pdo->lastInsertId();

    // A club_sessions row (no link) — Wednesday
    $csId = 'cs_' . bin2hex(random_bytes(6));
    $pdo->prepare("INSERT INTO club_sessions (id,user_id,title,type,date,duration_min) VALUES (?,?,?,?,?,?)")
        ->execute([$csId, $userId, 'Endurance Session', 'endurance', $wed, 90]);

    // A training_sessions row (no link) — Thursday
    $tsId = 'ts_' . bin2hex(random_bytes(6));
    $pdo->prepare("INSERT INTO training_sessions (id,title,session_date,duration_minutes,objective) VALUES (?,?,?,?,?)")
        ->execute([$tsId, 'Coordination Drill', $thu, 75, 'coordination']);

    // A LINKED pair: club_sessions row bridged to a training_sessions row — Friday
    $tsLinkedId = 'ts_' . bin2hex(random_bytes(6));
    $pdo->prepare("INSERT INTO training_sessions (id,title,session_date,duration_minutes,objective) VALUES (?,?,?,?,?)")
        ->execute([$tsLinkedId, 'Agility (bridged)', $fri, 60, 'agility']);
    $csLinkedId = 'cs_' . bin2hex(random_bytes(6));
    $pdo->prepare("INSERT INTO club_sessions (id,user_id,title,type,date,duration_min,linked_training_session_id) VALUES (?,?,?,?,?,?,?)")
        ->execute([$csLinkedId, $userId, 'Agility (bridged)', 'agility', $fri, 60, $tsLinkedId]);

    // ── player_rpe fixtures ──────────────────────────────────────────────
    $insertRpe = function (
        string $sessionId = null, $rpe, $duration, string $submittedAt,
        int $completedFull = 1, $actualDuration = null, int $trainingLoad = null
    ) use ($pdo, $userId) {
        $load = $trainingLoad ?? (($rpe !== null && $duration !== null) ? (int)round(((float)$rpe) * (float)($actualDuration ?? $duration)) : 0);
        $pdo->prepare(
            "INSERT INTO player_rpe
             (user_id, session_id, rpe_score, duration_minutes, training_load,
              completed_full_session, actual_duration_minutes, submitted_at)
             VALUES (?,?,?,?,?,?,?,?)"
        )->execute([$userId, $sessionId, $rpe, $duration, $load, $completedFull, $actualDuration, $submittedAt]);
    };

    // Monday: scheduled session, no RPE/attendance -> explicit missing record.
    // (intentionally nothing inserted)

    // Tuesday: TWO sessions same day, no session_id (standalone) -> summed not averaged
    $insertRpe(null, 3, 60, "$tue 08:00:00");
    $insertRpe(null, 4, 30, "$tue 18:00:00");

    // Wednesday: club_sessions session, decimal RPE 5.5
    $insertRpe($csId, 5.5, 60, "$wed 09:00:00");

    // Thursday: training_sessions session, actual duration < planned duration
    $insertRpe($tsId, 4, 75, "$thu 09:00:00", 0, 45); // completed_full_session=0, actual=45

    // Friday: BOTH ids of the linked pair logged (must dedupe to ONE session_load)
    $insertRpe($csLinkedId, 4, 60, "$fri 08:00:00");            // via club_sessions id
    $insertRpe($tsLinkedId, 4, 60, "$fri 08:05:00");            // via training_sessions id (same real session)

    // Saturday: MISSING_DURATION — rpe present, duration genuinely NULL (not entered)
    $pdo->prepare(
        "INSERT INTO player_rpe (user_id, rpe_score, duration_minutes, training_load, submitted_at)
         VALUES (?,?,?,?,?)"
    )->execute([$userId, 6, null, 0, "$sat 08:00:00"]);

    // Sunday: MISSING_RPE — duration present, rpe genuinely NULL (not entered)
    $pdo->prepare(
        "INSERT INTO player_rpe (user_id, rpe_score, duration_minutes, training_load, submitted_at)
         VALUES (?,?,?,?,?)"
    )->execute([$userId, null, 60, 0, "$sun 08:00:00"]);

    // Hooper rows on the same days with HIGH scores — must never affect load calc
    $pdo->prepare(
        "INSERT INTO player_hooper_index (user_id, sleep_quality, fatigue, stress, muscle_soreness, hooper_score, submitted_at)
         VALUES (?,7,7,7,7,28,?)"
    )->execute([$userId, "$wed 09:00:00"]);
    $hooperInserted = true;

    $pdo->commit();
    ok('fixtures created', true);
} catch (Exception $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    ok('fixtures created', false, $e->getMessage());
    exit(1);
}

try {
    $report = TrainingLoadCalculator::getPlayerWeeklyReport($pdo, $userId, null, $mon, $tz);

    echo "\n[ Week bounds ]\n";
    ok('week_start = Monday', $report['week_start'] === $mon);
    ok('week_end = Sunday', $report['week_end'] === $sun);

    $byDate = [];
    foreach ($report['days'] as $d) $byDate[$d['date']] = $d;

    echo "\n[ Monday — no record at all ]\n";
    ok('Monday status = HISTORICAL_STATUS_UNKNOWN', $byDate[$mon]['participation_status'] === TrainingLoadCalculator::DAY_HISTORICAL_UNKNOWN);
    ok('Monday daily_load = 0', almostEqual($byDate[$mon]['daily_load'], 0));

    echo "\n[ Tuesday — two sessions same day, summed not averaged ]\n";
    ok('Tuesday daily_load = 300 (180+120, not avg 150)', almostEqual($byDate[$tue]['daily_load'], 300));
    ok('Tuesday sessions_count = 2', $byDate[$tue]['sessions_count'] === 2);
    ok('Tuesday status = COMPLETE', $byDate[$tue]['participation_status'] === TrainingLoadCalculator::DAY_COMPLETE);

    echo "\n[ Wednesday — club_sessions source, decimal RPE ]\n";
    ok('Wednesday daily_load = 330 (5.5 x 60)', almostEqual($byDate[$wed]['daily_load'], 330));
    ok('Wednesday session_source = club_sessions', $byDate[$wed]['sessions'][0]['session_source'] === 'club_sessions');
    ok('Wednesday session_name = Endurance Session', $byDate[$wed]['sessions'][0]['session_name'] === 'Endurance Session');

    echo "\n[ Thursday — training_sessions source, actual < planned duration ]\n";
    ok('Thursday daily_load = 180 (4 x 45 actual, not 4 x 75 planned)', almostEqual($byDate[$thu]['daily_load'], 180));
    ok('Thursday session_source = training_sessions', $byDate[$thu]['sessions'][0]['session_source'] === 'training_sessions');

    echo "\n[ Friday — linked club_sessions<->training_sessions pair, must NOT double count ]\n";
    ok('Friday sessions_count = 1 (deduped)', $byDate[$fri]['sessions_count'] === 1);
    ok('Friday daily_load = 240 (4 x 60), not 480', almostEqual($byDate[$fri]['daily_load'], 240));
    ok('Friday resolved via linked training_sessions id', $byDate[$fri]['sessions'][0]['session_id'] === $tsLinkedId || $byDate[$fri]['sessions'][0]['session_source'] === 'club_sessions(linked)');

    echo "\n[ Saturday — missing duration ]\n";
    ok('Saturday status = MISSING_DURATION', $byDate[$sat]['participation_status'] === TrainingLoadCalculator::DAY_MISSING_DURATION);

    echo "\n[ Sunday — missing rpe ]\n";
    ok('Sunday status = MISSING_RPE', $byDate[$sun]['participation_status'] === TrainingLoadCalculator::DAY_MISSING_RPE);

    echo "\n[ Completeness ]\n";
    ok('completeness_status = INCOMPLETE', $report['completeness_status'] === TrainingLoadCalculator::COMPLETENESS_INCOMPLETE);
    $missingStatuses = array_column($report['missing_fields'], 'status');
    ok('unknown historical status is reported', in_array(TrainingLoadCalculator::DAY_HISTORICAL_UNKNOWN, $missingStatuses, true));
    ok('unscheduled day does not invent unresolved attendance', !in_array('UNRESOLVED_ATTENDANCE', $missingStatuses, true));
    ok('data quality blocks approval', $report['data_quality']['report_approvable'] === false);

    echo "\n[ Weekly aggregate (0 + 300 + 330 + 180 + 240 + 0 + 0) ]\n";
    $expectedWeekly = 0 + 300 + 330 + 180 + 240 + 0 + 0;
    ok("weekly_load = {$expectedWeekly}", almostEqual($report['weekly_load'], $expectedWeekly));

    echo "\n[ Hooper isolation — high hooper score on Wednesday must not alter load ]\n";
    ok('Wednesday load unaffected by hooper_score=28', almostEqual($byDate[$wed]['daily_load'], 330));

    echo "\n[ ACWR centralized — dashboard consumes quality-aware daily load ]\n";
    $dashboardSrc = file_get_contents(dirname(__DIR__) . '/player/monitoring/dashboard.php');
    ok('dashboard.php references TrainingLoadCalculator', strpos($dashboardSrc, 'TrainingLoadCalculator') !== false);
    ok('dashboard.php references AcwrCalculator', strpos($dashboardSrc, 'AcwrCalculator') !== false);
    ok('dashboard.php no longer owns DATE_SUB ACWR SQL', strpos($dashboardSrc, 'DATE_SUB(NOW(), INTERVAL 28 DAY)') === false);

    echo "\n[ Calendar week vs rolling-7-day differ by design ]\n";
    // Rolling-7-day (as ACWR computes it) from "today" would sum a totally
    // different, non-overlapping window than our fixed 2026-07-06..12 week.
    $stmt = $pdo->prepare(
        'SELECT SUM(training_load) as total FROM player_rpe WHERE user_id = ? AND submitted_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)'
    );
    $stmt->execute([$userId]);
    $rollingTotal = (int)($stmt->fetch()['total'] ?? 0);
    ok('rolling-7-day (from NOW()) sees none of the fixed test week', $rollingTotal === 0);
    ok('calendar week load is non-zero for the same player', $report['weekly_load'] > 0);

} catch (Exception $e) {
    ok('report generation did not throw', false, $e->getMessage());
}

// ── Coach-logged RPE scoping (linked_player_id, not user_id) ─────────────────
// A coach logging RPE on behalf of a roster player stores user_id = the
// COACH's id and linked_player_id = the player's club_players.id (see
// api/player/rpe/save.php). The report must scope by linked_player_id so
// this — the common real-world path — is not silently missed.
$coachId = null; $cpId = null; $targetPlayerUserId = null;
try {
    $pdo->beginTransaction();

    $pdo->prepare("INSERT INTO users (name,email,password_hash,role) VALUES (?,?,?,'club')")
        ->execute(['TL Test Coach', "tl_coach_{$ts}@test.com", 'x']);
    $coachId = (int)$pdo->lastInsertId();

    $pdo->prepare("INSERT INTO users (name,email,password_hash,role,player_type) VALUES (?,?,?,'player','club')")
        ->execute(['TL Coached Player', "tl_coached_{$ts}@test.com", 'x']);
    $targetPlayerUserId = (int)$pdo->lastInsertId();

    $cpId = 'cp_' . bin2hex(random_bytes(6));
    $pdo->prepare("INSERT INTO club_players (id,user_id,name,is_active,linked_user_id) VALUES (?,?,?,1,?)")
        ->execute([$cpId, $coachId, 'TL Coached Player', $targetPlayerUserId]);

    // Coach submits RPE FOR the player: user_id = coach, linked_player_id = cpId
    $pdo->prepare(
        "INSERT INTO player_rpe (user_id, linked_player_id, rpe_score, duration_minutes, training_load, recorded_by, submitted_at)
         VALUES (?,?,?,?,?,'coach',?)"
    )->execute([$coachId, $cpId, 4, 80, 320, "$wed 09:00:00"]);

    $pdo->commit();

    echo "\n[ Coach-logged RPE scoping ]\n";
    $viaLinkedId = TrainingLoadCalculator::getPlayerWeeklyReport($pdo, $targetPlayerUserId, $cpId, $mon, $tz, false);
    ok('coach-logged load found when scoped by linked_player_id', almostEqual($viaLinkedId['weekly_load'], 320));

    $viaUserIdOnly = TrainingLoadCalculator::getPlayerWeeklyReport($pdo, $targetPlayerUserId, null, $mon, $tz, false);
    ok('coach-logged load MISSED if scoped by user_id alone (documents why linked_player_id is required)', almostEqual($viaUserIdOnly['weekly_load'], 0));
} catch (Exception $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    ok('coach-logged RPE scoping fixtures', false, $e->getMessage());
}

// ── Player with NO personal login (linked_user_id NULL) — the common case ────
// api/club/team-wellness.php's training-load roster query must NOT require
// linked_user_id IS NOT NULL, since most club players never sign in
// themselves; only the Hooper-based readiness roster needs a real login.
$cpNoLoginId = null;
try {
    $pdo->beginTransaction();
    $cpNoLoginId = 'cp_' . bin2hex(random_bytes(6));
    $pdo->prepare("INSERT INTO club_players (id,user_id,name,is_active,player_type,linked_user_id) VALUES (?,?,?,1,'club',NULL)")
        ->execute([$cpNoLoginId, $coachId, 'TL No-Login Player']);

    // Coach logs RPE for this player — user_id is the coach's, linked_player_id is set,
    // exactly like the coach-managed case, but this player has no login at all.
    $pdo->prepare(
        "INSERT INTO player_rpe (user_id, linked_player_id, rpe_score, duration_minutes, training_load, recorded_by, submitted_at)
         VALUES (?,?,?,?,?,'coach',?)"
    )->execute([$coachId, $cpNoLoginId, 5, 60, 300, "$thu 09:00:00"]);
    $pdo->commit();

    echo "\n[ Player without personal login (linked_user_id NULL) ]\n";
    $stmt = $pdo->prepare(
        'SELECT id, linked_user_id FROM club_players WHERE user_id = ? AND is_active = 1 AND player_type = "club"'
    );
    $stmt->execute([$coachId]);
    $roster = $stmt->fetchAll();
    $found = null;
    foreach ($roster as $row) { if ($row['id'] === $cpNoLoginId) $found = $row; }
    ok('training-load roster query includes player with linked_user_id NULL', $found !== null);

    // team-wellness.php passes (int)($p['linked_user_id'] ?? 0) as the userId sentinel
    $reportNoLogin = TrainingLoadCalculator::getPlayerWeeklyReport($pdo, 0, $cpNoLoginId, $mon, $tz, false);
    ok('weekly report resolves correctly via linked_player_id even with userId=0 sentinel',
        almostEqual($reportNoLogin['weekly_load'], 300));
} catch (Exception $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    ok('no-login player fixtures', false, $e->getMessage());
}

// ── Cleanup ──────────────────────────────────────────────────────────────────
try {
    if ($cpNoLoginId) {
        $pdo->prepare('DELETE FROM player_rpe WHERE linked_player_id = ?')->execute([$cpNoLoginId]);
        $pdo->prepare('DELETE FROM club_players WHERE id = ?')->execute([$cpNoLoginId]);
    }
    if ($cpId) {
        $pdo->prepare('DELETE FROM player_rpe WHERE linked_player_id = ?')->execute([$cpId]);
        $pdo->prepare('DELETE FROM club_players WHERE id = ?')->execute([$cpId]);
    }
    if ($coachId || $targetPlayerUserId) {
        $pdo->prepare('DELETE FROM users WHERE id IN (?,?)')->execute([$coachId ?? 0, $targetPlayerUserId ?? 0]);
    }
    $pdo->prepare('DELETE FROM player_rpe WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM player_hooper_index WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM club_sessions WHERE user_id = ?')->execute([$userId]);
    $pdo->prepare('DELETE FROM training_sessions WHERE id IN (?,?)')->execute([$tsId, $tsLinkedId]);
    $pdo->prepare('DELETE FROM users WHERE id = ?')->execute([$userId]);
    ok('cleanup done', true);
} catch (Exception $e) {
    ok('cleanup', false, $e->getMessage());
}

echo "\n=== Result: $pass passed, $fail failed ===\n\n";
exit($fail > 0 ? 1 : 0);
