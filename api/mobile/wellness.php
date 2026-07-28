<?php
/**
 * api/mobile/wellness.php — Unified Hooper wellness endpoint.
 *
 * GET  ?action=list_hooper [&player_id=X] [&source_app=X] [&limit=N]
 * POST action=create_hooper
 *
 * Duplicate prevention: same player_id + same calendar date + same source_app
 * → updates the existing row rather than creating a duplicate.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../includes/source_app.php';

function mw_bearer(): string
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

function mw_auth(PDO $pdo): array
{
    $token = mw_bearer();
    if (!$token) { http_response_code(401); echo json_encode(['error' => 'Unauthorized']); exit; }
    $stmt = $pdo->prepare(
        'SELECT u.id, u.role, u.player_type, u.linked_player_id, u.club_user_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) { http_response_code(401); echo json_encode(['error' => 'Invalid or expired token']); exit; }
    return $user;
}

function mw_json(array $data, int $code = 200): void
{
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function mw_verify_player(PDO $pdo, array $user, string $player_id): void
{
    $isPlayer = !empty($user['player_type']);
    if ($isPlayer) {
        if (($user['linked_player_id'] ?? '') !== $player_id) {
            mw_json(['error' => 'Forbidden'], 403);
        }
        return;
    }
    $s = $pdo->prepare('SELECT id FROM club_players WHERE id = ? AND user_id = ? AND is_active = 1 LIMIT 1');
    $s->execute([$player_id, $user['id']]);
    if (!$s->fetch()) mw_json(['error' => 'Forbidden — player not in your account'], 403);
}

$method = $_SERVER['REQUEST_METHOD'];
$body   = $method === 'POST' ? (json_decode(file_get_contents('php://input'), true) ?? []) : [];
$action = $_GET['action'] ?? ($body['action'] ?? ($method === 'GET' ? 'list_hooper' : 'create_hooper'));

switch ($action) {

    // ── list_hooper ───────────────────────────────────────────────────────────
    case 'list_hooper': {
        $user      = mw_auth($pdo);
        $isPlayer  = !empty($user['player_type']);
        $player_id = $_GET['player_id'] ?? null;
        $src       = nk_normalize_source_app($_GET['source_app'] ?? 'all');
        $limit     = min((int)($_GET['limit'] ?? 30), 200);

        $where  = 'h.user_id = ?';
        $params = [(int)$user['id']];

        if ($player_id) {
            $where .= ' AND h.linked_player_id = ?';
            $params[] = $player_id;
        } elseif ($isPlayer) {
            $linked = $user['linked_player_id'] ?? '';
            if (!$linked) mw_json(['entries' => []]);
            $where   .= ' AND h.linked_player_id = ?';
            $params[] = $linked;
        }

        if ($src !== 'all') {
            $where   .= ' AND h.source_app = ?';
            $params[] = $src;
        }

        $stmt = $pdo->prepare(
            "SELECT h.id, h.sleep_quality, h.fatigue, h.stress, h.muscle_soreness,
                    h.sleep_hours, h.hooper_score, h.notes, h.submitted_at,
                    h.source_app, h.linked_player_id,
                    cp.name AS player_name
             FROM player_hooper_index h
             LEFT JOIN club_players cp ON cp.id = h.linked_player_id
             WHERE {$where}
             ORDER BY h.submitted_at DESC
             LIMIT " . (int)$limit
        );
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        foreach ($rows as &$r) {
            $r['source_app_label'] = nk_source_app_label($r['source_app'] ?? 'legacy');
        }
        unset($r);
        mw_json(['success' => true, 'entries' => $rows, 'count' => count($rows)]);
    }

    // ── create_hooper ─────────────────────────────────────────────────────────
    case 'create_hooper': {
        if ($method !== 'POST') mw_json(['error' => 'POST required'], 405);

        $user = mw_auth($pdo);

        $player_id  = trim($body['player_id'] ?? '');
        $source_app = trim($body['source_app'] ?? 'nextkick_mobile');

        if (!$player_id) mw_json(['error' => 'player_id is required'], 400);
        nk_require_valid_source_app($source_app);
        mw_verify_player($pdo, $user, $player_id);

        // Validate Hooper fields (1–7 scale)
        foreach (['sleep_quality', 'fatigue', 'stress', 'muscle_soreness'] as $f) {
            if (!isset($body[$f])) mw_json(['error' => "$f is required"], 400);
            $v = (int)$body[$f];
            if ($v < 1 || $v > 7) mw_json(['error' => "$f must be 1–7"], 400);
        }

        $sleepQ   = (int)$body['sleep_quality'];
        $fatigue  = (int)$body['fatigue'];
        $stress   = (int)$body['stress'];
        $soreness = (int)$body['muscle_soreness'];
        $hooper   = $sleepQ + $fatigue + $stress + $soreness;

        $sleepHours = isset($body['sleep_hours']) ? (float)$body['sleep_hours'] : null;
        $notes      = isset($body['notes']) ? substr($body['notes'], 0, 500) : null;
        $sessionId  = !empty($body['session_id']) ? $body['session_id'] : null;
        $clubId     = (int)($user['club_user_id'] ?? 0) ?: null;
        $extRef     = !empty($body['external_entry_ref']) ? trim($body['external_entry_ref']) : null;

        // Duplicate guard: same player + same date + same source → update
        $existing_id = null;
        $today = date('Y-m-d');
        $dup = $pdo->prepare(
            'SELECT id FROM player_hooper_index
             WHERE user_id = ? AND linked_player_id = ? AND source_app = ?
               AND DATE(submitted_at) = ?
             LIMIT 1'
        );
        $dup->execute([$user['id'], $player_id, $source_app, $today]);
        $existing_id = $dup->fetchColumn();

        if ($existing_id) {
            $pdo->prepare(
                'UPDATE player_hooper_index SET
                    sleep_quality = ?, fatigue = ?, stress = ?, muscle_soreness = ?,
                    sleep_hours = ?, hooper_score = ?, notes = COALESCE(?, notes),
                    source_app = ?
                 WHERE id = ?'
            )->execute([$sleepQ, $fatigue, $stress, $soreness, $sleepHours, $hooper, $notes, $source_app, $existing_id]);
            $id = $existing_id;
        } else {
            $stmt = $pdo->prepare(
                'INSERT INTO player_hooper_index
                 (user_id, linked_player_id, club_id, session_id, training_session_id,
                  sleep_quality, fatigue, stress, muscle_soreness, sleep_hours,
                  hooper_score, notes, source_app, external_entry_ref)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
            );
            $stmt->execute([
                $user['id'], $player_id, $clubId, $sessionId, $sessionId,
                $sleepQ, $fatigue, $stress, $soreness, $sleepHours,
                $hooper, $notes, $source_app, $extRef,
            ]);
            $id = (int)$pdo->lastInsertId();
        }

        $status = $hooper <= 10 ? 'normal' : ($hooper <= 16 ? 'moderate' : 'high_risk');

        mw_json([
            'success'      => true,
            'id'           => $id,
            'hooper_score' => $hooper,
            'status'       => $status,
            'action'       => $existing_id ? 'updated' : 'created',
        ]);
    }

    default:
        mw_json(['error' => "Unknown action: $action"], 400);
}
