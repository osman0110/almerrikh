<?php
require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';
require_once dirname(__DIR__) . '/includes/fitness/FitnessConfig.php';
require_once dirname(__DIR__) . '/includes/fitness/SchemaInspector.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

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
    return stripos($auth, 'Bearer ') === 0
        ? trim(substr($auth, 7))
        : trim($auth);
}

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if ($token === '') jsonOut(['error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.role FROM users u
         JOIN user_tokens t ON t.user_id = u.id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())
         LIMIT 1'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

function archivePeriod(
    PDO $pdo,
    int $clubId,
    int $teamId,
    int $userId,
    string $type,
    string $kind,
    DateTimeImmutable $from,
    DateTimeImmutable $to,
    int $dataCount
): void {
    $stmt = $pdo->prepare(
        'INSERT INTO report_period_archives
         (club_id, team_id, report_type, period_kind, period_start, period_end,
          data_count, generated_by_user_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
            data_count = VALUES(data_count),
            last_refreshed_at = CURRENT_TIMESTAMP'
    );
    $stmt->execute([
        $clubId,
        $teamId,
        $type,
        $kind,
        $from->format('Y-m-d'),
        $to->format('Y-m-d'),
        max(0, $dataCount),
        $userId,
    ]);
}

function countDates(array $dates, DateTimeImmutable $from, DateTimeImmutable $to): int {
    $start = $from->format('Y-m-d');
    $end = $to->format('Y-m-d');
    return count(array_filter(
        $dates,
        static fn(string $date): bool => $date >= $start && $date <= $end
    ));
}

function periodPlayerStats(
    array $records,
    DateTimeImmutable $from,
    DateTimeImmutable $to,
    array $activePlayerIds,
    int $rosterCount
): array {
    $start = $from->format('Y-m-d');
    $end = $to->format('Y-m-d');
    $playerIds = [];
    foreach ($records as $record) {
        $date = (string)($record['date'] ?? '');
        $playerId = trim((string)($record['player_id'] ?? ''));
        if ($playerId !== ''
            && isset($activePlayerIds[$playerId])
            && $date >= $start
            && $date <= $end) {
            $playerIds[$playerId] = true;
        }
    }
    $playerCount = count($playerIds);
    return [
        'player_count' => $playerCount,
        'data_completeness' => $rosterCount > 0
            ? round($playerCount / $rosterCount, 4)
            : 0.0,
    ];
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonOut(['error' => 'Method not allowed'], 405);
}

$user = getAuthUser($pdo);
if (in_array($user['role'], ['player', 'parent'], true)) {
    jsonOut(['error' => 'Forbidden'], 403);
}
$ctx = resolveClubContext($pdo, $user);
if (!$ctx['club_id']) jsonOut(['error' => 'Not a member of a club'], 403);

$canLoad = clubStaffCan((string)$ctx['staff_role'], 'fitness.training_load.view');
$canBody = clubStaffCan((string)$ctx['staff_role'], 'fitness.body_composition.view');
if (!$canLoad && !$canBody) jsonOut(['error' => 'Forbidden'], 403);
if (!SchemaInspector::hasTable($pdo, 'report_period_archives')) {
    jsonOut(['error' => 'REPORT_ARCHIVE_MIGRATION_REQUIRED'], 503);
}

$clubId = (int)$ctx['club_id'];
$teamScope = $ctx['team_id'] !== null ? (int)$ctx['team_id'] : 0;
$timezone = FitnessConfig::timezone();
$today = new DateTimeImmutable('today', $timezone);
$rosterSql = 'SELECT id FROM club_players WHERE club_id = ? AND is_active = 1';
$rosterParams = [$clubId];
if ($teamScope > 0) {
    $rosterSql .= ' AND team_id = ?';
    $rosterParams[] = $teamScope;
}
$rosterStmt = $pdo->prepare($rosterSql);
$rosterStmt->execute($rosterParams);
$activePlayerIds = array_fill_keys(
    array_map('strval', $rosterStmt->fetchAll(PDO::FETCH_COLUMN)),
    true
);
$rosterCount = count($activePlayerIds);
$loadRecords = [];
$bodyRecords = [];

if ($canLoad) {
    $activeFilter = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active')
        ? ' AND COALESCE(r.is_active, 1) = 1'
        : '';
    $teamFilter = $teamScope > 0 ? ' AND cp.team_id = ?' : '';
    $params = [$clubId];
    if ($teamScope > 0) $params[] = $teamScope;
    $stmt = $pdo->prepare(
        'SELECT cp.id AS player_id, r.submitted_at
         FROM player_rpe r
         INNER JOIN club_players cp
           ON cp.club_id = ?
          AND (cp.id = r.linked_player_id
               OR (r.linked_player_id IS NULL AND cp.linked_user_id = r.user_id))
         WHERE r.submitted_at IS NOT NULL' . $activeFilter . $teamFilter . '
         ORDER BY r.submitted_at ASC'
    );
    $stmt->execute($params);
    $loadDates = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $date = (new DateTimeImmutable((string)$row['submitted_at'], new DateTimeZone('UTC')))
            ->setTimezone($timezone)
            ->format('Y-m-d');
        $loadDates[] = $date;
        $loadRecords[] = [
            'player_id' => (string)$row['player_id'],
            'date' => $date,
        ];
    }

    if ($loadDates) {
        $first = new DateTimeImmutable(min($loadDates), $timezone);
        $weekStart = $first->modify('monday this week');
        $iterations = 0;
        for ($from = $weekStart; $iterations < 260; $from = $from->modify('+7 days'), $iterations++) {
            $to = $from->modify('+6 days');
            if ($to >= $today) break;
            archivePeriod(
                $pdo, $clubId, $teamScope, (int)$user['id'],
                'training_load_weekly', 'week', $from, $to,
                countDates($loadDates, $from, $to)
            );
        }

        $iterations = 0;
        for ($to = $weekStart->modify('+27 days'); $iterations < 260; $to = $to->modify('+7 days'), $iterations++) {
            if ($to >= $today) break;
            $from = $to->modify('-27 days');
            archivePeriod(
                $pdo, $clubId, $teamScope, (int)$user['id'],
                'training_load_28d', '28_days', $from, $to,
                countDates($loadDates, $from, $to)
            );
        }
    }
}

if ($canBody) {
    $bodyDates = [];
    $teamFilter = $teamScope > 0 ? ' AND cp.team_id = ?' : '';
    $params = [$clubId];
    if ($teamScope > 0) $params[] = $teamScope;
    $stmt = $pdo->prepare(
        'SELECT a.linked_player_id AS player_id, a.assessment_date
         FROM player_body_composition_assessments a
         LEFT JOIN club_players cp ON cp.id = a.linked_player_id
         WHERE a.club_id = ? AND a.deleted_at IS NULL' . $teamFilter
    );
    $stmt->execute($params);
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $date = substr((string)$row['assessment_date'], 0, 10);
        $bodyDates[] = $date;
        $bodyRecords[] = [
            'player_id' => (string)($row['player_id'] ?? ''),
            'date' => $date,
        ];
    }

    if ($bodyDates) {
        $from = (new DateTimeImmutable(min($bodyDates), $timezone))->modify('first day of this month');
        $iterations = 0;
        while ($from < $today->modify('first day of this month') && $iterations < 60) {
            $to = $from->modify('last day of this month');
            archivePeriod(
                $pdo, $clubId, $teamScope, (int)$user['id'],
                'body_composition_monthly', 'month', $from, $to,
                countDates($bodyDates, $from, $to)
            );
            $from = $from->modify('first day of next month');
            $iterations++;
        }
    }
}

$types = [];
if ($canLoad) $types = ['training_load_weekly', 'training_load_28d'];
if ($canBody) $types[] = 'body_composition_monthly';
$placeholders = implode(',', array_fill(0, count($types), '?'));
$stmt = $pdo->prepare(
    "SELECT id, report_type, period_kind, period_start, period_end,
            data_count, generated_at, last_refreshed_at
     FROM report_period_archives
     WHERE club_id = ? AND team_id = ? AND report_type IN ($placeholders)
     ORDER BY period_end DESC, report_type ASC
     LIMIT 200"
);
$stmt->execute([$clubId, $teamScope, ...$types]);
$reports = $stmt->fetchAll(PDO::FETCH_ASSOC);
foreach ($reports as &$report) {
    $from = new DateTimeImmutable((string)$report['period_start'], $timezone);
    $to = new DateTimeImmutable((string)$report['period_end'], $timezone);
    $records = $report['report_type'] === 'body_composition_monthly'
        ? $bodyRecords
        : $loadRecords;
    $stats = periodPlayerStats(
        $records,
        $from,
        $to,
        $activePlayerIds,
        $rosterCount
    );
    $report['player_count'] = $stats['player_count'];
    $report['data_completeness'] = $stats['data_completeness'];
}
unset($report);

jsonOut([
    'success' => true,
    'reports' => $reports,
]);
