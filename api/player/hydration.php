<?php
/**
 * Player self-service hydration log — daily ml water intake.
 * Distinct from nutrition_profiles.fluid_target_ml (the target) and
 * nutrition_day_plans.hydration_before/during/after (free-text instructions)
 * — this is the actual logged amount, one row per day (upserted on repeat).
 *
 * GET  ?days=14       — own recent history (default 14 days)
 * POST                 — log today's (or a given date's) intake { amount_ml, log_date? }
 */
require_once dirname(__DIR__) . '/db.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
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
        'SELECT u.id, u.role, u.linked_player_id FROM users u
         JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
$linkedPlayerId = $user['linked_player_id'] ?? null;
if (!$linkedPlayerId) jsonOut(['error' => 'This account is not linked to a club player profile'], 403);

$playerStmt = $pdo->prepare('SELECT club_id FROM club_players WHERE id = ?');
$playerStmt->execute([$linkedPlayerId]);
$clubId = $playerStmt->fetchColumn();
if (!$clubId) jsonOut(['error' => 'Player profile not found'], 404);

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $days = min(90, max(1, (int)($_GET['days'] ?? 14)));
    $stmt = $pdo->prepare(
        'SELECT log_date, amount_ml FROM hydration_logs
         WHERE player_id = ? AND log_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
         ORDER BY log_date DESC'
    );
    $stmt->execute([$linkedPlayerId, $days]);
    jsonOut(['success' => true, 'logs' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($method === 'POST') {
    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $amountMl = (int)($body['amount_ml'] ?? 0);
    if ($amountMl <= 0 || $amountMl > 15000) jsonOut(['error' => 'amount_ml must be 1-15000'], 400);

    $logDate = trim($body['log_date'] ?? '') ?: date('Y-m-d');
    if (!DateTime::createFromFormat('Y-m-d', $logDate)) jsonOut(['error' => 'log_date must be YYYY-MM-DD'], 400);

    $pdo->prepare(
        'INSERT INTO hydration_logs (club_id, player_id, log_date, amount_ml, logged_by_user_id)
         VALUES (?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE amount_ml = VALUES(amount_ml), logged_by_user_id = VALUES(logged_by_user_id)'
    )->execute([$clubId, $linkedPlayerId, $logDate, $amountMl, $user['id']]);

    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
