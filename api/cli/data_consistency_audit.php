<?php

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

$dbName = (string)(getenv('DB_NAME') ?: '');
if (getenv('APP_ENV') !== 'test' || stripos($dbName, 'test') === false) {
    fwrite(STDERR, "Refusing to run: APP_ENV=test and a Test DB_NAME are required.\n");
    exit(2);
}

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/fitness/SchemaInspector.php';
require_once dirname(__DIR__) . '/includes/fitness/FitnessConfig.php';

$issues = [];
$addIssue = static function (
    ?string $playerId,
    ?string $playerName,
    string $field,
    mixed $officialValue,
    mixed $observedValue,
    string $type,
    string $surface,
    string $status = 'open'
) use (&$issues): void {
    $issues[] = [
        'player_id' => $playerId,
        'player' => $playerName,
        'field' => $field,
        'official_value' => $officialValue,
        'observed_value' => $observedValue,
        'issue_type' => $type,
        'surface' => $surface,
        'status' => $status,
    ];
};

if (SchemaInspector::hasTable($pdo, 'player_body_composition_assessments')) {
    $stmt = $pdo->query(
        "SELECT a.linked_player_id, cp.name AS player_name, a.id,
                a.approval_status, a.calculation_status, a.assessment_date,
                a.body_fat_percentage, a.fat_mass_kg, a.fat_free_mass_kg
         FROM player_body_composition_assessments a
         LEFT JOIN club_players cp ON cp.id = a.linked_player_id
         WHERE a.deleted_at IS NULL"
    );
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $complete = strtoupper((string)$row['calculation_status']) === 'COMPLETE';
        foreach (['body_fat_percentage', 'fat_mass_kg', 'fat_free_mass_kg'] as $field) {
            if (!$complete && $row[$field] !== null) {
                $addIssue(
                    $row['linked_player_id'],
                    $row['player_name'],
                    $field,
                    null,
                    (float)$row[$field],
                    'incomplete_measurement_has_derived_value',
                    'player_body_composition_assessments'
                );
            }
        }
        if ($row['assessment_date'] > FitnessConfig::today()) {
            $addIssue(
                $row['linked_player_id'],
                $row['player_name'],
                'assessment_date',
                FitnessConfig::today(),
                $row['assessment_date'],
                'future_date',
                'player_body_composition_assessments'
            );
        }
    }

    $draftStmt = $pdo->query(
        "SELECT cp.id AS player_id, cp.name AS player_name,
                MAX(CASE WHEN a.approval_status = 'approved'
                    THEN CONCAT(a.assessment_date, ' ', a.created_at) END) AS approved_key,
                MAX(CASE WHEN a.approval_status <> 'approved'
                    THEN CONCAT(a.assessment_date, ' ', a.created_at) END) AS draft_key
         FROM club_players cp
         JOIN player_body_composition_assessments a
           ON a.linked_player_id = cp.id AND a.deleted_at IS NULL
         GROUP BY cp.id, cp.name"
    );
    foreach ($draftStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        if ($row['draft_key'] !== null
            && ($row['approved_key'] === null || $row['draft_key'] > $row['approved_key'])) {
            $addIssue(
                $row['player_id'],
                $row['player_name'],
                'latest_body_measurement',
                $row['approved_key'],
                $row['draft_key'],
                'newer_draft_must_not_replace_official_value',
                'official summaries and PDF',
                'guarded'
            );
        }
    }
}

if (SchemaInspector::hasTable($pdo, 'player_rpe')) {
    $activeFilter = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
        ? ' AND is_active_record = 1'
        : '';
    $stmt = $pdo->query(
        "SELECT pr.id, pr.linked_player_id, cp.name AS player_name,
                pr.rpe_score, pr.duration_minutes,
                " . (SchemaInspector::hasColumn($pdo, 'player_rpe', 'actual_duration_minutes')
                    ? 'pr.actual_duration_minutes'
                    : 'NULL AS actual_duration_minutes') . ",
                pr.training_load, pr.submitted_at
         FROM player_rpe pr
         LEFT JOIN club_players cp ON cp.id = pr.linked_player_id
         WHERE 1=1$activeFilter"
    );
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $duration = $row['actual_duration_minutes'] ?? $row['duration_minutes'];
        if ($row['rpe_score'] === null || $duration === null) {
            $addIssue(
                $row['linked_player_id'],
                $row['player_name'],
                $row['rpe_score'] === null ? 'rpe_score' : 'actual_duration_minutes',
                null,
                null,
                'missing_value',
                'player_rpe'
            );
            continue;
        }
        $expected = round((float)$row['rpe_score'] * (int)$duration, 2);
        $actual = round((float)$row['training_load'], 2);
        if (abs($expected - $actual) > 0.01) {
            $addIssue(
                $row['linked_player_id'],
                $row['player_name'],
                'training_load',
                $expected,
                $actual,
                'value_mismatch',
                'player_rpe'
            );
        }
    }

    if (SchemaInspector::hasColumn($pdo, 'player_rpe', 'session_id')) {
        $duplicates = $pdo->query(
            "SELECT linked_player_id, session_id, rpe_type, COUNT(*) AS row_count
             FROM player_rpe
             WHERE linked_player_id IS NOT NULL AND session_id IS NOT NULL$activeFilter
             GROUP BY linked_player_id, session_id, rpe_type
             HAVING COUNT(*) > 1"
        )->fetchAll(PDO::FETCH_ASSOC);
        foreach ($duplicates as $row) {
            $addIssue(
                $row['linked_player_id'],
                null,
                'rpe_record',
                1,
                (int)$row['row_count'],
                'duplicate_value',
                'player_rpe'
            );
        }
    }
}

if (SchemaInspector::hasTable($pdo, 'player_hooper_index')) {
    $stmt = $pdo->query(
        "SELECT h.linked_player_id, cp.name AS player_name,
                h.sleep_quality, h.fatigue, h.stress, h.muscle_soreness,
                h.hooper_score, h.submitted_at
         FROM player_hooper_index h
         LEFT JOIN club_players cp ON cp.id = h.linked_player_id"
    );
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $expected = (int)$row['sleep_quality']
            + (int)$row['fatigue']
            + (int)$row['stress']
            + (int)$row['muscle_soreness'];
        if ($expected !== (int)$row['hooper_score']) {
            $addIssue(
                $row['linked_player_id'],
                $row['player_name'],
                'hooper_score',
                $expected,
                (int)$row['hooper_score'],
                'value_mismatch',
                'player_hooper_index'
            );
        }
    }
}

echo json_encode([
    'database' => $dbName,
    'environment' => 'test',
    'generated_at' => gmdate('c'),
    'timezone' => FitnessConfig::TIMEZONE,
    'official_body_policy' => 'APPROVED_NEW_ONLY',
    'load_unit' => 'CE',
    'issues_count' => count($issues),
    'issues' => $issues,
], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . PHP_EOL;
