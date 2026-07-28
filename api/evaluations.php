<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once 'db.php';
require_once 'includes/club_auth.php';

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
        'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

// ── GET: evaluations for session or match ─────────────────────────────────────
if ($method === 'GET') {
    $sessionId = $_GET['session_id'] ?? null;
    $matchId   = $_GET['match_id']   ?? null;
    $playerId  = $_GET['player_id']  ?? null;

    if (($user['role'] ?? '') === 'player') {
        $where  = ['user_id = ?'];
        $params = [$user['id']];
    } else {
        $ctx    = requireClubPermission($pdo, $user, 'assessments.read');
        $where  = ['club_id = ?'];
        $params = [$ctx['club_id']];
    }

    if ($sessionId) { $where[] = 'session_id = ?'; $params[] = $sessionId; }
    if ($matchId)   { $where[] = 'match_id = ?';   $params[] = $matchId;   }
    if ($playerId)  { $where[] = 'player_id = ?';  $params[] = $playerId;  }

    $stmt = $pdo->prepare(
        'SELECT * FROM coach_evaluations WHERE ' . implode(' AND ', $where)
        . ' ORDER BY evaluated_at DESC'
    );
    $stmt->execute($params);
    $rows = $stmt->fetchAll();

    foreach ($rows as &$r) {
        foreach (['fitness_level','effort','speed','strength','agility','endurance'] as $f) {
            $r[$f] = $r[$f] !== null ? (int)$r[$f] : null;
        }
    }
    unset($r);

    jsonOut(['evaluations' => $rows]);
}

// ── POST: save (upsert) evaluation ────────────────────────────────────────────
if ($method === 'POST') {
    if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
        jsonOut(['error' => 'Forbidden — coaches only'], 403);
    }
    $ctx = requireClubPermission($pdo, $user, 'assessments.write');

    $body      = json_decode(file_get_contents('php://input'), true) ?? [];
    $sessionId = $body['session_id'] ?? null;
    $matchId   = $body['match_id']   ?? null;
    $playerId  = trim($body['player_id'] ?? '');

    if (!$playerId)              jsonOut(['error' => 'player_id required'], 400);
    if (!$sessionId && !$matchId) jsonOut(['error' => 'session_id or match_id required'], 400);

    // Delete existing evaluation for this player+session/match combo
    if ($sessionId) {
        $pdo->prepare('DELETE FROM coach_evaluations WHERE session_id = ? AND player_id = ? AND club_id = ?')
            ->execute([$sessionId, $playerId, $ctx['club_id']]);
    } else {
        $pdo->prepare('DELETE FROM coach_evaluations WHERE match_id = ? AND player_id = ? AND club_id = ?')
            ->execute([$matchId, $playerId, $ctx['club_id']]);
    }

    $stmt = $pdo->prepare(
        'INSERT INTO coach_evaluations
             (session_id, match_id, player_id, user_id, club_id, fitness_level, effort,
              speed, strength, agility, endurance, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );

    $stmt->execute([
        $sessionId,
        $matchId,
        $playerId,
        $user['id'],
        $ctx['club_id'],
        isset($body['fitness_level']) ? (int)$body['fitness_level'] : null,
        isset($body['effort'])        ? (int)$body['effort']        : null,
        isset($body['speed'])         ? (int)$body['speed']         : null,
        isset($body['strength'])      ? (int)$body['strength']      : null,
        isset($body['agility'])       ? (int)$body['agility']       : null,
        isset($body['endurance'])     ? (int)$body['endurance']     : null,
        $body['notes'] ?? null,
    ]);

    jsonOut(['success' => true, 'id' => $pdo->lastInsertId()]);
}

jsonOut(['error' => 'Method not allowed'], 405);
