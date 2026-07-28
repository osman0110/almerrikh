<?php
// GET /api/club/session_assessments.php?session_id=xxx
// Returns all assessments linked to a specific session.
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../includes/club_auth.php';

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
    if (!$token) { http_response_code(401); echo json_encode(['error' => 'Unauthorized']); exit; }
    $stmt = $pdo->prepare('SELECT u.id, u.name FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())');
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) { http_response_code(401); echo json_encode(['error' => 'Invalid token']); exit; }
    return $user;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

$user      = getAuthUser($pdo);
$ctx       = requireClubPermission($pdo, $user, 'assessments.read');
$sessionId = trim($_GET['session_id'] ?? '');
$limit     = min((int)($_GET['limit'] ?? 100), 200);

if (!$sessionId) {
    http_response_code(400);
    echo json_encode(['error' => 'session_id is required']);
    exit;
}

$stmt = $pdo->prepare(
    'SELECT a.id, a.player_id, a.player_name, a.type, a.session_id,
            a.overall_score, a.movement_quality_score, a.stability_score,
            a.symmetry_score, a.control_score, a.quality_score,
            a.issues_json, a.tips_json, a.angle_metrics_json, a.notes, a.created_at
     FROM assessments a
     JOIN club_players cp ON cp.id = a.player_id AND cp.club_id = a.club_id
     LEFT JOIN club_teams ct
       ON ct.club_id = cp.club_id AND ct.name = cp.team_name AND ct.is_active = 1
     WHERE a.club_id = ? AND a.session_id = ?' .
     ($ctx['team_id'] !== null ? ' AND COALESCE(cp.team_id, ct.id) = ?' : '') . '
     ORDER BY a.created_at DESC
     LIMIT ' . $limit
);
$stmt->execute([
    $ctx['club_id'],
    $sessionId,
    ...($ctx['team_id'] !== null ? [(int)$ctx['team_id']] : []),
]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

foreach ($rows as &$row) {
    $row['issues']  = json_decode($row['issues_json']       ?? '[]', true) ?? [];
    $row['tips']    = json_decode($row['tips_json']         ?? '[]', true) ?? [];
    $row['metrics'] = json_decode($row['angle_metrics_json']?? '{}', true) ?? [];
    $row['overall_score']          = (int)$row['overall_score'];
    $row['movement_quality_score'] = (int)($row['movement_quality_score'] ?? 0);
    $row['stability_score']        = (int)($row['stability_score'] ?? 0);
    $row['symmetry_score']         = (int)($row['symmetry_score'] ?? 0);
    $row['control_score']          = (int)($row['control_score'] ?? 0);
    $row['quality_score']          = (int)($row['quality_score'] ?? 0);
    unset($row['issues_json'], $row['tips_json'], $row['angle_metrics_json']);
}
unset($row);

echo json_encode([
    'assessments' => $rows,
    'count'       => count($rows),
    'session_id'  => $sessionId,
], JSON_UNESCAPED_UNICODE);
