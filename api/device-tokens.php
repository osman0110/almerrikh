<?php
/**
 * FCM device token registration — lets push.php find where to send a user's
 * notifications. Written to by the Flutter app on sign-in / token refresh,
 * and best-effort cleared on logout.
 *
 * POST action=register, token=X, platform=android|ios, club_id=Y (optional)
 * POST action=unregister, token=X
 * POST action=status  — this user's registered devices (diagnostics screen)
 * POST action=test    — send a test push to this user's devices and return
 *                       FCM's raw answer per device (diagnostics screen)
 * POST action=diag    — log a client-side registration report to error_log
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/includes/push.php';

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
    if (!$token) jsonOut(['success' => false, 'message' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.club_id FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
}

$user   = getAuthUser($pdo);
$body   = json_decode(file_get_contents('php://input'), true) ?? [];
$action = trim($body['action'] ?? 'register');
$token  = trim($body['token'] ?? '');

// Client-side push registration report (iOS debugging) — log only, no token needed.
if ($action === 'diag') {
    error_log('[push-diag] user ' . $user['id'] . ': ' . substr(json_encode($body['diag'] ?? null, JSON_UNESCAPED_UNICODE), 0, 1000));
    jsonOut(['success' => true]);
}

// Diagnostics: only ever about the caller's own devices.
if ($action === 'status') {
    $stmt = $pdo->prepare(
        'SELECT platform, CONCAT(LEFT(token, 12), "…") AS token_prefix, created_at, updated_at
         FROM device_tokens WHERE user_id = ? ORDER BY updated_at DESC'
    );
    $stmt->execute([$user['id']]);
    jsonOut([
        'success'         => true,
        'user_id'         => (int)$user['id'],
        'fcm_credentials' => is_file(fcmServiceAccountPath()),
        'devices'         => $stmt->fetchAll(PDO::FETCH_ASSOC),
    ]);
}

if ($action === 'test') {
    $auth = getFcmAccessToken();
    if (!$auth) jsonOut(['success' => false, 'message' => 'FCM credentials missing on server'], 500);
    $stmt = $pdo->prepare('SELECT platform, token FROM device_tokens WHERE user_id = ?');
    $stmt->execute([$user['id']]);
    $results = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $outcome = fcmSendToToken($auth['access_token'], $auth['project_id'], $row['token'],
            'Test notification', 'If you see this, push works on this device.',
            ['linked_route' => '']);
        $results[] = [
            'platform'     => $row['platform'],
            'token_prefix' => substr($row['token'], 0, 12) . '…',
            'outcome'      => $outcome,
            'fcm_response' => substr((string)($GLOBALS['fcm_last_response'] ?? ''), 0, 600),
        ];
    }
    error_log('[push-test] user ' . $user['id'] . ': ' . json_encode(array_column($results, 'outcome')));
    jsonOut(['success' => true, 'project_id' => $auth['project_id'], 'results' => $results]);
}

if (!$token) jsonOut(['success' => false, 'message' => 'token is required'], 400);

if ($action === 'unregister') {
    $pdo->prepare('DELETE FROM device_tokens WHERE token = ? AND user_id = ?')
        ->execute([$token, $user['id']]);
    jsonOut(['success' => true]);
}

if ($action === 'register') {
    $platform = trim($body['platform'] ?? 'android');
    $clubId   = $body['club_id'] ?? $user['club_id'] ?? null;

    $pdo->prepare(
        'INSERT INTO device_tokens (user_id, club_id, token, platform)
         VALUES (?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), club_id = VALUES(club_id),
             platform = VALUES(platform), updated_at = CURRENT_TIMESTAMP'
    )->execute([$user['id'], $clubId, $token, $platform]);
    error_log('[push] registered ' . $platform . ' token for user ' . $user['id']);

    jsonOut(['success' => true]);
}

jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
