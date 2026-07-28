<?php
/**
 * GET /api/player/training-load/weekly.php
 *
 * Single API surface for the TrainingLoadCalculator (sRPE / Monotony / Strain).
 * Do not recompute this math in any other endpoint or in Flutter — call this
 * service (or the calculator class directly, server-side) instead.
 *
 * Auth modes:
 *  - Player self-view: player's own bearer token, no player_id param.
 *  - Coach view: coach/club/academy bearer token + player_id=<club_players.id>,
 *    scoped via club_players.club_id (same pattern as
 *    api/coach/reports/player.php).
 *
 * Query params:
 *  - player_id   (optional) club_players.id — required for coach view
 *  - date        (optional) any date within the target week, YYYY-MM-DD; defaults to today
 *  - timezone    (optional compatibility parameter); only Africa/Kigali is accepted
 */
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/club_auth.php';
require_once __DIR__ . '/TrainingLoadCalculator.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
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
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
$requestedPlayerId = trim((string)($_GET['player_id'] ?? ''));

if ($requestedPlayerId !== '') {
    // Coach/club/academy view of a specific roster player — scoped by
    // club_id (a roster belongs to the whole club, shared across every
    // coach/staff member), not by whichever coach happens to be logged in.
    if (in_array($user['role'], ['player', 'parent'], true)) {
        jsonOut(['error' => 'Forbidden'], 403);
    }
    $ctx = requireClubPermission($pdo, $user, 'fitness.training_load.view');
    $stmt = $pdo->prepare(
        "SELECT id, name, position, team_name, linked_user_id
         FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1" .
         (($ctx['team_id'] ?? null) !== null ? ' AND team_id = ?' : '')
    );
    $playerParams = [$requestedPlayerId, $ctx['club_id']];
    if (($ctx['team_id'] ?? null) !== null) $playerParams[] = $ctx['team_id'];
    $stmt->execute($playerParams);
    $cp = $stmt->fetch();
    if (!$cp) jsonOut(['error' => 'Player not found or access denied'], 403);

    $targetUserId = $cp['linked_user_id'] !== null ? (int)$cp['linked_user_id'] : (int)$user['id'];
    $linkedPlayerId = $cp['id'];
    $playerMeta = ['id' => $cp['id'], 'name' => $cp['name'], 'position' => $cp['position'], 'team_name' => $cp['team_name']];
} else {
    // Self-view
    if ($user['role'] !== 'player') jsonOut(['error' => 'player_id is required'], 400);
    $targetUserId = (int)$user['id'];
    $linkedPlayerId = $user['linked_player_id'] ?? null;
    $playerMeta = ['id' => $linkedPlayerId, 'name' => null, 'position' => null, 'team_name' => null];
}

$date = trim((string)($_GET['date'] ?? '')) ?: FitnessConfig::today();
$timezone = trim((string)($_GET['timezone'] ?? '')) ?: TrainingLoadCalculator::DEFAULT_TIMEZONE;

if ($timezone !== TrainingLoadCalculator::DEFAULT_TIMEZONE) {
    jsonOut([
        'error' => 'OFFICIAL_TIMEZONE_REQUIRED',
        'timezone' => TrainingLoadCalculator::DEFAULT_TIMEZONE,
    ], 400);
}
try {
    new DateTime($date);
} catch (Exception $e) {
    jsonOut(['error' => 'Invalid date'], 400);
}

$report = TrainingLoadCalculator::getPlayerWeeklyReport($pdo, $targetUserId, $linkedPlayerId, $date, $timezone);

jsonOut(array_merge(['player' => $playerMeta], $report));
