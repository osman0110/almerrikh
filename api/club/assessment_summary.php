<?php
// GET /api/club/assessment_summary.php
// Returns per-player latest assessment summary, per-type trend, and risk flags.
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../report_helpers.php';

$user = rptAuthUser($pdo);
$uid  = (int)$user['id'];

// ── Fetch all active players ──────────────────────────────────────────────────
$stmt = $pdo->prepare(
    "SELECT id, name, position, team_name, status
     FROM club_players
     WHERE user_id = ? AND is_active = 1
     ORDER BY name ASC"
);
$stmt->execute([$uid]);
$players = $stmt->fetchAll(PDO::FETCH_ASSOC);

// ── Per-player: latest assessment per type + risk analysis ────────────────────
$result      = [];
$highRisk    = 0;
$mediumRisk  = 0;
$weekStart   = date('Y-m-d', strtotime('monday this week'));
$assessedThisWeek = 0;
$scoresByType = []; // for averages

$validTypes = [
    'squat','singleLegBalance','jumpLanding',
    'countermovementJump','squatJump','dropJump','singleLegDropJump'
];

foreach ($players as $player) {
    $pid = $player['id'];

    // Latest assessment per type (one row per type)
    $stmt2 = $pdo->prepare(
        "SELECT type, overall_score, stability_score, symmetry_score,
                control_score, movement_quality_score, angle_metrics_json,
                DATE(created_at) AS assessed_date, created_at
         FROM assessments
         WHERE user_id = ? AND player_id = ?
           AND created_at = (
               SELECT MAX(a2.created_at) FROM assessments a2
               WHERE a2.user_id = ? AND a2.player_id = ? AND a2.type = assessments.type
           )
         ORDER BY created_at DESC"
    );
    $stmt2->execute([$uid, $pid, $uid, $pid]);
    $rows = $stmt2->fetchAll(PDO::FETCH_ASSOC);

    $byType  = [];
    $flags   = [];
    $riskLevel = 'none';
    $latestDate = null;

    foreach ($rows as $row) {
        $type    = $row['type'];
        $overall = (int)$row['overall_score'];
        $metrics = json_decode($row['angle_metrics_json'] ?? '{}', true) ?? [];

        // Store score by type
        $scoresByType[$type][] = $overall;

        // Trend: compare with previous of same type
        $prev = $pdo->prepare(
            "SELECT overall_score FROM assessments
             WHERE user_id = ? AND player_id = ? AND type = ?
               AND created_at < ?
             ORDER BY created_at DESC LIMIT 1"
        );
        $prev->execute([$uid, $pid, $type, $row['created_at']]);
        $prevRow = $prev->fetch(PDO::FETCH_ASSOC);
        $trend   = 'no_data';
        if ($prevRow) {
            $delta = $overall - (int)$prevRow['overall_score'];
            $trend = $delta >= 5 ? 'improving' : ($delta <= -5 ? 'declining' : 'stable');
        }

        $byType[$type] = [
            'score'  => $overall,
            'date'   => $row['assessed_date'],
            'trend'  => $trend,
        ];

        // Track latest date (for weekly check)
        if ($latestDate === null || $row['created_at'] > $latestDate) {
            $latestDate = $row['created_at'];
        }

        // ── Risk flag detection ───────────────────────────────────────────────
        // Valgus flag (jump tests)
        $valgus = $metrics['Landing valgus score'] ?? $metrics['Left knee valgus'] ?? null;
        if ($valgus !== null && $valgus < 55) {
            $flags[] = 'knee_valgus';
        } elseif ($valgus !== null && $valgus < 70) {
            $flags[] = 'mild_valgus';
        }

        // Symmetry flag (SLDJ or squat symmetry_score)
        $asymScore = $metrics['L/R asymmetry score'] ?? null;
        if ($asymScore !== null && $asymScore < 60) {
            $flags[] = 'high_asymmetry';
        } elseif ((int)($row['symmetry_score'] ?? 100) < 55) {
            $flags[] = 'asymmetry';
        }

        // Poor landing flag
        $landStab = $metrics['Landing stability'] ?? $metrics['Left stability'] ?? null;
        if ($landStab !== null && $landStab < 45) {
            $flags[] = 'poor_landing';
        }

        // Low overall flag (squat or jump)
        if ($overall < 50 && $type === 'squat') {
            $flags[] = 'poor_squat';
        }
        if ($overall < 45 && in_array($type, ['countermovementJump','dropJump'])) {
            $flags[] = 'poor_jump_power';
        }
    }

    // Deduplicate flags
    $flags = array_values(array_unique($flags));

    // Risk level
    $criticalFlags  = ['knee_valgus', 'high_asymmetry'];
    $moderateFlags  = ['mild_valgus', 'asymmetry', 'poor_landing', 'poor_squat'];
    if (count(array_intersect($flags, $criticalFlags)) > 0) {
        $riskLevel = 'high';
        $highRisk++;
    } elseif (count(array_intersect($flags, $moderateFlags)) > 0) {
        $riskLevel = 'medium';
        $mediumRisk++;
    } elseif (!empty($byType)) {
        $riskLevel = 'low';
    }

    // Weekly assessment check
    if ($latestDate && $latestDate >= $weekStart) {
        $assessedThisWeek++;
    }

    $result[] = [
        'id'          => $player['id'],
        'name'        => $player['name'],
        'position'    => $player['position'],
        'team'        => $player['team_name'],
        'status'      => $player['status'],
        'assessments' => $byType,
        'risk_level'  => $riskLevel,
        'risk_flags'  => $flags,
        'latest_date' => $latestDate ? substr($latestDate, 0, 10) : null,
    ];
}

// Sort: high → medium → low → none
usort($result, function ($a, $b) {
    $order = ['high' => 0, 'medium' => 1, 'low' => 2, 'none' => 3];
    return ($order[$a['risk_level']] ?? 3) <=> ($order[$b['risk_level']] ?? 3);
});

// ── Averages per type ─────────────────────────────────────────────────────────
$avgByType = [];
foreach ($scoresByType as $type => $scores) {
    if (count($scores) > 0) {
        $avgByType[$type] = round(array_sum($scores) / count($scores), 1);
    }
}

echo json_encode([
    'players'           => $result,
    'summary' => [
        'total_players'      => count($players),
        'assessed_this_week' => $assessedThisWeek,
        'high_risk_count'    => $highRisk,
        'medium_risk_count'  => $mediumRisk,
        'avg_by_type'        => $avgByType,
    ],
], JSON_UNESCAPED_UNICODE);
