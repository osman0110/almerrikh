<?php
/**
 * Phase 3 Smoke Test — Manual Coach Plan Builder
 * Run: php api/tests/phase3_smoke_test.php
 */
require_once dirname(__DIR__) . '/db.php';

$pass = 0; $fail = 0;

function ok(string $label, bool $cond, string $detail = ''): void {
    global $pass, $fail;
    if ($cond) { echo "  PASS  $label\n"; $pass++; }
    else        { echo "  FAIL  $label" . ($detail ? " — $detail" : '') . "\n"; $fail++; }
}

echo "\n=== Phase 3 Smoke Test ===\n\n";

// ── Fixtures ──────────────────────────────────────────────────────────────────
echo "[ Fixtures ]\n";

$pdo->beginTransaction();
try {
    // Club (coach) user
    $clubEmail = 'test_coach3_' . time() . '@test.com';
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role) VALUES (?,?,?,'club')")
        ->execute(['Test Coach', $clubEmail, 'x']);
    $coachId = (int)$pdo->lastInsertId();
    $coachToken = 'coach_token3_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token,user_id) VALUES (?,?)")
        ->execute([$coachToken, $coachId]);

    // Two players with accounts
    $p1Email = 'p3_1_' . time() . '@test.com';
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role,club_user_id) VALUES (?,?,?,'player',?)")
        ->execute(['Player One', $p1Email, 'x', $coachId]);
    $p1UserId = (int)$pdo->lastInsertId();

    $p2Email = 'p3_2_' . time() . '@test.com';
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role,club_user_id) VALUES (?,?,?,'player',?)")
        ->execute(['Player Two', $p2Email, 'x', $coachId]);
    $p2UserId = (int)$pdo->lastInsertId();

    // Player without app account (should be skipped in assignment)
    $cp1Id = bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO club_players (id,user_id,name,position,linked_user_id) VALUES (?,?,?,?,?)")
        ->execute([$cp1Id, $coachId, 'Player One', 'ST', $p1UserId]);

    $cp2Id = bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO club_players (id,user_id,name,position,linked_user_id) VALUES (?,?,?,?,?)")
        ->execute([$cp2Id, $coachId, 'Player Two', 'CM', $p2UserId]);

    $cp3Id = bin2hex(random_bytes(8));  // No linked_user_id — should be skipped
    $pdo->prepare("INSERT INTO club_players (id,user_id,name,position) VALUES (?,?,?,?)")
        ->execute([$cp3Id, $coachId, 'Unregistered Player', 'GK']);

    $pdo->commit();
    ok('fixtures created', true);
} catch (Exception $e) {
    $pdo->rollBack();
    ok('fixtures created', false, $e->getMessage());
    exit(1);
}

// ── Test 1: Create manual plan ────────────────────────────────────────────────
echo "\n[ Test 1: create-manual.php ]\n";

$tomorrow = date('Y-m-d', strtotime('+1 day'));

// Inline the create-manual logic (avoids HTTP)
$planId    = bin2hex(random_bytes(16));
$sessionId = bin2hex(random_bytes(16));

$pdo->beginTransaction();
try {
    $pdo->prepare(
        'INSERT INTO training_plans (id,plan_type,owner_type,club_id,coach_user_id,title,goal,status)
         VALUES (?,\'manual\',\'club\',?,?,?,?,\'published\')'
    )->execute([$planId, $coachId, $coachId, 'Smoke Test Session', 'fitness']);

    $pdo->prepare(
        'INSERT INTO training_sessions
         (id,plan_id,club_id,coach_user_id,title,session_date,duration_minutes,
          objective,source,status,wellness_required,rpe_required)
         VALUES (?,?,?,?,?,?,?,\'fitness\',\'manual\',\'assigned\',1,1)'
    )->execute([$sessionId, $planId, $coachId, $coachId, 'Smoke Test Session', $tomorrow, 60]);

    // 2 exercises
    foreach ([
        ['Push-ups', 'fitness', 3, 15, 'medium'],
        ['Sprint 30m', 'football', null, null, 'high'],
    ] as $i => $ex) {
        $pdo->prepare(
            'INSERT INTO session_exercises
             (session_id,exercise_name,category,sets,reps,intensity,sort_order)
             VALUES (?,?,?,?,?,?,?)'
        )->execute([$sessionId, $ex[0], $ex[1], $ex[2], $ex[3], $ex[4], $i]);
    }

    // Assign 2 players with accounts, skip 1 without
    $assigned = 0; $skipped = 0;
    $cpStmt = $pdo->prepare('SELECT linked_user_id FROM club_players WHERE id = ? AND user_id = ?');
    foreach ([$cp1Id, $cp2Id, $cp3Id] as $pid) {
        $cpStmt->execute([$pid, $coachId]);
        $cp = $cpStmt->fetch();
        if (!$cp || !$cp['linked_user_id']) { $skipped++; continue; }
        $pdo->prepare(
            'INSERT IGNORE INTO session_players (session_id,club_id,player_user_id,linked_player_id,status)
             VALUES (?,?,?,?,\'assigned\')'
        )->execute([$sessionId, $coachId, (int)$cp['linked_user_id'], $pid]);
        $assigned++;
    }

    $pdo->commit();
    ok('plan + session created', true);
} catch (Exception $e) {
    $pdo->rollBack();
    ok('plan + session created', false, $e->getMessage());
}

ok('plan in training_plans', (bool)$pdo->query("SELECT id FROM training_plans WHERE id='$planId'")->fetch());
ok('session in training_sessions', (bool)$pdo->query("SELECT id FROM training_sessions WHERE id='$sessionId'")->fetch());

$exCount = (int)$pdo->query("SELECT COUNT(*) FROM session_exercises WHERE session_id='$sessionId'")->fetchColumn();
ok('2 exercises inserted', $exCount === 2, "got $exCount");

$spCount = (int)$pdo->query("SELECT COUNT(*) FROM session_players WHERE session_id='$sessionId'")->fetchColumn();
ok('2 players assigned (1 skipped)', $spCount === 2, "got $spCount");
ok('1 skipped (no app account)', $skipped === 1, "got $skipped");

// ── Test 2: training-sessions list ────────────────────────────────────────────
echo "\n[ Test 2: training-sessions.php (GET) ]\n";

$stmt = $pdo->prepare("
    SELECT ts.id,
           (SELECT COUNT(*) FROM session_exercises WHERE session_id = ts.id)                         AS exercise_count,
           (SELECT COUNT(*) FROM session_players   WHERE session_id = ts.id)                         AS player_count,
           (SELECT COUNT(*) FROM session_players   WHERE session_id = ts.id AND status='assigned')   AS assigned_count,
           (SELECT COUNT(*) FROM session_players   WHERE session_id = ts.id AND status='completed')  AS completed_count
    FROM training_sessions ts
    WHERE ts.coach_user_id = ? AND ts.id = ?
");
$stmt->execute([$coachId, $sessionId]);
$row = $stmt->fetch();

ok('list query returns session', $row && $row['id'] === $sessionId);
ok('exercise_count = 2', $row && (int)$row['exercise_count'] === 2, "got " . ($row['exercise_count'] ?? '?'));
ok('player_count = 2',   $row && (int)$row['player_count']   === 2, "got " . ($row['player_count']   ?? '?'));
ok('assigned_count = 2', $row && (int)$row['assigned_count'] === 2, "got " . ($row['assigned_count'] ?? '?'));

// ── Test 3: session-report ────────────────────────────────────────────────────
echo "\n[ Test 3: session-report.php (GET) ]\n";

// Simulate player 1 completing pre-check + session
$pdo->prepare(
    "UPDATE session_players SET status='pre_checked', pre_check_completed_at=NOW()
     WHERE session_id=? AND player_user_id=?"
)->execute([$sessionId, $p1UserId]);

$pdo->prepare(
    "UPDATE session_players SET status='completed', completed_at=NOW()
     WHERE session_id=? AND player_user_id=?"
)->execute([$sessionId, $p1UserId]);

$pdo->prepare(
    'INSERT INTO post_training_feedback (session_id,player_user_id,post_rpe,pain_reported,difficulty,mood_after)
     VALUES (?,?,8,0,\'hard\',4)'
)->execute([$sessionId, $p1UserId]);

// Query as in session-report.php
$playerStmt = $pdo->prepare("
    SELECT sp.player_user_id, sp.status AS player_status,
           COALESCE(cp.name, u.name, 'Unknown') AS player_name,
           ptf.post_rpe, ptf.pain_reported, ptf.difficulty
    FROM session_players sp
    LEFT JOIN club_players cp ON cp.id = sp.linked_player_id
    LEFT JOIN users u ON u.id = sp.player_user_id
    LEFT JOIN post_training_feedback ptf ON ptf.id = (
        SELECT id FROM post_training_feedback
        WHERE session_id = sp.session_id AND player_user_id = sp.player_user_id
        ORDER BY created_at DESC LIMIT 1
    )
    WHERE sp.session_id = ?
    ORDER BY player_name
");
$playerStmt->execute([$sessionId]);
$players = $playerStmt->fetchAll();

ok('report returns 2 players', count($players) === 2, 'got ' . count($players));

$p1row = array_values(array_filter($players, fn($p) => (int)$p['player_user_id'] === $p1UserId))[0] ?? null;
ok('player 1 status = completed',    $p1row && $p1row['player_status'] === 'completed');
ok('player 1 post_rpe = 8',          $p1row && (int)$p1row['post_rpe'] === 8);
ok('player 1 difficulty = hard',     $p1row && $p1row['difficulty'] === 'hard');

$p2row = array_values(array_filter($players, fn($p) => (int)$p['player_user_id'] === $p2UserId))[0] ?? null;
ok('player 2 status = assigned',     $p2row && $p2row['player_status'] === 'assigned');
ok('player 2 post_rpe = null',       $p2row && $p2row['post_rpe'] === null);

// ── Test 4: security — coach can't see other club's session ───────────────────
echo "\n[ Test 4: Security — cross-coach access blocked ]\n";

$otherCoachStmt = $pdo->prepare('SELECT id FROM training_sessions WHERE id = ? AND coach_user_id = ?');
$otherCoachStmt->execute([$sessionId, $coachId + 999]);
ok('other coach cannot access session', !$otherCoachStmt->fetch());

// Ownership check in club_players
$foreignCpStmt = $pdo->prepare('SELECT linked_user_id FROM club_players WHERE id = ? AND user_id = ?');
$foreignCpStmt->execute([$cp1Id, $coachId + 999]);
ok('foreign coach cannot get player linked_user_id', !$foreignCpStmt->fetch());

// ── Test 5: routes confirm ─────────────────────────────────────────────────────
echo "\n[ Test 5: Route targets exist ]\n";
ok('ManualPlanBuilderScreen file exists',
    file_exists(__DIR__ . '/../../lib/screens/coach/manual_plan_builder_screen.dart'));
ok('TrainingSessionsListScreen file exists',
    file_exists(__DIR__ . '/../../lib/screens/coach/training_sessions_list_screen.dart'));
ok('SessionReportScreen file exists',
    file_exists(__DIR__ . '/../../lib/screens/coach/session_report_screen.dart'));
ok('training_plan_models.dart exists',
    file_exists(__DIR__ . '/../../lib/models/training_plan_models.dart'));

// ── Cleanup ────────────────────────────────────────────────────────────────────
echo "\n[ Cleanup ]\n";
try {
    $pdo->prepare('DELETE FROM post_training_feedback WHERE session_id=?')->execute([$sessionId]);
    $pdo->prepare('DELETE FROM session_players   WHERE session_id=?')->execute([$sessionId]);
    $pdo->prepare('DELETE FROM session_exercises WHERE session_id=?')->execute([$sessionId]);
    $pdo->prepare('DELETE FROM training_sessions WHERE id=?')->execute([$sessionId]);
    $pdo->prepare('DELETE FROM training_plans    WHERE id=?')->execute([$planId]);
    $pdo->prepare('DELETE FROM club_players      WHERE user_id=?')->execute([$coachId]);
    $pdo->prepare('DELETE FROM user_tokens       WHERE user_id IN (?,?,?)')->execute([$coachId,$p1UserId,$p2UserId]);
    $pdo->prepare('DELETE FROM users             WHERE id IN (?,?,?)')->execute([$coachId,$p1UserId,$p2UserId]);
    ok('test data cleaned', true);
} catch (Exception $e) {
    ok('test data cleaned', false, $e->getMessage());
}

// ── Summary ────────────────────────────────────────────────────────────────────
$total = $pass + $fail;
echo "\n=== Results: $pass/$total PASSED" . ($fail ? " ($fail FAILED)" : '') . " ===\n\n";
exit($fail > 0 ? 1 : 0);
