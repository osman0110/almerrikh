<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';
require_once '../includes/club_auth.php';

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
        'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
if (in_array($user['role'], ['player', 'parent'], true)) {
    jsonOut(['error' => 'Forbidden — coaches only'], 403);
}
$ctx = requireClubPermission($pdo, $user, 'players.read');

// Fetch players — coaches only see club players, never independent
$playerSql = "SELECT * FROM club_players
              WHERE club_id = ? AND is_active = 1
                AND (player_type IS NULL OR player_type = 'club')";
$playerParams = [$ctx['club_id']];
if (($ctx['team_id'] ?? null) !== null) {
    $playerSql .= ' AND team_id = ?';
    $playerParams[] = $ctx['team_id'];
}
$playerSql .= ' ORDER BY name ASC';
$stmt = $pdo->prepare($playerSql);
$stmt->execute($playerParams);
$players = $stmt->fetchAll();

if (empty($players)) {
    jsonOut(['players' => []]);
}

// Fetch latest assessment per player
$playerIds = array_column($players, 'id');
$inPlaceholders = implode(',', array_fill(0, count($playerIds), '?'));

$stmt = $pdo->prepare("
    SELECT a.player_id, a.overall_score, a.type, a.created_at
    FROM assessments a
    INNER JOIN (
        SELECT player_id, MAX(created_at) AS max_date
        FROM assessments
        WHERE club_id = ? AND player_id IN ($inPlaceholders)
        GROUP BY player_id
    ) latest ON a.player_id = latest.player_id AND a.created_at = latest.max_date
    WHERE a.club_id = ?
");
$stmt->execute(array_merge([$ctx['club_id']], $playerIds, [$ctx['club_id']]));
$assessments = [];
foreach ($stmt->fetchAll() as $row) {
    $assessments[$row['player_id']] = $row;
}

// Build response
$result = [];
foreach ($players as $p) {
    $assessment = $assessments[$p['id']] ?? null;
    $aiScore    = $assessment ? (int)$assessment['overall_score'] : null;
    $aiType     = $assessment ? $assessment['type']               : null;
    $hasInjury  = !empty(trim($p['injury_notes'] ?? ''));

    $status = 'ready';
    if ($hasInjury) $status = 'injured';

    $result[] = [
        'id'             => $p['id'],
        'number'         => $p['number'] ?? null,
        'name'           => $p['name'],
        'position'       => $p['position']     ?? '—',
        'team'           => $p['team_name']    ?? '',
        'height_cm'      => $p['height_cm'] !== null ? (float)$p['height_cm'] : null,
        'weight_kg'      => $p['weight_kg'] !== null ? (float)$p['weight_kg'] : null,
        'dominant_foot'  => $p['dominant_foot'] ?? null,
        'injury_notes'   => $p['injury_notes'] ?? null,
        'photo_url'      => $p['photo_url']    ?? null,
        'status'         => $status,
        'readiness_pct'  => null,
        'readiness_status' => 'NO_DATA',
        'load_pct'       => null,
        'load_status'    => 'NO_DATA',
        'attendance_pct' => null,
        'attendance_status' => 'NO_DATA',
        'ai_score'       => $aiScore,
        'ai_type'        => $aiType,
        'injury_flag'    => $hasInjury,
        'last_session'   => null,
    ];
}

jsonOut(['players' => $result]);
