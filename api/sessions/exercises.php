<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../includes/club_auth.php';

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
        'SELECT u.id FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

// ── GET: list exercises for a session ─────────────────────────────────────────
if ($method === 'GET') {
    $sessionId = $_GET['session_id'] ?? '';
    if (!$sessionId) jsonOut(['error' => 'session_id required'], 400);

    // Reading a session's plan is club-wide (same as reading the session);
    // only the owning coach (or owner/admin) may change it — see POST/DELETE.
    $ctx = requireClubPermission($pdo, $user, 'sessions.read');
    $stmt = $pdo->prepare('SELECT id FROM club_sessions WHERE id = ? AND club_id = ?');
    $stmt->execute([$sessionId, $ctx['club_id']]);
    if (!$stmt->fetch()) jsonOut(['error' => 'Session not found'], 404);

    $stmt = $pdo->prepare(
        'SELECT * FROM club_session_exercises WHERE session_id = ? ORDER BY sort_order ASC, id ASC'
    );
    $stmt->execute([$sessionId]);
    $rows = $stmt->fetchAll();

    foreach ($rows as &$r) {
        $r['id']               = (int)$r['id'];
        $r['sets']             = $r['sets']             !== null ? (int)$r['sets']             : null;
        $r['reps']             = $r['reps']             !== null ? (int)$r['reps']             : null;
        $r['duration_seconds'] = $r['duration_seconds'] !== null ? (int)$r['duration_seconds'] : null;
        $r['rest_seconds']     = $r['rest_seconds']     !== null ? (int)$r['rest_seconds']     : null;
        $r['sort_order']       = (int)$r['sort_order'];
    }
    unset($r);

    jsonOut(['exercises' => $rows]);
}

// ── POST: save all exercises for a session (replace) ──────────────────────────
if ($method === 'POST') {
    $body      = json_decode(file_get_contents('php://input'), true) ?? [];
    $sessionId = trim($body['session_id'] ?? '');
    $exercises = $body['exercises'] ?? [];

    if (!$sessionId) jsonOut(['error' => 'session_id required'], 400);

    // Session in another club → 404; in this club but not the owner → 403.
    $ctx = requireClubPermission($pdo, $user, 'sessions.write');
    requireManageableSession($pdo, $user, $ctx, $sessionId);
    if (!is_array($exercises)) jsonOut(['error' => 'exercises must be a list'], 400);

    $pdo->beginTransaction();
    try {
        // Delete existing exercises
        $pdo->prepare('DELETE FROM club_session_exercises WHERE session_id = ?')
            ->execute([$sessionId]);

        // Insert new exercises
        $ins = $pdo->prepare(
            'INSERT INTO club_session_exercises
             (session_id, exercise_type, exercise_name, category, sets, reps,
              duration_seconds, rest_seconds, intensity, assessment_type, notes, sort_order)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );

        foreach ($exercises as $i => $ex) {
            $ins->execute([
                $sessionId,
                $ex['exercise_type'] ?? 'manual',
                trim($ex['exercise_name'] ?? $ex['name'] ?? ''),
                $ex['category']         ?? null,
                isset($ex['sets'])             ? (int)$ex['sets']             : null,
                isset($ex['reps'])             ? (int)$ex['reps']             : null,
                isset($ex['duration_seconds']) ? (int)$ex['duration_seconds'] : null,
                isset($ex['rest_seconds'])     ? (int)$ex['rest_seconds']     : null,
                $ex['intensity']        ?? 'medium',
                $ex['assessment_type']  ?? null,
                $ex['notes']            ?? null,
                $ex['sort_order']       ?? $i,
            ]);
        }

        // Update ai_enabled flag on session if any AI exercises
        $hasAi = !empty(array_filter($exercises, fn($e) => ($e['exercise_type'] ?? '') === 'ai'));
        $pdo->prepare('UPDATE club_sessions SET ai_enabled = ? WHERE id = ?')
            ->execute([(int)$hasAi, $sessionId]);

        $pdo->commit();
        jsonOut(['success' => true, 'count' => count($exercises)]);
    } catch (Throwable $e) {
        $pdo->rollBack();
        error_log('sessions/exercises.php: save failed: ' . $e->getMessage());
        jsonOut(['error' => 'Unable to save the session exercises'], 500);
    }
}

// ── DELETE: delete one exercise ────────────────────────────────────────────────
if ($method === 'DELETE') {
    $id = $_GET['id'] ?? (json_decode(file_get_contents('php://input'), true)['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id required'], 400);

    $ctx = requireClubPermission($pdo, $user, 'sessions.write');
    $lookup = $pdo->prepare(
        'SELECT cse.session_id FROM club_session_exercises cse
         JOIN club_sessions cs ON cs.id = cse.session_id
         WHERE cse.id = ? AND cs.club_id = ?'
    );
    $lookup->execute([(int)$id, $ctx['club_id']]);
    $exerciseSessionId = $lookup->fetchColumn();
    if ($exerciseSessionId === false) jsonOut(['error' => 'Exercise not found'], 404);
    requireManageableSession($pdo, $user, $ctx, (string)$exerciseSessionId);

    $stmt = $pdo->prepare('DELETE FROM club_session_exercises WHERE id = ?');
    $stmt->execute([(int)$id]);
    jsonOut(['success' => true, 'deleted' => $stmt->rowCount() > 0]);
}

jsonOut(['error' => 'Method not allowed'], 405);
