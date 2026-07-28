<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/wellness_baseline.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/AcwrCalculator.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/BodyCompositionRepository.php';
require_once dirname(__DIR__) . '/training-load/TrainingLoadCalculator.php';

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
        'SELECT u.id, u.role, u.linked_player_id FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);
$userId = $user['id'];
$linkedPlayerId = $user['linked_player_id'] ?? null;
$localToday = FitnessConfig::today();
$todayStartUtc = (new DateTimeImmutable($localToday . ' 00:00:00', FitnessConfig::timezone()))
    ->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');
$todayEndUtc = (new DateTimeImmutable($localToday . ' 23:59:59', FitnessConfig::timezone()))
    ->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');

// Unified body-composition source. Compatibility aliases keep existing
// Flutter consumers working while new reports use the canonical field names.
$bodyMetric = BodyCompositionRepository::latestForPlayer(
    $pdo,
    $linkedPlayerId,
    (int)$userId,
    true
);
if ($bodyMetric) {
    $bodyMetric['body_fat_percent'] = $bodyMetric['body_fat_percentage'];
    $bodyMetric['lean_mass_kg'] = $bodyMetric['fat_free_mass_kg'];
}

// Today's hooper (same calendar day, UTC)
$stmt = $pdo->prepare(
    'SELECT * FROM player_hooper_index
     WHERE user_id = ? AND submitted_at BETWEEN ? AND ?
     ORDER BY submitted_at DESC LIMIT 1'
);
$stmt->execute([$userId, $todayStartUtc, $todayEndUtc]);
$todayHooper = $stmt->fetch() ?: null;

// Last 3 days hooper for injury risk detection
$stmt = $pdo->prepare(
    'SELECT hooper_score, fatigue FROM player_hooper_index WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 3'
);
$stmt->execute([$userId]);
$recent3Hooper = $stmt->fetchAll();

// Last RPE
$activeRpeFilter = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
    ? ' AND is_active_record = 1'
    : '';
$stmt = $pdo->prepare(
    'SELECT * FROM player_rpe
     WHERE (linked_player_id = ? OR (linked_player_id IS NULL AND user_id = ?))' .
    $activeRpeFilter .
    ' ORDER BY submitted_at DESC LIMIT 1'
);
$stmt->execute([$linkedPlayerId, $userId]);
$lastRpe = $stmt->fetch() ?: null;

// Personal Hooper baseline (28-day rolling average, excludes today) — null
// when the player doesn't have enough history yet for a meaningful baseline.
$hooperBaseline = getHooperBaseline($pdo, $userId, $localToday);
$elevatedVsBaseline = $todayHooper
    ? isElevatedVsBaseline((float)$todayHooper['hooper_score'], $hooperBaseline)
    : false;

// ACWR uses the same deduplicated, quality-aware daily load source as the
// weekly report. Missing/unknown days make the result INSUFFICIENT_DATA.
$today = new DateTimeImmutable(FitnessConfig::today(), FitnessConfig::timezone());
$rollingStart = $today->modify('-27 days');
$dailyRecords = [];
$weekCache = [];
for ($cursor = $rollingStart; $cursor <= $today; $cursor = $cursor->modify('+1 day')) {
    $date = $cursor->format('Y-m-d');
    $bounds = TrainingLoadCalculator::weekBounds($date, TrainingLoadCalculator::DEFAULT_TIMEZONE);
    $weekKey = $bounds['week_start'];
    if (!isset($weekCache[$weekKey])) {
        $weekCache[$weekKey] = TrainingLoadCalculator::getPlayerWeeklyReport(
            $pdo,
            (int)$userId,
            $linkedPlayerId,
            $date,
            TrainingLoadCalculator::DEFAULT_TIMEZONE,
            false
        );
    }
    $day = null;
    foreach ($weekCache[$weekKey]['days'] as $candidate) {
        if ($candidate['date'] === $date) {
            $day = $candidate;
            break;
        }
    }
    $dailyRecords[] = [
        'date' => $date,
        'load' => $day !== null ? (float)$day['daily_load'] : null,
        'complete' => $day !== null && empty($day['data_quality_issues']),
    ];
}
$acwrDetails = AcwrCalculator::calculate($dailyRecords);
$acwr = $acwrDetails['acwr'];
$weeklyLoads = array_map(
    fn(array $row) => $row['load'] !== null ? (float)$row['load'] : null,
    array_slice($dailyRecords, -7)
);

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

    // Elevated relative to THIS player's own baseline, even if still under
    // the fixed "moderate/high_risk" absolute cutoffs — catches an early
    // warning sign for a player whose personal normal runs low.
    if ($elevatedVsBaseline && $h <= 16) $readiness -= 10;
}

if ($lastRpe && $lastRpe['training_load'] > 300) {
    $readiness -= 10;
}

if ($acwr !== null && $acwr > 1.5) {
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
if ($acwr !== null && $acwr > 1.5) {
    $injuryRiskCount++;
    $alerts[] = 'Acute-to-chronic load ratio exceeds safe threshold';
}

// Poor sleep pattern
if ($todayHooper && (int)$todayHooper['sleep_quality'] <= 2) {
    $injuryRiskCount++;
    $alerts[] = 'Poor sleep quality detected';
}

// Elevated vs personal baseline (only counted once, and only when the
// absolute-cutoff alert above didn't already flag today's score)
if ($elevatedVsBaseline && $todayHooper && (int)$todayHooper['hooper_score'] <= 16) {
    $injuryRiskCount++;
    $alerts[] = 'Hooper Index elevated compared to your own recent average';
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

if ($acwr !== null && $acwr > 1.3 && $acwr <= 1.5) {
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
    'acute_load'       => $acwrDetails['acute_load_7d'],
    'chronic_load'     => $acwrDetails['chronic_weekly_average'],
    'acwr_details'     => $acwrDetails,
    'wellness_status'  => $wellnessStatus,
    'hooper_baseline'  => $hooperBaseline, // null until 5+ entries of history exist
    'elevated_vs_baseline' => $elevatedVsBaseline,
    'injury_risk_count' => $injuryRiskCount,
    'alerts'           => $alerts,
    'insights'         => $insights,
    'recommendations'  => $recommendations,
]);
