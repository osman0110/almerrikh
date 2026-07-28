<?php
require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';
require_once dirname(__DIR__) . '/includes/fitness/ActiveSeasonResolver.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

$authorization = $_SERVER['HTTP_AUTHORIZATION']
    ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
    ?? $_SERVER['Authorization']
    ?? '';
if (stripos($authorization, 'Bearer ') === 0) $authorization = trim(substr($authorization, 7));
if (!$authorization) jsonError('Unauthorized', 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.role
     FROM users u JOIN user_tokens t ON t.user_id = u.id
     WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$authorization]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$user) jsonError('Invalid or expired token', 401);

$ctx = requireClubPermission($pdo, $user, 'players.read');
$season = ActiveSeasonResolver::resolve(
    $pdo,
    (int)$ctx['club_id'],
    $ctx['team_id'] ?? null
);
if (!$season) {
    http_response_code(409);
    echo json_encode([
        'error' => 'NO_ACTIVE_SEASON',
        'message' => 'The administration must configure an active season.',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

echo json_encode(['season' => $season], JSON_UNESCAPED_UNICODE);
