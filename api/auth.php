<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once 'db.php';

$action = $_GET['action'] ?? '';
$body = json_decode(file_get_contents('php://input'), true) ?? [];

function generateToken(): string {
    return bin2hex(random_bytes(32));
}

function jsonOut(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function bearerToken(): string {
    $auth = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? $_SERVER['Authorization']
        ?? '';

    if (!$auth && function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    }

    if (stripos($auth, 'Bearer ') === 0) {
        return trim(substr($auth, 7));
    }

    return trim($auth);
}

function normalizePhone(string $phone): string {
    return preg_replace('/[^\d+]/', '', trim($phone));
}

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

    $stmt = $pdo->prepare(
        'SELECT u.id, u.name, u.email, u.phone FROM users u
         JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ?'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

switch ($action) {

    case 'register':
        $name     = trim($body['name'] ?? '');
        $email    = strtolower(trim($body['email'] ?? ''));
        $phone    = normalizePhone($body['phone'] ?? '');
        $password = $body['password'] ?? '';

        if (!$name || !$email || !$phone || !$password) {
            jsonOut(['error' => 'All fields are required'], 400);
        }
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            jsonOut(['error' => 'Invalid email address'], 400);
        }
        if (strlen(preg_replace('/\D/', '', $phone)) < 8) {
            jsonOut(['error' => 'Invalid phone number'], 400);
        }
        if (strlen($password) < 6) {
            jsonOut(['error' => 'Password must be at least 6 characters'], 400);
        }

        $check = $pdo->prepare('SELECT id, email, phone FROM users WHERE email = ? OR phone = ?');
        $check->execute([$email, $phone]);
        if ($check->fetch()) {
            jsonOut(['error' => 'Email or phone is already registered'], 409);
        }

        $hash = password_hash($password, PASSWORD_BCRYPT);
        $ins  = $pdo->prepare('INSERT INTO users (name, email, phone, password_hash) VALUES (?, ?, ?, ?)');
        $ins->execute([$name, $email, $phone, $hash]);
        $userId = (int) $pdo->lastInsertId();

        $token = generateToken();
        $pdo->prepare('INSERT INTO user_tokens (token, user_id) VALUES (?, ?)')->execute([$token, $userId]);

        jsonOut([
            'token' => $token,
            'user'  => ['id' => $userId, 'name' => $name, 'email' => $email, 'phone' => $phone],
        ]);

    case 'login':
        $identifier = strtolower(trim($body['email'] ?? $body['login'] ?? ''));
        $phone      = normalizePhone($identifier);
        $password = $body['password'] ?? '';

        if (!$identifier || !$password) {
            jsonOut(['error' => 'Email/phone and password are required'], 400);
        }

        $stmt = $pdo->prepare(
            'SELECT id, name, email, phone, password_hash FROM users WHERE email = ? OR phone = ?'
        );
        $stmt->execute([$identifier, $phone]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$user || !password_verify($password, $user['password_hash'])) {
            jsonOut(['error' => 'Incorrect email or password'], 401);
        }

        $token = generateToken();
        $pdo->prepare('INSERT INTO user_tokens (token, user_id) VALUES (?, ?)')->execute([$token, $user['id']]);

        jsonOut([
            'token' => $token,
            'user'  => [
                'id' => (int) $user['id'],
                'name' => $user['name'],
                'email' => $user['email'],
                'phone' => $user['phone'],
            ],
        ]);

    case 'me':
        $user = getAuthUser($pdo);
        jsonOut(['user' => $user]);

    case 'logout':
        $token = bearerToken();
        if ($token) {
            $pdo->prepare('DELETE FROM user_tokens WHERE token = ?')->execute([$token]);
        }
        jsonOut(['success' => true]);

    default:
        jsonOut(['error' => 'Unknown action'], 400);
}
