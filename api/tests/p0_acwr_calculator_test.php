<?php
require_once dirname(__DIR__) . '/includes/fitness/AcwrCalculator.php';

function p0Assert($condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}

function p0DailyLoads(array $weeklyTotals): array {
    $start = new DateTimeImmutable('2026-06-29');
    $rows = [];
    foreach ($weeklyTotals as $weekIndex => $total) {
        for ($day = 0; $day < 7; $day++) {
            $rows[] = [
                'date' => $start->modify('+' . ($weekIndex * 7 + $day) . ' days')->format('Y-m-d'),
                'load' => $total / 7,
                'complete' => true,
            ];
        }
    }
    return $rows;
}

$constant = AcwrCalculator::calculate(p0DailyLoads([1000, 1000, 1000, 1000]));
p0Assert($constant['acute_load_7d'] === 1000.0, 'Constant acute load must be 1000');
p0Assert($constant['chronic_weekly_average'] === 1000.0, 'Constant chronic weekly average must be 1000');
p0Assert($constant['acwr'] === 1.0, 'Constant ACWR must be 1.0, never 0.25');
p0Assert($constant['classification'] === 'IN_TARGET', 'Constant load must be IN_TARGET');

$high = AcwrCalculator::calculate(p0DailyLoads([700, 700, 700, 1400]));
p0Assert($high['acwr'] > 1.0, 'Acute spike must increase ACWR');

$low = AcwrCalculator::calculate(p0DailyLoads([1400, 1400, 1400, 700]));
p0Assert($low['acwr'] < 1.0, 'Acute reduction must decrease ACWR');

$zero = AcwrCalculator::calculate(p0DailyLoads([0, 0, 0, 0]));
p0Assert($zero['acwr'] === null, 'Zero denominator must not return zero ratio');
p0Assert($zero['classification'] === 'NO_CHRONIC_LOAD', 'Zero denominator status mismatch');

$sevenDays = AcwrCalculator::calculate(array_slice(p0DailyLoads([1000, 1000, 1000, 1000]), -7));
p0Assert($sevenDays['classification'] === 'INSUFFICIENT_DATA', '7 days must be insufficient');

$fourteenDays = AcwrCalculator::calculate(array_slice(p0DailyLoads([1000, 1000, 1000, 1000]), -14));
p0Assert($fourteenDays['classification'] === 'INSUFFICIENT_DATA', '14 days must be insufficient');

$missing = p0DailyLoads([1000, 1000, 1000, 1000]);
$missing[5]['complete'] = false;
$missingResult = AcwrCalculator::calculate($missing);
p0Assert($missingResult['classification'] === 'INSUFFICIENT_DATA', 'Missing day must be insufficient');

echo "p0_acwr_calculator_test: OK\n";
