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
$ctx = requireClubPermission($pdo, $user, 'players.read');
$clubId = (int)$ctx['club_id'];
if (in_array($user['role'], ['player', 'parent'], true)) {
    jsonOut(['error' => 'Forbidden — coaches only'], 403);
}

$stmt = $pdo->prepare(
    'SELECT id, name, injury_notes FROM club_players
     WHERE club_id = ? AND is_active = 1 AND injury_notes IS NOT NULL AND injury_notes != ""'
);
$stmt->execute([$clubId]);
$injured = $stmt->fetchAll();

$alerts = [];
foreach ($injured as $idx => $p) {
    $alerts[] = [
        'id'          => 'alert-injury-' . $p['id'],
        'priority'    => 1,
        'type'        => 'injury_risk',
        'title'       => 'إصابة — ' . $p['name'],
        'description' => $p['injury_notes'],
        'minutes_ago' => 0,
    ];
}

// No load/wellness data available yet without player accounts linked
echo json_encode($alerts, JSON_UNESCAPED_UNICODE);
