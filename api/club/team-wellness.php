<?php
require_once dirname(__DIR__) . '/db.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

function jsonOut(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function bearerToken(): string {
    $auth = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? $_SERVER['Authorization'] ?? '';
    if (!$auth && function_exists('apache_request_headers')) {
        $h = apache_request_headers();
        $auth = $h['Authorization'] ?? $h['authorization'] ?? '';
    }
    if (stripos($auth, 'Bearer ') === 0) return trim(substr($auth, 7));
    return trim($auth);
}

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ?'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);

// For MVP, we return team-level stats computed from all player_hooper_index and player_rpe
// Future: link to a club_id via coaches or teams table

// ─ Team Readiness % (avg readiness across all monitored players) ─────
// For now, compute avg hooper for users who submitted today
$stmt = $pdo->prepare(
    'SELECT AVG(hooper_score) as avg_hooper FROM player_hooper_index
     WHERE DATE(submitted_at) = DATE(NOW())'
);
$stmt->execute();
$result = $stmt->fetch();
$avgHooper = (float)($result['avg_hooper'] ?? 0);

$teamReadiness = 100;
if ($avgHooper > 0) {
    if ($avgHooper <= 10) {
        // Normal
    } elseif ($avgHooper <= 16) {
        $teamReadiness -= 20;
    } else {
        $teamReadiness -= 40;
    }
}
$teamReadiness = max(0, min(100, (int)$teamReadiness));

// ─ Injury Risk Count (players with 2+ risk flags in last 3 days) ───
$stmt = $pdo->prepare(
    'SELECT COUNT(DISTINCT user_id) as count FROM player_hooper_index
     WHERE hooper_score >= 17 AND submitted_at >= DATE_SUB(NOW(), INTERVAL 3 DAY)'
);
$stmt->execute();
$injuryRiskCount = (int)($stmt->fetch()['count'] ?? 0);

// ─ Average RPE (last session) ─────────────────────────────────────
$stmt = $pdo->prepare('SELECT AVG(rpe_score) as avg_rpe FROM player_rpe');
$stmt->execute();
$avgRpe = (float)($stmt->fetch()['avg_rpe'] ?? 0);

// ─ Weekly Load (sum of last 7 days across team) ────────────────────
$stmt = $pdo->prepare(
    'SELECT SUM(training_load) as total FROM player_rpe WHERE submitted_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)'
);
$stmt->execute();
$weeklyLoad = (int)($stmt->fetch()['total'] ?? 0);

// ─ Recovery Score (% of players with good hooper today) ────────────
$stmt = $pdo->prepare(
    'SELECT COUNT(DISTINCT user_id) as total FROM (
        SELECT DISTINCT user_id FROM player_hooper_index WHERE DATE(submitted_at) = DATE(NOW())
    ) t'
);
$stmt->execute();
$totalCheckedIn = (int)($stmt->fetch()['total'] ?? 0);

$stmt = $pdo->prepare(
    'SELECT COUNT(DISTINCT user_id) as recovered FROM (
        SELECT DISTINCT user_id FROM player_hooper_index
        WHERE DATE(submitted_at) = DATE(NOW()) AND hooper_score <= 10
    ) t'
);
$stmt->execute();
$recoveredCount = (int)($stmt->fetch()['recovered'] ?? 0);

$recoveryScore = $totalCheckedIn > 0 ? round(($recoveredCount / $totalCheckedIn) * 100) : 0;

// ─ Players Needing Attention ────────────────────────────────────────
$stmt = $pdo->prepare(
    'SELECT DISTINCT h.user_id FROM player_hooper_index h
     WHERE DATE(h.submitted_at) = DATE(NOW()) AND (
        h.hooper_score >= 17 OR
        h.fatigue >= 6 OR
        h.sleep_quality <= 2
     )
     LIMIT 10'
);
$stmt->execute();
$playersNeedingAttention = count($stmt->fetchAll());

// ─ Highest Fatigue Players (today) ──────────────────────────────────
$stmt = $pdo->prepare(
    'SELECT user_id, fatigue FROM player_hooper_index
     WHERE DATE(submitted_at) = DATE(NOW())
     ORDER BY fatigue DESC LIMIT 5'
);
$stmt->execute();
$highestFatigue = $stmt->fetchAll();

// ─ Response ───────────────────────────────────────────────────────
jsonOut([
    'team_readiness_score'       => $teamReadiness,
    'injury_risk_count'          => $injuryRiskCount,
    'average_rpe'                => round($avgRpe, 2),
    'weekly_load'                => $weeklyLoad,
    'recovery_score'             => (int)$recoveryScore,
    'players_needing_attention'  => $playersNeedingAttention,
    'total_checked_in'           => $totalCheckedIn,
    'highest_fatigue_players'    => $highestFatigue,
]);
