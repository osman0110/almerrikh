<?php
/**
 * Physiotherapy & Massage Scheduling (roadmap item 4).
 * Independent treatment-session log, gated behind physio_sessions.read/write
 * (doctor, physiotherapist, massage specialist). Coach-visible availability
 * stays on the existing club_players.status field, untouched here.
 *
 * GET  ?player_id=X            — list sessions for a player (newest first)
 * GET  ?id=X                   — one session
 * GET  ?date=YYYY-MM-DD         — daily schedule for the club (therapist/room workload)
 * POST action=create           — book a new session
 * POST action=update           — update status/notes/recommendation, or reschedule
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';

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
    if (!$token) jsonOut(['success' => false, 'message' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.role, u.name FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

const VALID_REASON  = ['recovery', 'pain', 'muscle_tightness', 'pre_match', 'post_match'];
const VALID_INTENSITY = ['light', 'moderate', 'deep'];
const VALID_RECOMMENDATION = ['rest', 'modified_training', 'doctor_followup', 'another_session'];
const VALID_STATUS  = ['scheduled', 'completed', 'cancelled', 'no_show'];

function sessionOut(array $s): array {
    return [
        'id'                => (string)$s['id'],
        'player_id'         => $s['player_id'],
        'therapist_user_id' => (string)$s['therapist_user_id'],
        'scheduled_at'      => $s['scheduled_at'],
        'duration_minutes'  => (int)$s['duration_minutes'],
        'room'              => $s['room'],
        'body_area'         => $s['body_area'],
        'session_reason'    => $s['session_reason'],
        'treatment_type'    => $s['treatment_type'],
        'intensity'         => $s['intensity'],
        'contraindications' => $s['contraindications'],
        'specialist_notes'  => $s['specialist_notes'],
        'player_response'   => $s['player_response'],
        'recommendation'    => $s['recommendation'],
        'status'            => $s['status'],
        'created_at'        => $s['created_at'],
        'updated_at'        => $s['updated_at'],
    ];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

// ── GET ──────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $ctx = requireClubPermission($pdo, $user, 'physio_sessions.read');

    $id = trim($_GET['id'] ?? '');
    if ($id) {
        $stmt = $pdo->prepare('SELECT * FROM physio_sessions WHERE id = ? AND club_id = ?');
        $stmt->execute([$id, $ctx['club_id']]);
        $session = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$session) jsonOut(['success' => false, 'message' => 'Not found'], 404);
        jsonOut(['success' => true, 'session' => sessionOut($session)]);
    }

    $date = trim($_GET['date'] ?? '');
    if ($date) {
        $stmt = $pdo->prepare(
            "SELECT s.*, p.name AS player_name, u.name AS therapist_name
             FROM physio_sessions s
             LEFT JOIN club_players p ON p.id = s.player_id
             LEFT JOIN users u ON u.id = s.therapist_user_id
             WHERE s.club_id = ? AND DATE(s.scheduled_at) = ?
             ORDER BY s.scheduled_at ASC"
        );
        $stmt->execute([$ctx['club_id'], $date]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        jsonOut(['success' => true, 'sessions' => array_map(function ($s) {
            $out = sessionOut($s);
            $out['player_name'] = $s['player_name'];
            $out['therapist_name'] = $s['therapist_name'];
            return $out;
        }, $rows)]);
    }

    $playerId = trim($_GET['player_id'] ?? '');
    if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id, id or date is required'], 400);

    $stmt = $pdo->prepare(
        'SELECT * FROM physio_sessions WHERE player_id = ? AND club_id = ? ORDER BY scheduled_at DESC, id DESC'
    );
    $stmt->execute([$playerId, $ctx['club_id']]);
    jsonOut(['success' => true, 'sessions' => array_map('sessionOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
}

// ── POST ─────────────────────────────────────────────────────────────────────
if ($method === 'POST') {
    $ctx    = requireClubPermission($pdo, $user, 'physio_sessions.write');
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? 'create');

    if ($action === 'create') {
        $playerId    = trim($body['player_id'] ?? '');
        $scheduledAt = trim($body['scheduled_at'] ?? '');
        if (!$playerId)    jsonOut(['success' => false, 'message' => 'player_id is required'], 400);
        if (!$scheduledAt) jsonOut(['success' => false, 'message' => 'scheduled_at is required'], 400);

        $ownStmt = $pdo->prepare('SELECT 1 FROM club_players WHERE id = ? AND club_id = ?');
        $ownStmt->execute([$playerId, $ctx['club_id']]);
        if (!$ownStmt->fetchColumn()) jsonOut(['success' => false, 'message' => 'Player not found'], 404);

        $reason    = in_array($body['session_reason'] ?? '', VALID_REASON, true) ? $body['session_reason'] : 'recovery';
        $intensity = in_array($body['intensity'] ?? '', VALID_INTENSITY, true) ? $body['intensity'] : 'moderate';
        $duration  = (int)($body['duration_minutes'] ?? 30);
        if ($duration <= 0) $duration = 30;
        $therapistId = (int)($body['therapist_user_id'] ?? $user['id']);

        $stmt = $pdo->prepare(
            'INSERT INTO physio_sessions
                 (club_id, player_id, therapist_user_id, scheduled_at, duration_minutes, room,
                  body_area, session_reason, treatment_type, intensity, contraindications,
                  status, created_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \'scheduled\', ?)'
        );
        $stmt->execute([
            $ctx['club_id'], $playerId, $therapistId, $scheduledAt, $duration,
            trim($body['room'] ?? '') ?: null,
            trim($body['body_area'] ?? '') ?: null,
            $reason,
            trim($body['treatment_type'] ?? '') ?: null,
            $intensity,
            trim($body['contraindications'] ?? '') ?: null,
            $user['id'],
        ]);
        jsonOut(['success' => true, 'id' => (string)$pdo->lastInsertId()]);
    }

    if ($action === 'update') {
        $id = trim($body['id'] ?? '');
        if (!$id) jsonOut(['success' => false, 'message' => 'id is required'], 400);

        $stmt = $pdo->prepare('SELECT * FROM physio_sessions WHERE id = ? AND club_id = ?');
        $stmt->execute([$id, $ctx['club_id']]);
        $session = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$session) jsonOut(['success' => false, 'message' => 'Not found'], 404);

        $status         = in_array($body['status'] ?? '', VALID_STATUS, true) ? $body['status'] : $session['status'];
        $recommendation = in_array($body['recommendation'] ?? '', VALID_RECOMMENDATION, true)
            ? $body['recommendation'] : $session['recommendation'];
        $specialistNotes = array_key_exists('specialist_notes', $body) ? trim($body['specialist_notes']) : $session['specialist_notes'];
        $playerResponse  = array_key_exists('player_response', $body) ? trim($body['player_response']) : $session['player_response'];

        $pdo->prepare(
            'UPDATE physio_sessions
             SET status = ?, recommendation = ?, specialist_notes = ?, player_response = ?
             WHERE id = ?'
        )->execute([$status, $recommendation, $specialistNotes ?: null, $playerResponse ?: null, $id]);

        jsonOut(['success' => true]);
    }

    jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
