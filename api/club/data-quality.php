<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../includes/club_auth.php';
require_once __DIR__ . '/../includes/fitness/SchemaInspector.php';

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
    if (stripos($auth, 'Bearer ') === 0) return trim(substr($auth, 7));
    return trim($auth);
}

function authUser(PDO $pdo): array {
    $token = bearerToken();
    if ($token === '') jsonOut(['success' => false, 'error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.name, u.role
         FROM users u JOIN user_tokens t ON t.user_id = u.id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) jsonOut(['success' => false, 'error' => 'Invalid token'], 401);
    return $user;
}

function stringList($value): array {
    if (is_string($value)) $value = json_decode($value, true);
    if (!is_array($value)) return [];
    return array_values(array_unique(array_map('strval', $value)));
}

function hasIndex(PDO $pdo, string $table, string $index): bool {
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?'
    );
    $stmt->execute([$table, $index]);
    return (int)$stmt->fetchColumn() > 0;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonOut(['success' => false, 'error' => 'Method not allowed'], 405);
}

$user = authUser($pdo);
$ctx = requireClubPermission($pdo, $user, 'fitness.data_quality.view');
$clubId = (int)$ctx['club_id'];
$teamId = $ctx['team_id'] !== null ? (int)$ctx['team_id'] : null;
$teamName = null;
$scopedPlayerIds = [];
if ($teamId !== null && SchemaInspector::hasTable($pdo, 'club_teams')) {
    $teamStmt = $pdo->prepare(
        'SELECT name FROM club_teams WHERE id = ? AND club_id = ? AND is_active = 1'
    );
    $teamStmt->execute([$teamId, $clubId]);
    $teamName = $teamStmt->fetchColumn() ?: '';
    if (
        SchemaInspector::hasTable($pdo, 'club_players')
        && SchemaInspector::hasColumn($pdo, 'club_players', 'team_id')
    ) {
        $playerStmt = $pdo->prepare(
            'SELECT id FROM club_players
             WHERE club_id = ? AND is_active = 1
               AND (team_id = ? OR (team_id IS NULL AND team_name = ?))'
        );
        $playerStmt->execute([$clubId, $teamId, $teamName]);
        $scopedPlayerIds = array_values(array_unique(array_map(
            'strval',
            $playerStmt->fetchAll(PDO::FETCH_COLUMN)
        )));
    }
}

$requiredTables = [
    'clubs', 'club_staff', 'club_teams', 'club_players', 'club_sessions',
    'session_attendance', 'assessments', 'player_rpe',
    'player_hooper_index', 'audit_logs', 'matches',
];
$requiredColumns = [
    'club_staff' => ['club_id', 'user_id', 'staff_role', 'status', 'team_id'],
    'club_players' => ['club_id', 'team_id', 'linked_user_id', 'is_active'],
    'club_sessions' => [
        'club_id', 'team_id', 'player_ids', 'completed_player_ids',
        'assessment_count', 'linked_training_session_id',
    ],
    'session_attendance' => ['session_id', 'player_id', 'user_id', 'status', 'marked_at'],
    'assessments' => [
        'club_id', 'team_id', 'player_id', 'session_id',
        'attempt_group_id', 'attempt_number', 'is_valid',
    ],
    'player_rpe' => [
        'club_id', 'team_id', 'linked_player_id', 'training_session_id',
        'rpe_type', 'is_active_record',
    ],
    'player_hooper_index' => [
        'club_id', 'team_id', 'linked_player_id', 'training_session_id',
    ],
    'audit_logs' => [
        'entity_type', 'entity_id', 'field_name', 'old_value', 'new_value',
        'changed_by_user_id', 'created_at', 'club_id', 'player_id',
        'operation', 'operation_id',
    ],
    'matches' => ['club_id', 'player_ids', 'match_date', 'match_time'],
];
$requiredIndexes = [
    'club_staff' => ['idx_club_staff_team_scope'],
    'session_attendance' => ['uq_session_attendance', 'idx_session_attendance_session'],
    'audit_logs' => ['idx_audit_entity', 'idx_audit_created'],
    'club_sessions' => ['idx_club_sessions_club'],
    'player_rpe' => ['idx_rpe_submitted'],
    'player_hooper_index' => ['idx_hooper_submitted'],
];

$missingTables = [];
foreach ($requiredTables as $table) {
    if (!SchemaInspector::hasTable($pdo, $table)) $missingTables[] = $table;
}
$missingColumns = [];
foreach ($requiredColumns as $table => $columns) {
    foreach ($columns as $column) {
        if (!SchemaInspector::hasColumn($pdo, $table, $column)) {
            $missingColumns[] = ['table' => $table, 'column' => $column];
        }
    }
}
$missingIndexes = [];
foreach ($requiredIndexes as $table => $indexes) {
    if (!SchemaInspector::hasTable($pdo, $table)) continue;
    foreach ($indexes as $index) {
        if (!hasIndex($pdo, $table, $index)) {
            $missingIndexes[] = ['table' => $table, 'index' => $index];
        }
    }
}

$optionalColumns = [
    'club_staff.team_id',
    'player_rpe.is_active_record',
    'audit_logs.club_id',
    'audit_logs.player_id',
    'audit_logs.operation',
    'audit_logs.operation_id',
];
$blockingColumns = array_values(array_filter(
    $missingColumns,
    static fn(array $item): bool =>
        !in_array($item['table'] . '.' . $item['column'], $optionalColumns, true)
));
$schemaIssueCount = count($missingTables) + count($missingColumns) + count($missingIndexes);
if ($missingTables || $blockingColumns) {
    jsonOut([
        'success' => true,
        'generated_at' => gmdate('c'),
        'scope' => ['club_id' => $clubId, 'team_id' => $teamId],
        'schema' => [
            'missing_tables' => $missingTables,
            'missing_columns' => $missingColumns,
            'missing_indexes' => $missingIndexes,
            'is_ready' => false,
        ],
        'summary' => [
            'issue_groups' => $schemaIssueCount,
            'rpe_duplicate_groups' => 0,
            'hooper_duplicate_groups' => 0,
            'assessment_duplicate_groups' => 0,
            'orphan_records' => 0,
            'session_conflicts' => 0,
        ],
        'duplicates' => ['rpe' => [], 'hooper' => [], 'assessments' => []],
        'orphans' => ['assessments' => [], 'attendance' => [], 'rpe' => [], 'hooper' => []],
        'session_conflicts' => [],
        'recent_audit' => [],
    ]);
}

$teamClause = static function (
    string $alias,
    string $identityColumn
) use ($teamId, $scopedPlayerIds): array {
    if ($teamId === null) return ['', []];
    if (!$scopedPlayerIds) return [" AND $alias.team_id = ?", [$teamId]];
    $placeholders = implode(',', array_fill(0, count($scopedPlayerIds), '?'));
    return [
        " AND ($alias.team_id = ? OR $alias.$identityColumn IN ($placeholders))",
        [$teamId, ...$scopedPlayerIds],
    ];
};

[$rpeTeamSql, $rpeTeamParams] = $teamClause('r', 'linked_player_id');
$activeRpeSql = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
    ? ' AND r.is_active_record = 1' : '';
$rpeStmt = $pdo->prepare(
    "SELECT COALESCE(r.linked_player_id, CONCAT('user:', r.user_id)) AS identity_key,
            r.training_session_id, r.rpe_type, DATE(r.submitted_at) AS entry_date,
            COUNT(*) AS duplicate_count
     FROM player_rpe r
     WHERE r.club_id = ?$rpeTeamSql$activeRpeSql
     GROUP BY identity_key, r.training_session_id, r.rpe_type, DATE(r.submitted_at)
     HAVING COUNT(*) > 1
     ORDER BY duplicate_count DESC, entry_date DESC
     LIMIT 100"
);
$rpeStmt->execute([$clubId, ...$rpeTeamParams]);
$rpeDuplicates = $rpeStmt->fetchAll(PDO::FETCH_ASSOC);

[$hooperTeamSql, $hooperTeamParams] = $teamClause('h', 'linked_player_id');
$hooperStmt = $pdo->prepare(
    "SELECT COALESCE(h.linked_player_id, CONCAT('user:', h.user_id)) AS identity_key,
            h.training_session_id, DATE(h.submitted_at) AS entry_date,
            COUNT(*) AS duplicate_count
     FROM player_hooper_index h
     WHERE h.club_id = ?$hooperTeamSql
     GROUP BY identity_key, h.training_session_id, DATE(h.submitted_at)
     HAVING COUNT(*) > 1
     ORDER BY duplicate_count DESC, entry_date DESC
     LIMIT 100"
);
$hooperStmt->execute([$clubId, ...$hooperTeamParams]);
$hooperDuplicates = $hooperStmt->fetchAll(PDO::FETCH_ASSOC);

[$assessmentTeamSql, $assessmentTeamParams] = $teamClause('a', 'player_id');
$assessmentStmt = $pdo->prepare(
    "SELECT a.player_id, a.type, a.session_id, a.attempt_group_id,
            a.attempt_number, COUNT(*) AS duplicate_count
     FROM assessments a
     WHERE a.club_id = ?$assessmentTeamSql
     GROUP BY a.player_id, a.type, a.session_id, a.attempt_group_id, a.attempt_number
     HAVING COUNT(*) > 1
     ORDER BY duplicate_count DESC
     LIMIT 100"
);
$assessmentStmt->execute([$clubId, ...$assessmentTeamParams]);
$assessmentDuplicates = $assessmentStmt->fetchAll(PDO::FETCH_ASSOC);

$orphanAssessmentsStmt = $pdo->prepare(
    'SELECT a.id, a.player_id, a.session_id, a.created_at
     FROM assessments a
     LEFT JOIN club_players cp ON cp.id = a.player_id AND cp.club_id = a.club_id
     WHERE a.club_id = ? AND cp.id IS NULL' . $assessmentTeamSql . '
     ORDER BY a.created_at DESC LIMIT 100'
);
$orphanAssessmentsStmt->execute([$clubId, ...$assessmentTeamParams]);
$orphanAssessments = $orphanAssessmentsStmt->fetchAll(PDO::FETCH_ASSOC);

$orphanAttendanceStmt = $pdo->prepare(
    'SELECT sa.id, sa.session_id, sa.player_id, sa.status, sa.marked_at
     FROM session_attendance sa
     LEFT JOIN club_sessions cs ON cs.id = sa.session_id
     LEFT JOIN club_players cp ON cp.id = sa.player_id
     WHERE (cs.id IS NULL OR cp.id IS NULL)
       AND (cs.club_id = ? OR cp.club_id = ?)' .
     ($teamId !== null
        ? ' AND (
              cs.team_id = ? OR cp.team_id = ?
              OR (cs.team_id IS NULL AND cs.team_name = ?)
              OR (cp.team_id IS NULL AND cp.team_name = ?)
            )'
        : '') . '
     ORDER BY sa.marked_at DESC LIMIT 100'
);
$orphanAttendanceStmt->execute([
    $clubId,
    $clubId,
    ...($teamId !== null ? [$teamId, $teamId, $teamName, $teamName] : []),
]);
$orphanAttendance = $orphanAttendanceStmt->fetchAll(PDO::FETCH_ASSOC);

$orphanRpeStmt = $pdo->prepare(
    'SELECT r.id, r.linked_player_id, r.training_session_id, r.submitted_at
     FROM player_rpe r
     LEFT JOIN club_players cp ON cp.id = r.linked_player_id
     WHERE r.club_id = ? AND r.linked_player_id IS NOT NULL AND cp.id IS NULL' .
     $rpeTeamSql . '
     ORDER BY r.submitted_at DESC LIMIT 100'
);
$orphanRpeStmt->execute([$clubId, ...$rpeTeamParams]);
$orphanRpe = $orphanRpeStmt->fetchAll(PDO::FETCH_ASSOC);

$orphanHooperStmt = $pdo->prepare(
    'SELECT h.id, h.linked_player_id, h.training_session_id, h.submitted_at
     FROM player_hooper_index h
     LEFT JOIN club_players cp ON cp.id = h.linked_player_id
     WHERE h.club_id = ? AND h.linked_player_id IS NOT NULL AND cp.id IS NULL' .
     $hooperTeamSql . '
     ORDER BY h.submitted_at DESC LIMIT 100'
);
$orphanHooperStmt->execute([$clubId, ...$hooperTeamParams]);
$orphanHooper = $orphanHooperStmt->fetchAll(PDO::FETCH_ASSOC);

$sessionWhere = ['cs.club_id = ?'];
$sessionParams = [$clubId];
if ($teamId !== null) {
    $sessionWhere[] = '(cs.team_id = ? OR (cs.team_id IS NULL AND cs.team_name = ?))';
    $sessionParams[] = $teamId;
    $sessionParams[] = $teamName;
}
$sessionStmt = $pdo->prepare(
    'SELECT cs.id, cs.title, cs.date, cs.player_ids, cs.completed_player_ids,
            cs.assessment_count
     FROM club_sessions cs
     WHERE ' . implode(' AND ', $sessionWhere) . '
     ORDER BY cs.date DESC LIMIT 300'
);
$sessionStmt->execute($sessionParams);
$sessionRows = $sessionStmt->fetchAll(PDO::FETCH_ASSOC);
$sessionIds = array_values(array_unique(array_map('strval', array_column($sessionRows, 'id'))));

$attendanceBySession = [];
$assessedBySession = [];
if ($sessionIds) {
    $placeholders = implode(',', array_fill(0, count($sessionIds), '?'));
    $attStmt = $pdo->prepare(
        "SELECT session_id, player_id FROM session_attendance
         WHERE session_id IN ($placeholders) AND status IN ('present', 'late')"
    );
    $attStmt->execute($sessionIds);
    foreach ($attStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $attendanceBySession[$row['session_id']][(string)$row['player_id']] = true;
    }

    $actualStmt = $pdo->prepare(
        "SELECT session_id, player_id FROM assessments
         WHERE club_id = ? AND session_id IN ($placeholders) AND is_valid = 1"
    );
    $actualStmt->execute([$clubId, ...$sessionIds]);
    foreach ($actualStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $assessedBySession[$row['session_id']][(string)$row['player_id']] = true;
    }
}

$sessionConflicts = [];
foreach ($sessionRows as $session) {
    $sessionId = (string)$session['id'];
    $completed = stringList($session['completed_player_ids'] ?? []);
    $completedSet = array_fill_keys($completed, true);
    $attendanceSet = $attendanceBySession[$sessionId] ?? [];
    $assessedSet = $assessedBySession[$sessionId] ?? [];
    $attendanceOnly = array_values(array_diff(
        array_keys(array_intersect_key($completedSet, $attendanceSet)),
        array_keys($assessedSet)
    ));
    $missingCompleted = array_values(array_diff(array_keys($assessedSet), $completed));
    $countMismatch = (int)$session['assessment_count'] !== count($assessedSet);
    if ($attendanceOnly || $missingCompleted || $countMismatch) {
        $sessionConflicts[] = [
            'session_id' => $sessionId,
            'title' => $session['title'],
            'date' => $session['date'],
            'stored_assessment_count' => (int)$session['assessment_count'],
            'actual_assessed_players' => count($assessedSet),
            'attendance_ids_in_completed' => $attendanceOnly,
            'assessed_ids_missing_from_completed' => $missingCompleted,
        ];
    }
}

$auditHasClub = SchemaInspector::hasColumn($pdo, 'audit_logs', 'club_id');
$auditHasPlayer = SchemaInspector::hasColumn($pdo, 'audit_logs', 'player_id');
if ($teamId !== null && (!$auditHasClub || !$auditHasPlayer || !$scopedPlayerIds)) {
    $recentAudit = [];
} elseif ($auditHasClub) {
    $auditTeamSql = '';
    $auditParams = [$clubId];
    if ($teamId !== null) {
        $auditPlaceholders = implode(',', array_fill(0, count($scopedPlayerIds), '?'));
        $auditTeamSql = " AND al.player_id IN ($auditPlaceholders)";
        $auditParams = [...$auditParams, ...$scopedPlayerIds];
    }
    $auditStmt = $pdo->prepare(
        'SELECT al.*, u.name AS changed_by_name
         FROM audit_logs al
         LEFT JOIN users u ON u.id = al.changed_by_user_id
         WHERE al.club_id = ?' . $auditTeamSql . '
         ORDER BY al.created_at DESC LIMIT 50'
    );
    $auditStmt->execute($auditParams);
    $recentAudit = $auditStmt->fetchAll(PDO::FETCH_ASSOC);
} else {
    $auditStmt = $pdo->prepare(
        'SELECT al.*, u.name AS changed_by_name
         FROM audit_logs al
         LEFT JOIN users u ON u.id = al.changed_by_user_id
         LEFT JOIN club_staff cs ON cs.user_id = al.changed_by_user_id AND cs.status = \'active\'
         WHERE cs.club_id = ?
         ORDER BY al.created_at DESC LIMIT 50'
    );
    $auditStmt->execute([$clubId]);
    $recentAudit = $auditStmt->fetchAll(PDO::FETCH_ASSOC);
}

$issueCount = count($rpeDuplicates)
    + count($hooperDuplicates)
    + count($assessmentDuplicates)
    + count($orphanAssessments)
    + count($orphanAttendance)
    + count($orphanRpe)
    + count($orphanHooper)
    + count($sessionConflicts)
    + $schemaIssueCount;

jsonOut([
    'success' => true,
    'generated_at' => gmdate('c'),
    'scope' => ['club_id' => $clubId, 'team_id' => $teamId],
    'schema' => [
        'missing_tables' => $missingTables,
        'missing_columns' => $missingColumns,
        'missing_indexes' => $missingIndexes,
        'is_ready' => !$missingTables && !$missingColumns && !$missingIndexes,
    ],
    'summary' => [
        'issue_groups' => $issueCount,
        'rpe_duplicate_groups' => count($rpeDuplicates),
        'hooper_duplicate_groups' => count($hooperDuplicates),
        'assessment_duplicate_groups' => count($assessmentDuplicates),
        'orphan_records' => count($orphanAssessments) + count($orphanAttendance)
            + count($orphanRpe) + count($orphanHooper),
        'session_conflicts' => count($sessionConflicts),
    ],
    'duplicates' => [
        'rpe' => $rpeDuplicates,
        'hooper' => $hooperDuplicates,
        'assessments' => $assessmentDuplicates,
    ],
    'orphans' => [
        'assessments' => $orphanAssessments,
        'attendance' => $orphanAttendance,
        'rpe' => $orphanRpe,
        'hooper' => $orphanHooper,
    ],
    'session_conflicts' => $sessionConflicts,
    'recent_audit' => $recentAudit,
]);
