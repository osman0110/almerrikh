<?php
/**
 * Medical workbench data for doctor/medical staff.
 * Keeps clinical cases, today's readiness alerts, and treatment sessions in
 * one permission-gated response without exposing this data to coaches.
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
        $headers = apache_request_headers();
        $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    }
    return stripos($auth, 'Bearer ') === 0 ? trim(substr($auth, 7)) : trim($auth);
}

function authUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['success' => false, 'message' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.role, u.name FROM users u
         JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

$user = authUser($pdo);
$ctx = requireClubPermission($pdo, $user, 'medical.read');
$clubId = (int)$ctx['club_id'];
$date = trim($_GET['date'] ?? date('Y-m-d'));

$rosterStmt = $pdo->prepare(
    "SELECT id, name, position, linked_user_id, status, unavailable_reason, expected_return_date
     FROM club_players
     WHERE club_id = ? AND is_active = 1
       AND (player_type IS NULL OR player_type = 'club')
     ORDER BY name ASC"
);
$rosterStmt->execute([$clubId]);
$players = $rosterStmt->fetchAll(PDO::FETCH_ASSOC);

$linkedIds = array_values(array_filter(array_map(
    static fn($id): int => (int)$id,
    array_column($players, 'linked_user_id')
)));
$hooperByUser = [];
if ($linkedIds) {
    $placeholders = implode(',', array_fill(0, count($linkedIds), '?'));
    $stmt = $pdo->prepare(
        "SELECT user_id, hooper_score, fatigue, sleep_quality, muscle_soreness,
                pain_today, submitted_at
         FROM player_hooper_index
         WHERE DATE(submitted_at) = ? AND user_id IN ($placeholders)
         ORDER BY submitted_at DESC"
    );
    $stmt->execute(array_merge([$date], $linkedIds));
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $userId = (int)$row['user_id'];
        if (!isset($hooperByUser[$userId])) $hooperByUser[$userId] = $row;
    }
}

$casesStmt = $pdo->prepare(
    "SELECT c.id, c.player_id, p.name AS player_name, c.injury_date,
            c.body_location, c.injury_type, c.severity, c.case_status,
            c.rtp_stage, c.expected_return_date, c.updated_at
     FROM injury_cases c
     JOIN club_players p ON p.id = c.player_id AND p.club_id = c.club_id
     WHERE c.club_id = ? AND c.case_status NOT IN ('graduated', 'closed')
     ORDER BY c.updated_at DESC, c.id DESC"
);
$casesStmt->execute([$clubId]);
$cases = $casesStmt->fetchAll(PDO::FETCH_ASSOC);
$openCaseByPlayer = [];
foreach ($cases as $index => $case) {
    $openCaseByPlayer[(string)$case['player_id']] = true;
    $case['id'] = (string)$case['id'];
    $case['player_id'] = (string)$case['player_id'];
    $case['severity'] = $case['severity'] ?? 'moderate';
    $case['case_status'] = $case['case_status'] ?? 'open';
    $cases[$index] = $case;
}

$sessionsStmt = $pdo->prepare(
    "SELECT sp.id, sp.player_id, p.name AS player_name, s.therapist_user_id,
            u.name AS therapist_name, COALESCE(cs.staff_role, u.role) AS therapist_role,
            s.scheduled_at, s.duration_minutes, s.room, s.body_area,
            s.session_reason, s.treatment_type, sp.status, sp.recommendation
     FROM physio_session_players sp
     JOIN physio_sessions s ON s.id = sp.session_id
     LEFT JOIN club_players p ON p.id = sp.player_id AND p.club_id = s.club_id
     LEFT JOIN users u ON u.id = s.therapist_user_id
     LEFT JOIN club_staff cs ON cs.user_id = s.therapist_user_id
                            AND cs.club_id = s.club_id AND cs.status = 'active'
     WHERE s.club_id = ? AND DATE(s.scheduled_at) = ?
     ORDER BY s.scheduled_at ASC, sp.id ASC"
);
$sessionsStmt->execute([$clubId, $date]);
$sessions = array_map(static function (array $row): array {
    $row['id'] = (string)$row['id'];
    $row['player_id'] = (string)$row['player_id'];
    $row['therapist_user_id'] = (string)$row['therapist_user_id'];
    $row['duration_minutes'] = (int)$row['duration_minutes'];
    return $row;
}, $sessionsStmt->fetchAll(PDO::FETCH_ASSOC));

$attention = [];
$submitted = 0;
$missing = 0;
$highRisk = 0;
$painAlerts = 0;
$rehabDue = 0;
$today = new DateTimeImmutable($date);
$dueLimit = $today->modify('+7 days')->format('Y-m-d');

foreach ($players as $player) {
    $playerId = (string)$player['id'];
    $userId = (int)($player['linked_user_id'] ?? 0);
    $hooper = $userId > 0 ? ($hooperByUser[$userId] ?? null) : null;
    if ($hooper) {
        $submitted++;
    } else {
        $missing++;
    }

    if (!empty($player['expected_return_date']) &&
        $player['expected_return_date'] >= $today->format('Y-m-d') &&
        $player['expected_return_date'] <= $dueLimit) {
        $rehabDue++;
    }

    if ($hooper) {
        $score = (float)($hooper['hooper_score'] ?? 0);
        $pain = (int)($hooper['pain_today'] ?? 0);
        $soreness = (int)($hooper['muscle_soreness'] ?? 0);
        if ($score >= 17) {
            $highRisk++;
            $attention[] = [
                'type' => 'high_risk',
                'severity' => 'danger',
                'player_id' => $playerId,
                'player_name' => $player['name'],
                'message' => 'High Hooper risk score: ' . (int)$score,
                'hooper_score' => (int)$score,
            ];
        }
        if ($pain > 0) {
            $painAlerts++;
            $attention[] = [
                'type' => 'pain_reported',
                'severity' => 'danger',
                'player_id' => $playerId,
                'player_name' => $player['name'],
                'message' => 'Player reported pain today',
                'pain_today' => $pain,
            ];
        } elseif ($soreness >= 7) {
            $attention[] = [
                'type' => 'muscle_soreness',
                'severity' => 'warning',
                'player_id' => $playerId,
                'player_name' => $player['name'],
                'message' => 'High muscle soreness reported today',
                'muscle_soreness' => $soreness,
            ];
        }
    }

    if (isset($openCaseByPlayer[$playerId])) {
        $attention[] = [
            'type' => 'open_injury_case',
            'severity' => 'danger',
            'player_id' => $playerId,
            'player_name' => $player['name'],
            'message' => 'Open injury or rehabilitation case',
        ];
    }
}

$rosterOut = array_map(static function (array $player): array {
    return [
        'player_id' => (string)$player['id'],
        'player_name' => $player['name'],
        'position' => $player['position'],
        'status' => $player['status'],
    ];
}, $players);

jsonOut([
    'success' => true,
    'date' => $date,
    'summary' => [
        'open_injury_cases' => count($cases),
        'readiness_submitted' => $submitted,
        'readiness_missing' => $missing,
        'high_risk' => $highRisk,
        'pain_alerts' => $painAlerts,
        'sessions_today' => count($sessions),
        'rehab_due_7_days' => $rehabDue,
    ],
    'cases' => array_values($cases),
    'sessions' => $sessions,
    'attention' => $attention,
    'players' => $rosterOut,
]);
