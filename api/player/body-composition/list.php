<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once __DIR__ . '/_helpers.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/SchemaInspector.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/BodyCompositionRepository.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$user = getAuthUser($pdo);
if (in_array($user['role'], ['player', 'parent'], true)) jsonOut(['error' => 'Forbidden — coaches only'], 403);
$ctx = requireClubPermission($pdo, $user, 'fitness.body_composition.view');

$page = max(1, (int)($_GET['page'] ?? 1));
$perPage = min(100, max(1, (int)($_GET['per_page'] ?? 25)));
$offset = ($page - 1) * $perPage;

$where = ['a.deleted_at IS NULL', 'a.club_id = ?'];
$params = [(int)$ctx['club_id']];

if (($ctx['team_id'] ?? null) !== null) {
    $where[] = 'cp.team_id = ?';
    $params[] = (int)$ctx['team_id'];
}

// Approval gating removed — a coach-recorded measurement is usable in
// reports the moment it's saved, no separate approval step.
if (isset($_GET['created_by']) && $_GET['created_by'] !== '') {
    $where[] = 'a.created_by = ?';
    $params[] = (int)$_GET['created_by'];
}

if (!empty($_GET['player_id'])) {
    $where[] = 'a.linked_player_id = ?';
    $params[] = (string)$_GET['player_id'];
}
if (!empty($_GET['team'])) {
    $where[] = 'a.team_name = ?';
    $params[] = (string)$_GET['team'];
}
if (!empty($_GET['position'])) {
    $where[] = 'a.position = ?';
    $params[] = (string)$_GET['position'];
}
if (!empty($_GET['assessment_type'])) {
    $where[] = 'a.assessment_type = ?';
    $params[] = (string)$_GET['assessment_type'];
}
if (!empty($_GET['date_from'])) {
    $where[] = 'a.assessment_date >= ?';
    $params[] = (string)$_GET['date_from'];
}
if (!empty($_GET['date_to'])) {
    $where[] = 'a.assessment_date <= ?';
    $params[] = (string)$_GET['date_to'];
}
if (isset($_GET['body_fat_min']) && $_GET['body_fat_min'] !== '') {
    $where[] = 'a.body_fat_percentage >= ?';
    $params[] = (float)$_GET['body_fat_min'];
}
if (isset($_GET['body_fat_max']) && $_GET['body_fat_max'] !== '') {
    $where[] = 'a.body_fat_percentage <= ?';
    $params[] = (float)$_GET['body_fat_max'];
}

// Only the latest assessment per player, unless the caller wants full history rows
$latestOnly = !isset($_GET['all_history']) || $_GET['all_history'] !== '1';

$sql = 'SELECT a.*, cp.name AS player_name, cp.photo_url AS player_photo_url
        FROM player_body_composition_assessments a
        LEFT JOIN club_players cp ON cp.id = a.linked_player_id
        WHERE ' . implode(' AND ', $where);

if ($latestOnly) {
    $sql = 'SELECT a.*, cp.name AS player_name, cp.photo_url AS player_photo_url
            FROM player_body_composition_assessments a
            LEFT JOIN club_players cp ON cp.id = a.linked_player_id
            INNER JOIN (
                SELECT linked_player_id, MAX(CONCAT(assessment_date, \' \', created_at)) AS max_key
                FROM player_body_composition_assessments
                WHERE deleted_at IS NULL AND club_id = ? AND linked_player_id IS NOT NULL
                GROUP BY linked_player_id
            ) latest ON latest.linked_player_id = a.linked_player_id
                    AND CONCAT(a.assessment_date, \' \', a.created_at) = latest.max_key
            WHERE ' . implode(' AND ', $where);
    $params = array_merge([(int)$ctx['club_id']], $params);
}

$countStmt = $pdo->prepare(str_replace('SELECT a.*, cp.name AS player_name, cp.photo_url AS player_photo_url', 'SELECT COUNT(*) AS c', $sql));
$countStmt->execute($params);
$total = (int)$countStmt->fetch(PDO::FETCH_ASSOC)['c'];

$sql .= ' ORDER BY a.assessment_date DESC, a.created_at DESC LIMIT ' . (int)$perPage . ' OFFSET ' . (int)$offset;
$stmt = $pdo->prepare($sql);
$stmt->execute($params);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

// Latest-list compatibility: include one legacy fallback for roster players
// who have no new-system record in this result. Legacy rows are explicitly
// read-only and keep their source marker; they are never copied or deleted.
if ($latestOnly && !isset($_GET['created_by'])) {
    $presentPlayerIds = array_values(array_filter(array_column($rows, 'linked_player_id')));
    $rosterSql = 'SELECT id, name, position, team_name, linked_user_id
                  FROM club_players
                  WHERE club_id = ? AND is_active = 1
                    AND (player_type IS NULL OR player_type = \'club\')';
    $rosterParams = [$ctx['club_id']];
    if (($ctx['team_id'] ?? null) !== null) {
        $rosterSql .= ' AND team_id = ?';
        $rosterParams[] = $ctx['team_id'];
    }
    if (!empty($_GET['player_id'])) {
        $rosterSql .= ' AND id = ?';
        $rosterParams[] = (string)$_GET['player_id'];
    }
    if (!empty($_GET['team'])) {
        $rosterSql .= ' AND team_name = ?';
        $rosterParams[] = (string)$_GET['team'];
    }
    if (!empty($_GET['position'])) {
        $rosterSql .= ' AND position = ?';
        $rosterParams[] = (string)$_GET['position'];
    }
    $rosterStmt = $pdo->prepare($rosterSql);
    $rosterStmt->execute($rosterParams);

    foreach ($rosterStmt->fetchAll(PDO::FETCH_ASSOC) as $player) {
        if (in_array($player['id'], $presentPlayerIds, true)) continue;
        $measurement = BodyCompositionRepository::latestForPlayer(
            $pdo,
            $player['id'],
            $player['linked_user_id'] !== null ? (int)$player['linked_user_id'] : null,
            true
        );
        if (!$measurement || $measurement['source_system'] !== 'LEGACY_SYSTEM') continue;
        $date = substr((string)$measurement['measured_at'], 0, 10);
        if (!empty($_GET['date_from']) && $date < (string)$_GET['date_from']) continue;
        if (!empty($_GET['date_to']) && $date > (string)$_GET['date_to']) continue;
        if (!empty($_GET['assessment_type'])) continue;
        $bodyFat = $measurement['body_fat_percentage'];
        if (isset($_GET['body_fat_min']) && $_GET['body_fat_min'] !== ''
            && ($bodyFat === null || $bodyFat < (float)$_GET['body_fat_min'])) continue;
        if (isset($_GET['body_fat_max']) && $_GET['body_fat_max'] !== ''
            && ($bodyFat === null || $bodyFat > (float)$_GET['body_fat_max'])) continue;

        $rows[] = [
            'id' => 'legacy:' . $measurement['id'],
            'linked_player_id' => $player['id'],
            'player_name' => $player['name'],
            'team_name' => $player['team_name'],
            'position' => $player['position'],
            'assessment_date' => $date,
            'assessment_time' => substr((string)$measurement['measured_at'], 11, 5) ?: null,
            'assessment_type' => 'legacy',
            'height_cm' => $measurement['height_cm'],
            'weight_kg' => $measurement['weight_kg'],
            'body_fat_percentage' => $measurement['body_fat_percentage'],
            'fat_mass_kg' => $measurement['fat_mass_kg'],
            'fat_free_mass_kg' => $measurement['fat_free_mass_kg'],
            'muscle_mass_kg' => null,
            'bmi' => $measurement['raw']['bmi'] ?? null,
            'measurement_method' => $measurement['measurement_method'],
            'approval_status' => 'legacy_unreviewed',
            'source_system' => 'LEGACY_SYSTEM',
            'is_legacy' => true,
            'read_only' => true,
        ];
        $total++;
    }
    usort($rows, fn(array $a, array $b) => strcmp(
        (string)$b['assessment_date'],
        (string)$a['assessment_date']
    ));
    $rows = array_slice($rows, 0, $perPage);
}

// goal_status filter is applied after the fact (goals aren't in the base table)
$goalStatusFilter = $_GET['goal_status'] ?? null;
if ($goalStatusFilter || true) {
    $linkedIds = array_values(array_unique(array_filter(array_column($rows, 'linked_player_id'))));
    $goalsByPlayer = [];
    if ($linkedIds) {
        $in = implode(',', array_fill(0, count($linkedIds), '?'));
        $gStmt = $pdo->prepare("SELECT * FROM player_body_composition_goals WHERE linked_player_id IN ($in)");
        $gStmt->execute($linkedIds);
        foreach ($gStmt->fetchAll(PDO::FETCH_ASSOC) as $g) $goalsByPlayer[$g['linked_player_id']] = $g;
    }
    foreach ($rows as &$row) {
        $goal = $goalsByPlayer[$row['linked_player_id']] ?? null;
        $row['goal_status'] = bcGoalStatus($goal, $row['body_fat_percentage'] !== null ? (float)$row['body_fat_percentage'] : null, $row['assessment_date']);
    }
    unset($row);
    if ($goalStatusFilter) {
        $rows = array_values(array_filter($rows, fn($r) => ($r['goal_status']['status'] ?? null) === $goalStatusFilter));
    }
}

foreach ($rows as &$row) {
    $row['source_system'] = $row['source_system'] ?? 'NEW_SYSTEM';
    $row['is_legacy'] = $row['is_legacy'] ?? false;
    $row['muscle_mass_kg'] = $row['muscle_mass_kg'] ?? null;
    if (!$row['is_legacy'] && !empty($row['linked_player_id'])) {
        $previousStmt = $pdo->prepare(
            'SELECT assessment_date, weight_kg, body_fat_percentage,
                    fat_mass_kg, fat_free_mass_kg, skinfold_sum_mm
             FROM player_body_composition_assessments
             WHERE linked_player_id = ? AND deleted_at IS NULL AND id != ?
               AND CONCAT(assessment_date, \' \', created_at) <
                   CONCAT(?, \' \', ?)
             ORDER BY assessment_date DESC, created_at DESC LIMIT 1'
        );
        $previousStmt->execute([
            $row['linked_player_id'],
            $row['id'],
            $row['assessment_date'],
            $row['created_at'],
        ]);
        $previous = $previousStmt->fetch(PDO::FETCH_ASSOC);
        if ($previous) {
            $delta = static fn(string $field) =>
                $row[$field] !== null && $previous[$field] !== null
                    ? round((float)$row[$field] - (float)$previous[$field], 2)
                    : null;
            $row['delta'] = [
                'weight_kg' => $delta('weight_kg'),
                'body_fat_percentage' => $delta('body_fat_percentage'),
                'fat_mass_kg' => $delta('fat_mass_kg'),
                'fat_free_mass_kg' => $delta('fat_free_mass_kg'),
                'skinfold_sum_mm' => $delta('skinfold_sum_mm'),
                'previous_date' => $previous['assessment_date'],
            ];
        }
    }
}
unset($row);

$missingPlayers = [];
if ($latestOnly) {
    $presentPlayerIds = array_values(array_filter(array_column($rows, 'linked_player_id')));
    $missingSql = 'SELECT id, name, position, team_name, photo_url
                   FROM club_players
                   WHERE club_id = ? AND is_active = 1
                     AND (player_type IS NULL OR player_type = \'club\')';
    $missingParams = [(int)$ctx['club_id']];
    if (($ctx['team_id'] ?? null) !== null) {
        $missingSql .= ' AND team_id = ?';
        $missingParams[] = (int)$ctx['team_id'];
    }
    if (!empty($_GET['team'])) {
        $missingSql .= ' AND team_name = ?';
        $missingParams[] = (string)$_GET['team'];
    }
    if (!empty($_GET['position'])) {
        $missingSql .= ' AND position = ?';
        $missingParams[] = (string)$_GET['position'];
    }
    $missingSql .= ' ORDER BY name ASC';
    $missingStmt = $pdo->prepare($missingSql);
    $missingStmt->execute($missingParams);
    $missingPlayers = array_values(array_filter(
        $missingStmt->fetchAll(PDO::FETCH_ASSOC),
        static fn(array $player) => !in_array($player['id'], $presentPlayerIds, true)
    ));
}

jsonOut([
    'assessments' => $rows,
    'players_without_data' => $missingPlayers,
    'permissions' => [
        'can_create' => clubStaffCan($ctx['staff_role'], 'fitness.body_composition.create'),
        'can_update' => clubStaffCan($ctx['staff_role'], 'fitness.body_composition.update'),
        'can_approve' => clubStaffCan($ctx['staff_role'], 'fitness.body_composition.approve'),
        'can_import' => clubStaffCan($ctx['staff_role'], 'fitness.body_composition.import'),
    ],
    'total' => $total,
    'page' => $page,
    'per_page' => $perPage,
]);
