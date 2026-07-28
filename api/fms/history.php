<?php
require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

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
        'SELECT u.id, u.role, u.player_type, u.linked_player_id FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
$isPlayer = !empty($user['player_type']) || $user['role'] === 'player';

if ($isPlayer) {
    // Players may only ever see their OWN FMS history, from the server-known link
    $playerId = $user['linked_player_id'] ?? null;
    if (!$playerId) jsonOut(['history' => []]);
} else {
    $playerId = trim($_GET['player_id'] ?? '');
    if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);
    // Ownership check — scoped to the caller's club, not just the owner account
    $ctx = requireClubPermission($pdo, $user, 'assessments.read');
    $ownerStmt = $pdo->prepare(
        'SELECT cp.id FROM club_players cp
         LEFT JOIN club_teams ct
           ON ct.club_id = cp.club_id AND ct.name = cp.team_name AND ct.is_active = 1
         WHERE cp.id = ? AND cp.club_id = ?' .
         ($ctx['team_id'] !== null ? ' AND COALESCE(cp.team_id, ct.id) = ?' : '')
    );
    $ownerStmt->execute([
        $playerId,
        $ctx['club_id'],
        ...($ctx['team_id'] !== null ? [(int)$ctx['team_id']] : []),
    ]);
    if (!$ownerStmt->fetch()) jsonOut(['error' => 'Forbidden — player not in your club'], 403);
}

$limit = min(30, max(1, (int)($_GET['limit'] ?? 10)));

$stmt = $pdo->prepare(
    'SELECT * FROM fms_assessments WHERE player_id = ? ORDER BY created_at DESC LIMIT ?'
);
$stmt->execute([$playerId, $limit]);
$assessments = $stmt->fetchAll(PDO::FETCH_ASSOC);

if ($assessments) {
    $ids = array_column($assessments, 'id');
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $mStmt = $pdo->prepare(
        "SELECT * FROM fms_movement_scores WHERE assessment_id IN ($placeholders)"
    );
    $mStmt->execute($ids);
    $byAssessment = [];
    foreach ($mStmt->fetchAll(PDO::FETCH_ASSOC) as $m) {
        $m['left_score']  = $m['left_score']  !== null ? (int)$m['left_score']  : null;
        $m['right_score'] = $m['right_score'] !== null ? (int)$m['right_score'] : null;
        $m['final_score'] = (int)$m['final_score'];
        $m['pain']        = (bool)$m['pain'];
        $byAssessment[$m['assessment_id']][] = $m;
    }
    foreach ($assessments as &$a) {
        $a['total_score'] = (int)$a['total_score'];
        $a['movements'] = $byAssessment[$a['id']] ?? [];
    }
    unset($a);
}

jsonOut(['history' => $assessments, 'count' => count($assessments)]);
