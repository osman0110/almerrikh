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
        'SELECT u.id FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
$ctx = requireClubPermission($pdo, $user, 'players.read');
$clubId = (int)$ctx['club_id'];

$stmt = $pdo->prepare(
    'SELECT id, name, position, injury_notes FROM club_players
     WHERE club_id = ? AND is_active = 1 ORDER BY name ASC LIMIT 20'
);
$stmt->execute([$clubId]);
$players = $stmt->fetchAll();

// Get latest AI score per player
$playerIds = array_column($players, 'id');
$aiScores  = [];

if (!empty($playerIds)) {
    $in = implode(',', array_fill(0, count($playerIds), '?'));
    $stmt = $pdo->prepare("
        SELECT a.player_id, a.overall_score
        FROM assessments a
        INNER JOIN (
            SELECT player_id, MAX(created_at) AS max_date
            FROM assessments
            WHERE club_id = ? AND player_id IN ($in)
            GROUP BY player_id
        ) latest ON a.player_id = latest.player_id AND a.created_at = latest.max_date
        WHERE a.club_id = ?
    ");
    $stmt->execute(array_merge([$clubId], $playerIds, [$clubId]));
    foreach ($stmt->fetchAll() as $row) {
        $aiScores[$row['player_id']] = (int)$row['overall_score'];
    }
}

$result = [];
foreach ($players as $p) {
    $hasInjury = !empty(trim($p['injury_notes'] ?? ''));
    $status    = $hasInjury ? 'injured' : 'ready';
    $loadPct   = $hasInjury ? 0 : 50;

    $result[] = [
        'number'   => 0,
        'name'     => $p['name'],
        'position' => $p['position'] ?? '—',
        'load_pct' => $loadPct,
        'status'   => $status,
        'ai_score' => $aiScores[$p['id']] ?? 0,
    ];
}

echo json_encode($result, JSON_UNESCAPED_UNICODE);
