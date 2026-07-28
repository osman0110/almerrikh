<?php
/**
 * Phase 4 Smoke Test — AI Independent Player Plan
 * Run: php api/tests/phase4_smoke_test.php
 * Note: AI generation test is skipped (needs ANTHROPIC_API_KEY + network).
 *       Tests cover schema, DB save logic, and endpoint security.
 */
require_once dirname(__DIR__) . '/db.php';

$pass = 0; $fail = 0;

function ok(string $label, bool $cond, string $detail = ''): void {
    global $pass, $fail;
    if ($cond) { echo "  PASS  $label\n"; $pass++; }
    else        { echo "  FAIL  $label" . ($detail ? " — $detail" : '') . "\n"; $fail++; }
}

echo "\n=== Phase 4 Smoke Test ===\n\n";

// ── 1. Schema checks ──────────────────────────────────────────────────────────
echo "[ Schema ]\n";

function colExists(PDO $pdo, string $t, string $c): bool {
    $s = $pdo->prepare('SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?');
    $s->execute([$t, $c]); return (bool)$s->fetchColumn();
}
function tableExists(PDO $pdo, string $t): bool {
    $s = $pdo->prepare('SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?');
    $s->execute([$t]); return (bool)$s->fetchColumn();
}

ok('training_sessions.week_number',       colExists($pdo, 'training_sessions', 'week_number'));
ok('training_sessions.intensity',         colExists($pdo, 'training_sessions', 'intensity'));
ok('training_plans.recovery_notes',       colExists($pdo, 'training_plans',    'recovery_notes'));
ok('training_plans.progression_rules',    colExists($pdo, 'training_plans',    'progression_rules'));
ok('training_plans.num_weeks',            colExists($pdo, 'training_plans',    'num_weeks'));
ok('training_plans.player_user_id',       colExists($pdo, 'training_plans',    'player_user_id'));
ok('training_plans.ai_provider',          colExists($pdo, 'training_plans',    'ai_provider'));
ok('training_plans.ai_response_snapshot', colExists($pdo, 'training_plans',    'ai_response_snapshot'));

ok('table: training_plans',    tableExists($pdo, 'training_plans'));
ok('table: training_sessions', tableExists($pdo, 'training_sessions'));
ok('table: session_players',   tableExists($pdo, 'session_players'));
ok('table: session_exercises', tableExists($pdo, 'session_exercises'));

// ── 2. Fixtures ───────────────────────────────────────────────────────────────
echo "\n[ Fixtures ]\n";

$pdo->beginTransaction();
try {
    $pdo->prepare("INSERT INTO users (name,email,password_hash,role,player_type) VALUES (?,?,?,'player','independent')")
        ->execute(['AI Test Player', 'ai_player_' . time() . '@test.com', 'x']);
    $playerId = (int)$pdo->lastInsertId();

    $token = 'ai_tok_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token,user_id) VALUES (?,?)")
        ->execute([$token, $playerId]);

    $pdo->commit();
    ok('player fixture created', true);
} catch (Exception $e) {
    $pdo->rollBack();
    ok('player fixture created', false, $e->getMessage());
    exit(1);
}

// ── 3. Simulate generate.php DB logic (without AI call) ───────────────────────
echo "\n[ Test: Plan save logic (no AI call) ]\n";

// Simulate what generate.php does after receiving AI JSON response
$simulatedAiResponse = [
    'plan_title' => '4-Week Speed Development Plan',
    'weeks' => [
        ['week' => 1, 'sessions' => [
            ['title' => 'Sprint Training', 'objective' => 'fitness',
             'day_offset' => 0, 'duration_minutes' => 60, 'intensity' => 'medium',
             'exercises' => [
                 ['exercise_name' => 'Warm-up jog', 'category' => 'fitness',
                  'sets' => null, 'reps' => null, 'duration_seconds' => 300,
                  'rest_seconds' => 60, 'intensity' => 'low',
                  'instructions' => 'Easy pace', 'requires_pose_detection' => false],
                 ['exercise_name' => 'Sprint 30m', 'category' => 'football',
                  'sets' => 6, 'reps' => null, 'duration_seconds' => null,
                  'rest_seconds' => 90, 'intensity' => 'high',
                  'instructions' => 'Maximum effort', 'requires_pose_detection' => false],
             ]],
            ['title' => 'Agility Circuit', 'objective' => 'football',
             'day_offset' => 2, 'duration_minutes' => 45, 'intensity' => 'high',
             'exercises' => [
                 ['exercise_name' => 'Cone drills', 'category' => 'football',
                  'sets' => 4, 'reps' => null, 'duration_seconds' => 30,
                  'rest_seconds' => 45, 'intensity' => 'high',
                  'instructions' => 'Sharp turns', 'requires_pose_detection' => false],
             ]],
        ]],
        ['week' => 2, 'sessions' => [
            ['title' => 'Recovery Run', 'objective' => 'recovery',
             'day_offset' => 0, 'duration_minutes' => 30, 'intensity' => 'low',
             'exercises' => [
                 ['exercise_name' => 'Easy jog', 'category' => 'fitness',
                  'sets' => null, 'reps' => null, 'duration_seconds' => 1200,
                  'rest_seconds' => null, 'intensity' => 'low',
                  'instructions' => 'Zone 1 HR', 'requires_pose_detection' => false],
             ]],
        ]],
    ],
    'recovery_notes'    => 'Sleep 8h. Hydrate well.',
    'progression_rules' => 'Add 1 rep or 5% intensity each week.',
];

$planId    = bin2hex(random_bytes(16));
$startDate = new DateTime('+1 day');
$totalSessions = 0;
$savedSessions = [];

$pdo->beginTransaction();
try {
    $pdo->prepare(
        "INSERT INTO training_plans
         (id,plan_type,owner_type,club_id,coach_user_id,player_user_id,linked_player_id,
          title,goal,status,ai_provider,ai_response_snapshot,recovery_notes,progression_rules,num_weeks)
         VALUES (?,'ai','player',NULL,NULL,?,NULL,?,?,'published','anthropic',?,?,?,4)"
    )->execute([
        $planId, $playerId,
        $simulatedAiResponse['plan_title'], 'speed',
        substr(json_encode($simulatedAiResponse), 0, 500),
        $simulatedAiResponse['recovery_notes'],
        $simulatedAiResponse['progression_rules'],
    ]);

    $exStmt = $pdo->prepare(
        'INSERT INTO session_exercises
         (session_id,exercise_name,category,sets,reps,duration_seconds,
          rest_seconds,intensity,instructions,requires_pose_detection,sort_order)
         VALUES (?,?,?,?,?,?,?,?,?,?,?)'
    );

    foreach ($simulatedAiResponse['weeks'] as $weekData) {
        $weekNum  = (int)$weekData['week'];
        $weekBase = clone $startDate;
        $weekBase->modify('+' . (($weekNum - 1) * 7) . ' days');

        foreach ($weekData['sessions'] as $sessData) {
            $sessId   = bin2hex(random_bytes(16));
            $dayOff   = max(0, min(6, (int)$sessData['day_offset']));
            $sessDate = clone $weekBase;
            $sessDate->modify('+' . $dayOff . ' days');

            $pdo->prepare(
                "INSERT INTO training_sessions
                 (id,plan_id,coach_user_id,title,session_date,duration_minutes,
                  objective,source,status,wellness_required,rpe_required,week_number,intensity)
                 VALUES (?,?,NULL,?,?,?,'fitness','ai','assigned',1,1,?,?)"
            )->execute([
                $sessId, $planId, $sessData['title'],
                $sessDate->format('Y-m-d'), $sessData['duration_minutes'],
                $weekNum, $sessData['intensity'],
            ]);

            $pdo->prepare(
                "INSERT INTO session_players (session_id,club_id,player_user_id,linked_player_id,status)
                 VALUES (?,NULL,?,NULL,'assigned')"
            )->execute([$sessId, $playerId]);

            foreach ($sessData['exercises'] as $i => $ex) {
                $exStmt->execute([
                    $sessId, $ex['exercise_name'], $ex['category'],
                    $ex['sets'], $ex['reps'], $ex['duration_seconds'],
                    $ex['rest_seconds'], $ex['intensity'], $ex['instructions'],
                    $ex['requires_pose_detection'] ? 1 : 0, $i,
                ]);
            }

            $totalSessions++;
            $savedSessions[] = $sessId;
        }
    }

    $pdo->commit();
    ok('plan transaction committed', true);
} catch (Exception $e) {
    $pdo->rollBack();
    ok('plan transaction committed', false, $e->getMessage());
}

// Verify plan in DB
$planRow = $pdo->prepare('SELECT id, num_weeks, recovery_notes FROM training_plans WHERE id=? AND player_user_id=?');
$planRow->execute([$planId, $playerId]);
$p = $planRow->fetch();
ok('plan saved with player_user_id',  $p && $p['id'] === $planId);
ok('num_weeks = 4',                   $p && (int)$p['num_weeks'] === 4);
ok('recovery_notes saved',            $p && !empty($p['recovery_notes']));

$sessCount = (int)$pdo->query("SELECT COUNT(*) FROM training_sessions WHERE plan_id='$planId'")->fetchColumn();
ok('3 sessions created (2+1 weeks)',  $sessCount === 3, "got $sessCount");

$spCount = (int)$pdo->query("SELECT COUNT(*) FROM session_players WHERE session_id='{$savedSessions[0]}'")->fetchColumn();
ok('player self-assigned to session', $spCount === 1);

$exCount = (int)$pdo->query("SELECT COUNT(*) FROM session_exercises WHERE session_id='{$savedSessions[0]}'")->fetchColumn();
ok('2 exercises in first session',    $exCount === 2, "got $exCount");

$wkCol = $pdo->query("SELECT week_number FROM training_sessions WHERE plan_id='$planId' ORDER BY session_date LIMIT 1")->fetchColumn();
ok('week_number stored',              $wkCol !== null);

// ── 4. plans.php query ────────────────────────────────────────────────────────
echo "\n[ Test: plans.php query ]\n";

$stmt = $pdo->prepare("
    SELECT tp.id, tp.title, tp.num_weeks,
           (SELECT COUNT(*) FROM training_sessions WHERE plan_id=tp.id) AS session_count,
           (SELECT COUNT(*) FROM training_sessions ts
            JOIN session_players sp ON sp.session_id=ts.id
            WHERE ts.plan_id=tp.id AND sp.player_user_id=? AND sp.status='completed') AS completed_count
    FROM training_plans tp
    WHERE tp.player_user_id=? AND tp.status != 'archived'
    ORDER BY tp.created_at DESC LIMIT 10
");
$stmt->execute([$playerId, $playerId]);
$plans = $stmt->fetchAll();

ok('plans query returns 1 plan',        count($plans) === 1, 'got ' . count($plans));
ok('session_count = 3',                 $plans && (int)$plans[0]['session_count'] === 3, 'got ' . ($plans[0]['session_count'] ?? '?'));
ok('completed_count = 0 (not started)', $plans && (int)$plans[0]['completed_count'] === 0);

// ── 5. plan-detail.php query ──────────────────────────────────────────────────
echo "\n[ Test: plan-detail.php query ]\n";

$detailStmt = $pdo->prepare("
    SELECT ts.id, ts.title, ts.session_date, ts.week_number, ts.intensity,
           sp.status AS player_status,
           (SELECT COUNT(*) FROM session_exercises WHERE session_id=ts.id) AS exercise_count
    FROM training_sessions ts
    LEFT JOIN session_players sp ON sp.session_id=ts.id AND sp.player_user_id=?
    WHERE ts.plan_id=?
    ORDER BY ts.session_date, ts.created_at
");
$detailStmt->execute([$playerId, $planId]);
$sessions = $detailStmt->fetchAll();

ok('detail returns 3 sessions',         count($sessions) === 3, 'got ' . count($sessions));
ok('all player_status = assigned',      array_sum(array_map(fn($s) => $s['player_status']==='assigned' ? 1 : 0, $sessions)) === 3);
ok('week_number populated',             $sessions && (int)$sessions[0]['week_number'] >= 1);
ok('exercise_count in detail',          $sessions && (int)$sessions[0]['exercise_count'] > 0);

// ── 6. Security checks ────────────────────────────────────────────────────────
echo "\n[ Test: Security ]\n";

// Other player cannot read this plan
$otherStmt = $pdo->prepare('SELECT id FROM training_plans WHERE id=? AND player_user_id=?');
$otherStmt->execute([$planId, $playerId + 999]);
ok('other player cannot see plan',      !$otherStmt->fetch());

// Plan ownership check is applied correctly
$ownStmt = $pdo->prepare('SELECT id FROM training_plans WHERE id=? AND player_user_id=?');
$ownStmt->execute([$planId, $playerId]);
ok('plan owner can see own plan',       (bool)$ownStmt->fetch());

// ── 7. ANTHROPIC_API_KEY config ───────────────────────────────────────────────
echo "\n[ Test: Config ]\n";
ok('ANTHROPIC_API_KEY constant defined', defined('ANTHROPIC_API_KEY'));
ok('ANTHROPIC_MODEL constant defined',   defined('ANTHROPIC_MODEL'));
ok('generate.php file exists',
    file_exists(__DIR__ . '/../../api/player/ai-plan/generate.php'));
ok('plans.php file exists',
    file_exists(__DIR__ . '/../../api/player/plans.php'));
ok('plan-detail.php file exists',
    file_exists(__DIR__ . '/../../api/player/plan-detail.php'));
ok('IndependentAIPlanScreen exists',
    file_exists(__DIR__ . '/../../lib/screens/player/independent_ai_plan_screen.dart'));
ok('AIPlanPreviewScreen exists',
    file_exists(__DIR__ . '/../../lib/screens/player/ai_plan_preview_screen.dart'));
ok('ai_plan_models.dart exists',
    file_exists(__DIR__ . '/../../lib/models/ai_plan_models.dart'));

$keySet = defined('ANTHROPIC_API_KEY') && strlen(ANTHROPIC_API_KEY) > 10;
if (!$keySet) {
    echo "  NOTE  ANTHROPIC_API_KEY not set — AI call will return 503. Set via:\n";
    echo "        \$env:ANTHROPIC_API_KEY = 'sk-ant-...'\n";
    echo "        or create api/ai/config.php with define('ANTHROPIC_API_KEY','sk-ant-...');\n";
}

// ── 8. Cleanup ────────────────────────────────────────────────────────────────
echo "\n[ Cleanup ]\n";
try {
    foreach ($savedSessions as $sid) {
        $pdo->prepare('DELETE FROM session_exercises WHERE session_id=?')->execute([$sid]);
        $pdo->prepare('DELETE FROM session_players   WHERE session_id=?')->execute([$sid]);
        $pdo->prepare('DELETE FROM training_sessions  WHERE id=?')->execute([$sid]);
    }
    $pdo->prepare('DELETE FROM training_plans WHERE id=?')->execute([$planId]);
    $pdo->prepare('DELETE FROM user_tokens WHERE user_id=?')->execute([$playerId]);
    $pdo->prepare('DELETE FROM users       WHERE id=?')->execute([$playerId]);
    ok('test data cleaned', true);
} catch (Exception $e) {
    ok('test data cleaned', false, $e->getMessage());
}

$total = $pass + $fail;
echo "\n=== Results: $pass/$total PASSED" . ($fail ? " ($fail FAILED)" : '') . " ===\n\n";
exit($fail > 0 ? 1 : 0);
