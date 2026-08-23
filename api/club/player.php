<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';
require_once dirname(__DIR__) . '/includes/fitness/BodyCompositionRepository.php';
require_once dirname(__DIR__) . '/includes/fitness/SchemaInspector.php';

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

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
}

// Auth
$token = bearerToken();
if (!$token) jsonOut(['success' => false, 'message' => 'Unauthorized'], 401);

$authStmt = $pdo->prepare(
    'SELECT u.id FROM users u JOIN user_tokens t ON u.id = t.user_id
     WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$authStmt->execute([$token]);
$user = $authStmt->fetch();
if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);

$playerId = trim($_GET['id'] ?? '');
if (!$playerId) jsonOut(['success' => false, 'message' => 'Missing player id'], 400);

$ctx = requireClubPermission($pdo, $user, 'players.read');

// Fetch player by UUID, scoped to the requesting staff member's club
$pStmt = $pdo->prepare(
    'SELECT * FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1' .
    (($ctx['team_id'] ?? null) !== null ? ' AND team_id = ?' : '') .
    ' LIMIT 1'
);
$playerParams = [$playerId, $ctx['club_id']];
if (($ctx['team_id'] ?? null) !== null) $playerParams[] = $ctx['team_id'];
$pStmt->execute($playerParams);
$player = $pStmt->fetch(PDO::FETCH_ASSOC);

if (!$player) jsonOut(['success' => false, 'message' => 'Player not found'], 404);

// Normalize types
$player['height_cm']            = $player['height_cm'] !== null ? (float)$player['height_cm'] : null;
$player['weight_kg']            = $player['weight_kg'] !== null ? (float)$player['weight_kg'] : null;
$player['is_active']            = (bool)$player['is_active'];
$player['latest_score']         = $player['latest_score'] !== null ? (float)$player['latest_score'] : null;
$player['movement_score']       = $player['movement_score'] !== null ? (float)$player['movement_score'] : null;
$player['stability_score']      = $player['stability_score'] !== null ? (float)$player['stability_score'] : null;
$player['symmetry_score']       = $player['symmetry_score'] !== null ? (float)$player['symmetry_score'] : null;
$player['control_score']        = $player['control_score'] !== null ? (float)$player['control_score'] : null;
$player['status']               = $player['status'] ?? 'active';
$player['expected_return_date'] = $player['expected_return_date'] ?? null;
$player['unavailable_reason']   = $player['unavailable_reason'] ?? null;
$player['last_assessment_at']   = $player['last_assessment_at'] ?? null;

// Assessments for this player (coach must own them)
$coachNotesSelect = SchemaInspector::hasColumn($pdo, 'assessments', 'coach_notes')
    ? 'coach_notes'
    : 'NULL AS coach_notes';
$aStmt = $pdo->prepare(
    "SELECT id, player_id, player_name, type, session_id,
            overall_score, movement_quality_score, stability_score,
            symmetry_score, control_score, quality_score,
            $coachNotesSelect, created_at
     FROM assessments
     WHERE club_id = ? AND player_id = ?
     ORDER BY created_at DESC
     LIMIT 20"
);
$aStmt->execute([$ctx['club_id'], $playerId]);
$assessments = $aStmt->fetchAll(PDO::FETCH_ASSOC);
foreach ($assessments as &$a) {
    $a['overall_score']          = (int)($a['overall_score'] ?? 0);
    $a['movement_quality_score'] = (int)($a['movement_quality_score'] ?? 0);
    $a['stability_score']        = (int)($a['stability_score'] ?? 0);
    $a['symmetry_score']         = (int)($a['symmetry_score'] ?? 0);
    $a['control_score']          = (int)($a['control_score'] ?? 0);
    $a['quality_score']          = (int)($a['quality_score'] ?? 0);
    $a['issues']                 = [];
    $a['tips']                   = [];
}
unset($a);

// Wellness snapshot (Hooper + RPE + body fat) — best-effort, never fatal
$wellness = null;
try {
    $hStmt = $pdo->prepare(
        'SELECT hooper_score, fatigue, sleep_quality, stress, muscle_soreness
         FROM player_hooper_index
         WHERE linked_player_id = ?
         ORDER BY submitted_at DESC LIMIT 1'
    );
    $hStmt->execute([$playerId]);
    $hooper = $hStmt->fetch(PDO::FETCH_ASSOC);

    $activeRpeFilter = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
        ? ' AND is_active_record = 1'
        : '';
    $rStmt = $pdo->prepare(
        "SELECT rpe_score, duration_minutes, actual_duration_minutes,
                training_load, submitted_at
         FROM player_rpe
         WHERE linked_player_id = ? AND rpe_type = 'post'$activeRpeFilter
         ORDER BY submitted_at DESC LIMIT 1"
    );
    $rStmt->execute([$playerId]);
    $rpe = $rStmt->fetch(PDO::FETCH_ASSOC);

    $linkedUserId = $player['linked_user_id'] ?? null;
    $bodyMeasurement = BodyCompositionRepository::latestForPlayer(
        $pdo,
        $playerId,
        $linkedUserId !== null ? (int)$linkedUserId : null,
        true
    );
    $bodyFat = $bodyMeasurement['body_fat_percentage'] ?? null;

    if ($hooper || $rpe || $bodyMeasurement) {
        $wellness = [
            'hooper_score'    => $hooper ? (int)$hooper['hooper_score'] : null,
            'fatigue'         => $hooper ? (int)$hooper['fatigue'] : null,
            'sleep_quality'   => $hooper ? (int)$hooper['sleep_quality'] : null,
            'stress'          => $hooper ? (int)$hooper['stress'] : null,
            'muscle_soreness' => $hooper ? (int)$hooper['muscle_soreness'] : null,
            'last_rpe'        => $rpe && $rpe['rpe_score'] !== null ? (float)$rpe['rpe_score'] : null,
            'last_duration_minutes' => $rpe
                && ($rpe['actual_duration_minutes'] ?? $rpe['duration_minutes']) !== null
                ? (int)($rpe['actual_duration_minutes'] ?? $rpe['duration_minutes'])
                : null,
            'last_load'       => $rpe && $rpe['training_load'] !== null ? (float)$rpe['training_load'] : null,
            'last_rpe_at'     => $rpe ? ($rpe['submitted_at'] ?? null) : null,
            'body_fat'        => $bodyFat,
            'body_fat_measured_at' => $bodyMeasurement['measured_at'] ?? null,
            'body_measurement_status' => $bodyMeasurement['status'] ?? null,
            'body_measurement_source' => $bodyMeasurement['source_system'] ?? null,
        ];
    }
} catch (Throwable $e) {
    // Wellness is optional — swallow the error
}

$discipline = [
    'yellow_cards_total' => 0, 'current_yellow_cards' => 0,
    'red_cards_total' => 0, 'suspensions_total' => 0,
    'active_suspensions' => 0, 'executed_suspensions' => 0,
    'status' => 'available',
];
$cardStmt = $pdo->prepare('SELECT card_type, COUNT(*) AS total FROM match_cards mc JOIN matches m ON m.id = mc.match_id WHERE m.club_id = ? AND mc.player_id = ? GROUP BY card_type');
$cardStmt->execute([(int)$ctx['club_id'], $playerId]);
foreach ($cardStmt->fetchAll() as $row) {
    if ($row['card_type'] === 'yellow') $discipline['yellow_cards_total'] = (int)$row['total'];
    if ($row['card_type'] === 'red') $discipline['red_cards_total'] = (int)$row['total'];
}
$cycleStmt = $pdo->prepare('SELECT COALESCE(SUM(current_yellow_cards), 0) FROM player_discipline_cycles WHERE club_id = ? AND player_id = ? AND completed_at IS NULL');
$cycleStmt->execute([(int)$ctx['club_id'], $playerId]);
$discipline['current_yellow_cards'] = (int)$cycleStmt->fetchColumn();
$suspensionStmt = $pdo->prepare("SELECT COUNT(*) AS total, SUM(status = 'active') AS active, SUM(status = 'completed') AS completed FROM player_suspensions WHERE club_id = ? AND player_id = ?");
$suspensionStmt->execute([(int)$ctx['club_id'], $playerId]);
$suspensions = $suspensionStmt->fetch() ?: [];
$discipline['suspensions_total'] = (int)($suspensions['total'] ?? 0);
$discipline['active_suspensions'] = (int)($suspensions['active'] ?? 0);
$discipline['executed_suspensions'] = (int)($suspensions['completed'] ?? 0);
$discipline['status'] = $discipline['active_suspensions'] > 0 ? 'suspended' : ($discipline['current_yellow_cards'] > 0 ? 'available_warning' : 'available');

jsonOut([
    'success'     => true,
    'player'      => $player,
    'assessments' => $assessments,
    'wellness'    => $wellness,
    'discipline'  => $discipline,
    'load'        => null,
]);
