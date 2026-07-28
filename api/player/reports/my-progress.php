<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/report_helpers.php';

$user = rptAuthUser($pdo);

// player only — linked_player_id from token, never from request
if ($user['role'] !== 'player') {
    jsonOut(['error' => 'Forbidden — players only'], 403);
}

$userId         = (int)$user['id'];
$linkedPlayerId = $user['linked_player_id'] ?? null;

// ── Hooper trend (by user_id, last 30 records) ───────────────────────────
$stmt = $pdo->prepare(
    'SELECT DATE(submitted_at) AS date, hooper_score AS score
     FROM player_hooper_index WHERE user_id = ?
     ORDER BY submitted_at DESC LIMIT 30'
);
$stmt->execute([$userId]);
$hooperRows = array_reverse($stmt->fetchAll(PDO::FETCH_ASSOC));
$hooperTrend = [];
foreach ($hooperRows as $r) {
    $hooperTrend[] = ['date' => $r['date'], 'score' => (int)$r['score']];
}

// ── RPE trend (by user_id, last 30 days grouped) ─────────────────────────
$stmt = $pdo->prepare(
    "SELECT DATE(submitted_at) AS date,
            MAX(CASE WHEN rpe_type = 'pre'  THEN rpe_score END) AS pre_rpe,
            MAX(CASE WHEN rpe_type = 'post' THEN rpe_score END) AS post_rpe
     FROM player_rpe WHERE user_id = ?
     GROUP BY DATE(submitted_at)
     ORDER BY date DESC LIMIT 30"
);
$stmt->execute([$userId]);
$rpeRows = array_reverse($stmt->fetchAll(PDO::FETCH_ASSOC));
$rpeTrend = [];
foreach ($rpeRows as $r) {
    $rpeTrend[] = [
        'date'     => $r['date'],
        'pre_rpe'  => $r['pre_rpe']  !== null ? (float)$r['pre_rpe']  : null,
        'post_rpe' => $r['post_rpe'] !== null ? (float)$r['post_rpe'] : null,
    ];
}

// ── Session completion 30d (by player_user_id) ────────────────────────────
$since30 = date('Y-m-d H:i:s', strtotime('-30 days'));
$stmt = $pdo->prepare(
    "SELECT COUNT(*) AS total,
            SUM(CASE WHEN sp.status IN ('completed','pre_checked','started') THEN 1 ELSE 0 END) AS done
     FROM session_players sp
     INNER JOIN training_sessions ts ON sp.session_id = ts.id
     WHERE sp.player_user_id = ? AND ts.session_date >= ?"
);
$stmt->execute([$userId, $since30]);
$compRow     = $stmt->fetch(PDO::FETCH_ASSOC);
$totalSess   = (int)($compRow['total'] ?? 0);
$doneSess    = (int)($compRow['done']  ?? 0);
$sessionCompletion = [
    'completed'       => $doneSess,
    'assigned'        => $totalSess,
    'completion_rate' => $totalSess > 0 ? round($doneSess / $totalSess * 100) : 0,
];

// ── Assessment history (by linked_player_id) ──────────────────────────────
$assessmentHistory = [];
if ($linkedPlayerId) {
    $stmt = $pdo->prepare(
        'SELECT DATE(created_at) AS date, type AS assessment_type,
                overall_score, stability_score, symmetry_score, control_score
         FROM assessments WHERE player_id = ?
         ORDER BY created_at DESC LIMIT 30'
    );
    $stmt->execute([$linkedPlayerId]);
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
        $assessmentHistory[] = [
            'date'            => $r['date'],
            'assessment_type' => $r['assessment_type'],
            'overall_score'   => (int)$r['overall_score'],
            'stability_score' => (int)$r['stability_score'],
            'symmetry_score'  => (int)$r['symmetry_score'],
            'control_score'   => (int)$r['control_score'],
        ];
    }
}

// ── Body metrics history (last 10 records) ────────────────────────────────
$stmt = $pdo->prepare(
    'SELECT DATE(measured_at) AS date, weight_kg, height_cm, body_fat_percent, bmi
     FROM player_body_metrics WHERE user_id = ?
     ORDER BY measured_at DESC LIMIT 10'
);
$stmt->execute([$userId]);
$bodyMetricsHistory = [];
foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
    $lbm = null;
    if ($r['weight_kg'] !== null && $r['body_fat_percent'] !== null) {
        $lbm = round((float)$r['weight_kg'] * (1 - (float)$r['body_fat_percent'] / 100), 2);
    }
    $bodyMetricsHistory[] = [
        'date'             => $r['date'],
        'weight_kg'        => $r['weight_kg']        !== null ? (float)$r['weight_kg']        : null,
        'height_cm'        => $r['height_cm']        !== null ? (float)$r['height_cm']        : null,
        'body_fat_percent' => $r['body_fat_percent'] !== null ? (float)$r['body_fat_percent'] : null,
        'bmi'              => $r['bmi']              !== null ? (float)$r['bmi']              : null,
        'lean_body_mass'   => $lbm,
    ];
}

// ── Weekly load (last 8 ISO weeks) ───────────────────────────────────────
$stmt = $pdo->prepare(
    "SELECT YEARWEEK(submitted_at, 1) AS yw,
            DATE_FORMAT(MIN(submitted_at), '%Y-W%v') AS week_label,
            SUM(training_load) AS total_load
     FROM player_rpe WHERE user_id = ? AND submitted_at >= DATE_SUB(NOW(), INTERVAL 8 WEEK)
     GROUP BY YEARWEEK(submitted_at, 1)
     ORDER BY yw ASC"
);
$stmt->execute([$userId]);
$weeklyLoad = [];
foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
    $weeklyLoad[] = [
        'week'       => $r['week_label'],
        'total_load' => (int)$r['total_load'],
    ];
}

jsonOut([
    'success'                => true,
    'hooper_trend'           => $hooperTrend,
    'rpe_trend'              => $rpeTrend,
    'session_completion_30d' => $sessionCompletion,
    'assessment_history'     => $assessmentHistory,
    'body_metrics_history'   => $bodyMetricsHistory,
    'weekly_load'            => $weeklyLoad,
]);
