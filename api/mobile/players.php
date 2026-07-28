<?php
/**
 * api/mobile/players.php — Unified player management endpoint.
 *
 * Actions (GET ?action=...  |  POST with action in body):
 *   list       — list all active club players for the authenticated coach
 *   upsert     — create or update a player with dedup (returns canonical player_id)
 *   view       — fetch a single player by player_id
 *   deactivate — soft-delete a player
 *
 * Security:
 *   - user_id is always derived from the bearer token, never from the request body.
 *   - cross-account access (player not owned by caller) returns 403.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../includes/source_app.php';
require_once __DIR__ . '/../includes/player_matching.php';
require_once __DIR__ . '/../includes/club_auth.php';

// ── Auth helpers (duplicated from auth.php pattern to stay self-contained) ────

function mp_bearer(): string
{
    $auth = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? $_SERVER['Authorization'] ?? '';
    if (!$auth && function_exists('apache_request_headers')) {
        $h = apache_request_headers();
        $auth = $h['Authorization'] ?? $h['authorization'] ?? '';
    }
    return stripos($auth, 'Bearer ') === 0 ? trim(substr($auth, 7)) : trim($auth);
}

function mp_auth(PDO $pdo): array
{
    $token = mp_bearer();
    if (!$token) { http_response_code(401); echo json_encode(['error' => 'Unauthorized']); exit; }

    $stmt = $pdo->prepare(
        'SELECT u.id, u.role, u.player_type, u.club_user_id, u.linked_player_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) { http_response_code(401); echo json_encode(['error' => 'Invalid or expired token']); exit; }

    // Only coaches/clubs may manage player records
    if (!empty($user['player_type'])) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden — coaches only']);
        exit;
    }
    return $user;
}

function mp_json(array $data, int $code = 200): void
{
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

// ── Request parsing ───────────────────────────────────────────────────────────

$method = $_SERVER['REQUEST_METHOD'];
$body   = [];
if ($method === 'POST') {
    $raw  = file_get_contents('php://input');
    $body = json_decode($raw, true) ?? [];
}

$action = $_GET['action'] ?? ($body['action'] ?? 'list');

// ── Routes ────────────────────────────────────────────────────────────────────

switch ($action) {

    // ── list ─────────────────────────────────────────────────────────────────
    case 'list': {
        $user = mp_auth($pdo);
        $ctx  = requireClubPermission($pdo, $user, 'players.read');
        $stmt = $pdo->prepare(
            "SELECT id, name, position, team_name, category, dominant_foot,
                    height_cm, weight_kg, date_of_birth, nationality, status,
                    latest_score, movement_score, stability_score, symmetry_score,
                    control_score, last_assessment_at, source_app, external_player_ref,
                    is_active, created_at, updated_at
             FROM club_players
             WHERE club_id = ? AND is_active = 1 AND (player_type IS NULL OR player_type = 'club')
             ORDER BY name ASC"
        );
        $stmt->execute([$ctx['club_id']]);
        mp_json(['success' => true, 'players' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    }

    // ── upsert ───────────────────────────────────────────────────────────────
    case 'upsert': {
        if ($method !== 'POST') mp_json(['error' => 'POST required'], 405);

        $user = mp_auth($pdo);
        $ctx  = requireClubPermission($pdo, $user, 'players.write');

        $name       = trim($body['name'] ?? '');
        $source_app = trim($body['source_app'] ?? 'nextkick_mobile');

        if (!$name) mp_json(['error' => 'name is required'], 400);

        // Validate source_app — this exits with 400 if unknown/disabled
        nk_require_valid_source_app($source_app);

        $result = nk_upsert_player(
            $pdo, (int)$user['id'], $ctx['club_id'],
            array_merge($body, ['source_app' => $source_app])
        );

        if (isset($result['error'])) mp_json(['error' => $result['error']], 400);

        mp_json([
            'success'   => true,
            'player_id' => $result['player_id'],
            'action'    => $result['action'],
        ]);
    }

    // ── view ─────────────────────────────────────────────────────────────────
    case 'view': {
        $user      = mp_auth($pdo);
        $ctx       = requireClubPermission($pdo, $user, 'players.read');
        $player_id = $_GET['player_id'] ?? ($body['player_id'] ?? '');
        if (!$player_id) mp_json(['error' => 'player_id is required'], 400);

        $stmt = $pdo->prepare(
            'SELECT * FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1 LIMIT 1'
        );
        $stmt->execute([$player_id, $ctx['club_id']]);
        $player = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$player) mp_json(['error' => 'Player not found'], 404);
        mp_json(['success' => true, 'player' => $player]);
    }

    // ── deactivate ───────────────────────────────────────────────────────────
    case 'deactivate': {
        if ($method !== 'POST') mp_json(['error' => 'POST required'], 405);

        $user      = mp_auth($pdo);
        $ctx       = requireClubPermission($pdo, $user, 'players.delete');
        $player_id = $body['player_id'] ?? '';
        if (!$player_id) mp_json(['error' => 'player_id is required'], 400);

        $stmt = $pdo->prepare(
            'UPDATE club_players SET is_active = 0, status = "inactive", updated_at = NOW()
             WHERE id = ? AND club_id = ?'
        );
        $stmt->execute([$player_id, $ctx['club_id']]);

        if ($stmt->rowCount() === 0) mp_json(['error' => 'Player not found or not yours'], 403);
        mp_json(['success' => true]);
    }

    default:
        mp_json(['error' => "Unknown action: $action"], 400);
}
