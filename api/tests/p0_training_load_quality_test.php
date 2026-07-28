<?php
require_once dirname(__DIR__) . '/includes/fitness/TrainingLoadDataQuality.php';

function qualityP0Assert($condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}

$completeDays = [];
for ($i = 0; $i < 7; $i++) {
    $completeDays[] = [
        'expected_records' => 1,
        'completed_records' => 1,
        'data_quality_issues' => [],
    ];
}
$complete = TrainingLoadDataQuality::summarize($completeDays);
qualityP0Assert($complete['report_approvable'] === true, 'Complete week must be approvable');
qualityP0Assert($complete['completeness_ratio'] === 1.0, 'Complete ratio must be 1');

foreach ([
    'MISSING_RPE',
    'MISSING_DURATION',
    'SCHEDULED_SESSION_MISSING_RECORD',
    'MATCH_MISSING_RPE',
    'PARTIAL_SESSION_MISSING_DURATION',
    'UNRESOLVED_ATTENDANCE',
    'UNKNOWN_DAY_STATUS',
    'DUPLICATE_RPE',
    'INVALID_DURATION',
    'INVALID_RPE',
    'HISTORICAL_STATUS_UNKNOWN',
] as $status) {
    $days = $completeDays;
    $days[0]['completed_records'] = 0;
    $days[0]['data_quality_issues'] = [$status];
    $result = TrainingLoadDataQuality::summarize($days);
    qualityP0Assert($result['report_approvable'] === false, "$status must block approval");
    qualityP0Assert($result['can_calculate_monotony_strain'] === false, "$status must block Monotony/Strain");
}

echo "p0_training_load_quality_test: OK\n";
