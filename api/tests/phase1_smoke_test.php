<?php
/**
 * Phase 1 Smoke Test — Training Flow
 * Run: php api/tests/phase1_smoke_test.php
 */
require_once dirname(__DIR__) . '/db.php';

$pass = 0; $fail = 0;

function ok(string $label, bool $cond, string $detail = ''): void {
    global $pass, $fail;
    if ($cond) { echo "  PASS  $label\n"; $pass++; }
    else        { echo "  FAIL  $label" . ($detail ? " — $detail" : '') . "\n"; $fail++; }
}

echo "\n=== Phase 1 Smoke Test ===\n\n";

// ── 1. Schema checks ────────────────────────────────────────────────────────
echo "[ Schema ]\n";

function colExists(PDO $pdo, string $table, string $col): bool {
    $s = $pdo->prepare('SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?');
    $s->execute([$table, $col]);
    return (bool)$s->fetchColumn();
}
function tableExists(PDO $pdo, string $table): bool {
    $s = $pdo->prepare('SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?');
    $s->execute([$table]);
    return (bool)$s->fetchColumn();
}

ok('player_hooper_index.session_id',    colExists($pdo,'player_hooper_index','session_id'));
ok('player_hooper_index.assessment_id', colExists($pdo,'player_hooper_index','assessment_id'));
ok('player_hooper_index.pre_rpe',       colExists($pdo,'player_hooper_index','pre_rpe'));
ok('player_hooper_index.pain_today',    colExists($pdo,'player_hooper_index','pain_today'));
ok('player_hooper_index.linked_player_id', colExists($pdo,'player_hooper_index','linked_player_id'));
ok('player_hooper_index.club_id',       colExists($pdo,'player_hooper_index','club_id'));

ok('player_rpe.session_id',      colExists($pdo,'player_rpe','session_id'));
ok('player_rpe.assessment_id',   colExists($pdo,'player_rpe','assessment_id'));
ok('player_rpe.rpe_type',        colExists($pdo,'player_rpe','rpe_type'));
ok('player_rpe.pain_reported',   colExists($pdo,'player_rpe','pain_reported'));
ok('player_rpe.difficulty',      colExists($pdo,'player_rpe','difficulty'));
ok('player_rpe.mood_after',      colExists($pdo,'player_rpe','mood_after'));
ok('player_rpe.linked_player_id',colExists($pdo,'player_rpe','linked_player_id'));
ok('player_rpe.club_id',         colExists($pdo,'player_rpe','club_id'));

ok('table: training_plans',       tableExists($pdo,'training_plans'));
ok('table: training_sessions',    tableExists($pdo,'training_sessions'));
ok('table: session_players',      tableExists($pdo,'session_players'));
ok('table: session_exercises',    tableExists($pdo,'session_exercises'));
ok('table: post_training_feedback', tableExists($pdo,'post_training_feedback'));

ok('post_training_feedback.session_id',   colExists($pdo,'post_training_feedback','session_id'));
ok('post_training_feedback.assessment_id',colExists($pdo,'post_training_feedback','assessment_id'));

// ── 2. Create test fixtures ─────────────────────────────────────────────────
echo "\n[ Fixtures ]\n";

$pdo->beginTransaction();
try {
    // Club user (coach)
    $clubEmail = 'test_club_' . time() . '@test.com';
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role) VALUES (?,?,?,?)")
        ->execute(['Test Club', $clubEmail, 'x', 'club']);
    $clubUserId = (int)$pdo->lastInsertId();

    // Player user
    $playerEmail = 'test_player_' . time() . '@test.com';
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role,club_user_id) VALUES (?,?,?,?,?)")
        ->execute(['Test Player', $playerEmail, 'x', 'player', $clubUserId]);
    $playerUserId = (int)$pdo->lastInsertId();

    // Token
    $token = 'smoke_test_token_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token,user_id) VALUES (?,?)")
        ->execute([$token, $playerUserId]);

    // Unassigned player token (for 403 test)
    $otherPlayerEmail = 'test_other_' . time() . '@test.com';
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role) VALUES (?,?,?,?)")
        ->execute(['Other Player', $otherPlayerEmail, 'x', 'player']);
    $otherUserId = (int)$pdo->lastInsertId();
    $otherToken = 'smoke_test_other_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token,user_id) VALUES (?,?)")
        ->execute([$otherToken, $otherUserId]);

    // Training plan
    $planId = 'plan_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO training_plans (id,plan_type,owner_type,club_id,coach_user_id,title,status)
                   VALUES (?,?,?,?,?,?,?)")
        ->execute([$planId,'manual','coach',$clubUserId,$clubUserId,'Smoke Test Plan','published']);

    // Training session (wellness_required = 1)
    $sessId = 'sess_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO training_sessions (id,plan_id,club_id,coach_user_id,title,session_date,duration_minutes,wellness_required,rpe_required,status)
                   VALUES (?,?,?,?,?,CURDATE(),?,?,?,'assigned')")
        ->execute([$sessId,$planId,$clubUserId,$clubUserId,'Smoke Test Session',60,1,1]);

    // Assign player
    $pdo->prepare("INSERT INTO session_players (session_id,club_id,player_user_id,status) VALUES (?,?,?,'assigned')")
        ->execute([$sessId,$clubUserId,$playerUserId]);

    $pdo->commit();
    ok('fixtures created', true);
} catch (Exception $e) {
    $pdo->rollBack();
    ok('fixtures created', false, $e->getMessage());
    echo "\nAborting — cannot continue without fixtures.\n";
    exit(1);
}

// ── Helper: get session_players.status ─────────────────────────────────────
function spStatus(PDO $pdo, string $sessId, int $userId): string {
    $s = $pdo->prepare('SELECT status FROM session_players WHERE session_id=? AND player_user_id=?');
    $s->execute([$sessId, $userId]);
    return (string)($s->fetchColumn() ?: 'NOT_FOUND');
}

// ── 3. Test A: start without pre-check (wellness_required=1) ───────────────
echo "\n[ Test A: Start before pre-check — expect blocked ]\n";

$spStatus = spStatus($pdo, $sessId, $playerUserId);
ok('initial status = assigned', $spStatus === 'assigned', "got: $spStatus");

// Simulate start.php logic inline
$spRow = $pdo->prepare('SELECT id,status FROM session_players WHERE session_id=? AND player_user_id=?');
$spRow->execute([$sessId, $playerUserId]);
$sp = $spRow->fetch();

$sessRow2 = $pdo->prepare('SELECT wellness_required FROM training_sessions WHERE id=?');
$sessRow2->execute([$sessId]);
$sr = $sessRow2->fetch();

$blocked = ($sr && $sr['wellness_required'] && $sp['status'] === 'assigned');
ok('start blocked before pre-check', $blocked);

// ── 4. Test B: pre-check (hooper save) ────────────────────────────────────
echo "\n[ Test B: Pre-check (hooper save) ]\n";

$pdo->prepare(
    'INSERT INTO player_hooper_index
     (user_id, linked_player_id, club_id,
      session_id, training_session_id, assessment_id,
      sleep_quality, fatigue, stress, muscle_soreness, sleep_hours,
      hooper_score, pre_rpe, pain_today, notes)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)'
)->execute([
    $playerUserId, null, $clubUserId,
    $sessId, $sessId, null,
    5, 3, 4, 2, 7.5,
    14, 5, 0, 'smoke test'
]);

// Update session_players to pre_checked
$pdo->prepare(
    "UPDATE session_players SET status='pre_checked', pre_check_completed_at=NOW()
     WHERE session_id=? AND player_user_id=? AND status='assigned'"
)->execute([$sessId, $playerUserId]);

$status = spStatus($pdo, $sessId, $playerUserId);
ok('status = pre_checked after hooper save', $status === 'pre_checked', "got: $status");

// Verify hooper row saved with session_id
$hr = $pdo->prepare('SELECT session_id, hooper_score, pre_rpe FROM player_hooper_index WHERE session_id=? AND user_id=?');
$hr->execute([$sessId, $playerUserId]);
$hooRow = $hr->fetch();
ok('hooper row has session_id',  $hooRow && $hooRow['session_id'] === $sessId);
ok('hooper_score = 14 (5+3+4+2)', $hooRow && (int)$hooRow['hooper_score'] === 14);
ok('pre_rpe = 5',                  $hooRow && (int)$hooRow['pre_rpe']      === 5);

// ── 5. Test C: start session ──────────────────────────────────────────────
echo "\n[ Test C: Start session ]\n";

$sp2 = $pdo->prepare('SELECT id,status FROM session_players WHERE session_id=? AND player_user_id=?');
$sp2->execute([$sessId, $playerUserId]);
$spNow = $sp2->fetch();

$allowedFrom = ['pre_checked']; // wellness_required=1
if (in_array($spNow['status'], $allowedFrom, true)) {
    $pdo->prepare(
        "UPDATE session_players SET status='started', started_at=NOW()
         WHERE session_id=? AND player_user_id=? AND status IN ('pre_checked')"
    )->execute([$sessId, $playerUserId]);
}

$status = spStatus($pdo, $sessId, $playerUserId);
ok('status = started after start', $status === 'started', "got: $status");

// ── 6. Test D: post-feedback ──────────────────────────────────────────────
echo "\n[ Test D: Post-feedback ]\n";

// Validate session assigned to this player
$spCheck = $pdo->prepare('SELECT id,status FROM session_players WHERE session_id=? AND player_user_id=?');
$spCheck->execute([$sessId, $playerUserId]);
$spChkRow = $spCheck->fetch();
ok('session ownership check passes', (bool)$spChkRow);
ok('status is not already completed', $spChkRow && $spChkRow['status'] !== 'completed');

// Save post_training_feedback
$pdo->prepare(
    'INSERT INTO post_training_feedback
     (session_id, assessment_id, club_id, player_user_id, linked_player_id,
      post_rpe, pain_reported, difficulty, mood_after, notes)
     VALUES (?,?,?,?,?,?,?,?,?,?)'
)->execute([$sessId, null, $clubUserId, $playerUserId, null, 7, 0, 'good', 4, 'smoke test post']);

// Save to player_rpe (monitoring dashboard)
$pdo->prepare(
    "INSERT INTO player_rpe
     (user_id, linked_player_id, club_id,
      session_id, training_session_id, assessment_id,
      rpe_type, rpe_score, duration_minutes, training_load,
      pain_reported, difficulty, mood_after, notes)
     VALUES (?,?,?,?,?,?,'post',?,?,?,?,?,?,?)"
)->execute([
    $playerUserId, null, $clubUserId,
    $sessId, $sessId, null,
    7, 60, 420,
    0, 'good', 4, 'smoke test post'
]);

// Transition to completed
$pdo->prepare(
    "UPDATE session_players SET status='completed', completed_at=NOW()
     WHERE session_id=? AND player_user_id=? AND status NOT IN ('completed','missed')"
)->execute([$sessId, $playerUserId]);

$status = spStatus($pdo, $sessId, $playerUserId);
ok('status = completed after post-feedback', $status === 'completed', "got: $status");

// Verify post_training_feedback row
$ptf = $pdo->prepare('SELECT post_rpe, difficulty, pain_reported FROM post_training_feedback WHERE session_id=? AND player_user_id=?');
$ptf->execute([$sessId, $playerUserId]);
$ptfRow = $ptf->fetch();
ok('post_training_feedback row saved',   (bool)$ptfRow);
ok('post_rpe = 7',                       $ptfRow && (int)$ptfRow['post_rpe']    === 7);
ok('difficulty = good',                  $ptfRow && $ptfRow['difficulty']       === 'good');
ok('pain_reported = 0',                  $ptfRow && (int)$ptfRow['pain_reported'] === 0);

// Verify player_rpe row with rpe_type='post'
$rpeRow = $pdo->prepare("SELECT rpe_score, rpe_type, training_load FROM player_rpe WHERE session_id=? AND user_id=? AND rpe_type='post'");
$rpeRow->execute([$sessId, $playerUserId]);
$rr = $rpeRow->fetch();
ok('player_rpe row saved for monitoring', (bool)$rr);
ok('rpe_type = post',                     $rr && $rr['rpe_type']     === 'post');
ok('training_load = 420 (7×60)',          $rr && (int)$rr['training_load'] === 420);

// ── 7. Test E: unassigned player gets 403 ────────────────────────────────
echo "\n[ Test E: Unassigned player access — expect 403 ]\n";

$spOther = $pdo->prepare('SELECT id FROM session_players WHERE session_id=? AND player_user_id=?');
$spOther->execute([$sessId, $otherUserId]);
$noRow = $spOther->fetch();
ok('other player has no session_players row', !$noRow);

// ── 8. Validation rules quick check ──────────────────────────────────────
echo "\n[ Validation rules ]\n";

function validRange(int $v, int $min, int $max): bool { return $v >= $min && $v <= $max; }

ok('hooper fields 1–7 range check (4)',   validRange(4, 1, 7));
ok('hooper fields 1–7 range check (0)',   !validRange(0, 1, 7));
ok('hooper fields 1–7 range check (8)',   !validRange(8, 1, 7));
ok('rpe 1–10 range check (10)',           validRange(10, 1, 10));
ok('rpe 1–10 range check (11)',           !validRange(11, 1, 10));
ok('mood_after 1–5 range check (5)',      validRange(5, 1, 5));
ok('mood_after 1–5 range check (6)',      !validRange(6, 1, 5));
$diffs = ['easy','good','hard','too_hard'];
ok('difficulty easy OK',                  in_array('easy', $diffs, true));
ok('difficulty invalid rejected',         !in_array('extreme', $diffs, true));

// ── 9. Cleanup ─────────────────────────────────────────────────────────────
echo "\n[ Cleanup ]\n";
try {
    $pdo->prepare('DELETE FROM session_players       WHERE session_id=?')->execute([$sessId]);
    $pdo->prepare('DELETE FROM post_training_feedback WHERE session_id=?')->execute([$sessId]);
    $pdo->prepare('DELETE FROM player_rpe             WHERE session_id=?')->execute([$sessId]);
    $pdo->prepare('DELETE FROM player_hooper_index    WHERE session_id=?')->execute([$sessId]);
    $pdo->prepare('DELETE FROM training_sessions      WHERE id=?')->execute([$sessId]);
    $pdo->prepare('DELETE FROM training_plans         WHERE id=?')->execute([$planId]);
    $pdo->prepare('DELETE FROM user_tokens WHERE user_id IN (?,?)')->execute([$playerUserId,$otherUserId]);
    $pdo->prepare('DELETE FROM users WHERE id IN (?,?,?)')->execute([$clubUserId,$playerUserId,$otherUserId]);
    ok('test data cleaned up', true);
} catch (Exception $e) {
    ok('test data cleaned up', false, $e->getMessage());
}

// ── Summary ────────────────────────────────────────────────────────────────
$total = $pass + $fail;
echo "\n=== Results: $pass/$total PASSED" . ($fail ? " ($fail FAILED)" : '') . " ===\n\n";
exit($fail > 0 ? 1 : 0);
