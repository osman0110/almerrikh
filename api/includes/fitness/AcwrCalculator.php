<?php

require_once __DIR__ . '/FitnessConfig.php';

final class AcwrCalculator
{
    /**
     * @param array<int,array{date:string,load:?float,complete:bool}> $dailyRecords
     */
    public static function calculate(array $dailyRecords): array
    {
        usort($dailyRecords, fn(array $a, array $b) => strcmp($a['date'], $b['date']));
        $records = array_slice($dailyRecords, -28);
        $availableDays = count(array_filter(
            $records,
            fn(array $row) => !empty($row['complete']) && $row['load'] !== null
        ));
        $completeness = count($records) > 0 ? $availableDays / 28 : 0.0;

        $base = [
            'acute_load_7d' => null,
            'chronic_load_28d_total' => null,
            'chronic_weekly_average' => null,
            'acwr' => null,
            'classification' => 'INSUFFICIENT_DATA',
            'data_completeness' => round(min(1.0, $completeness), 4),
            'available_days' => $availableDays,
            'required_days' => FitnessConfig::ACWR_MIN_COMPLETE_DAYS,
            'available_weeks' => round($availableDays / 7, 2),
            'formula_version' => FitnessConfig::ACWR_FORMULA_VERSION,
        ];

        if (count($records) !== 28 || $availableDays !== 28) {
            return $base;
        }

        $loads = array_map(fn(array $row) => (float)$row['load'], $records);
        $acute = array_sum(array_slice($loads, -7));
        $chronicTotal = array_sum($loads);
        $chronicWeeklyAverage = $chronicTotal / 4;

        $base['acute_load_7d'] = round($acute, 2);
        $base['chronic_load_28d_total'] = round($chronicTotal, 2);
        $base['chronic_weekly_average'] = round($chronicWeeklyAverage, 2);

        if ($chronicWeeklyAverage <= 0.0) {
            $base['classification'] = 'NO_CHRONIC_LOAD';
            return $base;
        }

        $ratio = $acute / $chronicWeeklyAverage;
        $base['acwr'] = round($ratio, 2);
        $base['classification'] = self::classify($ratio);
        return $base;
    }

    private static function classify(float $ratio): string
    {
        $thresholds = FitnessConfig::acwrThresholds();
        if ($ratio < $thresholds['target_min']) return 'BELOW_TARGET';
        if ($ratio <= $thresholds['in_target_max']) return 'IN_TARGET';
        if ($ratio <= $thresholds['caution_max']) return 'CAUTION';
        return 'ABOVE_TARGET';
    }
}
