<?php
/**
 * GET /api/mobile/player/assessments.php
 *
 * Player-scoped assessment history.
 * SECURITY: player_id is NEVER taken from the request.
 *           It is always read from users.linked_player_id in the database.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') { http_response_code(405); echo '{"error":"GET only"}'; exit; }

require_once '../db.php';

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

// ── Auth + load user identity from DB (never from request) ───────────────────
$token = bearerToken();
if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.player_type, u.linked_player_id
     FROM users u JOIN user_tokens t ON u.id = t.user_id
     WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['error' => 'Invalid token'], 401);

// Only players may use this endpoint
if (empty($user['player_type'])) {
    jsonOut(['error' => 'Forbidden — use /assessments.php for coach access'], 403);
}

// linked_player_id must exist
$linkedPlayerId = $user['linked_player_id'] ?? null;
if (!$linkedPlayerId) {
    jsonOut([
        'error'   => 'player_profile_missing',
        'message' => 'Player profile not linked. Please log in again.',
        'assessments' => [],
    ], 404);
}

// ── Fetch assessments scoped to this player ONLY ─────────────────────────────
$limit = min((int)($_GET['limit'] ?? 50), 200);

$stmt = $pdo->prepare(
    'SELECT * FROM assessments
     WHERE user_id = ? AND player_id = ?
     ORDER BY created_at DESC
     LIMIT ' . $limit
);
$stmt->execute([$user['id'], $linkedPlayerId]);
$rows = $stmt->fetchAll();

foreach ($rows as &$row) {
    $row['issues']  = json_decode($row['issues_json']        ?? '[]', true) ?? [];
    $row['tips']    = json_decode($row['tips_json']          ?? '[]', true) ?? [];
    $row['drills']  = json_decode($row['drills_json']        ?? '[]', true) ?? [];
    $row['metrics'] = json_decode($row['angle_metrics_json'] ?? '{}', true) ?? [];
    $row['overall_score']          = (int)($row['overall_score']          ?? 0);
    $row['movement_quality_score'] = (int)($row['movement_quality_score'] ?? 0);
    $row['stability_score']        = (int)($row['stability_score']        ?? 0);
    $row['symmetry_score']         = (int)($row['symmetry_score']         ?? 0);
    $row['control_score']          = (int)($row['control_score']          ?? 0);
    $row['quality_score']          = (int)($row['quality_score']          ?? 0);
    $row['pre_hooper_index'] = isset($row['pre_hooper_index']) ? (int)$row['pre_hooper_index'] : null;
    $row['pre_rpe']          = isset($row['pre_rpe'])          ? (int)$row['pre_rpe']          : null;
    $row['post_rpe']         = isset($row['post_rpe'])         ? (int)$row['post_rpe']         : null;
    $row['pain_reported']    = (bool)($row['pain_reported'] ?? false);
    $row['mood_after']       = isset($row['mood_after']) ? (int)$row['mood_after'] : null;
    unset($row['issues_json'], $row['tips_json'], $row['drills_json'], $row['angle_metrics_json']);
}
unset($row);

jsonOut([
    'assessments'      => $rows,
    'count'            => count($rows),
    'player_id'        => $linkedPlayerId,  // confirm which player was queried
]);
