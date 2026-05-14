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
$userId = $user['id'];
$period = (int)($_GET['period'] ?? 7);
if (!in_array($period, [7, 14, 28])) $period = 7;

// ─ Fatigue Trend ────────────────────────────────────────────────────

$stmt = $pdo->prepare(
    'SELECT DATE(submitted_at) as date, AVG(fatigue) as avg_fatigue
     FROM player_hooper_index WHERE user_id = ? AND submitted_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
     GROUP BY DATE(submitted_at) ORDER BY submitted_at ASC'
);
$stmt->execute([$userId, $period]);
$fatigueTrend = [];
foreach ($stmt->fetchAll() as $row) {
    $fatigueTrend[] = ['date' => $row['date'], 'value' => (float)($row['avg_fatigue'] ?? 0)];
}

// ─ Recovery (inverse of Hooper) ─────────────────────────────────────

$stmt = $pdo->prepare(
    'SELECT DATE(submitted_at) as date, AVG(hooper_score) as avg_hooper
     FROM player_hooper_index WHERE user_id = ? AND submitted_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
     GROUP BY DATE(submitted_at) ORDER BY submitted_at ASC'
);
$stmt->execute([$userId, $period]);
$recoveryTrend = [];
foreach ($stmt->fetchAll() as $row) {
    // Recovery is 28 - hooper (lower hooper = better recovery)
    $recovery = 28 - (int)($row['avg_hooper'] ?? 0);
    $recoveryTrend[] = ['date' => $row['date'], 'value' => max(0, $recovery)];
}

// ─ Training Load Trend ──────────────────────────────────────────────

$stmt = $pdo->prepare(
    'SELECT DATE(submitted_at) as date, SUM(training_load) as daily_load
     FROM player_rpe WHERE user_id = ? AND submitted_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
     GROUP BY DATE(submitted_at) ORDER BY submitted_at ASC'
);
$stmt->execute([$userId, $period]);
$loadTrend = [];
foreach ($stmt->fetchAll() as $row) {
    $loadTrend[] = ['date' => $row['date'], 'value' => (int)($row['daily_load'] ?? 0)];
}

// ─ Sleep Quality Trend ──────────────────────────────────────────────

$stmt = $pdo->prepare(
    'SELECT DATE(submitted_at) as date, AVG(sleep_quality) as avg_sleep, AVG(sleep_hours) as avg_hours
     FROM player_hooper_index WHERE user_id = ? AND submitted_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
     GROUP BY DATE(submitted_at) ORDER BY submitted_at ASC'
);
$stmt->execute([$userId, $period]);
$sleepTrend = [];
foreach ($stmt->fetchAll() as $row) {
    $sleepTrend[] = [
        'date' => $row['date'],
        'quality' => (float)($row['avg_sleep'] ?? 0),
        'hours' => (float)($row['avg_hours'] ?? 0),
    ];
}

// ─ Averages ─────────────────────────────────────────────────────────

$avgFatigue = 0;
$avgRecovery = 0;
$avgLoad = 0;
$avgSleep = 0;

if (!empty($fatigueTrend)) {
    $avgFatigue = array_sum(array_column($fatigueTrend, 'value')) / count($fatigueTrend);
}
if (!empty($recoveryTrend)) {
    $avgRecovery = array_sum(array_column($recoveryTrend, 'value')) / count($recoveryTrend);
}
if (!empty($loadTrend)) {
    $avgLoad = array_sum(array_column($loadTrend, 'value')) / count($loadTrend);
}
if (!empty($sleepTrend)) {
    $avgSleep = array_sum(array_column($sleepTrend, 'quality')) / count($sleepTrend);
}

jsonOut([
    'period_days'    => $period,
    'fatigue_trend'  => $fatigueTrend,
    'recovery_trend' => $recoveryTrend,
    'load_trend'     => $loadTrend,
    'sleep_trend'    => $sleepTrend,
    'averages'       => [
        'fatigue'  => round($avgFatigue, 2),
        'recovery' => round($avgRecovery, 2),
        'load'     => round($avgLoad, 2),
        'sleep'    => round($avgSleep, 2),
    ],
]);
