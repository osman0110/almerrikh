<?php

require_once dirname(__DIR__, 2) . '/player/training-load/TrainingLoadCalculator.php';
require_once __DIR__ . '/AcwrCalculator.php';

/**
 * Builds 7/28-day presentation data exclusively from TrainingLoadCalculator.
 * No training-load or ACWR formula is duplicated here.
 */
final class TrainingLoadWindowService
{
    public static function build(
        PDO $pdo,
        int $userId,
        string $linkedPlayerId,
        string $endDate
    ): array {
        $end = new DateTimeImmutable($endDate, FitnessConfig::timezone());
        $start = $end->modify('-27 days');
        $weeks = [];
        $days = [];

        for ($cursor = $start; $cursor <= $end; $cursor = $cursor->modify('+1 day')) {
            $date = $cursor->format('Y-m-d');
            $bounds = TrainingLoadCalculator::weekBounds($date);
            $key = $bounds['week_start'];
            if (!isset($weeks[$key])) {
                $weeks[$key] = TrainingLoadCalculator::getPlayerWeeklyReport(
                    $pdo,
                    $userId,
                    $linkedPlayerId,
                    $date,
                    TrainingLoadCalculator::DEFAULT_TIMEZONE,
                    false
                );
            }
            foreach ($weeks[$key]['days'] as $day) {
                if ($day['date'] === $date) {
                    $days[] = $day;
                    break;
                }
            }
        }

        $dailyRecords = array_map(static function (array $day): array {
            $complete = empty($day['data_quality_issues']);
            return [
                'date' => $day['date'],
                'load' => $complete ? (float)$day['daily_load'] : null,
                'complete' => $complete,
            ];
        }, $days);
        $acwr = AcwrCalculator::calculate($dailyRecords);

        $last7 = array_slice($days, -7);
        $summarize = static function (array $period): array {
            $sessions = [];
            $missingRpe = 0;
            $missingDuration = 0;
            $expected = 0;
            $completed = 0;
            foreach ($period as $day) {
                $expected += (int)($day['expected_records'] ?? 0);
                $completed += (int)($day['completed_records'] ?? 0);
                foreach ($day['data_quality_issues'] ?? [] as $issue) {
                    if (str_contains((string)$issue, 'RPE')) $missingRpe++;
                    if (str_contains((string)$issue, 'DURATION')) $missingDuration++;
                }
                foreach ($day['sessions'] ?? [] as $session) $sessions[] = $session;
            }
            $validRpe = array_values(array_filter(
                array_column($sessions, 'rpe'),
                static fn($value) => $value !== null
            ));
            $minutes = array_sum(array_map(
                static fn(array $session) => (int)($session['actual_duration_minutes'] ?? 0),
                $sessions
            ));
            $preliminaryLoad = array_sum(array_map(
                static fn(array $day) => (float)($day['daily_load'] ?? 0),
                $period
            ));
            return [
                'sessions_count' => count($sessions),
                'total_minutes' => $minutes,
                'average_rpe' => $validRpe
                    ? round(array_sum($validRpe) / count($validRpe), 2)
                    : null,
                'preliminary_load' => round($preliminaryLoad, 2),
                'missing_rpe_count' => $missingRpe,
                'missing_duration_count' => $missingDuration,
                'expected_records' => $expected,
                'completed_records' => $completed,
                'data_completeness' => $expected > 0
                    ? round(min(1, $completed / $expected), 4)
                    : null,
            ];
        };

        return [
            'days' => $days,
            'last_7_days' => $summarize($last7),
            'last_28_days' => $summarize($days),
            'acwr_details' => $acwr,
        ];
    }
}
