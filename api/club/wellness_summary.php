<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';
require_once dirname(__DIR__) . '/includes/fitness/BodyCompositionRepository.php';
require_once dirname(__DIR__) . '/includes/fitness/FitnessConfig.php';

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
    'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['error' => 'Invalid token'], 401);
if (in_array($user['role'], ['player', 'parent'])) jsonOut(['error' => 'Forbidden'], 403);

$ctx = requireClubPermission($pdo, $user, 'fitness.training_load.view');
$today = FitnessConfig::today();
$todayStartUtc = (new DateTimeImmutable($today . ' 00:00:00', FitnessConfig::timezone()))
    ->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');
$todayEndUtc = (new DateTimeImmutable($today . ' 23:59:59', FitnessConfig::timezone()))
    ->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');

// Today's hooper data per linked player
$stmt = $pdo->prepare(
    "SELECT
        cp.id           AS player_id,
        cp.name,
        cp.status       AS player_status,
        hi.hooper_score,
        hi.fatigue,
        hi.sleep_quality,
        hi.stress,
        hi.muscle_soreness,
        hi.pain_today,
        hi.submitted_at AS hooper_at,
        (SELECT rpe_score FROM player_rpe pr
         WHERE pr.linked_player_id = cp.id AND pr.rpe_type = 'post'
           AND pr.submitted_at BETWEEN ? AND ?
         ORDER BY pr.submitted_at DESC LIMIT 1) AS last_rpe,
        (SELECT training_load FROM player_rpe pr2
         WHERE pr2.linked_player_id = cp.id AND pr2.rpe_type = 'post'
           AND pr2.submitted_at BETWEEN ? AND ?
         ORDER BY pr2.submitted_at DESC LIMIT 1) AS last_load
     FROM club_players cp
     LEFT JOIN player_hooper_index hi
           ON hi.linked_player_id = cp.id AND hi.submitted_at BETWEEN ? AND ?
     WHERE cp.club_id = ? AND cp.is_active = 1
       AND (cp.player_type IS NULL OR cp.player_type = 'club')
       " . (($ctx['team_id'] ?? null) !== null ? 'AND cp.team_id = ?' : '') . "
     ORDER BY COALESCE(hi.hooper_score, 0) DESC"
);
$summaryParams = [
    $todayStartUtc, $todayEndUtc,
    $todayStartUtc, $todayEndUtc,
    $todayStartUtc, $todayEndUtc,
    $ctx['club_id'],
];
if (($ctx['team_id'] ?? null) !== null) $summaryParams[] = $ctx['team_id'];
$stmt->execute($summaryParams);
$rows = $stmt->fetchAll();

$totalPlayers = count($rows);
$submitted    = 0;
$readyCount   = 0;
$moderateCount= 0;
$highRiskCount= 0;
$players      = [];
$top5Fatigued = [];

foreach ($rows as $r) {
    $bodyMeasurement = BodyCompositionRepository::latestForPlayer(
        $pdo,
        $r['player_id'],
        null,
        true
    );
    $hs = $r['hooper_score'] !== null ? (int)$r['hooper_score'] : null;
    if ($hs !== null) {
        $submitted++;
        if ($hs >= 17)      { $highRiskCount++; $wStatus = 'high_risk'; }
        elseif ($hs >= 13)  { $moderateCount++;  $wStatus = 'moderate'; }
        else                { $readyCount++;      $wStatus = 'normal'; }
    } else {
        $wStatus = 'no_data';
    }

    $entry = [
        'id'              => $r['player_id'],
        'name'            => $r['name'],
        'player_status'   => $r['player_status'],
        'hooper_score'    => $hs,
        'fatigue'         => $hs !== null ? (int)$r['fatigue'] : null,
        'sleep_quality'   => $hs !== null ? (int)$r['sleep_quality'] : null,
        'stress'          => $hs !== null ? (int)$r['stress'] : null,
        'muscle_soreness' => $hs !== null ? (int)$r['muscle_soreness'] : null,
        'pain_today'      => (int)($r['pain_today'] ?? 0),
        'hooper_at'       => $r['hooper_at'],
        'last_rpe'        => $r['last_rpe'] !== null ? (float)$r['last_rpe'] : null,
        'last_load'       => $r['last_load'] !== null ? (float)$r['last_load'] : null,
        'body_fat'        => $bodyMeasurement['body_fat_percentage'] ?? null,
        'body_measurement_source' => $bodyMeasurement['source_system'] ?? null,
        'wellness_status' => $wStatus,
    ];

    $players[] = $entry;
    if ($hs !== null && $hs >= 13) {
        $top5Fatigued[] = $entry;
    }
}

// Sort top5 by hooper score descending, take first 5
usort($top5Fatigued, fn($a, $b) => ($b['hooper_score'] ?? 0) - ($a['hooper_score'] ?? 0));
$top5Fatigued = array_slice($top5Fatigued, 0, 5);

$avgHooper = $submitted > 0
    ? round(array_sum(array_column(
        array_filter($players, fn($p) => $p['hooper_score'] !== null),
        'hooper_score'
      )) / $submitted, 1)
    : null;

jsonOut([
    'success'         => true,
    'date'            => $today,
    'total_players'   => $totalPlayers,
    'submitted'       => $submitted,
    'missing'         => max(0, $totalPlayers - $submitted),
    'ready'           => $readyCount,
    'moderate'        => $moderateCount,
    'high_risk'       => $highRiskCount,
    'avg_hooper'      => $avgHooper,
    'top5_fatigued'   => $top5Fatigued,
    'players'         => $players,
]);
