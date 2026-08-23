<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
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

$token = bearerToken();
if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['error' => 'Invalid token'], 401);
if (in_array($user['role'], ['player', 'parent'])) jsonOut(['error' => 'Forbidden'], 403);

$ctx = requireClubPermission($pdo, $user, 'sessions.read');
$clubId = (int)$ctx['club_id'];

$sessionId = trim($_GET['session_id'] ?? '');
if (!$sessionId) jsonOut(['error' => 'session_id is required'], 400);

// Verify session belongs to this coach
$sStmt = $pdo->prepare(
    'SELECT id, title, date, duration_min FROM club_sessions WHERE id = ? AND club_id = ?'
);
$sStmt->execute([$sessionId, $clubId]);
$session = $sStmt->fetch();
if (!$session) jsonOut(['error' => 'Session not found'], 404);

// Get session players with their pre (hooper) and post (rpe) wellness
$stmt = $pdo->prepare(
    "SELECT
        sp.player_user_id,
        cp.name,
        cp.id AS club_player_id,
        sp.status AS session_status,

        -- Pre-training Hooper for this session
        hi.hooper_score,
        hi.fatigue        AS hi_fatigue,
        hi.sleep_quality  AS hi_sleep,
        hi.stress         AS hi_stress,
        hi.muscle_soreness AS hi_soreness,
        hi.pain_today,
        hi.submitted_at   AS hooper_at,

        -- Post-training RPE for this session
        rpe.rpe_score,
        rpe.duration_minutes,
        rpe.training_load,
        rpe.submitted_at  AS rpe_at
     FROM session_players sp
     JOIN club_players cp
           ON cp.linked_user_id = sp.player_user_id
          AND cp.club_id = ?
     LEFT JOIN player_hooper_index hi
           ON hi.user_id = sp.player_user_id
          AND (hi.session_id = ? OR hi.training_session_id = ?)
     LEFT JOIN player_rpe rpe
           ON rpe.user_id = sp.player_user_id
          AND (rpe.session_id = ? OR rpe.training_session_id = ?)
          AND rpe.rpe_type = 'post'
     WHERE sp.session_id = ?
     ORDER BY cp.name ASC"
);
$stmt->execute([$clubId, $sessionId, $sessionId, $sessionId, $sessionId, $sessionId]);
$rows = $stmt->fetchAll();

$total         = count($rows);
$preCompleted  = 0;
$postCompleted = 0;
$players       = [];

foreach ($rows as $r) {
    $hasHooper = $r['hooper_score'] !== null;
    $hasRpe    = $r['rpe_score']    !== null;
    if ($hasHooper) $preCompleted++;
    if ($hasRpe)    $postCompleted++;

    $hs = $hasHooper ? (int)$r['hooper_score'] : null;
    $wStatus = match(true) {
        $hs === null        => 'no_data',
        $hs >= 17           => 'high_risk',
        $hs >= 13           => 'moderate',
        default             => 'normal',
    };

    $players[] = [
        'player_id'       => $r['club_player_id'],
        'name'            => $r['name'],
        'session_status'  => $r['session_status'],
        'pre_wellness'    => $hasHooper ? [
            'hooper_score'    => $hs,
            'fatigue'         => (int)$r['hi_fatigue'],
            'sleep_quality'   => (int)$r['hi_sleep'],
            'stress'          => (int)$r['hi_stress'],
            'muscle_soreness' => (int)$r['hi_soreness'],
            'pain_today'      => (int)($r['pain_today'] ?? 0),
            'submitted_at'    => $r['hooper_at'],
            'wellness_status' => $wStatus,
        ] : null,
        'post_rpe' => $hasRpe ? [
            'rpe_score'       => $r['rpe_score'] !== null ? (float)$r['rpe_score'] : null,
            'duration_minutes'=> (int)$r['duration_minutes'],
            'training_load'   => $r['training_load'] !== null ? (float)$r['training_load'] : null,
            'submitted_at'    => $r['rpe_at'],
        ] : null,
    ];
}

jsonOut([
    'success'          => true,
    'session_id'       => $sessionId,
    'session_title'    => $session['title'],
    'session_date'     => $session['date'],
    'total_players'    => $total,
    'pre_completed'    => $preCompleted,
    'post_completed'   => $postCompleted,
    'pre_pct'          => $total > 0 ? round($preCompleted / $total * 100) : 0,
    'post_pct'         => $total > 0 ? round($postCompleted / $total * 100) : 0,
    'players'          => $players,
]);
