<?php
/**
 * Player full report — one-call aggregate combining profile, latest
 * readiness check-in, 30-day training attendance, match participation stats,
 * latest assessment scores, and a coach-safe medical/physio summary (status
 * and counts only — never diagnosis or specialist notes).
 *
 * GET ?player_id=X
 */
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
if (!$token) jsonOut(['success' => false, 'message' => 'Unauthorized'], 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id
     WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

$ctx = requireClubPermission($pdo, $user, 'players.read');
$cid = (int)$ctx['club_id'];

$playerId = trim($_GET['player_id'] ?? '');
if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id is required'], 400);

$stmt = $pdo->prepare(
    'SELECT id, name, number, position, dominant_foot, team_name, status,
            unavailable_reason, expected_return_date, date_of_birth,
            latest_score, movement_score, stability_score, symmetry_score,
            control_score, last_assessment_at, linked_user_id
     FROM club_players WHERE id = ? AND club_id = ?'
);
$stmt->execute([$playerId, $cid]);
$player = $stmt->fetch();
if (!$player) jsonOut(['success' => false, 'message' => 'Player not found'], 404);

$today = date('Y-m-d');
$from30 = date('Y-m-d', strtotime('-30 days'));
$from90 = date('Y-m-d', strtotime('-90 days'));

// ── Latest readiness check-in ────────────────────────────────────────────────
$readiness = null;
if ($player['linked_user_id']) {
    $stmt = $pdo->prepare(
        'SELECT hooper_score, fatigue, sleep_quality, submitted_at
         FROM player_hooper_index WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 1'
    );
    $stmt->execute([(int)$player['linked_user_id']]);
    $readiness = $stmt->fetch() ?: null;
}

// ── 30-day training attendance ───────────────────────────────────────────────
$attendance = ['present' => 0, 'late' => 0, 'absent' => 0];
$stmt = $pdo->prepare(
    'SELECT sa.status, COUNT(*) AS cnt
     FROM session_attendance sa
     JOIN club_sessions cs ON cs.id = sa.session_id
     WHERE cs.club_id = ? AND sa.player_id = ? AND cs.date BETWEEN ? AND ?
     GROUP BY sa.status'
);
$stmt->execute([$cid, $playerId, $from30, $today]);
foreach ($stmt->fetchAll() as $row) {
    if (isset($attendance[$row['status']])) $attendance[$row['status']] = (int)$row['cnt'];
}

// ── 90-day match participation ───────────────────────────────────────────────
$partStmt = $pdo->prepare(
    'SELECT mp.starter, mp.played, mp.minutes_played, mp.goals, mp.assists
     FROM match_participations mp
     JOIN matches m ON m.id = mp.match_id
     WHERE m.club_id = ? AND mp.player_id = ? AND m.match_date BETWEEN ? AND ?'
);
$partStmt->execute([$cid, $playerId, $from90, $today]);
$appearances = 0; $starts = 0; $minutes = 0; $goals = 0; $assists = 0;
foreach ($partStmt->fetchAll() as $r) {
    if ((int)$r['played'] === 1) {
        $appearances++;
        if ((int)$r['starter'] === 1) $starts++;
    }
    $minutes += (int)$r['minutes_played'];
    $goals   += (int)$r['goals'];
    $assists += (int)$r['assists'];
}

$yellow = 0; $red = 0;
$cardStmt = $pdo->prepare(
    'SELECT mc.card_type, COUNT(*) AS cnt
     FROM match_cards mc JOIN matches m ON m.id = mc.match_id
     WHERE m.club_id = ? AND mc.player_id = ? AND m.match_date BETWEEN ? AND ?
     GROUP BY mc.card_type'
);
$cardStmt->execute([$cid, $playerId, $from90, $today]);
foreach ($cardStmt->fetchAll() as $r) {
    if ($r['card_type'] === 'yellow') $yellow = (int)$r['cnt'];
    if ($r['card_type'] === 'red')    $red    = (int)$r['cnt'];
}

// ── Coach-safe medical/physio summary — counts only, never diagnosis ────────
$stmt = $pdo->prepare(
    'SELECT COUNT(*) FROM injury_cases WHERE club_id = ? AND player_id = ? AND case_status = "open"'
);
$stmt->execute([$cid, $playerId]);
$openInjuryCases = (int)$stmt->fetchColumn();

$stmt = $pdo->prepare(
    'SELECT COUNT(*) FROM physio_sessions WHERE club_id = ? AND player_id = ? AND scheduled_at >= ?'
);
$stmt->execute([$cid, $playerId, $from30]);
$physioSessions30d = (int)$stmt->fetchColumn();

jsonOut([
    'success' => true,
    'profile' => [
        'player_id'      => $player['id'],
        'name'           => $player['name'],
        'number'         => $player['number'],
        'position'       => $player['position'],
        'dominant_foot'  => $player['dominant_foot'],
        'team_name'      => $player['team_name'],
        'status'         => $player['status'],
        'date_of_birth'  => $player['date_of_birth'],
    ],
    'readiness' => $readiness ? [
        'hooper_score'  => (int)$readiness['hooper_score'],
        'fatigue'       => (int)$readiness['fatigue'],
        'sleep_quality' => (int)$readiness['sleep_quality'],
        'submitted_at'  => $readiness['submitted_at'],
    ] : null,
    'training_30d' => $attendance,
    'matches_90d' => [
        'appearances' => $appearances,
        'starts'      => $starts,
        'minutes'     => $minutes,
        'goals'       => $goals,
        'assists'     => $assists,
        'yellow_cards' => $yellow,
        'red_cards'    => $red,
    ],
    'assessments' => [
        'latest_score'    => $player['latest_score'] !== null ? (float)$player['latest_score'] : null,
        'movement_score'  => $player['movement_score'] !== null ? (float)$player['movement_score'] : null,
        'stability_score' => $player['stability_score'] !== null ? (float)$player['stability_score'] : null,
        'symmetry_score'  => $player['symmetry_score'] !== null ? (float)$player['symmetry_score'] : null,
        'control_score'   => $player['control_score'] !== null ? (float)$player['control_score'] : null,
        'last_assessment_at' => $player['last_assessment_at'],
    ],
    'medical' => [
        'status'                => $player['status'],
        'unavailable_reason'    => $player['unavailable_reason'],
        'expected_return_date'  => $player['expected_return_date'],
        'open_injury_cases'     => $openInjuryCases,
        'physio_sessions_30d'   => $physioSessions30d,
    ],
]);
