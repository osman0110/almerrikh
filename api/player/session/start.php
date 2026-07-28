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
        'SELECT u.id, u.role, u.linked_player_id, u.club_user_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);
$body = json_decode(file_get_contents('php://input'), true) ?? [];

if (!isset($body['session_id'])) jsonOut(['error' => 'session_id is required'], 400);
$sessionId = (string)$body['session_id'];

// Fetch session_players row — verifies this player is assigned
$sp = $pdo->prepare(
    'SELECT id, status FROM session_players WHERE session_id = ? AND player_user_id = ?'
);
$sp->execute([$sessionId, $user['id']]);
$spRow = $sp->fetch();

if (!$spRow) jsonOut(['error' => 'Session not assigned to you'], 403);

if (in_array($spRow['status'], ['completed', 'missed'], true)) {
    jsonOut(['error' => 'Session already ' . $spRow['status']], 400);
}

// Fetch session settings
$sess = $pdo->prepare('SELECT wellness_required FROM training_sessions WHERE id = ?');
$sess->execute([$sessionId]);
$sessRow = $sess->fetch();

$wellnessRequired = $sessRow ? (bool)$sessRow['wellness_required'] : true; // safe default

// Block start if wellness required but pre-check not done yet
if ($wellnessRequired && $spRow['status'] === 'assigned') {
    jsonOut([
        'error' => 'Pre-training wellness check required before starting',
        'code'  => 'wellness_required',
    ], 400);
}

// Determine which statuses are valid to transition from:
// - wellness_required=1 → must be pre_checked
// - wellness_required=0 → can start from assigned or pre_checked
$allowedFrom = $wellnessRequired ? ['pre_checked'] : ['assigned', 'pre_checked'];

if (!in_array($spRow['status'], $allowedFrom, true)) {
    jsonOut(['error' => 'Cannot start session from status: ' . $spRow['status']], 400);
}

$placeholders = implode(',', array_fill(0, count($allowedFrom), '?'));
$pdo->prepare(
    "UPDATE session_players SET status = 'started', started_at = NOW()
     WHERE session_id = ? AND player_user_id = ? AND status IN ($placeholders)"
)->execute(array_merge([$sessionId, $user['id']], $allowedFrom));

// Mark training_session as in_progress if still draft/assigned
$pdo->prepare(
    "UPDATE training_sessions SET status = 'in_progress', updated_at = NOW()
     WHERE id = ? AND status IN ('draft','assigned')"
)->execute([$sessionId]);

jsonOut(['success' => true, 'session_id' => $sessionId]);
