<?php
require_once dirname(__DIR__, 2) . '/db.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonError('Method not allowed', 405);

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
        'SELECT u.id FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ?'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
$body = json_decode(file_get_contents('php://input'), true) ?? [];

if (!isset($body['rpe_score'])) jsonOut(['error' => 'rpe_score is required'], 400);
if (!isset($body['duration_minutes'])) jsonOut(['error' => 'duration_minutes is required'], 400);

$rpe      = (int)$body['rpe_score'];
$duration = (int)$body['duration_minutes'];

if ($rpe < 1 || $rpe > 10) jsonOut(['error' => 'rpe_score must be 1–10'], 400);
if ($duration < 1 || $duration > 480) jsonOut(['error' => 'duration_minutes must be 1–480'], 400);

$load        = $rpe * $duration;
$notes       = isset($body['notes']) ? substr((string)$body['notes'], 0, 500) : null;
$sessionId   = isset($body['training_session_id']) ? (string)$body['training_session_id'] : null;
$sessionType = isset($body['session_type']) ? substr((string)$body['session_type'], 0, 50) : null;

$stmt = $pdo->prepare(
    'INSERT INTO player_rpe
     (user_id, training_session_id, session_type, rpe_score, duration_minutes, training_load, notes)
     VALUES (?, ?, ?, ?, ?, ?, ?)'
);
$stmt->execute([$user['id'], $sessionId, $sessionType, $rpe, $duration, $load, $notes]);
$id = (int)$pdo->lastInsertId();

jsonOut(['success' => true, 'id' => $id, 'training_load' => $load]);
