<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, PUT, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/report_helpers.php';

$user = rptAuthUser($pdo);
if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['error' => 'Forbidden'], 403);
}

$ctx = requireClubPermission($pdo, $user, 'players.read');
$clubId = (int)$ctx['club_id'];
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'PUT') {
    // The management report is read-only. Only the physical coach owns this
    // manual readiness decision.
    if (($ctx['staff_role'] ?? '') !== 'coach') {
        jsonOut(['error' => 'Only the physical coach can update readiness'], 403);
    }

    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $playerId = trim((string)($body['player_id'] ?? ''));
    $status = trim((string)($body['status'] ?? ''));
    if ($playerId === '' || !in_array($status, ['ready', 'not_ready'], true)) {
        jsonOut(['error' => 'Invalid player_id or status'], 422);
    }

    $stmt = $pdo->prepare(
        'UPDATE club_players
         SET physical_readiness_status = ?,
             physical_readiness_updated_by = ?,
             physical_readiness_updated_at = NOW()
         WHERE id = ? AND club_id = ? AND is_active = 1'
    );
    $stmt->execute([$status, $user['id'], $playerId, $clubId]);
    if ($stmt->rowCount() === 0) {
        $exists = $pdo->prepare(
            'SELECT 1 FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1'
        );
        $exists->execute([$playerId, $clubId]);
        if (!$exists->fetchColumn()) jsonOut(['error' => 'Player not found'], 404);
    }

    jsonOut(['success' => true]);
}

if ($method !== 'GET') {
    jsonOut(['error' => 'Method not allowed'], 405);
}

$rosterSql =
    "SELECT id, name, position, team_name, linked_user_id,
            COALESCE(physical_readiness_status, 'ready') AS physical_readiness_status,
            physical_readiness_updated_at
     FROM club_players
     WHERE club_id = ? AND is_active = 1
       AND (player_type IS NULL OR player_type = 'club')";
$rosterParams = [$clubId];
if (($ctx['team_id'] ?? null) !== null) {
    $rosterSql .= ' AND team_id = ?';
    $rosterParams[] = (int)$ctx['team_id'];
}
$rosterSql .= ' ORDER BY name ASC';

$roster = $pdo->prepare($rosterSql);
$roster->execute($rosterParams);
$players = $roster->fetchAll(PDO::FETCH_ASSOC);

$activeRpeFilter = rptActiveRpeFilter($pdo);
$loadStmt = $pdo->prepare(
    "SELECT COALESCE(SUM(training_load), 0) AS weekly_load,
            COUNT(DISTINCT COALESCE(
                NULLIF(session_id, ''),
                NULLIF(training_session_id, ''),
                CONCAT('rpe-', id)
            )) AS rpe_sessions
     FROM player_rpe
     WHERE submitted_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
       AND (club_id = ? OR club_id IS NULL)
       AND (
           linked_player_id = ?
           OR (
               ? IS NOT NULL
               AND (linked_player_id IS NULL OR linked_player_id = '')
               AND user_id = ?
           )
       )$activeRpeFilter"
);

$attendanceStmt = $pdo->prepare(
    "SELECT COUNT(DISTINCT sa.session_id)
     FROM session_attendance sa
     JOIN club_sessions cs ON cs.id = sa.session_id
     WHERE sa.player_id = ? AND cs.club_id = ?
       AND cs.date >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
       AND sa.status IN ('present', 'late')"
);

$decisionStmt = $pdo->prepare(
    'SELECT player_id, participation_status
     FROM player_daily_decisions
     WHERE club_id = ? AND decision_date = CURDATE()'
);
$decisionStmt->execute([$clubId]);
$todayDecisions = [];
foreach ($decisionStmt->fetchAll(PDO::FETCH_ASSOC) as $decision) {
    $todayDecisions[$decision['player_id']] = $decision['participation_status'];
}

$rows = [];
$readyCount = 0;
$bodyFatValues = [];

foreach ($players as $player) {
    $linkedUserId = $player['linked_user_id'] !== null
        ? (int)$player['linked_user_id']
        : null;

    $measurement = BodyCompositionRepository::latestForPlayer(
        $pdo,
        $player['id'],
        $linkedUserId,
        false
    );
    $bodyFat = $measurement && $measurement['body_fat_percentage'] !== null
        ? round((float)$measurement['body_fat_percentage'], 1)
        : null;
    if ($bodyFat !== null) $bodyFatValues[] = $bodyFat;

    $loadStmt->execute([$clubId, $player['id'], $linkedUserId, $linkedUserId]);
    $load = $loadStmt->fetch(PDO::FETCH_ASSOC) ?: [];

    $attendanceStmt->execute([$player['id'], $clubId]);
    $attendanceSessions = (int)$attendanceStmt->fetchColumn();
    $sessions = $attendanceSessions > 0
        ? $attendanceSessions
        : (int)($load['rpe_sessions'] ?? 0);

    $todayDecision = $todayDecisions[$player['id']] ?? null;
    $isReady = $todayDecision !== null
        ? $todayDecision !== 'unavailable'
        : ($player['physical_readiness_status'] ?? 'ready') !== 'not_ready';
    if ($isReady) $readyCount++;

    $rows[] = [
        'player_id' => $player['id'],
        'player_name' => $player['name'],
        'position' => $player['position'] ?? '',
        'team_name' => $player['team_name'] ?? '',
        'is_ready' => $isReady,
        'readiness_updated_at' => $player['physical_readiness_updated_at'],
        'body_fat_percentage' => $bodyFat,
        'weekly_load' => round((float)($load['weekly_load'] ?? 0)),
        'sessions_count' => $sessions,
    ];
}

$avgBodyFat = $bodyFatValues
    ? round(array_sum($bodyFatValues) / count($bodyFatValues), 1)
    : null;

$sessionSummarySql =
    "SELECT COUNT(*) FROM club_sessions
     WHERE club_id = ? AND date >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
       AND status != 'cancelled'";
$sessionSummaryParams = [$clubId];
if (($ctx['team_id'] ?? null) !== null) {
    $sessionSummarySql .= ' AND team_id = ?';
    $sessionSummaryParams[] = (int)$ctx['team_id'];
}
$sessionSummaryStmt = $pdo->prepare($sessionSummarySql);
$sessionSummaryStmt->execute($sessionSummaryParams);
$totalSessions = (int)$sessionSummaryStmt->fetchColumn();

jsonOut([
    'success' => true,
    'period_days' => 7,
    'summary' => [
        'total_players' => count($rows),
        'ready_players' => $readyCount,
        'not_ready_players' => count($rows) - $readyCount,
        'average_body_fat' => $avgBodyFat,
        'total_sessions' => $totalSessions,
    ],
    'players' => $rows,
]);
