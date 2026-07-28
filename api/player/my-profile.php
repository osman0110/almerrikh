<?php
/**
 * GET /api/mobile/player/my-profile.php
 * Returns the club_players record for the authenticated player (independent or club).
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';
require_once '../includes/fitness/BodyCompositionRepository.php';

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
        'SELECT u.id, u.name, u.role, u.player_type, u.linked_player_id, u.club_user_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid token'], 401);
    return $user;
}

$user = getAuthUser($pdo);

// Find player record — either linked explicitly or owned directly
$stmt = $pdo->prepare(
    'SELECT cp.*
     FROM club_players cp
     WHERE (cp.linked_user_id = ? OR (cp.user_id = ? AND cp.player_type = "independent"))
       AND cp.is_active = 1
     ORDER BY cp.created_at DESC
     LIMIT 1'
);
$stmt->execute([$user['id'], $user['id']]);
$player = $stmt->fetch();

// Unified approved new-system measurement, then legacy fallback.
$metrics = BodyCompositionRepository::latestForPlayer(
    $pdo,
    $player ? $player['id'] : ($user['linked_player_id'] ?? null),
    (int)$user['id'],
    true
);
if ($metrics) {
    $metrics['body_fat_percent'] = $metrics['body_fat_percentage'];
    $metrics['bmi'] = $metrics['raw']['bmi'] ?? null;
}

// Fetch latest Hooper
$hooperStmt = $pdo->prepare(
    'SELECT hooper_score, submitted_at FROM player_hooper_index WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 1'
);
$hooperStmt->execute([$user['id']]);
$hooper = $hooperStmt->fetch() ?: null;

// Fetch latest assessment score
$assStmt = $pdo->prepare(
    'SELECT overall_score, type, created_at FROM assessments WHERE user_id = ? ORDER BY created_at DESC LIMIT 1'
);
$assStmt->execute([$user['id']]);
$assessment = $assStmt->fetch() ?: null;

jsonOut([
    'user' => [
        'id'          => (int)$user['id'],
        'name'        => $user['name'],
        'role'        => $user['role']             ?? 'player',
        'player_type' => $user['player_type']      ?? 'independent',
        'club_user_id'=> $user['club_user_id'] ? (int)$user['club_user_id'] : null,
    ],
    'player'     => $player ?: null,
    'metrics'    => $metrics,
    'hooper'     => $hooper,
    'assessment' => $assessment,
]);
