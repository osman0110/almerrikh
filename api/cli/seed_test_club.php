<?php
// Creates (or removes) a clearly-marked TEST club with 3 fully populated
// players, so the club can compare how every report looks with real data —
// without touching the real club's players, averages or dashboards.
//
//   php api/cli/seed_test_club.php --confirm=CREATE
//   php api/cli/seed_test_club.php --delete --confirm=DELETE
//
// What it creates (last 28 days, values plausible and internally consistent):
//   • one club named "[TEST] نادي اختبار — delete me" + one team
//   • accounts: admin, physical coach, doctor, and a login per player
//   • 3 players with full profiles:
//       1) fit, high availability          2) fatigued, rising load
//       3) injured: injury case + physio session + training restriction
//   • ~12 sessions with attendance, post-session RPE (training_load =
//     RPE × minutes), daily Hooper, 2 body-composition assessments each,
//     one FMS screening each, and a daily participation decision
//   • NO AI assessment results: AI tests are disabled and their scores must
//     come from real measurement, never from seeded numbers.
//
// Everything is tagged: the club name starts with "[TEST]", ids start with
// "testclub-", emails end with "@merr-test.invalid". --delete removes exactly
// those rows and nothing else.
if (PHP_SAPI !== 'cli') { fwrite(STDERR, "CLI only.\n"); exit(1); }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/fitness/RpeIdentity.php';
require_once dirname(__DIR__) . '/includes/body_composition_calculator.php';

$args     = $argv;
$isDelete = in_array('--delete', $args, true);
$confirm  = '';
foreach ($args as $a) if (str_starts_with($a, '--confirm=')) $confirm = substr($a, 10);

const TEST_CLUB_PREFIX = '[TEST]';
const TEST_EMAIL_DOMAIN = '@merr-test.invalid';
const ID_PREFIX = 'testclub-';

function tableExists(PDO $pdo, string $t): bool {
    return (bool)$pdo->query('SHOW TABLES LIKE ' . $pdo->quote($t))->fetchColumn();
}
function say(string $m): void { echo $m, "\n"; }

// ─────────────────────────────────────────────────────────────────────────────
// DELETE
// ─────────────────────────────────────────────────────────────────────────────
if ($isDelete) {
    if ($confirm !== 'DELETE') {
        fwrite(STDERR, "Refusing: pass --confirm=DELETE to remove the test club.\n");
        exit(2);
    }
    $clubIds = $pdo->query(
        'SELECT id FROM clubs WHERE name LIKE ' . $pdo->quote(TEST_CLUB_PREFIX . '%')
    )->fetchAll(PDO::FETCH_COLUMN);
    if (!$clubIds) { say('No [TEST] club found — nothing to delete.'); exit(0); }
    $list = implode(',', array_map('intval', $clubIds));
    $userIds = $pdo->query("SELECT id FROM users WHERE club_id IN ($list) OR email LIKE '%" . TEST_EMAIL_DOMAIN . "'")
        ->fetchAll(PDO::FETCH_COLUMN);
    $uids = $userIds ? implode(',', array_map('intval', $userIds)) : '0';
    $sessionIds = $pdo->query("SELECT id FROM club_sessions WHERE club_id IN ($list)")->fetchAll(PDO::FETCH_COLUMN);
    $sList = $sessionIds ? implode(',', array_map([$pdo, 'quote'], $sessionIds)) : "''";

    $statements = [
        "DELETE FROM fms_movement_scores WHERE assessment_id IN (SELECT id FROM fms_assessments WHERE club_id IN ($list))",
        "DELETE FROM fms_assessments WHERE club_id IN ($list)",
        "DELETE FROM player_body_composition_assessments WHERE club_id IN ($list)",
        "DELETE FROM player_rpe WHERE club_id IN ($list) OR user_id IN ($uids)",
        "DELETE FROM player_hooper_index WHERE club_id IN ($list) OR user_id IN ($uids)",
        "DELETE FROM player_daily_decisions WHERE club_id IN ($list)",
        "DELETE FROM injury_updates WHERE injury_case_id IN (SELECT id FROM injury_cases WHERE club_id IN ($list))",
        "DELETE FROM injury_cases WHERE club_id IN ($list)",
        "DELETE FROM physio_session_players WHERE session_id IN (SELECT id FROM physio_sessions WHERE club_id IN ($list))",
        "DELETE FROM physio_sessions WHERE club_id IN ($list)",
        "DELETE FROM club_session_exercises WHERE session_id IN ($sList)",
        "DELETE FROM session_attendance WHERE session_id IN ($sList)",
        "DELETE FROM session_players WHERE session_id IN ($sList)",
        "DELETE FROM training_sessions WHERE club_id IN ($list)",
        "DELETE FROM club_sessions WHERE club_id IN ($list)",
        "DELETE FROM assessments WHERE club_id IN ($list)",
        "DELETE FROM player_notes WHERE player_id LIKE '" . ID_PREFIX . "%'",
        "DELETE FROM player_status_history WHERE player_id LIKE '" . ID_PREFIX . "%'",
        "DELETE FROM notifications WHERE club_id IN ($list)",
        "DELETE FROM audit_logs WHERE changed_by_user_id IN ($uids)",
        "DELETE FROM club_players WHERE club_id IN ($list)",
        "DELETE FROM club_teams WHERE club_id IN ($list)",
        "DELETE FROM club_staff WHERE club_id IN ($list)",
        "DELETE FROM club_access_codes WHERE club_id IN ($list)",
        "DELETE FROM device_tokens WHERE user_id IN ($uids)",
        "DELETE FROM user_tokens WHERE user_id IN ($uids)",
        "DELETE FROM users WHERE id IN ($uids)",
        "DELETE FROM clubs WHERE id IN ($list)",
    ];
    $removed = 0;
    foreach ($statements as $sql) {
        if (preg_match('/DELETE FROM (\w+)/', $sql, $m) && !tableExists($pdo, $m[1])) continue;
        try { $removed += $pdo->exec($sql); }
        catch (Throwable $e) { fwrite(STDERR, "skip: $sql → " . $e->getMessage() . "\n"); }
    }
    say("Deleted the [TEST] club(s) $list — $removed rows removed.");
    exit(0);
}

// ─────────────────────────────────────────────────────────────────────────────
// CREATE
// ─────────────────────────────────────────────────────────────────────────────
if ($confirm !== 'CREATE') {
    fwrite(STDERR, "Refusing: pass --confirm=CREATE to seed the test club.\n");
    exit(2);
}
if ($pdo->query('SELECT id FROM clubs WHERE name LIKE ' . $pdo->quote(TEST_CLUB_PREFIX . '%'))->fetchColumn()) {
    fwrite(STDERR, "A [TEST] club already exists. Remove it first: --delete --confirm=DELETE\n");
    exit(2);
}

$tz    = new DateTimeZone('Africa/Khartoum');
$today = new DateTimeImmutable('today', $tz);
$stamp = $today->format('Ymd');
$pw    = 'Test' . random_int(1000, 9999) . '!';
$hash  = password_hash($pw, PASSWORD_BCRYPT, ['cost' => 11]);
$created = [];

$mkUser = function (string $key, string $name, string $role) use ($pdo, $hash, $stamp, &$created): int {
    $email = "$key.$stamp" . TEST_EMAIL_DOMAIN;
    $pdo->prepare(
        'INSERT INTO users (name, email, password_hash, role, account_type, player_type, is_active, status)
         VALUES (?, ?, ?, ?, ?, ?, 1, "active")'
    )->execute([$name, $email, $hash, $role === 'player' ? 'player' : 'staff',
                $role === 'player' ? 'player' : 'staff', $role === 'player' ? 'club' : null]);
    $id = (int)$pdo->lastInsertId();
    $created[] = ['role' => $role, 'name' => $name, 'email' => $email, 'user_id' => $id];
    return $id;
};

$pdo->beginTransaction();
try {
    // ── Club, staff, team ───────────────────────────────────────────────────
    $adminId = $mkUser('admin', 'مدير الاختبار', 'admin');
    $pdo->prepare('INSERT INTO clubs (owner_user_id, name, status) VALUES (?, ?, "active")')
        ->execute([$adminId, TEST_CLUB_PREFIX . ' نادي اختبار — delete me']);
    $clubId = (int)$pdo->lastInsertId();
    $pdo->prepare('UPDATE users SET club_id = ? WHERE id = ?')->execute([$clubId, $adminId]);

    $coachId  = $mkUser('coach', 'مدرب بدني اختبار', 'coach');
    $doctorId = $mkUser('doctor', 'طبيب اختبار', 'doctor');
    $staffIns = $pdo->prepare('INSERT INTO club_staff (club_id, user_id, staff_role, status) VALUES (?, ?, ?, "active")');
    $staffIns->execute([$clubId, $adminId, 'owner']);
    $staffIns->execute([$clubId, $coachId, 'coach']);
    $staffIns->execute([$clubId, $doctorId, 'doctor']);
    $pdo->prepare('UPDATE users SET club_id = ? WHERE id IN (?, ?)')->execute([$clubId, $coachId, $doctorId]);

    $teamName = 'الفريق الأول (اختبار)';
    $pdo->prepare('INSERT INTO club_teams (id, user_id, club_id, name, category, is_active) VALUES (?, ?, ?, ?, ?, 1)')
        ->execute([ID_PREFIX . 'team-' . $stamp, $adminId, $clubId, $teamName, 'first_team']);

    // ── Players ─────────────────────────────────────────────────────────────
    // profile, load level, wellness level, and whether they carry an injury
    $roster = [
        ['key' => 'p1', 'name' => 'لاعب اختبار ١', 'number' => '7',  'pos' => 'MID', 'dob' => '2001-03-14',
         'h' => 176.0, 'w' => 70.5, 'foot' => 'right', 'rpe' => [6, 7], 'hooper' => [6, 9],  'injured' => false],
        ['key' => 'p2', 'name' => 'لاعب اختبار ٢', 'number' => '11', 'pos' => 'FWD', 'dob' => '1999-08-02',
         'h' => 181.0, 'w' => 76.0, 'foot' => 'left',  'rpe' => [7, 9], 'hooper' => [11, 17], 'injured' => false],
        ['key' => 'p3', 'name' => 'لاعب اختبار ٣', 'number' => '4',  'pos' => 'DEF', 'dob' => '2003-11-21',
         'h' => 186.0, 'w' => 80.0, 'foot' => 'right', 'rpe' => [3, 5], 'hooper' => [9, 14], 'injured' => true],
    ];

    $playerIns = $pdo->prepare(
        'INSERT INTO club_players
            (id, user_id, club_id, name, player_type, linked_user_id, number, position, team_name,
             category, dominant_foot, date_of_birth, nationality, height_cm, weight_kg,
             physical_notes, status, is_active)
         VALUES (?, ?, ?, ?, "club", ?, ?, ?, ?, "first_team", ?, ?, "السودان", ?, ?, ?, ?, 1)'
    );
    foreach ($roster as &$p) {
        $p['user_id'] = $mkUser($p['key'], $p['name'], 'player');
        $p['id'] = ID_PREFIX . $p['key'] . '-' . $stamp;
        $playerIns->execute([
            $p['id'], $adminId, $clubId, $p['name'], $p['user_id'], $p['number'], $p['pos'], $teamName,
            $p['foot'], $p['dob'], $p['h'], $p['w'],
            'بيانات اختبار — يمكن حذفها', $p['injured'] ? 'injured' : 'active',
        ]);
        $pdo->prepare('UPDATE users SET club_id = ?, linked_player_id = ? WHERE id = ?')
            ->execute([$clubId, $p['id'], $p['user_id']]);
    }
    unset($p);

    // ── Sessions + attendance + RPE (last 28 days, Sun/Tue/Thu) ─────────────
    $rpeIns = $pdo->prepare(
        'INSERT INTO player_rpe
            (user_id, linked_player_id, club_id, session_id, session_type, rpe_type, rpe_score,
             duration_minutes, training_load, pain_reported, completed_full_session,
             actual_duration_minutes, recorded_by, logical_key, source_type, revision_number,
             is_active_record, submitted_at)
         VALUES (?, ?, ?, ?, "team_training", "post", ?, ?, ?, ?, 1, ?, ?, ?, "manual", 1, 1, ?)'
    );
    $sessIns = $pdo->prepare(
        'INSERT INTO club_sessions
            (id, user_id, club_id, title, type, scope, status, date, start_time, duration_min,
             location, team_name, player_count, intensity, attendance_required, rpe_required,
             coach_name, player_ids, completed_player_ids, linked_training_session_id)
         VALUES (?, ?, ?, ?, "training", "team", "completed", ?, "17:00", ?, "ملعب الاختبار", ?, ?, ?, 1, 1,
                 "مدرب بدني اختبار", ?, ?, ?)'
    );
    $tsIns = $pdo->prepare(
        'INSERT INTO training_sessions (id, club_id, coach_user_id, title, session_date, duration_minutes, rpe_required)
         VALUES (?, ?, ?, ?, ?, ?, 1)'
    );
    $spIns = $pdo->prepare(
        'INSERT INTO session_players (session_id, club_id, player_user_id, linked_player_id, status)
         VALUES (?, ?, ?, ?, "completed")'
    );
    $attIns = $pdo->prepare(
        'INSERT INTO session_attendance (session_id, player_id, user_id, club_id, status, marked_at, elapsed_seconds)
         VALUES (?, ?, ?, ?, ?, ?, ?)'
    );

    $playerIds = array_column($roster, 'id');
    $sessionCount = 0;
    for ($back = 27; $back >= 0; $back--) {
        $day = $today->sub(new DateInterval("P{$back}D"));
        $dow = (int)$day->format('w');            // 0 Sun, 2 Tue, 4 Thu
        if (!in_array($dow, [0, 2, 4], true)) continue;
        $sessionCount++;
        $date = $day->format('Y-m-d');
        $sid = ID_PREFIX . 'sess-' . $date;
        $duration = [75, 90, 105][$sessionCount % 3];
        $title = 'حصة تدريب اختبار ' . $sessionCount;
        $sessIns->execute([$sid, $coachId, $clubId, $title, $date, $duration, $teamName,
            count($playerIds), ['low', 'medium', 'high'][$sessionCount % 3],
            json_encode($playerIds), json_encode($playerIds), $sid]);
        $tsIns->execute([$sid, $clubId, $coachId, $title, $date, $duration]);

        foreach ($roster as $i => $p) {
            // player 3 misses the two most recent sessions (injury)
            $absent = $p['injured'] && $back <= 6;
            $status = $absent ? 'absent' : ($i === 1 && $back === 13 ? 'late' : 'present');
            $spIns->execute([$sid, $clubId, $p['user_id'], $p['id']]);
            $attIns->execute([$sid, $p['id'], $coachId, $clubId, $status,
                $date . ' 18:40:00', $absent ? 0 : $duration * 60]);
            if ($absent) continue;

            [$lo, $hi] = $p['rpe'];
            $rpe = $lo + (($sessionCount + $i) % (($hi - $lo) + 1));
            $actual = $status === 'late' ? (int)round($duration * 0.8) : $duration;
            $load = $rpe * $actual;
            $rpeIns->execute([
                $p['user_id'], $p['id'], $clubId, $sid, $rpe, $duration, $load,
                0, $actual, $p['user_id'],
                RpeIdentity::logicalKey($p['id'], $p['user_id'], $sid, 'post', $date, 'team_training', 'default'),
                $date . ' 19:15:00',
            ]);
        }
    }

    // ── Daily Hooper for all 28 days ────────────────────────────────────────
    $hooperIns = $pdo->prepare(
        'INSERT INTO player_hooper_index
            (user_id, linked_player_id, club_id, sleep_quality, fatigue, stress, muscle_soreness,
             sleep_hours, hooper_score, recorded_by, submitted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    foreach ($roster as $i => $p) {
        [$lo, $hi] = $p['hooper'];
        for ($back = 27; $back >= 0; $back--) {
            $day = $today->sub(new DateInterval("P{$back}D"));
            $total = $lo + (($back + $i * 2) % (($hi - $lo) + 1));   // 4..28 scale
            // split the total across the four 1..7 items, keeping each in range
            $base = intdiv($total, 4);
            $rest = $total - $base * 4;
            $items = [$base, $base, $base, $base];
            for ($k = 0; $k < $rest; $k++) $items[$k]++;
            foreach ($items as &$v) $v = max(1, min(7, $v));
            unset($v);
            $hooperIns->execute([
                $p['user_id'], $p['id'], $clubId,
                $items[0], $items[1], $items[2], $items[3],
                7.5 - ($items[1] * 0.2), array_sum($items), $p['user_id'],
                $day->format('Y-m-d') . ' 08:10:00',
            ]);
        }
    }

    // ── Body composition: 4 weeks ago and today ─────────────────────────────
    $bcIns = $pdo->prepare(
        'INSERT INTO player_body_composition_assessments
            (id, user_id, club_id, linked_player_id, recorded_by, approval_status, team_name, position,
             assessment_date, assessment_type, measurement_method, height_cm, weight_kg, age_at_assessment,
             biceps_mm, triceps_mm, subscapular_mm, suprailiac_mm, skinfold_sum_mm,
             calculation_formula_code, calculation_status, measurement_completeness,
             body_fat_percentage, fat_mass_kg, fat_free_mass_kg, bmi, assessed_by, created_by)
         VALUES (?, ?, ?, ?, ?, "approved", ?, ?, ?, "skinfold", "skinfold_4_site", ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    foreach ($roster as $i => $p) {
        foreach ([['28', $today->sub(new DateInterval('P28D')), 0.0], ['00', $today, -0.6]] as [$tag, $when, $drift]) {
            $age  = bc_calc_age($p['dob'], $when->format('Y-m-d')) ?? 22;
            $sk   = [6.0 + $i * 0.6 + $drift, 9.5 + $i * 0.8 + $drift, 10.0 + $i * 0.7 + $drift, 12.0 + $i * 0.9 + $drift];
            $sum  = array_sum($sk);
            $calc = bc_calculate_body_fat($pdo, $sum, $age, 'male');
            $bf   = $calc['body_fat_percentage'] ?? null;
            $wt   = $p['w'] + $drift;
            $fat  = $bf !== null ? round($wt * $bf / 100, 2) : null;
            $bcIns->execute([
                ID_PREFIX . 'bc-' . $p['key'] . '-' . $tag, $p['user_id'], $clubId, $p['id'], $coachId,
                $teamName, $p['pos'], $when->format('Y-m-d'), $p['h'], $wt, $age,
                round($sk[0], 1), round($sk[1], 1), round($sk[2], 1), round($sk[3], 1), round($sum, 1),
                $calc['formula_code'] ?? 'durnin_womersley_4site',
                $calc['calculation_status'] ?? 'OK', 'complete',
                $bf, $fat, $fat !== null ? round($wt - $fat, 2) : null,
                round($wt / (($p['h'] / 100) ** 2), 1), 'مدرب بدني اختبار', $coachId,
            ]);
        }
    }

    // ── FMS screening (7 movements, 1–3 each) ───────────────────────────────
    $fmsIns = $pdo->prepare(
        'INSERT INTO fms_assessments (id, user_id, player_id, player_name, total_score, notes, assessor_name, club_id, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $fmsScore = $pdo->prepare(
        'INSERT INTO fms_movement_scores (assessment_id, movement, left_score, right_score, final_score, pain)
         VALUES (?, ?, ?, ?, ?, 0)'
    );
    $movements = ['deep_squat', 'hurdle_step', 'inline_lunge', 'shoulder_mobility',
                  'active_straight_leg_raise', 'trunk_stability_pushup', 'rotary_stability'];
    foreach ($roster as $i => $p) {
        $fid = ID_PREFIX . 'fms-' . $p['key'];
        $scores = [];
        foreach ($movements as $m => $name) $scores[$name] = 2 + (($m + $i) % 2); // 2 or 3
        if ($p['injured']) $scores['inline_lunge'] = 1;
        $fmsIns->execute([$fid, $coachId, $p['id'], $p['name'], array_sum($scores),
            'فحص اختبار', 'مدرب بدني اختبار', $clubId, $today->sub(new DateInterval('P10D'))->format('Y-m-d H:i:s')]);
        foreach ($scores as $name => $sc) {
            $bilateral = !in_array($name, ['deep_squat', 'trunk_stability_pushup'], true);
            $fmsScore->execute([$fid, $name, $bilateral ? $sc : null, $bilateral ? $sc : null, $sc]);
        }
    }

    // ── Injury case + physio session + training restriction (player 3) ──────
    $injured = $roster[2];
    $pdo->prepare(
        'INSERT INTO injury_cases
            (club_id, player_id, injury_date, body_location, injury_type, severity, diagnosis,
             exam_notes, case_status, rtp_stage, expected_return_date, created_by_user_id)
         VALUES (?, ?, ?, "hamstring_left", "strain", "moderate", ?, ?, "in_treatment", "light_activity", ?, ?)'
    )->execute([
        $clubId, $injured['id'], $today->sub(new DateInterval('P6D'))->format('Y-m-d'),
        'شد عضلي خلفي درجة ٢ (بيانات اختبار)', 'ألم عند الجس في منتصف العضلة (بيانات اختبار)',
        $today->add(new DateInterval('P10D'))->format('Y-m-d'), $doctorId,
    ]);
    $caseId = (int)$pdo->lastInsertId();
    if (tableExists($pdo, 'injury_updates')) {
        $pdo->prepare(
            'INSERT INTO injury_updates (injury_case_id, author_user_id, note, rtp_stage, case_status, created_at)
             VALUES (?, ?, ?, "light_activity", "in_treatment", ?)'
        )->execute([$caseId, $doctorId, 'بدأ الجري الخفيف (بيانات اختبار)',
            $today->sub(new DateInterval('P2D'))->format('Y-m-d H:i:s')]);
    }
    $pdo->prepare(
        'INSERT INTO physio_sessions
            (club_id, therapist_user_id, scheduled_at, duration_minutes, room, body_area, session_reason,
             treatment_type, intensity, contraindications, created_by_user_id, session_name)
         VALUES (?, ?, ?, 30, "غرفة العلاج", "hamstring_left", "pain", "massage", "moderate", ?, ?, "جلسة اختبار")'
    )->execute([$clubId, $doctorId, $today->format('Y-m-d') . ' 11:00:00',
        'تجنب الجري السريع (بيانات اختبار)', $doctorId]);
    $physioId = (int)$pdo->lastInsertId();
    $pdo->prepare(
        'INSERT INTO physio_session_players (session_id, player_id, status, specialist_notes, player_response, recommendation)
         VALUES (?, ?, "completed", ?, ?, "modified_training")'
    )->execute([$physioId, $injured['id'],
        'عمل يدوي على العضلة الخلفية (بيانات اختبار)', 'تحسن ملحوظ (بيانات اختبار)']);

    $decisionIns = $pdo->prepare(
        'INSERT INTO player_daily_decisions
            (club_id, player_id, decision_date, participation_status, allowed_duration_minutes, restrictions, decided_by_user_id)
         VALUES (?, ?, ?, ?, ?, ?, ?)'
    );
    $decisionIns->execute([$clubId, $injured['id'], $today->format('Y-m-d'), 'modified', 45,
        'تجنب الجري السريع والاحتكاك (بيانات اختبار)', $doctorId]);
    foreach ([$roster[0], $roster[1]] as $p) {
        $decisionIns->execute([$clubId, $p['id'], $today->format('Y-m-d'), 'full', null, null, $coachId]);
    }

    // ── A coach note per player ─────────────────────────────────────────────
    if (tableExists($pdo, 'player_notes')) {
        $noteIns = $pdo->prepare(
            'INSERT INTO player_notes (player_id, coach_user_id, author_name, note_text, created_at) VALUES (?, ?, ?, ?, ?)'
        );
        foreach ($roster as $p) {
            $noteIns->execute([$p['id'], $coachId, 'مدرب بدني اختبار', 'ملاحظة مدرب — بيانات اختبار', $today->format('Y-m-d H:i:s')]);
        }
    }

    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    fwrite(STDERR, 'Seed failed: ' . $e->getMessage() . ' @ line ' . $e->getLine() . "\n");
    exit(1);
}

say('');
say('Test club created (club_id ' . $clubId . '): ' . TEST_CLUB_PREFIX . ' نادي اختبار — delete me');
say('Sessions: ' . $sessionCount . ' over the last 28 days, with attendance, RPE, Hooper, body composition, FMS,');
say('one injury case + physio session + restrictions. No AI assessment results were created.');
say('');
say('Accounts — same password for all: ' . $pw);
foreach ($created as $c) {
    say(sprintf('  %-8s %-22s %s', $c['role'], $c['name'], $c['email']));
}
say('');
say('Remove everything again with:');
say('  php api/cli/seed_test_club.php --delete --confirm=DELETE');
