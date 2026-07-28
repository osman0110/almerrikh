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

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

    $stmt = $pdo->prepare(
        'SELECT u.id, u.name, u.email, u.phone FROM users u
         JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $user = getAuthUser($pdo);

    $stmt = $pdo->prepare('SELECT * FROM user_profiles WHERE user_id = ?');
    $stmt->execute([$user['id']]);
    $profile = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($profile && isset($profile['weaknesses'])) {
        $profile['weaknesses'] = json_decode($profile['weaknesses'], true) ?? [];
    }

    jsonOut(['user' => $user, 'profile' => $profile ?: null]);

} elseif ($method === 'POST') {
    $user = getAuthUser($pdo);
    $body = json_decode(file_get_contents('php://input'), true) ?? [];

    $playerName = trim($body['player_name'] ?? $user['name']);
    $age        = (int) ($body['age'] ?? 16);
    $position   = $body['position'] ?? null;
    $foot       = $body['foot'] ?? null;
    $trainingPath = $body['training_path'] ?? null;
    $height     = (float) ($body['height'] ?? 0);
    $weight     = (float) ($body['weight'] ?? 0);
    $gender     = $body['gender'] ?? null;
    $fitnessLevel = $body['fitness_level'] ?? null;
    $skillLevel = $body['skill_level'] ?? null;
    $goal       = $body['goal'] ?? null;
    $daysPerWeek = (int) ($body['days_per_week'] ?? 3);
    $injury     = $body['injury_limitations'] ?? null;
    $duration   = (int) ($body['preferred_duration'] ?? 30);
    $weaknesses = json_encode($body['weaknesses'] ?? []);

    $stmt = $pdo->prepare(
        'INSERT INTO user_profiles (user_id, player_name, age, position, foot, training_path, height, weight, gender, fitness_level, skill_level, goal, days_per_week, injury_limitations, preferred_duration, weaknesses)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
             player_name = VALUES(player_name),
             age         = VALUES(age),
             position    = VALUES(position),
             foot        = VALUES(foot),
             training_path = VALUES(training_path),
             height      = VALUES(height),
             weight      = VALUES(weight),
             gender      = VALUES(gender),
             fitness_level = VALUES(fitness_level),
             skill_level = VALUES(skill_level),
             goal        = VALUES(goal),
             days_per_week = VALUES(days_per_week),
             injury_limitations = VALUES(injury_limitations),
             preferred_duration = VALUES(preferred_duration),
             weaknesses  = VALUES(weaknesses),
             updated_at  = CURRENT_TIMESTAMP'
    );
    $stmt->execute([$user['id'], $playerName, $age, $position, $foot, $trainingPath, $height, $weight, $gender, $fitnessLevel, $skillLevel, $goal, $daysPerWeek, $injury, $duration, $weaknesses]);

    jsonOut(['success' => true]);

} else {
    jsonOut(['error' => 'Method not allowed'], 405);
}
