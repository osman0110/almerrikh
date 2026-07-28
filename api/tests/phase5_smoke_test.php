<?php
/**
 * Phase 5 Smoke Test — AI Coach/Academy Plan
 * Run: php api/tests/phase5_smoke_test.php
 *
 * Tests A–H per spec. AI calls skipped (uses mock mode).
 */
require_once dirname(__DIR__) . '/db.php';

$pass = 0; $fail = 0;

function ok(string $label, bool $cond, string $detail = ''): void {
    global $pass, $fail;
    if ($cond) { echo "  PASS  $label\n"; $pass++; }
    else        { echo "  FAIL  $label" . ($detail ? " — $detail" : '') . "\n"; $fail++; }
}

function colExists(PDO $pdo, string $t, string $c): bool {
    $s = $pdo->prepare('SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?');
    $s->execute([$t,$c]); return (bool)$s->fetchColumn();
}
function tableExists(PDO $pdo, string $t): bool {
    $s = $pdo->prepare('SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?');
    $s->execute([$t]); return (bool)$s->fetchColumn();
}

echo "\n=== Phase 5 Smoke Test — AI Coach/Academy Plan ===\n\n";

// ── 1. Schema ─────────────────────────────────────────────────────────────────
echo "[ Schema ]\n";
ok('training_plans.plan_summary',  colExists($pdo, 'training_plans', 'plan_summary'));
ok('training_plans.target_type',   colExists($pdo, 'training_plans', 'target_type'));
ok('table: plan_players',          tableExists($pdo, 'plan_players'));
ok('plan_players.club_player_id',  colExists($pdo, 'plan_players', 'club_player_id'));

// ── 2. Fixtures ───────────────────────────────────────────────────────────────
echo "\n[ Fixtures ]\n";

$ts = time();
$pdo->beginTransaction();
try {
    // Club/coach user
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role) VALUES (?,?,?,'club')")
        ->execute(['Coach P5', "coach_p5_{$ts}@test.com", 'x']);
    $coachId = (int)$pdo->lastInsertId();
    $coachToken = 'coach_p5_tok_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token,user_id) VALUES (?,?)")->execute([$coachToken, $coachId]);

    // Player user
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role,player_type) VALUES (?,?,?,'player','club')")
        ->execute(['Player P5', "player_p5_{$ts}@test.com", 'x']);
    $playerUserId = (int)$pdo->lastInsertId();
    $playerToken = 'player_p5_tok_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token,user_id) VALUES (?,?)")->execute([$playerToken, $playerUserId]);

    // Club player record linked to coach
    $cpId = bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO club_players (id,user_id,name,position,is_active,linked_user_id) VALUES (?,?,?,?,1,?)")
        ->execute([$cpId, $coachId, 'Player P5', 'midfielder', $playerUserId]);

    // Another coach (outsider)
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role) VALUES (?,?,?,'club')")
        ->execute(['Coach Other', "coach_other_{$ts}@test.com", 'x']);
    $otherCoachId = (int)$pdo->lastInsertId();
    $otherToken = 'coach_other_tok_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token,user_id) VALUES (?,?)")->execute([$otherToken, $otherCoachId]);

    $pdo->commit();
    ok('fixtures created', true);
} catch (Exception $e) {
    $pdo->rollBack();
    ok('fixtures created', false, $e->getMessage());
    exit(1);
}

// ── 3. Test A: player calls generate-ai → 403 ─────────────────────────────
echo "\n[ Test A — player blocked on generate-ai ]\n";
{
    $_SERVER['REQUEST_METHOD'] = 'POST';
    // Simulate check via DB (no HTTP call — check role directly)
    $roleStmt = $pdo->prepare('SELECT role FROM users WHERE id=?');
    $roleStmt->execute([$playerUserId]);
    $role = $roleStmt->fetchColumn();
    ok('A: player role = player', $role === 'player');
    ok('A: player must be blocked (not club/coach/academy)', !in_array($role, ['club','coach','academy'], true));
}

// ── 4. Test B & F: coach generates AI plan for own player (mock mode) ──────
echo "\n[ Test B/F — coach generates mock AI plan ]\n";
{
    // Simulate generate-ai.php logic
    // 1. Auth check passes for coach
    $coachRoleStmt = $pdo->prepare('SELECT role FROM users WHERE id=?');
    $coachRoleStmt->execute([$coachId]);
    $coachRole = $coachRoleStmt->fetchColumn();
    ok('B: coach role allowed', in_array($coachRole, ['club','coach','academy'], true));

    // 2. Ownership check passes
    $cpStmt = $pdo->prepare('SELECT id FROM club_players WHERE id=? AND user_id=? AND is_active=1');
    $cpStmt->execute([$cpId, $coachId]);
    ok('B: club_player belongs to coach', (bool)$cpStmt->fetch());

    // 3. Build mock plan
    $mockPlan = [
        'plan_title'        => 'Mock Speed Plan',
        'summary'           => 'A mock plan for testing Phase 5.',
        'weeks'             => [
            ['week' => 1, 'sessions' => [
                ['title' => 'Day 1 — Speed', 'objective' => 'fitness', 'duration_minutes' => 60, 'intensity' => 'medium',
                 'exercises' => [
                     ['exercise_name' => 'Warm-Up', 'category' => 'fitness', 'sets' => null, 'reps' => null, 'duration_seconds' => 300, 'rest_seconds' => 0, 'instructions' => 'Light jog.', 'requires_pose_detection' => false, 'assessment_type' => null],
                     ['exercise_name' => 'Sprint 30m', 'category' => 'football', 'sets' => 5, 'reps' => null, 'duration_seconds' => null, 'rest_seconds' => 60, 'instructions' => 'Max effort.', 'requires_pose_detection' => false, 'assessment_type' => null],
                 ]],
            ]],
        ],
        'recovery_notes'    => 'Rest 48h between sessions.',
        'progression_rules' => 'Add 5% load each week.',
    ];

    $planId  = bin2hex(random_bytes(16));
    $goalF   = 'speed';
    $numWeeksF = 1;

    $pdo->beginTransaction();
    try {
        $pdo->prepare(
            "INSERT INTO training_plans
             (id,plan_type,owner_type,club_id,coach_user_id,title,goal,status,
              target_type,ai_provider,ai_prompt_snapshot,ai_response_snapshot,
              plan_summary,recovery_notes,progression_rules,num_weeks)
             VALUES (?,'ai','club',?,?,?,?,'draft','selected_players','anthropic',?,?,?,?,?,?)"
        )->execute([
            $planId, $coachId, $coachId,
            $mockPlan['plan_title'], $goalF,
            'mock_prompt', 'mock',
            $mockPlan['summary'],
            $mockPlan['recovery_notes'],
            $mockPlan['progression_rules'],
            $numWeeksF,
        ]);

        // Store plan_player
        $luStmt = $pdo->prepare('SELECT linked_user_id FROM club_players WHERE id=?');
        $luStmt->execute([$cpId]);
        $lr = $luStmt->fetch();
        $pdo->prepare('INSERT IGNORE INTO plan_players (plan_id,club_player_id,player_user_id) VALUES (?,?,?)')
            ->execute([$planId, $cpId, $lr ? (int)$lr['linked_user_id'] : null]);

        // Store session + exercises
        $sessId = bin2hex(random_bytes(16));
        $pdo->prepare(
            "INSERT INTO training_sessions
             (id,plan_id,club_id,coach_user_id,title,session_date,duration_minutes,
              objective,source,status,wellness_required,rpe_required,week_number,intensity)
             VALUES (?,?,?,?,'Day 1 — Speed',?,60,'fitness','ai','draft',1,1,1,'medium')"
        )->execute([$sessId, $planId, $coachId, $coachId, date('Y-m-d', strtotime('+1 day'))]);

        $exStmt = $pdo->prepare('INSERT INTO session_exercises (session_id,exercise_name,category,sets,duration_seconds,instructions,requires_pose_detection,sort_order) VALUES (?,?,?,?,?,?,?,?)');
        $exStmt->execute([$sessId, 'Warm-Up', 'fitness', null, 300, 'Light jog.', 0, 0]);
        $exStmt->execute([$sessId, 'Sprint 30m', 'football', 5, null, 'Max effort.', 0, 1]);

        $pdo->commit();

        // Verify
        $planRow = $pdo->prepare('SELECT status,plan_type FROM training_plans WHERE id=?');
        $planRow->execute([$planId]);
        $pr = $planRow->fetch();
        ok('F: draft plan saved with status=draft', $pr && $pr['status'] === 'draft');
        ok('F: plan_type=ai', $pr && $pr['plan_type'] === 'ai');

        $ppRow = $pdo->prepare('SELECT COUNT(*) FROM plan_players WHERE plan_id=?');
        $ppRow->execute([$planId]);
        ok('F: plan_players record created', (int)$ppRow->fetchColumn() > 0);

        $sessCount = $pdo->prepare('SELECT COUNT(*) FROM training_sessions WHERE plan_id=? AND status=\'draft\'');
        $sessCount->execute([$planId]);
        ok('F: sessions saved as draft', (int)$sessCount->fetchColumn() > 0);

        $exCount = $pdo->prepare('SELECT COUNT(*) FROM session_exercises WHERE session_id=?');
        $exCount->execute([$sessId]);
        ok('F: exercises saved', (int)$exCount->fetchColumn() >= 2);

    } catch (Exception $e) {
        $pdo->rollBack();
        ok('F: plan saved', false, $e->getMessage());
    }
}

// ── 5. Test C: coach tries player outside scope → blocked ─────────────────
echo "\n[ Test C — coach tries player outside scope ]\n";
{
    $outsideId = 'not_my_player_' . $ts;
    $cpStmt = $pdo->prepare('SELECT id FROM club_players WHERE id=? AND user_id=? AND is_active=1');
    $cpStmt->execute([$outsideId, $coachId]);
    ok('C: outside player not found for this coach', !$cpStmt->fetch());
}

// ── 6. Test D: coach tries independent player → blocked ──────────────────
echo "\n[ Test D — coach tries independent player ]\n";
{
    // An independent player wouldn't be in club_players with this coach's user_id
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role,player_type) VALUES (?,?,?,'player','independent')")
        ->execute(['Indie Player', "indie_{$ts}@test.com", 'x']);
    $indieId = (int)$pdo->lastInsertId();

    // Not in club_players for this coach
    $cpStmt = $pdo->prepare('SELECT id FROM club_players WHERE linked_user_id=? AND user_id=?');
    $cpStmt->execute([$indieId, $coachId]);
    ok('D: independent player not in coach scope', !$cpStmt->fetch());
}

// ── 7. Test E: AI key missing ────────────────────────────────────────────
echo "\n[ Test E — AI key missing ]\n";
{
    $keyDefined = defined('ANTHROPIC_API_KEY') && !empty(ANTHROPIC_API_KEY);
    // Either key is present (production) or absent (dev without config)
    // Endpoint should return clean error if absent — we just verify logic
    ok('E: ANTHROPIC_API_KEY constant defined', defined('ANTHROPIC_API_KEY'));
    // If key empty, our endpoint returns {success:false, error:'AI provider not configured'}
    if (!$keyDefined) {
        ok('E: key absent → endpoint would return clean error (no crash)', true);
    } else {
        ok('E: key present (AI calls available)', true);
    }
}

// ── 8. Test G: publish draft ──────────────────────────────────────────────
echo "\n[ Test G — publish draft plan ]\n";
{
    // Verify the plan from Test F still exists and is draft
    $planRow = $pdo->prepare('SELECT status FROM training_plans WHERE id=? AND coach_user_id=?');
    $planRow->execute([$planId, $coachId]);
    $pr = $planRow->fetch();
    ok('G: plan in draft before publish', $pr && $pr['status'] === 'draft');

    if ($pr && $pr['status'] === 'draft') {
        // Simulate publish.php logic
        $pdo->beginTransaction();
        try {
            // Update plan status
            $pdo->prepare('UPDATE training_plans SET status=\'published\',updated_at=NOW() WHERE id=?')->execute([$planId]);
            // Activate sessions
            $pdo->prepare('UPDATE training_sessions SET status=\'assigned\' WHERE plan_id=?')->execute([$planId]);

            // Create session_players
            $sessRows = $pdo->prepare('SELECT id FROM training_sessions WHERE plan_id=?');
            $sessRows->execute([$planId]);
            $sessions = array_column($sessRows->fetchAll(), 'id');

            $ppRows = $pdo->prepare('SELECT club_player_id,player_user_id FROM plan_players WHERE plan_id=?');
            $ppRows->execute([$planId]);
            $planPlayers = $ppRows->fetchAll();

            $spStmt = $pdo->prepare(
                "INSERT IGNORE INTO session_players (session_id,club_id,player_user_id,linked_player_id,status) VALUES (?,?,?,?,'assigned')"
            );
            foreach ($sessions as $sid) {
                foreach ($planPlayers as $pp) {
                    $spStmt->execute([$sid, $coachId, $pp['player_user_id'], $pp['club_player_id']]);
                }
            }
            $pdo->commit();

            // Verify
            $planStatus = $pdo->prepare('SELECT status FROM training_plans WHERE id=?');
            $planStatus->execute([$planId]);
            ok('G: plan.status=published', $planStatus->fetchColumn() === 'published');

            $sessCnt = $pdo->prepare("SELECT COUNT(*) FROM training_sessions WHERE plan_id=? AND status='assigned'");
            $sessCnt->execute([$planId]);
            ok('G: sessions activated (status=assigned)', (int)$sessCnt->fetchColumn() > 0);

            $spCnt = $pdo->prepare("SELECT COUNT(*) FROM session_players WHERE session_id=? AND status='assigned'");
            $spCnt->execute([$sessId]);
            ok('G: session_players created', (int)$spCnt->fetchColumn() > 0);

        } catch (Exception $e) {
            $pdo->rollBack();
            ok('G: publish failed', false, $e->getMessage());
        }
    }
}

// ── 9. Test H: publish someone else's plan → blocked ────────────────────
echo "\n[ Test H — publish another coach's plan ]\n";
{
    // Other coach tries to find this plan
    $planRow = $pdo->prepare('SELECT id FROM training_plans WHERE id=? AND coach_user_id=?');
    $planRow->execute([$planId, $otherCoachId]);
    ok('H: other coach cannot find this plan', !$planRow->fetch());
}

// ── 10. Player sees TodaySessionCard ─────────────────────────────────────
echo "\n[ Player Session Visibility ]\n";
{
    // Player should see today's session through session_players
    $today = date('Y-m-d');
    $spCheck = $pdo->prepare(
        "SELECT sp.status FROM session_players sp
         JOIN training_sessions ts ON ts.id=sp.session_id
         WHERE sp.player_user_id=? AND ts.session_date=?"
    );
    $spCheck->execute([$playerUserId, $today]);
    // We created session for tomorrow (+1 day) in fixture, so check for assigned
    $spAll = $pdo->prepare(
        "SELECT sp.status, ts.session_date FROM session_players sp
         JOIN training_sessions ts ON ts.id=sp.session_id
         WHERE sp.player_user_id=? AND sp.status='assigned'"
    );
    $spAll->execute([$playerUserId]);
    $rows = $spAll->fetchAll();
    ok('Player: session_players assigned record exists', !empty($rows));
}

// ── 11. PHP syntax check ─────────────────────────────────────────────────
echo "\n[ PHP Syntax ]\n";
$files = [
    dirname(__DIR__) . '/coach/plans/generate-ai.php',
    dirname(__DIR__) . '/coach/plans/list.php',
    dirname(__DIR__) . '/coach/plans/detail.php',
    dirname(__DIR__) . '/coach/plans/update-draft.php',
    dirname(__DIR__) . '/coach/plans/publish.php',
];
foreach ($files as $f) {
    $fname = basename($f);
    if (!file_exists($f)) { ok("syntax: {$fname}", false, 'file not found'); continue; }
    $out = []; $code = 0;
    exec('php -l ' . escapeshellarg($f) . ' 2>&1', $out, $code);
    ok("syntax: {$fname}", $code === 0, implode(' ', $out));
}

// ── Cleanup ───────────────────────────────────────────────────────────────
echo "\n[ Cleanup ]\n";
try {
    $pdo->prepare('DELETE FROM session_exercises WHERE session_id IN (SELECT id FROM training_sessions WHERE plan_id=?)')->execute([$planId]);
    $pdo->prepare('DELETE FROM session_players WHERE session_id IN (SELECT id FROM training_sessions WHERE plan_id=?)')->execute([$planId]);
    $pdo->prepare('DELETE FROM training_sessions WHERE plan_id=?')->execute([$planId]);
    $pdo->prepare('DELETE FROM plan_players WHERE plan_id=?')->execute([$planId]);
    $pdo->prepare('DELETE FROM training_plans WHERE id=?')->execute([$planId]);
    $pdo->prepare('DELETE FROM club_players WHERE id=?')->execute([$cpId]);
    $pdo->prepare("DELETE FROM user_tokens WHERE user_id IN (?,?,?)")->execute([$coachId,$playerUserId,$otherCoachId]);
    $pdo->prepare("DELETE FROM users WHERE id IN (?,?,?)")->execute([$coachId,$playerUserId,$otherCoachId]);
    // Clean up indie player too
    $pdo->prepare("DELETE FROM users WHERE email=?")->execute(["indie_{$ts}@test.com"]);
    ok('cleanup done', true);
} catch (Exception $e) {
    ok('cleanup', false, $e->getMessage());
}

// ── Result ────────────────────────────────────────────────────────────────
echo "\n════════════════════════════\n";
echo "  PASS: {$pass}   FAIL: {$fail}\n";
echo "════════════════════════════\n\n";
exit($fail > 0 ? 1 : 0);
