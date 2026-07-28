<?php
/**
 * GET /api/coach/plans/detail.php?id=<plan_id>
 * Returns plan + sessions (grouped by week) + exercises + assigned players.
 * Allowed roles: club, coach, academy
 */
require_once dirname(__DIR__, 2) . '/db.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') { http_response_code(405); echo '{"error":"Method not allowed"}'; exit; }

function jsonOut(array $d, int $c = 200): never {
    http_response_code($c);
    echo json_encode($d, JSON_UNESCAPED_UNICODE);
    exit;
}
function bearerToken(): string {
    $a = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? $_SERVER['Authorization'] ?? '';
    if (!$a && function_exists('apache_request_headers')) { $h = apache_request_headers(); $a = $h['Authorization'] ?? $h['authorization'] ?? ''; }
    return stripos($a, 'Bearer ') === 0 ? trim(substr($a, 7)) : trim($a);
}
function getAuthUser(PDO $pdo): array {
    $tok = bearerToken();
    if (!$tok) jsonOut(['error' => 'Unauthorized'], 401);
    $s = $pdo->prepare('SELECT u.id,u.role FROM users u JOIN user_tokens t ON u.id=t.user_id WHERE t.token=?');
    $s->execute([$tok]); $u = $s->fetch();
    if (!$u) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $u;
}

$user = getAuthUser($pdo);
if (!in_array($user['role'], ['club','coach','academy'], true)) jsonOut(['error' => 'Forbidden'], 403);
$coachId = (int)$user['id'];

$planId = trim((string)($_GET['id'] ?? ''));
if (!$planId) jsonOut(['error' => 'id is required'], 400);

// Verify ownership
$stmt = $pdo->prepare(
    'SELECT id,plan_type,title,goal,status,target_type,num_weeks,
            plan_summary,recovery_notes,progression_rules,created_at
     FROM training_plans WHERE id=? AND coach_user_id=?'
);
$stmt->execute([$planId, $coachId]);
$plan = $stmt->fetch();
if (!$plan) jsonOut(['error' => 'Plan not found'], 404);

// Assigned players
$ps = $pdo->prepare(
    'SELECT pp.club_player_id, cp.name, cp.position
     FROM plan_players pp
     LEFT JOIN club_players cp ON cp.id = pp.club_player_id
     WHERE pp.plan_id = ?'
);
$ps->execute([$planId]);
$players = $ps->fetchAll();

// Sessions
$ss = $pdo->prepare(
    'SELECT id,title,session_date,duration_minutes,objective,status,week_number,intensity
     FROM training_sessions WHERE plan_id=? ORDER BY week_number,session_date'
);
$ss->execute([$planId]);
$sessRows = $ss->fetchAll();

// Exercises per session
$exs = $pdo->prepare(
    'SELECT id,session_id,exercise_name,category,sets,reps,
            duration_seconds,rest_seconds,instructions,
            requires_pose_detection,assessment_type,sort_order
     FROM session_exercises WHERE session_id=? ORDER BY sort_order'
);

// Completion counts per session (published plans)
$compStmt = $pdo->prepare(
    "SELECT COUNT(*) total, SUM(status='completed') done FROM session_players WHERE session_id=?"
);

$weekMap = [];
foreach ($sessRows as $sess) {
    $wn = (int)$sess['week_number'];
    if (!isset($weekMap[$wn])) $weekMap[$wn] = [];

    $exs->execute([$sess['id']]);
    $exercises = [];
    foreach ($exs->fetchAll() as $ex) {
        $exercises[] = [
            'id'                      => $ex['id'],
            'exercise_name'           => $ex['exercise_name'],
            'category'                => $ex['category'],
            'sets'                    => $ex['sets']             !== null ? (int)$ex['sets']             : null,
            'reps'                    => $ex['reps']             !== null ? (int)$ex['reps']             : null,
            'duration_seconds'        => $ex['duration_seconds'] !== null ? (int)$ex['duration_seconds'] : null,
            'rest_seconds'            => $ex['rest_seconds']     !== null ? (int)$ex['rest_seconds']     : null,
            'instructions'            => $ex['instructions'],
            'requires_pose_detection' => (bool)$ex['requires_pose_detection'],
            'assessment_type'         => $ex['assessment_type'],
            'sort_order'              => (int)$ex['sort_order'],
        ];
    }

    $compStmt->execute([$sess['id']]);
    $comp = $compStmt->fetch();

    $weekMap[$wn][] = [
        'id'               => $sess['id'],
        'title'            => $sess['title'],
        'session_date'     => $sess['session_date'],
        'duration_minutes' => (int)$sess['duration_minutes'],
        'objective'        => $sess['objective'],
        'status'           => $sess['status'],
        'intensity'        => $sess['intensity'],
        'exercise_count'   => count($exercises),
        'exercises'        => $exercises,
        'assigned_count'   => (int)($comp['total'] ?? 0),
        'completed_count'  => (int)($comp['done']  ?? 0),
    ];
}

ksort($weekMap);
$weeks = [];
foreach ($weekMap as $wn => $sessions) {
    $weeks[] = ['week' => $wn, 'sessions' => $sessions];
}

jsonOut([
    'success' => true,
    'plan' => [
        'id'                => $plan['id'],
        'plan_type'         => $plan['plan_type'],
        'title'             => $plan['title'],
        'goal'              => $plan['goal'],
        'status'            => $plan['status'],
        'target_type'       => $plan['target_type'],
        'num_weeks'         => (int)$plan['num_weeks'],
        'summary'           => $plan['plan_summary'],
        'recovery_notes'    => $plan['recovery_notes'],
        'progression_rules' => $plan['progression_rules'],
        'created_at'        => $plan['created_at'],
        'players'           => array_map(fn($p) => [
            'club_player_id' => $p['club_player_id'],
            'name'           => $p['name'],
            'position'       => $p['position'],
        ], $players),
        'weeks' => $weeks,
    ],
]);
