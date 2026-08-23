<?php
/**
 * GET /api/player/my-physio-sessions.php
 * Read-only: the authenticated player's own physiotherapy/massage sessions.
 * Never exposes other players' data — scoped to the caller's own club_players.id.
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

$stmt = $pdo->prepare(
    "SELECT id FROM club_players
     WHERE linked_user_id = ? AND is_active = 1 AND player_type = 'club'
     ORDER BY created_at DESC LIMIT 1"
);
$stmt->execute([$user['id']]);
$playerId = $stmt->fetchColumn();

if (!$playerId) jsonOut(['sessions' => []]);

$stmt = $pdo->prepare(
    'SELECT sp.id, s.scheduled_at, s.duration_minutes, s.room, s.body_area, s.session_reason,
            s.treatment_type, sp.status, sp.recommendation,
            COALESCE(cs.staff_role, u.role) AS therapist_role
     FROM physio_session_players sp
     JOIN physio_sessions s ON s.id = sp.session_id
     LEFT JOIN users u ON u.id = s.therapist_user_id
     LEFT JOIN club_staff cs ON cs.user_id = s.therapist_user_id
                            AND cs.club_id = s.club_id
                            AND cs.status = \'active\'
     WHERE sp.player_id = ?
     ORDER BY s.scheduled_at DESC
     LIMIT 30'
);
$stmt->execute([$playerId]);
$sessions = array_map(function ($s) {
    return [
        'id'               => (string)$s['id'],
        'scheduled_at'     => $s['scheduled_at'],
        'duration_minutes' => (int)$s['duration_minutes'],
        'room'             => $s['room'],
        'body_area'        => $s['body_area'],
        'session_reason'   => $s['session_reason'],
        'treatment_type'   => $s['treatment_type'],
        'status'           => $s['status'],
        'recommendation'   => $s['recommendation'],
        'therapist_role'   => $s['therapist_role'],
    ];
}, $stmt->fetchAll(PDO::FETCH_ASSOC));

jsonOut(['sessions' => $sessions]);
