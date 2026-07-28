<?php
/**
 * GET /api/player/my-daily-status.php?date=YYYY-MM-DD
 * Read-only: the authenticated player's own participation decision for the
 * day (fully_available / modified_training / unavailable), plus whether a
 * physio session or nutrition compliance entry exists for that day. Never
 * exposes diagnosis, clinical notes, or other players' data.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';

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
        'SELECT u.id, u.role FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);

$date = trim($_GET['date'] ?? date('Y-m-d'));

$stmt = $pdo->prepare(
    "SELECT id, status, unavailable_reason, expected_return_date FROM club_players
     WHERE linked_user_id = ? AND is_active = 1 AND player_type = 'club'
     ORDER BY created_at DESC LIMIT 1"
);
$stmt->execute([$user['id']]);
$player = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$player) {
    jsonOut(['date' => $date, 'decision' => null, 'status' => null, 'physio_today' => null, 'nutrition_status_today' => null]);
}

$stmt = $pdo->prepare(
    'SELECT participation_status, allowed_duration_minutes, restrictions
     FROM player_daily_decisions WHERE player_id = ? AND decision_date = ?'
);
$stmt->execute([$player['id'], $date]);
$decision = $stmt->fetch(PDO::FETCH_ASSOC);

$stmt = $pdo->prepare(
    'SELECT status FROM physio_sessions WHERE player_id = ? AND DATE(scheduled_at) = ? LIMIT 1'
);
$stmt->execute([$player['id'], $date]);
$physioToday = $stmt->fetchColumn();

$stmt = $pdo->prepare(
    'SELECT status FROM nutrition_compliance_logs WHERE player_id = ? AND log_date = ?'
);
$stmt->execute([$player['id'], $date]);
$nutritionToday = $stmt->fetchColumn();

jsonOut([
    'date'   => $date,
    'status' => $player['status'],
    'unavailable_reason' => $player['unavailable_reason'],
    'expected_return_date' => $player['expected_return_date'],
    'decision' => $decision ? [
        'participation_status'     => $decision['participation_status'],
        'allowed_duration_minutes' => $decision['allowed_duration_minutes'] !== null
            ? (int)$decision['allowed_duration_minutes'] : null,
        'restrictions'             => $decision['restrictions'],
    ] : null,
    'physio_today'           => $physioToday ?: null,
    'nutrition_status_today' => $nutritionToday ?: null,
]);
