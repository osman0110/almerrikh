<?php
/**
 * Admin/org-level dashboard aggregate — composite player status counts
 * (ready/ready_with_note/high_strain/injured/rehab/incomplete_data), rolling
 * minutes + cards totals, medical/massage session counts, and the next
 * upcoming matches/sessions. One call instead of the club dashboard fanning
 * out to 5+ endpoints just to show admin-level totals.
 *
 * GET ?date=YYYY-MM-DD (defaults to today)
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';
require_once dirname(__DIR__) . '/includes/player_status.php';

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

$ctx  = requireClubPermission($pdo, $user, 'admin_dashboard.read');
$cid  = (int)$ctx['club_id'];
$date = trim($_GET['date'] ?? date('Y-m-d'));
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
    jsonOut(['success' => false, 'message' => 'Invalid date'], 400);
}
$parsedDate = DateTimeImmutable::createFromFormat('!Y-m-d', $date);
if (!$parsedDate || $parsedDate->format('Y-m-d') !== $date) {
    jsonOut(['success' => false, 'message' => 'Invalid date'], 400);
}
$rangeTo   = $date;
$rangeFrom = date('Y-m-d', strtotime('-30 days', strtotime($rangeTo)));

// ── Roster + today's readiness + today's decision → composite status ────────
$roster = $pdo->prepare(
    'SELECT id, linked_user_id, status FROM club_players
     WHERE club_id = ? AND is_active = 1 AND player_type = "club"'
);
$roster->execute([$cid]);
$players = $roster->fetchAll(PDO::FETCH_ASSOC);

$linkedUserIds = array_values(array_filter(array_column($players, 'linked_user_id')));
$hooperByUser = [];
if ($linkedUserIds) {
    $inList = implode(',', array_fill(0, count($linkedUserIds), '?'));
    $stmt = $pdo->prepare(
        "SELECT user_id, hooper_score, fatigue, sleep_quality
         FROM player_hooper_index
         WHERE DATE(submitted_at) = ? AND user_id IN ($inList)"
    );
    $stmt->execute(array_merge([$date], $linkedUserIds));
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $hooperByUser[(int)$row['user_id']] = $row;
    }
}

$decisionByPlayer = [];
$stmt = $pdo->prepare(
    'SELECT player_id, participation_status FROM player_daily_decisions
     WHERE club_id = ? AND decision_date = ?'
);
$stmt->execute([$cid, $date]);
foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
    $decisionByPlayer[$row['player_id']] = $row;
}

$compositeCounts = [
    'ready' => 0, 'ready_with_note' => 0, 'high_strain' => 0,
    'injured' => 0, 'rehab' => 0, 'incomplete_data' => 0,
];
$playersCheckedIn = 0;
foreach ($players as $p) {
    $userId = $p['linked_user_id'] ? (int)$p['linked_user_id'] : null;
    $hooper = $userId && isset($hooperByUser[$userId]) ? $hooperByUser[$userId] : null;
    if ($hooper !== null) $playersCheckedIn++;
    $decision = $decisionByPlayer[$p['id']] ?? null;
    $status = computePlayerCompositeStatus($p['status'], $hooper, $decision);
    $compositeCounts[$status]++;
}

$readyCount = $compositeCounts['ready'];
$followUpCount = $compositeCounts['ready_with_note']
    + $compositeCounts['high_strain']
    + $compositeCounts['incomplete_data'];
$unavailableCount = $compositeCounts['injured'] + $compositeCounts['rehab'];

// ── Rolling minutes + cards totals (last 30 days, club-wide) ────────────────
$totalMinutes = 0;
$mStmt = $pdo->prepare(
    'SELECT player_minutes FROM matches WHERE club_id = ? AND match_date BETWEEN ? AND ?'
);
$mStmt->execute([$cid, $rangeFrom, $rangeTo]);
foreach ($mStmt->fetchAll() as $row) {
    $minutes = $row['player_minutes'] && $row['player_minutes'] !== 'null'
        ? json_decode($row['player_minutes'], true) ?? [] : [];
    foreach ($minutes as $mins) {
        $totalMinutes += (int)$mins;
    }
}

$yellowCards = 0;
$redCards    = 0;
$cStmt = $pdo->prepare(
    'SELECT mc.card_type, COUNT(*) AS cnt
     FROM match_cards mc JOIN matches m ON m.id = mc.match_id
     WHERE m.club_id = ? AND m.match_date BETWEEN ? AND ?
     GROUP BY mc.card_type'
);
$cStmt->execute([$cid, $rangeFrom, $rangeTo]);
foreach ($cStmt->fetchAll() as $row) {
    if ($row['card_type'] === 'yellow') $yellowCards = (int)$row['cnt'];
    if ($row['card_type'] === 'red')    $redCards    = (int)$row['cnt'];
}

// ── Medical / massage session counts ─────────────────────────────────────────
$stmt = $pdo->prepare('SELECT COUNT(*) FROM injury_cases WHERE club_id = ? AND case_status = "open"');
$stmt->execute([$cid]);
$openInjuryCases = (int)$stmt->fetchColumn();

$stmt = $pdo->prepare(
    'SELECT COUNT(*) FROM physio_sessions WHERE club_id = ? AND DATE(scheduled_at) = ?'
);
$stmt->execute([$cid, $date]);
$physioSessionsToday = (int)$stmt->fetchColumn();

$overdueTasks = 0;
$tasksAvailable = SchemaInspector::hasTable($pdo, 'tasks');
if ($tasksAvailable) {
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM tasks
         WHERE club_id = ?
           AND due_date IS NOT NULL
           AND due_date < ?
           AND status NOT IN ("completed", "cancelled")'
    );
    $stmt->execute([$cid, $date]);
    $overdueTasks = (int)$stmt->fetchColumn();
}

// ── Upcoming matches/sessions (next 5, combined, from today forward) ────────
$upcoming = [];
$stmt = $pdo->prepare(
    'SELECT id, title AS name, date AS event_date, "session" AS type
     FROM club_sessions WHERE club_id = ? AND date >= ?
     ORDER BY date ASC LIMIT 5'
);
$stmt->execute([$cid, $date]);
$upcoming = array_merge($upcoming, $stmt->fetchAll(PDO::FETCH_ASSOC));

$stmt = $pdo->prepare(
    'SELECT id, opponent AS name, match_date AS event_date, "match" AS type
     FROM matches WHERE club_id = ? AND match_date >= ?
     ORDER BY match_date ASC LIMIT 5'
);
$stmt->execute([$cid, $date]);
$upcoming = array_merge($upcoming, $stmt->fetchAll(PDO::FETCH_ASSOC));

usort($upcoming, fn($a, $b) => strcmp($a['event_date'], $b['event_date']));
$upcoming = array_slice($upcoming, 0, 5);

jsonOut([
    'success'          => true,
    'generated_at'     => date(DATE_ATOM),
    'date'             => $date,
    'composite_counts' => $compositeCounts,
    'today_summary'    => [
        'ready'           => $readyCount,
        'needs_follow_up' => $followUpCount,
        'unavailable'     => $unavailableCount,
        'total_players'   => count($players),
    ],
    'data_quality'     => [
        'total_players'      => count($players),
        'players_checked_in' => $playersCheckedIn,
        'missing_check_in'   => $compositeCounts['incomplete_data'],
        'tasks_available'    => $tasksAvailable,
    ],
    'attention_items'  => [
        [
            'type' => 'injuries',
            'count' => $openInjuryCases,
            'route' => '/club/players',
            'filter' => 'injured',
        ],
        [
            'type' => 'missing_check_in',
            'count' => $compositeCounts['incomplete_data'],
            'route' => '/club/players',
            'filter' => 'missing_wellness',
        ],
        [
            'type' => 'overdue_tasks',
            'count' => $overdueTasks,
            'route' => '/club/tasks',
        ],
        [
            'type' => 'physio_today',
            'count' => $physioSessionsToday,
            'route' => '/club/reports',
        ],
    ],
    'range'            => ['from' => $rangeFrom, 'to' => $rangeTo],
    'totals'           => [
        'total_minutes' => $totalMinutes,
        'yellow_cards'  => $yellowCards,
        'red_cards'     => $redCards,
    ],
    'medical' => [
        'open_injury_cases'     => $openInjuryCases,
        'physio_sessions_today' => $physioSessionsToday,
    ],
    'upcoming' => array_values($upcoming),
]);
