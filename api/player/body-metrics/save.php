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
        'SELECT u.id, u.name FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ?'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
$body = json_decode(file_get_contents('php://input'), true) ?? [];

$weight = isset($body['weight_kg']) ? (float)$body['weight_kg'] : null;
$height = isset($body['height_cm']) ? (float)$body['height_cm'] : null;
$fat    = isset($body['body_fat_percent']) ? (float)$body['body_fat_percent'] : null;

if ($weight === null || $height === null || $fat === null)
    jsonOut(['error' => 'weight_kg, height_cm, body_fat_percent are required'], 400);
if ($weight < 20 || $weight > 300)
    jsonOut(['error' => 'weight_kg must be 20–300'], 400);
if ($height < 100 || $height > 250)
    jsonOut(['error' => 'height_cm must be 100–250'], 400);
if ($fat < 1 || $fat > 60)
    jsonOut(['error' => 'body_fat_percent must be 1–60'], 400);

$heightM = $height / 100;
$bmi = round($weight / ($heightM * $heightM), 2);

$stmt = $pdo->prepare(
    'INSERT INTO player_body_metrics (user_id, weight_kg, height_cm, body_fat_percent, bmi)
     VALUES (?, ?, ?, ?, ?)'
);
$stmt->execute([$user['id'], $weight, $height, $fat, $bmi]);
$id = (int)$pdo->lastInsertId();

jsonOut(['success' => true, 'id' => $id, 'bmi' => $bmi]);
