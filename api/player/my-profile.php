<?php
/**
 * GET /api/mobile/player/my-profile.php
 * Returns the club_players record for the authenticated player (independent or club).
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';
require_once '../includes/fitness/BodyCompositionRepository.php';

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
        'SELECT u.id, u.name, u.role, u.player_type, u.linked_player_id, u.club_user_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid token'], 401);
    return $user;
}

$user = getAuthUser($pdo);

// Find player record — either linked explicitly or owned directly
$stmt = $pdo->prepare(
    'SELECT cp.*
     FROM club_players cp
     WHERE (cp.linked_user_id = ? OR (cp.user_id = ? AND cp.player_type = "independent"))
       AND cp.is_active = 1
     ORDER BY cp.created_at DESC
     LIMIT 1'
);
$stmt->execute([$user['id'], $user['id']]);
$player = $stmt->fetch();

// Unified approved new-system measurement, then legacy fallback.
$metrics = BodyCompositionRepository::latestForPlayer(
    $pdo,
    $player ? $player['id'] : ($user['linked_player_id'] ?? null),
    (int)$user['id'],
    true
);
if ($metrics) {
    $metrics['body_fat_percent'] = $metrics['body_fat_percentage'];
    $metrics['bmi'] = $metrics['raw']['bmi'] ?? null;
}

// Fetch latest Hooper
$hooperStmt = $pdo->prepare(
    'SELECT hooper_score, submitted_at FROM player_hooper_index WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 1'
);
$hooperStmt->execute([$user['id']]);
$hooper = $hooperStmt->fetch() ?: null;

// Fetch latest assessment score
$assStmt = $pdo->prepare(
    'SELECT overall_score, type, created_at FROM assessments WHERE user_id = ? ORDER BY created_at DESC LIMIT 1'
);
$assStmt->execute([$user['id']]);
$assessment = $assStmt->fetch() ?: null;

$discipline = [
    'yellow_cards_total' => 0,
    'current_yellow_cards' => 0,
    'red_cards_total' => 0,
    'suspensions_total' => 0,
    'active_suspensions' => 0,
    'matches_remaining' => 0,
    'status' => 'available',
];
if ($player) {
    $cardStmt = $pdo->prepare(
        'SELECT mc.card_type, COUNT(*) AS total
         FROM match_cards mc JOIN matches m ON m.id = mc.match_id
         WHERE m.club_id = ? AND mc.player_id = ? GROUP BY mc.card_type'
    );
    $cardStmt->execute([(int)$player['club_id'], $player['id']]);
    foreach ($cardStmt->fetchAll() as $row) {
        if ($row['card_type'] === 'yellow') $discipline['yellow_cards_total'] = (int)$row['total'];
        if ($row['card_type'] === 'red') $discipline['red_cards_total'] = (int)$row['total'];
    }
    $cycleStmt = $pdo->prepare(
        'SELECT COALESCE(SUM(current_yellow_cards), 0)
         FROM player_discipline_cycles WHERE club_id = ? AND player_id = ? AND completed_at IS NULL'
    );
    $cycleStmt->execute([(int)$player['club_id'], $player['id']]);
    $discipline['current_yellow_cards'] = (int)$cycleStmt->fetchColumn();
    $suspensionStmt = $pdo->prepare(
        "SELECT COUNT(*) AS total, SUM(status = 'active') AS active,
                COALESCE(SUM(CASE WHEN status = 'active' THEN matches_remaining ELSE 0 END), 0) AS remaining
         FROM player_suspensions WHERE club_id = ? AND player_id = ?"
    );
    $suspensionStmt->execute([(int)$player['club_id'], $player['id']]);
    $suspensions = $suspensionStmt->fetch() ?: [];
    $discipline['suspensions_total'] = (int)($suspensions['total'] ?? 0);
    $discipline['active_suspensions'] = (int)($suspensions['active'] ?? 0);
    $discipline['matches_remaining'] = (int)($suspensions['remaining'] ?? 0);
    $discipline['status'] = $discipline['active_suspensions'] > 0
        ? 'suspended'
        : ($discipline['current_yellow_cards'] > 0 ? 'available_warning' : 'available');
}

// Per-competition breakdown — cards/suspensions are tracked separately per
// active competition (a player can carry different card counts in the
// league vs. a cup running at the same time).
$disciplineByCompetition = [];
if ($player) {
    $compStmt = $pdo->prepare(
        'SELECT id, name FROM club_competitions WHERE club_id = ? AND is_active = 1 ORDER BY id'
    );
    $compStmt->execute([(int)$player['club_id']]);
    $competitions = $compStmt->fetchAll();

    if ($competitions) {
        $cardsByCompetition = [];
        $cardStmt = $pdo->prepare(
            'SELECT m.competition_id, mc.card_type, COUNT(*) AS total
             FROM match_cards mc JOIN matches m ON m.id = mc.match_id
             WHERE m.club_id = ? AND mc.player_id = ? AND m.competition_id IS NOT NULL
             GROUP BY m.competition_id, mc.card_type'
        );
        $cardStmt->execute([(int)$player['club_id'], $player['id']]);
        foreach ($cardStmt->fetchAll() as $row) {
            $cardsByCompetition[(int)$row['competition_id']][$row['card_type']] = (int)$row['total'];
        }

        $currentYellowByCompetition = [];
        $cycleByCompStmt = $pdo->prepare(
            'SELECT competition_id, COALESCE(SUM(current_yellow_cards), 0) AS total
             FROM player_discipline_cycles
             WHERE club_id = ? AND player_id = ? AND completed_at IS NULL
             GROUP BY competition_id'
        );
        $cycleByCompStmt->execute([(int)$player['club_id'], $player['id']]);
        foreach ($cycleByCompStmt->fetchAll() as $row) {
            $currentYellowByCompetition[(int)$row['competition_id']] = (int)$row['total'];
        }

        $suspensionsByCompetition = [];
        $suspByCompStmt = $pdo->prepare(
            "SELECT competition_id, COUNT(*) AS total, SUM(status = 'active') AS active,
                    COALESCE(SUM(CASE WHEN status = 'active' THEN matches_remaining ELSE 0 END), 0) AS remaining
             FROM player_suspensions WHERE club_id = ? AND player_id = ? GROUP BY competition_id"
        );
        $suspByCompStmt->execute([(int)$player['club_id'], $player['id']]);
        foreach ($suspByCompStmt->fetchAll() as $row) {
            $suspensionsByCompetition[(int)$row['competition_id']] = $row;
        }

        foreach ($competitions as $comp) {
            $cid = (int)$comp['id'];
            $currentYellow = $currentYellowByCompetition[$cid] ?? 0;
            $susp = $suspensionsByCompetition[$cid] ?? null;
            $activeSuspensions = $susp ? (int)($susp['active'] ?? 0) : 0;
            $disciplineByCompetition[] = [
                'competition_id' => $cid,
                'competition_name' => $comp['name'],
                'yellow_cards_total' => $cardsByCompetition[$cid]['yellow'] ?? 0,
                'current_yellow_cards' => $currentYellow,
                'red_cards_total' => $cardsByCompetition[$cid]['red'] ?? 0,
                'suspensions_total' => $susp ? (int)($susp['total'] ?? 0) : 0,
                'active_suspensions' => $activeSuspensions,
                'matches_remaining' => $susp ? (int)($susp['remaining'] ?? 0) : 0,
                'status' => $activeSuspensions > 0
                    ? 'suspended'
                    : ($currentYellow > 0 ? 'available_warning' : 'available'),
            ];
        }
    }
}

jsonOut([
    'user' => [
        'id'          => (int)$user['id'],
        'name'        => $user['name'],
        'role'        => $user['role']             ?? 'player',
        'player_type' => $user['player_type']      ?? 'independent',
        'club_user_id'=> $user['club_user_id'] ? (int)$user['club_user_id'] : null,
    ],
    'player'     => $player ?: null,
    'metrics'    => $metrics,
    'hooper'     => $hooper,
    'assessment' => $assessment,
    'discipline' => $discipline,
    'discipline_by_competition' => $disciplineByCompetition,
]);
