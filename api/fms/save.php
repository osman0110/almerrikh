<?php
require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';

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
        'SELECT u.id, u.role, u.player_type, u.name FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
// FMS is administered by a coach, never self-reported by the player
if (!empty($user['player_type']) || $user['role'] === 'player') {
    jsonOut(['error' => 'Forbidden — coaches only'], 403);
}

$body = json_decode(file_get_contents('php://input'), true) ?? [];

$playerId = trim($body['player_id'] ?? '');
if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);

// Ownership check — scoped to the caller's club, not just the owner account
$ctx = requireClubPermission($pdo, $user, 'assessments.write');
$ownerStmt = $pdo->prepare(
    'SELECT cp.name FROM club_players cp
     LEFT JOIN club_teams ct
       ON ct.club_id = cp.club_id AND ct.name = cp.team_name AND ct.is_active = 1
     WHERE cp.id = ? AND cp.club_id = ?' .
     ($ctx['team_id'] !== null ? ' AND COALESCE(cp.team_id, ct.id) = ?' : '')
);
$ownerStmt->execute([
    $playerId,
    $ctx['club_id'],
    ...($ctx['team_id'] !== null ? [(int)$ctx['team_id']] : []),
]);
$player = $ownerStmt->fetch(PDO::FETCH_ASSOC);
if (!$player) jsonOut(['error' => 'Forbidden — player not in your club'], 403);

$sessionId = !empty($body['session_id']) ? (string)$body['session_id'] : null;
$notes     = isset($body['notes']) ? substr((string)$body['notes'], 0, 1000) : null;

// ── The 7 FMS movements — bilateral ones require left+right; unilateral need only 'score' ──
$bilateral = ['hurdle_step', 'inline_lunge', 'shoulder_mobility', 'active_straight_leg_raise', 'rotary_stability'];
$unilateral = ['deep_squat', 'trunk_stability_pushup'];
$allMovements = array_merge($unilateral, $bilateral);

$movementsInput = $body['movements'] ?? [];
if (!is_array($movementsInput)) jsonOut(['error' => 'movements is required'], 400);

$computed = [];
$totalScore = 0;

foreach ($allMovements as $m) {
    $entry = $movementsInput[$m] ?? null;
    if (!is_array($entry)) jsonOut(['error' => "movements.$m is required"], 400);

    $pain = (int)(bool)($entry['pain'] ?? false);
    $movementNotes = isset($entry['notes']) ? substr((string)$entry['notes'], 0, 255) : null;

    if (in_array($m, $bilateral, true)) {
        if (!isset($entry['left'], $entry['right']))
            jsonOut(['error' => "movements.$m requires left and right scores"], 400);
        $left = (int)$entry['left'];
        $right = (int)$entry['right'];
        if ($left < 0 || $left > 3 || $right < 0 || $right > 3)
            jsonOut(['error' => "movements.$m scores must be 0-3"], 400);
        // FMS rule: a positive pain provocation on the clearing test forces 0
        // regardless of the raw movement score; otherwise bilateral score = weaker side.
        $final = $pain ? 0 : min($left, $right);
        $computed[$m] = ['left' => $left, 'right' => $right, 'final' => $final, 'pain' => $pain, 'notes' => $movementNotes];
    } else {
        if (!isset($entry['score'])) jsonOut(['error' => "movements.$m requires a score"], 400);
        $score = (int)$entry['score'];
        if ($score < 0 || $score > 3) jsonOut(['error' => "movements.$m score must be 0-3"], 400);
        $final = $pain ? 0 : $score;
        $computed[$m] = ['left' => null, 'right' => null, 'final' => $final, 'pain' => $pain, 'notes' => $movementNotes];
    }

    $totalScore += $computed[$m]['final'];
}

$id = bin2hex(random_bytes(16));

$pdo->beginTransaction();
try {
    $pdo->prepare(
        'INSERT INTO fms_assessments (id, user_id, club_id, player_id, player_name, session_id, total_score, notes, assessor_name)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
    )->execute([$id, $user['id'], $ctx['club_id'], $playerId, $player['name'], $sessionId, $totalScore, $notes, $user['name'] ?? null]);

    $movStmt = $pdo->prepare(
        'INSERT INTO fms_movement_scores (assessment_id, movement, left_score, right_score, final_score, pain, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?)'
    );
    foreach ($computed as $movement => $c) {
        $movStmt->execute([$id, $movement, $c['left'], $c['right'], $c['final'], $c['pain'], $c['notes']]);
    }

    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    jsonOut(['error' => 'Failed to save FMS assessment'], 500);
}

jsonOut(['success' => true, 'id' => $id, 'total_score' => $totalScore, 'movements' => $computed]);
