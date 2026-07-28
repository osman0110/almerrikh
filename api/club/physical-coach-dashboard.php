<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../includes/club_auth.php';

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
        $headers = apache_request_headers();
        $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    }
    if (stripos($auth, 'Bearer ') === 0) return trim(substr($auth, 7));
    return trim($auth);
}

function authUser(PDO $pdo): array {
    $token = bearerToken();
    if ($token === '') jsonOut(['success' => false, 'error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.name, u.role
         FROM users u JOIN user_tokens t ON t.user_id = u.id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) jsonOut(['success' => false, 'error' => 'Invalid token'], 401);
    return $user;
}

function stringList($value): array {
    if (is_string($value)) $value = json_decode($value, true);
    if (!is_array($value)) return [];
    return array_values(array_unique(array_map('strval', $value)));
}

function normalizeSessionRow(array $row): array {
    $row['duration_min'] = (int)($row['duration_min'] ?? 0);
    $row['player_count'] = (int)($row['player_count'] ?? 0);
    $row['assessment_count'] = (int)($row['assessment_count'] ?? 0);
    $row['attendance_present_count'] = (int)($row['attendance_present_count'] ?? 0);
    $row['ai_enabled'] = (bool)($row['ai_enabled'] ?? false);
    $row['attendance_required'] = (bool)($row['attendance_required'] ?? false);
    $row['rpe_required'] = (bool)($row['rpe_required'] ?? false);
    $row['wellness_required'] = (bool)($row['wellness_required'] ?? false);
    $row['player_ids'] = stringList($row['player_ids'] ?? []);
    $row['completed_player_ids'] = stringList($row['completed_player_ids'] ?? []);
    $row['assessment_types'] = stringList($row['assessment_types'] ?? []);
    return $row;
}

function normalizeMatchRow(array $row): array {
    $row['wellness_required'] = (bool)($row['wellness_required'] ?? false);
    $row['rpe_required'] = (bool)($row['rpe_required'] ?? false);
    $row['player_ids'] = stringList($row['player_ids'] ?? []);
    $minutes = $row['player_minutes'] ?? [];
    if (is_string($minutes)) $minutes = json_decode($minutes, true);
    $row['player_minutes'] = is_array($minutes) ? $minutes : [];
    return $row;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonOut(['success' => false, 'error' => 'Method not allowed'], 405);
}

$user = authUser($pdo);
$ctx = requireClubPermission($pdo, $user, 'sessions.read');
$clubId = (int)$ctx['club_id'];
$teamId = $ctx['team_id'] !== null ? (int)$ctx['team_id'] : null;

$clubStmt = $pdo->prepare('SELECT name FROM clubs WHERE id = ?');
$clubStmt->execute([$clubId]);
$clubName = (string)($clubStmt->fetchColumn() ?: '');

$teamName = null;
if ($teamId !== null) {
    $teamStmt = $pdo->prepare(
        'SELECT name FROM club_teams WHERE id = ? AND club_id = ? AND is_active = 1'
    );
    $teamStmt->execute([$teamId, $clubId]);
    $teamName = $teamStmt->fetchColumn() ?: null;
}

$playerWhere = [
    'cp.club_id = ?',
    'cp.is_active = 1',
    "(cp.player_type IS NULL OR cp.player_type = 'club')",
];
$playerParams = [$clubId];
if ($teamId !== null) {
    $playerWhere[] = '(cp.team_id = ? OR (cp.team_id IS NULL AND cp.team_name = ?))';
    $playerParams[] = $teamId;
    $playerParams[] = $teamName;
}
$playerStmt = $pdo->prepare(
    'SELECT cp.*, COALESCE(cp.team_id, ct.id) AS resolved_team_id
     FROM club_players cp
     LEFT JOIN club_teams ct
       ON ct.club_id = cp.club_id AND ct.name = cp.team_name AND ct.is_active = 1
     WHERE ' . implode(' AND ', $playerWhere) . '
     ORDER BY cp.name ASC, cp.id ASC'
);
$playerStmt->execute($playerParams);
$players = $playerStmt->fetchAll(PDO::FETCH_ASSOC);
$scopedPlayerIds = array_values(array_unique(array_map(
    'strval',
    array_column($players, 'id')
)));

$from = date('Y-m-d', strtotime('-365 days'));
$to = date('Y-m-d', strtotime('+365 days'));
$sessionWhere = ['cs.club_id = ?', 'cs.date BETWEEN ? AND ?'];
$sessionParams = [$clubId, $from, $to];
if ($teamId !== null) {
    $sessionWhere[] = '(cs.team_id = ? OR (cs.team_id IS NULL AND cs.team_name = ?))';
    $sessionParams[] = $teamId;
    $sessionParams[] = $teamName;
}
$sessionStmt = $pdo->prepare(
    "SELECT cs.*,
            (SELECT COUNT(*)
             FROM session_attendance sa
             WHERE sa.session_id = cs.id
               AND sa.status IN ('present', 'late')) AS attendance_present_count
     FROM club_sessions cs
     WHERE " . implode(' AND ', $sessionWhere) . '
     ORDER BY cs.date ASC, cs.start_time ASC, cs.id ASC
     LIMIT 400'
);
$sessionStmt->execute($sessionParams);
$sessions = array_map('normalizeSessionRow', $sessionStmt->fetchAll(PDO::FETCH_ASSOC));

$matchStmt = $pdo->prepare(
    'SELECT * FROM matches
     WHERE club_id = ? AND match_date BETWEEN ? AND ?
     ORDER BY match_date ASC, match_time ASC, id ASC
     LIMIT 400'
);
$matchStmt->execute([$clubId, $from, $to]);
$matches = [];
foreach ($matchStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
    $match = normalizeMatchRow($row);
    if ($teamId !== null) {
        $matchPlayerIds = $match['player_ids'];
        if (!$matchPlayerIds || !array_intersect($matchPlayerIds, $scopedPlayerIds)) {
            continue;
        }
    }
    $matches[] = $match;
}

jsonOut([
    'success' => true,
    'profile' => [
        'user_id' => (int)$user['id'],
        'name' => (string)($user['name'] ?? ''),
        'club_id' => $clubId,
        'club_name' => $clubName,
        'team_id' => $teamId,
        'team_name' => $teamName,
        'staff_role' => $ctx['staff_role'],
    ],
    'players' => $players,
    'sessions' => $sessions,
    'matches' => $matches,
    'range' => ['from' => $from, 'to' => $to],
]);
