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

$fields = ['sleep_quality', 'fatigue', 'stress', 'muscle_soreness'];
foreach ($fields as $f) {
    if (!isset($body[$f])) jsonOut(['error' => "$f is required"], 400);
    $v = (int)$body[$f];
    if ($v < 1 || $v > 7) jsonOut(['error' => "$f must be 1–7"], 400);
}

$sleepQ   = (int)$body['sleep_quality'];
$fatigue  = (int)$body['fatigue'];
$stress   = (int)$body['stress'];
$soreness = (int)$body['muscle_soreness'];
$hooper   = $sleepQ + $fatigue + $stress + $soreness;

$sleepHours = isset($body['sleep_hours']) ? (float)$body['sleep_hours'] : null;
if ($sleepHours !== null && ($sleepHours < 0 || $sleepHours > 24))
    jsonOut(['error' => 'sleep_hours must be 0–24'], 400);

$notes     = isset($body['notes']) ? substr((string)$body['notes'], 0, 500) : null;
$sessionId = isset($body['training_session_id']) ? (string)$body['training_session_id'] : null;

$stmt = $pdo->prepare(
    'INSERT INTO player_hooper_index
     (user_id, training_session_id, sleep_quality, fatigue, stress, muscle_soreness, sleep_hours, hooper_score, notes)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
);
$stmt->execute([$user['id'], $sessionId, $sleepQ, $fatigue, $stress, $soreness, $sleepHours, $hooper, $notes]);
$id = (int)$pdo->lastInsertId();

// Determine wellness status
$status = $hooper <= 10 ? 'normal' : ($hooper <= 16 ? 'moderate' : 'high_risk');

jsonOut(['success' => true, 'id' => $id, 'hooper_score' => $hooper, 'status' => $status]);
