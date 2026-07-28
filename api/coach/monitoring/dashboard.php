<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../../db.php';
require_once '../../includes/wellness_baseline.php';
require_once '../../includes/club_auth.php';
require_once '../../includes/fitness/SchemaInspector.php';
require_once '../../includes/fitness/BodyCompositionRepository.php';
require_once '../../includes/fitness/FitnessConfig.php';

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

$token = bearerToken();
if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.name, u.role FROM users u
     JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['error' => 'Invalid token'], 401);
if (in_array($user['role'], ['player', 'parent'])) jsonOut(['error' => 'Forbidden'], 403);

$ctx    = requireClubPermission($pdo, $user, 'fitness.training_load.view');
$clubId = $ctx['club_id'];
$today  = FitnessConfig::today();
$activeRpePr = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
    ? ' AND pr.is_active_record = 1'
    : '';
$activeRpePr2 = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
    ? ' AND pr2.is_active_record = 1'
    : '';

// ── Players stats ─────────────────────────────────────────────────────────────
$weekStart = date('Y-m-d', strtotime('monday this week'));

$pStmt = $pdo->prepare(
    "SELECT
        COUNT(*)                                          AS total,
        SUM(status = 'active')                            AS active,
        SUM(status = 'injured')                           AS injured,
        SUM(status = 'recovering')                        AS recovering,
        SUM(status = 'suspended')                         AS suspended,
        SUM(status = 'inactive')                          AS unavailable,
        SUM(status IN ('injured','recovering'))           AS injured_count,
        SUM(status = 'active')                            AS available_count,
        SUM(last_assessment_at IS NOT NULL
            AND last_assessment_at >= ?)                  AS assessed_this_week
     FROM club_players
     WHERE club_id = ? AND is_active = 1
       AND (player_type IS NULL OR player_type = 'club')"
);
$pStmt->execute([$weekStart, $clubId]);
$pStats = $pStmt->fetch();

// ── Sessions today ────────────────────────────────────────────────────────────
$sStmt = $pdo->prepare(
    "SELECT COUNT(*) AS sessions_today FROM club_sessions WHERE club_id = ? AND date = ?"
);
$sStmt->execute([$clubId, $today]);
$sRow = $sStmt->fetch();

// ── Assessments today ─────────────────────────────────────────────────────────
$aStmt = $pdo->prepare(
    "SELECT COUNT(*) AS assessments_today FROM assessments
     WHERE club_id = ? AND DATE(created_at) = ?"
);
$aStmt->execute([$clubId, $today]);
$aRow = $aStmt->fetch();

// ── Players needing review (score < 65) ───────────────────────────────────────
$rStmt = $pdo->prepare(
    "SELECT COUNT(*) AS needs_review FROM club_players
     WHERE club_id = ? AND is_active = 1 AND latest_score IS NOT NULL AND latest_score < 65"
);
$rStmt->execute([$clubId]);
$rRow = $rStmt->fetch();

// ── Wellness: linked players' hooper today ────────────────────────────────────
$wStmt = $pdo->prepare(
    "SELECT
        cp.id             AS player_id,
        cp.name           AS player_name,
        cp.status,
        cp.linked_user_id,
        hi.hooper_score,
        hi.fatigue,
        hi.sleep_quality,
        hi.muscle_soreness,
        hi.pain_today,
        (SELECT rpe_score FROM player_rpe pr
         WHERE pr.linked_player_id = cp.id
           AND pr.rpe_type = 'post'
           AND DATE(pr.submitted_at) = ?$activeRpePr
         ORDER BY pr.submitted_at DESC LIMIT 1) AS post_rpe,
        (SELECT SUM(training_load) FROM player_rpe pr2
         WHERE pr2.linked_player_id = cp.id
           AND DATE(pr2.submitted_at) = ?$activeRpePr2) AS today_load,
        (SELECT total_score FROM fms_assessments fa
         WHERE fa.player_id = cp.id
         ORDER BY fa.created_at DESC LIMIT 1) AS fms_score
     FROM club_players cp
     LEFT JOIN player_hooper_index hi
           ON hi.linked_player_id = cp.id
          AND DATE(hi.submitted_at) = ?
     WHERE cp.club_id = ? AND cp.is_active = 1
       AND (cp.player_type IS NULL OR cp.player_type = 'club')
     ORDER BY cp.name ASC"
);
$wStmt->execute([$today, $today, $today, $clubId]);
$wellnessRows = $wStmt->fetchAll();

// Build wellness summary
$submitted = 0;
$ready = $fatigue = $highRisk = 0;
$playerStatuses = [];

foreach ($wellnessRows as $w) {
    $bodyMeasurement = BodyCompositionRepository::latestForPlayer(
        $pdo,
        $w['player_id'],
        $w['linked_user_id'] !== null ? (int)$w['linked_user_id'] : null,
        true
    );
    $hasHooper = $w['hooper_score'] !== null;
    if ($hasHooper) $submitted++;

    $hs = (int)($w['hooper_score'] ?? 0);
    if ($hs >= 17)      { $highRisk++; $status = 'high_risk'; }
    elseif ($hs >= 13)  { $fatigue++;  $status = 'moderate'; }
    else                { $ready++;    $status = 'normal'; }

    $playerStatuses[] = [
        'id'           => $w['player_id'],
        'name'         => $w['player_name'],
        'status'       => $w['status'],
        'hooper_score' => $hasHooper ? (int)$hs : null,
        'fatigue'      => $hasHooper ? (int)$w['fatigue'] : null,
        'pain_today'   => (int)($w['pain_today'] ?? 0),
        'post_rpe'     => $w['post_rpe'] !== null ? (float)$w['post_rpe'] : null,
        'training_load' => $w['today_load'] !== null ? (float)$w['today_load'] : null,
        'body_fat'     => $bodyMeasurement['body_fat_percentage'] ?? null,
        'body_measurement_source' => $bodyMeasurement['source_system'] ?? null,
        'fms_score'    => $w['fms_score'] !== null ? (int)$w['fms_score'] : null,
        'wellness_status' => $status ?? 'normal',
    ];
}

// ── Alerts ────────────────────────────────────────────────────────────────────
$alerts = [];
foreach ($wellnessRows as $w) {
    if ((int)($w['hooper_score'] ?? 0) >= 17) {
        $alerts[] = [
            'player_id'   => $w['player_id'],
            'player_name' => $w['player_name'],
            'type'        => 'high_fatigue',
            'severity'    => 'danger',
            'value'       => (int)$w['hooper_score'],
        ];
    } elseif ($w['hooper_score'] !== null && !empty($w['linked_user_id']) &&
              isElevatedVsBaseline((float)$w['hooper_score'], getHooperBaseline($pdo, (int)$w['linked_user_id'], $today))) {
        // Under the absolute cutoff, but meaningfully high for THIS player
        $alerts[] = [
            'player_id'   => $w['player_id'],
            'player_name' => $w['player_name'],
            'type'        => 'elevated_vs_baseline',
            'severity'    => 'warning',
            'value'       => (int)$w['hooper_score'],
        ];
    } elseif ((int)($w['pain_today'] ?? 0) > 0) {
        $alerts[] = [
            'player_id'   => $w['player_id'],
            'player_name' => $w['player_name'],
            'type'        => 'injury_risk',
            'severity'    => 'warning',
            'value'       => (int)$w['pain_today'],
        ];
    } elseif ((int)($w['muscle_soreness'] ?? 0) >= 7) {
        $alerts[] = [
            'player_id'   => $w['player_id'],
            'player_name' => $w['player_name'],
            'type'        => 'muscle_soreness',
            'severity'    => 'warning',
            'value'       => (int)$w['muscle_soreness'],
        ];
    }
}

$totalPlayers    = (int)($pStats['total']             ?? 0);
$activePlayers   = (int)($pStats['active']            ?? 0);
$assessedWeek    = (int)($pStats['assessed_this_week'] ?? 0);
$assessPct       = $activePlayers > 0
    ? round($assessedWeek / $activePlayers * 100) : 0;

jsonOut([
    'success' => true,
    'summary' => [
        'total_players'             => $totalPlayers,
        'active_players'            => $activePlayers,
        'injured_players'           => (int)($pStats['injured']       ?? 0),
        'recovering_players'        => (int)($pStats['recovering']    ?? 0),
        'suspended_players'         => (int)($pStats['suspended']     ?? 0),
        'unavailable_players'       => (int)($pStats['unavailable']   ?? 0),
        'available_count'           => (int)($pStats['available_count'] ?? 0),
        'injured_count'             => (int)($pStats['injured_count']   ?? 0),
        'sessions_today'            => (int)($sRow['sessions_today']    ?? 0),
        'assessments_today'         => (int)($aRow['assessments_today'] ?? 0),
        'players_review'            => (int)($rRow['needs_review']      ?? 0),
        'submitted_today'           => $submitted,
        'ready_count'               => $ready,
        'fatigue_count'             => $fatigue,
        'high_risk_count'           => $highRisk,
        'missing_count'             => max(0, $totalPlayers - $submitted),
        'assessed_this_week'        => $assessedWeek,
        'assessment_total'          => $activePlayers,
        'assessment_completion_pct' => $assessPct,
    ],
    'players'  => $playerStatuses,
    'alerts'   => $alerts,
]);
