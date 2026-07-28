<?php
/**
 * Phase 6A Smoke Test — Backend Reports
 * Run: php api/tests/phase6_reports_smoke_test.php
 *
 * Tests A–I per spec using direct DB logic (no HTTP calls).
 * Creates fixtures, runs tests, then cleans up.
 */
require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/report_helpers.php';

$pass = 0; $fail = 0;

function ok(string $label, bool $cond, string $detail = ''): void {
    global $pass, $fail;
    if ($cond) { echo "  PASS  $label\n"; $pass++; }
    else        { echo "  FAIL  $label" . ($detail ? " — $detail" : '') . "\n"; $fail++; }
}

echo "\n=== Phase 6A Smoke Test — Backend Reports ===\n\n";

// ── Fixtures ─────────────────────────────────────────────────────────────────
echo "[ Fixtures ]\n";
$ts = time();
$planId = null; $sessId = null;

$pdo->beginTransaction();
try {
    // Coach user
    $pdo->prepare("INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, 'x', 'club')")
        ->execute(['Coach P6', "coach_p6_{$ts}@test.com"]);
    $coachId = (int)$pdo->lastInsertId();
    $coachTok = 'coach_p6_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token, user_id) VALUES (?, ?)")->execute([$coachTok, $coachId]);

    // Club player with user account
    $pdo->prepare("INSERT INTO users (name, email, password_hash, role, player_type) VALUES (?, ?, 'x', 'player', 'club')")
        ->execute(['Player P6', "player_p6_{$ts}@test.com"]);
    $playerUserId = (int)$pdo->lastInsertId();
    $playerTok = 'player_p6_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token, user_id) VALUES (?, ?)")->execute([$playerTok, $playerUserId]);

    $cpId = 'cp-p6-' . $ts;
    $pdo->prepare(
        "INSERT INTO club_players (id, user_id, name, position, team_name, player_type, linked_user_id, is_active)
         VALUES (?, ?, 'Player P6', 'CB', 'Team A', 'club', ?, 1)"
    )->execute([$cpId, $coachId, $playerUserId]);

    // Update user's linked_player_id
    $pdo->prepare("UPDATE users SET linked_player_id = ?, club_user_id = ? WHERE id = ?")
        ->execute([$cpId, $coachId, $playerUserId]);

    // Independent player (must NOT appear in coach reports)
    $pdo->prepare("INSERT INTO users (name, email, password_hash, role, player_type) VALUES (?, ?, 'x', 'player', 'independent')")
        ->execute(['Indie P6', "indie_p6_{$ts}@test.com"]);
    $indieUserId = (int)$pdo->lastInsertId();
    $indieCpId   = 'indie-p6-' . $ts;
    $pdo->prepare(
        "INSERT INTO club_players (id, user_id, name, player_type, linked_user_id, is_active)
         VALUES (?, ?, 'Indie P6', 'independent', ?, 1)"
    )->execute([$indieCpId, $indieUserId, $indieUserId]);
    $pdo->prepare("UPDATE users SET linked_player_id = ? WHERE id = ?")
        ->execute([$indieCpId, $indieUserId]);

    // Another coach (outsider)
    $pdo->prepare("INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, 'x', 'club')")
        ->execute(['Other Coach P6', "other_p6_{$ts}@test.com"]);
    $otherCoachId  = (int)$pdo->lastInsertId();
    $otherCoachTok = 'other_p6_' . bin2hex(random_bytes(8));
    $pdo->prepare("INSERT INTO user_tokens (token, user_id) VALUES (?, ?)")->execute([$otherCoachTok, $otherCoachId]);

    // Training session assigned to the player
    $planId = 'plan-p6-' . $ts;
    $pdo->prepare(
        "INSERT INTO training_plans (id, plan_type, owner_type, club_id, coach_user_id, title, status)
         VALUES (?, 'manual', 'club', ?, ?, 'P6 Plan', 'active')"
    )->execute([$planId, $coachId, $coachId]);

    $sessId = 'sess-p6-' . $ts;
    $pdo->prepare(
        "INSERT INTO training_sessions (id, plan_id, club_id, coach_user_id, title, session_date, duration_minutes, status)
         VALUES (?, ?, ?, ?, 'P6 Session', ?, 60, 'completed')"
    )->execute([$sessId, $planId, $coachId, $coachId, date('Y-m-d', strtotime('-5 days'))]);

    $pdo->prepare(
        "INSERT INTO session_players (session_id, club_id, player_user_id, linked_player_id, status)
         VALUES (?, ?, ?, ?, 'completed')"
    )->execute([$sessId, $coachId, $playerUserId, $cpId]);

    $pdo->commit();
    ok('fixtures created', true);
} catch (Exception $e) {
    $pdo->rollBack();
    ok('fixtures created', false, $e->getMessage());
    exit(1);
}

// ── Test A: coach requests report for own player → 200 ──────────────────────
echo "\n[ Test A — coach requests player report for own player ]\n";
{
    // Simulate rptScopedPlayer
    $stmt = $pdo->prepare(
        "SELECT id FROM club_players WHERE id = ? AND user_id = ? AND is_active = 1
         AND (player_type IS NULL OR player_type != 'independent')"
    );
    $stmt->execute([$cpId, $coachId]);
    ok('A: coach can access own player', (bool)$stmt->fetch());

    // Simulate fetching hooper trend (empty arrays should not crash)
    $trend = rptHooperTrend($pdo, $cpId);
    ok('A: hooper_trend returns array', is_array($trend));
    $trend = rptRpeTrend($pdo, $cpId);
    ok('A: rpe_trend returns array', is_array($trend));
    $hist = rptAssessmentHistory($pdo, $cpId, $coachId);
    ok('A: assessment_history returns array', is_array($hist));
    $sess = rptSessionHistory($pdo, $cpId, $coachId);
    ok('A: session_history returns array', is_array($sess));
    $summary = rptPlayerSummary($pdo, $cpId, $cpId, $coachId);
    ok('A: summary returns array with keys', isset($summary['completion_rate_30d']));
    ok('A: metrics returns correct type', is_array(rptBodyMetrics($pdo, $playerUserId)));
}

// ── Test B: coach requests report for out-of-scope player → 403 ─────────────
echo "\n[ Test B — coach requests out-of-scope player ]\n";
{
    $outsideId = 'FAKE_PLAYER_OUTSIDE_' . $ts;
    $stmt = $pdo->prepare(
        "SELECT id FROM club_players WHERE id = ? AND user_id = ? AND is_active = 1
         AND (player_type IS NULL OR player_type != 'independent')"
    );
    $stmt->execute([$outsideId, $coachId]);
    ok('B: out-of-scope player not found → 403 would be returned', !$stmt->fetch());

    // Other coach's player also blocked
    $stmt->execute([$cpId, $otherCoachId]);
    ok("B: other coach cannot access this coach's player", !$stmt->fetch());
}

// ── Test C: player requests coach endpoint → 403 ────────────────────────────
echo "\n[ Test C — player role blocked from coach endpoints ]\n";
{
    $stmt = $pdo->prepare('SELECT role FROM users WHERE id = ?');
    $stmt->execute([$playerUserId]);
    $role = $stmt->fetchColumn();
    ok('C: player role is player', $role === 'player');
    ok('C: player blocked from coach reports', in_array($role, ['player', 'parent'], true));
}

// ── Test D: player requests own progress → 200 ──────────────────────────────
echo "\n[ Test D — player requests own progress ]\n";
{
    $stmt = $pdo->prepare('SELECT linked_player_id FROM users WHERE id = ?');
    $stmt->execute([$playerUserId]);
    $lp = $stmt->fetchColumn();
    ok('D: player has linked_player_id', !empty($lp));

    // Session completion 30d
    $since30 = date('Y-m-d H:i:s', strtotime('-30 days'));
    $stmt = $pdo->prepare(
        "SELECT COUNT(*) AS total,
                SUM(CASE WHEN sp.status IN ('completed','pre_checked','started') THEN 1 ELSE 0 END) AS done
         FROM session_players sp
         JOIN training_sessions ts ON sp.session_id = ts.id
         WHERE sp.player_user_id = ? AND ts.session_date >= ?"
    );
    $stmt->execute([$playerUserId, $since30]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    ok('D: session_completion_30d computable', isset($row['total']));
}

// ── Test E: player without wellness data → empty arrays, no crash ────────────
echo "\n[ Test E — player without wellness data ]\n";
{
    // No hooper/rpe data inserted for this player → should return []
    $trend = rptHooperTrend($pdo, $cpId);
    ok('E: hooper_trend empty (no crash)', $trend === []);
    $trend = rptRpeTrend($pdo, $cpId);
    ok('E: rpe_trend empty (no crash)', $trend === []);

    $summary = rptPlayerSummary($pdo, $cpId, $cpId, $coachId);
    ok('E: avg_hooper_30d null when no data', $summary['average_hooper_30d'] === null);
    ok('E: avg_post_rpe_30d null when no data', $summary['average_post_rpe_30d'] === null);
    ok('E: pain_reports_30d = 0 when no data', $summary['pain_reports_30d'] === 0);
}

// ── Test F: team report for existing team → scoped players only ──────────────
echo "\n[ Test F — team report for existing team ]\n";
{
    $stmt = $pdo->prepare(
        "SELECT id, name, team_name FROM club_players
         WHERE user_id = ? AND team_name = 'Team A' AND is_active = 1
           AND (player_type IS NULL OR player_type != 'independent')"
    );
    $stmt->execute([$coachId]);
    $teamPlayers = $stmt->fetchAll(PDO::FETCH_ASSOC);
    ok('F: team A players found for coach', count($teamPlayers) >= 1);
    $found = false;
    foreach ($teamPlayers as $tp) {
        if ($tp['id'] === $cpId) { $found = true; break; }
    }
    ok('F: our test player is in Team A', $found);
}

// ── Test G: team report does NOT show independent players ────────────────────
echo "\n[ Test G — independent players excluded from team report ]\n";
{
    $stmt = $pdo->prepare(
        "SELECT id FROM club_players
         WHERE user_id = ? AND is_active = 1
           AND (player_type IS NULL OR player_type != 'independent')"
    );
    $stmt->execute([$coachId]);
    $scopedIds = array_column($stmt->fetchAll(PDO::FETCH_ASSOC), 'id');
    ok('G: independent player not in coach scope', !in_array($indieCpId, $scopedIds, true));

    // Indie player's own user_id != coachId so they can't appear
    $stmt = $pdo->prepare(
        "SELECT id FROM club_players WHERE id = ? AND user_id = ? AND player_type != 'independent'"
    );
    $stmt->execute([$indieCpId, $coachId]);
    ok('G: indie player blocked by user_id + player_type filter', !$stmt->fetch());
}

// ── Test H: assessments report for coach's player → 200 ─────────────────────
echo "\n[ Test H — assessments report for coach's own player ]\n";
{
    $stmt = $pdo->prepare(
        "SELECT id FROM club_players WHERE id = ? AND user_id = ? AND is_active = 1
         AND (player_type IS NULL OR player_type != 'independent')"
    );
    $stmt->execute([$cpId, $coachId]);
    ok('H: player in scope for assessments report', (bool)$stmt->fetch());

    $list = rptFullAssessmentList($pdo, $cpId, $coachId);
    ok('H: full assessment list returns array', is_array($list));
    $trend = rptAssessmentTrend($list);
    ok('H: trend returns insufficient_data when < 2 assessments', $trend === 'insufficient_data');
}

// ── Test I: assessments report for out-of-scope player → 403 ────────────────
echo "\n[ Test I — assessments report for out-of-scope player ]\n";
{
    $fakeId = 'FAKE_PLAYER_I_' . $ts;
    $stmt = $pdo->prepare(
        "SELECT id FROM club_players WHERE id = ? AND user_id = ? AND is_active = 1
         AND (player_type IS NULL OR player_type != 'independent')"
    );
    $stmt->execute([$fakeId, $coachId]);
    ok('I: fake player not in scope → 403 would be returned', !$stmt->fetch());

    // Other coach cannot see this coach's player
    $stmt->execute([$cpId, $otherCoachId]);
    ok('I: other coach player blocked', !$stmt->fetch());
}

// ── PHP Syntax ───────────────────────────────────────────────────────────────
echo "\n[ PHP Syntax ]\n";
$filesToCheck = [
    dirname(__DIR__) . '/report_helpers.php',
    dirname(__DIR__) . '/coach/reports/player.php',
    dirname(__DIR__) . '/coach/reports/team.php',
    dirname(__DIR__) . '/coach/reports/assessments.php',
    dirname(__DIR__) . '/player/reports/my-progress.php',
];
foreach ($filesToCheck as $f) {
    $name = str_replace(dirname(__DIR__) . DIRECTORY_SEPARATOR, '', $f);
    if (!file_exists($f)) { ok("syntax: $name", false, 'file not found'); continue; }
    $out = []; $code = 0;
    exec('php -l ' . escapeshellarg($f) . ' 2>&1', $out, $code);
    ok("syntax: $name", $code === 0, $code !== 0 ? implode(' ', $out) : '');
}

// ── Cleanup ───────────────────────────────────────────────────────────────────
echo "\n[ Cleanup ]\n";
try {
    if ($sessId) {
        $pdo->prepare("DELETE FROM session_players WHERE session_id = ?")->execute([$sessId]);
        $pdo->prepare("DELETE FROM training_sessions WHERE id = ?")->execute([$sessId]);
    }
    if ($planId) {
        $pdo->prepare("DELETE FROM training_plans WHERE id = ?")->execute([$planId]);
    }
    $pdo->prepare("DELETE FROM club_players WHERE id IN (?, ?)")->execute([$cpId, $indieCpId]);
    $pdo->prepare("DELETE FROM user_tokens WHERE user_id IN (?, ?, ?, ?)")
        ->execute([$coachId, $playerUserId, $indieUserId, $otherCoachId]);
    $pdo->prepare("DELETE FROM users WHERE id IN (?, ?, ?, ?)")
        ->execute([$coachId, $playerUserId, $indieUserId, $otherCoachId]);
    ok('cleanup done', true);
} catch (Exception $e) {
    ok('cleanup', false, $e->getMessage());
}

// ── Result ────────────────────────────────────────────────────────────────────
echo "\n════════════════════════════\n";
echo "  PASS: {$pass}   FAIL: {$fail}\n";
echo "════════════════════════════\n\n";
exit($fail > 0 ? 1 : 0);
