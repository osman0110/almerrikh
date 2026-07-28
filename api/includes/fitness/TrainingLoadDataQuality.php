<?php

final class TrainingLoadDataQuality
{
    private const BLOCKING_STATUSES = [
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
    ];

    public static function summarize(array $days): array
    {
        $reasons = [];
        $expected = 0;
        $complete = 0;

        foreach ($days as $day) {
            $expected += (int)($day['expected_records'] ?? 0);
            $complete += (int)($day['completed_records'] ?? 0);
            foreach (($day['data_quality_issues'] ?? []) as $issue) {
                if (in_array($issue, self::BLOCKING_STATUSES, true)) $reasons[] = $issue;
            }
        }

        $reasons = array_values(array_unique($reasons));
        $missing = max(0, $expected - $complete);
        if ($reasons && $missing === 0) $missing = count($reasons);
        $ratio = $expected > 0 ? $complete / $expected : 0.0;
        $approvable = !$reasons && $expected > 0 && $complete === $expected;

        return [
            'expected_records' => $expected,
            'completed_records' => $complete,
            'missing_records' => $missing,
            'completeness_ratio' => round(min(1.0, $ratio), 4),
            'missing_reasons' => $reasons,
            'report_approvable' => $approvable,
            'can_calculate_monotony_strain' => $approvable,
            'can_calculate_acwr' => $approvable,
        ];
    }
}
