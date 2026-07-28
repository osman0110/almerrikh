<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once 'db.php';

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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonOut(['error' => 'Method not allowed'], 405);
}

// Auth check
$token = bearerToken();
if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8mb4", $username, $password, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $stmt = $pdo->prepare('SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())');
    $stmt->execute([$token]);
    $authUser = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$authUser) jsonOut(['error' => 'Invalid token'], 401);
    // Player accounts upload their own avatar elsewhere; this endpoint is for
    // club staff attaching a roster player's photo, not open to any token holder.
    if (in_array($authUser['role'] ?? '', ['player', 'parent'], true)) {
        jsonOut(['error' => 'Forbidden'], 403);
    }
} catch (Exception $e) {
    jsonOut(['error' => 'DB error'], 500);
}

if (!isset($_FILES['photo']) || $_FILES['photo']['error'] !== UPLOAD_ERR_OK) {
    jsonOut(['error' => 'No photo uploaded'], 400);
}

$file = $_FILES['photo'];
$ext  = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'])) {
    jsonOut(['error' => 'Invalid file type'], 400);
}
if ($file['size'] > 5 * 1024 * 1024) {
    jsonOut(['error' => 'File too large (max 5MB)'], 400);
}

$uploadDir = __DIR__ . '/../uploads/players/';
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0755, true);
}

$filename = 'player_' . uniqid('', true) . '.' . $ext;
$dest = $uploadDir . $filename;

if (!move_uploaded_file($file['tmp_name'], $dest)) {
    jsonOut(['error' => 'Upload failed'], 500);
}

// Build public URL
$isLocal = strpos($_SERVER['HTTP_HOST'], 'localhost') !== false;
$appRoot = $isLocal ? '/merr' : '';
$scheme  = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ? 'https' : 'http';
$url = $scheme . '://' . $_SERVER['HTTP_HOST'] . $appRoot . '/uploads/players/' . $filename;

jsonOut(['success' => true, 'url' => $url]);
