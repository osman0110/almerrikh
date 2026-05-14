<?php
require_once dirname(__DIR__, 2) . '/db.php';

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

// Latest body metric
$stmt = $pdo->prepare('SELECT * FROM player_body_metrics WHERE user_id = ? ORDER BY measured_at DESC LIMIT 1');
$stmt->execute([$userId]);
$bodyMetric = $stmt->fetch() ?: null;

// Today's hooper (same calendar day, UTC)
$stmt = $pdo->prepare(
    'SELECT * FROM player_hooper_index WHERE user_id = ? AND DATE(submitted_at) = DATE(NOW()) ORDER BY submitted_at DESC LIMIT 1'
);
$stmt->execute([$userId]);
$todayHooper = $stmt->fetch() ?: null;

// Last 3 days hooper for injury risk detection
$stmt = $pdo->prepare(
    'SELECT hooper_score, fatigue FROM player_hooper_index WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 3'
);
$stmt->execute([$userId]);
$recent3Hooper = $stmt->fetchAll();

// Last RPE
$stmt = $pdo->prepare('SELECT * FROM player_rpe WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 1');
$stmt->execute([$userId]);
$lastRpe = $stmt->fetch() ?: null;

// Weekly loads (last 7 days)
$stmt = $pdo->prepare(
    'SELECT DATE(submitted_at) as date, SUM(training_load) as daily_load FROM player_rpe
     WHERE user_id = ? AND submitted_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
     GROUP BY DATE(submitted_at) ORDER BY submitted_at ASC'
);
$stmt->execute([$userId]);
$weeklyLoads = [];
foreach ($stmt->fetchAll() as $row) {
    $weeklyLoads[] = (int)($row['daily_load'] ?? 0);
}
// Pad to 7 days
while (count($weeklyLoads) < 7) array_unshift($weeklyLoads, 0);
$weeklyLoads = array_slice($weeklyLoads, -7);

// ACWR: Acute (last 7 days) vs Chronic (last 28 days)
$stmt = $pdo->prepare(
    'SELECT SUM(training_load) as total FROM player_rpe WHERE user_id = ? AND submitted_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)'
);
$stmt->execute([$userId]);
$acuteTotal = (int)(($stmt->fetch()['total'] ?? 0));
$acuteLoad = $acuteTotal > 0 ? $acuteTotal / 7 : 0;

$stmt = $pdo->prepare(
    'SELECT SUM(training_load) as total FROM player_rpe WHERE user_id = ? AND submitted_at >= DATE_SUB(NOW(), INTERVAL 28 DAY)'
);
$stmt->execute([$userId]);
$chronicTotal = (int)(($stmt->fetch()['total'] ?? 0));
$chronicLoad = $chronicTotal > 0 ? $chronicTotal / 28 : 0;

$acwr = $chronicLoad > 0 ? round($acuteLoad / $chronicLoad, 2) : 0;

// ─ Readiness Score (0–100) ─────────────────────────────────────────────
$readiness = 100;

if ($todayHooper) {
    $h = (int)$todayHooper['hooper_score'];
    if ($h <= 10) {
        // Normal: +0
    } elseif ($h <= 16) {
        $readiness -= 20; // Moderate: -20
    } else {
        $readiness -= 40; // High risk: -40
    }
    if ((int)$todayHooper['fatigue'] >= 6) $readiness -= 15;
    if ((int)$todayHooper['sleep_quality'] <= 2) $readiness -= 15;
    if ((float)($todayHooper['sleep_hours'] ?? 0) < 6) $readiness -= 10;
}

if ($lastRpe && $lastRpe['training_load'] > 300) {
    $readiness -= 10;
}

if ($acwr > 1.5) {
    $readiness -= 20;
}

$readiness = max(0, min(100, $readiness));

// ─ Injury Risk Detection ────────────────────────────────────────────────
$injuryRiskCount = 0;
$alerts = [];

// Multi-day hooper elevation
if (count($recent3Hooper) >= 2) {
    $highHooperCount = 0;
    foreach ($recent3Hooper as $h) {
        if ($h['hooper_score'] >= 17) $highHooperCount++;
    }
    if ($highHooperCount >= 2) {
        $injuryRiskCount++;
        $alerts[] = 'Elevated Hooper Index over multiple days';
    }
}

// High fatigue sustained
if ($todayHooper && (int)$todayHooper['fatigue'] >= 6 && $lastRpe && $lastRpe['rpe_score'] >= 7) {
    $injuryRiskCount++;
    $alerts[] = 'High fatigue with elevated training load';
}

// ACWR danger zone
if ($acwr > 1.5) {
    $injuryRiskCount++;
    $alerts[] = 'Acute-to-chronic load ratio exceeds safe threshold';
}

// Poor sleep pattern
if ($todayHooper && (int)$todayHooper['sleep_quality'] <= 2) {
    $injuryRiskCount++;
    $alerts[] = 'Poor sleep quality detected';
}

// ─ AI Insights Feed ────────────────────────────────────────────────────
$insights = [];

if ($readiness >= 80) {
    $insights[] = 'Player recovered well today';
}

if ($lastRpe && $lastRpe['duration_minutes'] > 60) {
    $insights[] = 'High-volume session completed';
}

if ($todayHooper && (int)$todayHooper['hooper_score'] <= 10) {
    $insights[] = 'Excellent wellness status — ready for intense training';
}

if ($acwr > 1.3 && $acwr <= 1.5) {
    $insights[] = 'Monitor load carefully — approaching caution zone';
}

if ($readiness < 40) {
    $insights[] = 'Recommend recovery session or reduced intensity';
}

// ─ Smart Recommendations ────────────────────────────────────────────────
$recommendations = [];

if ($todayHooper && ((int)$todayHooper['fatigue'] >= 6 || (int)$todayHooper['muscle_soreness'] >= 6)) {
    $recommendations[] = 'Recovery session';
    $recommendations[] = 'Mobility work';
    $recommendations[] = 'Light stretching';
}

if ($readiness < 50) {
    $recommendations[] = 'Reduced intensity';
    $recommendations[] = 'Extra recovery time';
}

if ($todayHooper && (int)$todayHooper['sleep_hours'] < 6) {
    $recommendations[] = 'Prioritize sleep';
}

// ─ Wellness Status ──────────────────────────────────────────────────────
$wellnessStatus = 'good';
if ($injuryRiskCount >= 2 || $readiness < 40) {
    $wellnessStatus = 'high_risk';
} elseif ($readiness < 60 || $injuryRiskCount >= 1) {
    $wellnessStatus = 'moderate';
}

// ─ Response ───────────────────────────────────────────────────────────
jsonOut([
    'body_metric'      => $bodyMetric,
    'today_hooper'     => $todayHooper,
    'last_rpe'         => $lastRpe,
    'weekly_loads'     => $weeklyLoads,
    'readiness_score'  => (int)$readiness,
    'acwr'             => $acwr,
    'acute_load'       => round($acuteLoad, 2),
    'chronic_load'     => round($chronicLoad, 2),
    'wellness_status'  => $wellnessStatus,
    'injury_risk_count' => $injuryRiskCount,
    'alerts'           => $alerts,
    'insights'         => $insights,
    'recommendations'  => $recommendations,
]);
