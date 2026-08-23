<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';
require_once '../includes/club_auth.php';

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

$token = bearerToken();
if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['error' => 'Invalid token'], 401);
if (in_array($user['role'], ['player', 'parent'])) jsonOut(['error' => 'Forbidden'], 403);

$method = $_SERVER['REQUEST_METHOD'];
$ctx    = requireClubPermission($pdo, $user, 'competitions.read');
$cid    = (int)$ctx['club_id'];

// ── GET — list active competitions for this club ────────────────────────────

if ($method === 'GET') {
    $stmt = $pdo->prepare(
        'SELECT c.id, c.club_id, c.season_id, c.name, c.type, c.notes, c.created_at, s.name AS season_name,
                c.yellow_card_threshold, c.suspension_matches, c.reset_yellow_cycle,
                c.carry_cards_between_stages, c.carry_suspensions_forward,
                c.direct_red_suspension_matches, c.two_yellows_suspension_matches,
                c.allow_admin_override,
                c.format_type, c.stages_count, c.win_points, c.draw_points, c.loss_points,
                c.tie_break_rule, c.competition_status
         FROM club_competitions c
         LEFT JOIN club_seasons s ON s.id = c.season_id
         WHERE c.club_id = ? AND c.is_active = 1
         ORDER BY c.created_at DESC'
    );
    $stmt->execute([$cid]);
    jsonOut(['competitions' => $stmt->fetchAll()]);
}

// ── POST — create/update a competition ──────────────────────────────────────

if ($method === 'POST') {
    requireClubPermission($pdo, $user, 'competitions.write');

    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $name = trim($body['name'] ?? '');
    if (!$name) jsonOut(['error' => 'Competition name is required'], 422);

    $requestedType = $body['type'] ?? 'league';
    $type = in_array($requestedType, ['league', 'cup', 'friendly'], true)
        ? $requestedType : 'league';
    $seasonId = isset($body['season_id']) && $body['season_id'] !== '' && $body['season_id'] !== null
        ? (int)$body['season_id'] : null;
    $notes = $body['notes'] ?? null;
    $yellowThreshold = max(1, (int)($body['yellow_card_threshold'] ?? 3));
    $suspensionMatches = max(1, (int)($body['suspension_matches'] ?? 1));
    $directRedMatches = max(1, (int)($body['direct_red_suspension_matches'] ?? 2));
    $twoYellowsMatches = max(1, (int)($body['two_yellows_suspension_matches'] ?? 1));
    $resetYellowCycle = (int)(bool)($body['reset_yellow_cycle'] ?? true);
    $carryCards = (int)(bool)($body['carry_cards_between_stages'] ?? true);
    $carrySuspensions = (int)(bool)($body['carry_suspensions_forward'] ?? false);
    $allowAdminOverride = (int)(bool)($body['allow_admin_override'] ?? true);

    $requestedFormat = $body['format_type'] ?? 'league';
    $formatType = in_array($requestedFormat, ['league', 'knockout', 'groups', 'friendly'], true)
        ? $requestedFormat : 'league';
    $stagesCount = max(1, (int)($body['stages_count'] ?? 1));
    $winPoints = max(0, (int)($body['win_points'] ?? 3));
    $drawPoints = max(0, (int)($body['draw_points'] ?? 1));
    $lossPoints = max(0, (int)($body['loss_points'] ?? 0));
    $requestedTieBreak = $body['tie_break_rule'] ?? 'goal_difference';
    $tieBreakRule = in_array($requestedTieBreak, ['goal_difference', 'head_to_head', 'goals_scored'], true)
        ? $requestedTieBreak : 'goal_difference';
    $requestedStatus = $body['competition_status'] ?? 'upcoming';
    $competitionStatus = in_array($requestedStatus, ['upcoming', 'ongoing', 'completed'], true)
        ? $requestedStatus : 'upcoming';

    $id = $body['id'] ?? null;

    if ($id) {
        $stmt = $pdo->prepare('SELECT id FROM club_competitions WHERE id = ? AND club_id = ? AND is_active = 1');
        $stmt->execute([$id, $cid]);
        if (!$stmt->fetch()) jsonOut(['error' => 'Competition not found'], 404);

        $pdo->prepare(
            'UPDATE club_competitions SET name = ?, type = ?, season_id = ?, notes = ?,
             yellow_card_threshold = ?, suspension_matches = ?, reset_yellow_cycle = ?,
             carry_cards_between_stages = ?, carry_suspensions_forward = ?,
             direct_red_suspension_matches = ?, two_yellows_suspension_matches = ?,
             allow_admin_override = ?, format_type = ?, stages_count = ?, win_points = ?,
             draw_points = ?, loss_points = ?, tie_break_rule = ?, competition_status = ?
             WHERE id = ? AND club_id = ?'
        )->execute([$name, $type, $seasonId, $notes, $yellowThreshold, $suspensionMatches,
            $resetYellowCycle, $carryCards, $carrySuspensions, $directRedMatches,
            $twoYellowsMatches, $allowAdminOverride, $formatType, $stagesCount, $winPoints,
            $drawPoints, $lossPoints, $tieBreakRule, $competitionStatus, $id, $cid]);

        jsonOut(['success' => true, 'id' => (int)$id]);
    }

    $stmt = $pdo->prepare(
        'INSERT INTO club_competitions
         (club_id, season_id, name, type, notes, yellow_card_threshold, suspension_matches,
          reset_yellow_cycle, carry_cards_between_stages, carry_suspensions_forward,
          direct_red_suspension_matches, two_yellows_suspension_matches, allow_admin_override,
          format_type, stages_count, win_points, draw_points, loss_points, tie_break_rule,
          competition_status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $stmt->execute([$cid, $seasonId, $name, $type, $notes, $yellowThreshold, $suspensionMatches,
        $resetYellowCycle, $carryCards, $carrySuspensions, $directRedMatches,
        $twoYellowsMatches, $allowAdminOverride, $formatType, $stagesCount, $winPoints,
        $drawPoints, $lossPoints, $tieBreakRule, $competitionStatus]);

    jsonOut(['success' => true, 'id' => (int)$pdo->lastInsertId()]);
}

// ── DELETE — soft-delete a competition ───────────────────────────────────────

if ($method === 'DELETE') {
    requireClubPermission($pdo, $user, 'competitions.write');

    $id = $_GET['id'] ?? (json_decode(file_get_contents('php://input'), true)['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id required'], 422);

    $pdo->prepare('UPDATE club_competitions SET is_active = 0 WHERE id = ? AND club_id = ?')
        ->execute([$id, $cid]);

    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
