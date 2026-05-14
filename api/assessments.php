<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once 'db.php';

function jsonOut(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function bearerToken(): string {
    $auth = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? $_SERVER['Authorization']
        ?? '';
    if (!$auth && function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    }
    if (stripos($auth, 'Bearer ') === 0) return trim(substr($auth, 7));
    return trim($auth);
}

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.name, u.email FROM users u
         JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ?'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$method = $_SERVER['REQUEST_METHOD'];

// ── GET: list assessments ─────────────────────────────────────────────────────
if ($method === 'GET') {
    $user     = getAuthUser($pdo);
    $playerId = $_GET['player_id'] ?? null;
    $limit    = min((int)($_GET['limit'] ?? 50), 200);

    if ($playerId) {
        $stmt = $pdo->prepare(
            'SELECT * FROM assessments WHERE user_id = ? AND player_id = ?
             ORDER BY created_at DESC LIMIT ' . $limit
        );
        $stmt->execute([$user['id'], $playerId]);
    } else {
        $stmt = $pdo->prepare(
            'SELECT * FROM assessments WHERE user_id = ?
             ORDER BY created_at DESC LIMIT ' . $limit
        );
        $stmt->execute([$user['id']]);
    }

    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($rows as &$row) {
        $row['issues']  = json_decode($row['issues_json']        ?? '[]', true) ?? [];
        $row['tips']    = json_decode($row['tips_json']          ?? '[]', true) ?? [];
        $row['drills']  = json_decode($row['drills_json']        ?? '[]', true) ?? [];
        $row['metrics'] = json_decode($row['angle_metrics_json'] ?? '{}', true) ?? [];
        $row['overall_score']          = (int) $row['overall_score'];
        $row['movement_quality_score'] = (int) $row['movement_quality_score'];
        $row['stability_score']        = (int) $row['stability_score'];
        $row['symmetry_score']         = (int) $row['symmetry_score'];
        $row['control_score']          = (int) $row['control_score'];
        $row['quality_score']          = (int) $row['quality_score'];
        unset($row['issues_json'], $row['tips_json'], $row['drills_json'], $row['angle_metrics_json']);
    }
    unset($row);

    jsonOut(['assessments' => $rows, 'count' => count($rows)]);

// ── POST: save / upsert assessment ───────────────────────────────────────────
} elseif ($method === 'POST') {
    $user = getAuthUser($pdo);
    $body = json_decode(file_get_contents('php://input'), true) ?? [];

    $id         = trim($body['id'] ?? '');
    $playerId   = trim($body['player_id'] ?? '');
    $playerName = trim($body['player_name'] ?? '');
    $type       = trim($body['type'] ?? '');
    $overall    = (int)($body['overall_score'] ?? 0);
    $movement   = (int)($body['movement_quality_score'] ?? 0);
    $stability  = (int)($body['stability_score'] ?? 0);
    $symmetry   = (int)($body['symmetry_score'] ?? 0);
    $control    = (int)($body['control_score'] ?? 0);
    $quality    = (int)($body['quality_score'] ?? 0);
    $issues     = json_encode($body['issues'] ?? [], JSON_UNESCAPED_UNICODE);
    $tips       = json_encode($body['correction_tips'] ?? [], JSON_UNESCAPED_UNICODE);
    $drills     = json_encode($body['recommended_drills'] ?? [], JSON_UNESCAPED_UNICODE);
    $metrics    = json_encode($body['angle_metrics'] ?? [], JSON_UNESCAPED_UNICODE);
    $notes      = $body['coach_notes'] ?? null;

    if (!$id || !$playerId || !$type) {
        jsonOut(['error' => 'id, player_id and type are required'], 400);
    }

    $stmt = $pdo->prepare(
        'INSERT INTO assessments
             (id, user_id, player_id, player_name, type,
              overall_score, movement_quality_score, stability_score,
              symmetry_score, control_score, quality_score,
              issues_json, tips_json, drills_json, angle_metrics_json, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
             overall_score          = VALUES(overall_score),
             movement_quality_score = VALUES(movement_quality_score),
             stability_score        = VALUES(stability_score),
             symmetry_score         = VALUES(symmetry_score),
             control_score          = VALUES(control_score),
             quality_score          = VALUES(quality_score),
             issues_json            = VALUES(issues_json),
             tips_json              = VALUES(tips_json),
             drills_json            = VALUES(drills_json),
             angle_metrics_json     = VALUES(angle_metrics_json),
             notes                  = VALUES(notes)'
    );
    $stmt->execute([
        $id, $user['id'], $playerId, $playerName, $type,
        $overall, $movement, $stability, $symmetry, $control, $quality,
        $issues, $tips, $drills, $metrics, $notes,
    ]);

    jsonOut(['success' => true, 'id' => $id]);

} else {
    jsonOut(['error' => 'Method not allowed'], 405);
}
