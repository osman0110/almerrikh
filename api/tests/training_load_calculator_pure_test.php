<?php
/**
 * Pure-math unit tests for TrainingLoadCalculator — no DB required.
 * Run: php api/tests/training_load_calculator_pure_test.php
 */
require_once dirname(__DIR__) . '/player/training-load/TrainingLoadCalculator.php';

$pass = 0; $fail = 0;

function ok(string $label, bool $cond, string $detail = ''): void {
    global $pass, $fail;
    if ($cond) { echo "  PASS  $label\n"; $pass++; }
    else        { echo "  FAIL  $label" . ($detail ? " — $detail" : '') . "\n"; $fail++; }
}

function almostEqual($a, $b, float $eps = 1e-6): bool {
    if ($a === null || $b === null) return $a === $b;
    return abs($a - $b) < $eps;
}

echo "\n=== TrainingLoadCalculator — Pure Math Tests ===\n\n";

// ── Reference case 1 (from RPE APR Rwanda spec) ─────────────────────────────
echo "[ Reference case 1 ]\n";
$s1 = TrainingLoadCalculator::computeWeekStats([60, 0, 180, 255, 450, 240, 80]);
ok('weekly_load = 1265', almostEqual($s1['weekly_load'], 1265));
ok('daily_mean = 180.71428571428572', almostEqual($s1['daily_mean'], 180.71428571428572));
ok('standard_deviation = 152.1629765369074', almostEqual($s1['standard_deviation'], 152.1629765369074));
ok('monotony = 1.1876363740193605', almostEqual($s1['monotony'], 1.1876363740193605));
ok('strain = 1502.360013134491', almostEqual($s1['strain'], 1502.360013134491));
ok('calculation_status = OK', $s1['calculation_status'] === TrainingLoadCalculator::CALC_OK);

// ── Reference case 2 ─────────────────────────────────────────────────────────
echo "\n[ Reference case 2 ]\n";
$s2 = TrainingLoadCalculator::computeWeekStats([0, 270, 360, 150, 120, 0, 380]);
ok('weekly_load = 1280', almostEqual($s2['weekly_load'], 1280));
ok('daily_mean = 182.85714285714286', almostEqual($s2['daily_mean'], 182.85714285714286));
ok('standard_deviation = 157.97829869049374', almostEqual($s2['standard_deviation'], 157.97829869049374));
ok('monotony = 1.157482669283526', almostEqual($s2['monotony'], 1.157482669283526));
ok('strain = 1481.5778166829134', almostEqual($s2['strain'], 1481.5778166829134));

// ── Full week with no load ───────────────────────────────────────────────────
echo "\n[ No-load week ]\n";
$s3 = TrainingLoadCalculator::computeWeekStats([0, 0, 0, 0, 0, 0, 0]);
ok('weekly_load = 0', almostEqual($s3['weekly_load'], 0));
ok('daily_mean = 0', almostEqual($s3['daily_mean'], 0));
ok('standard_deviation = 0', almostEqual($s3['standard_deviation'], 0));
ok('monotony = null', $s3['monotony'] === null);
ok('strain = null', $s3['strain'] === null);
ok('calculation_status = NO_LOAD', $s3['calculation_status'] === TrainingLoadCalculator::CALC_NO_LOAD);
ok('no NAN/INF leaks', is_finite($s3['standard_deviation']));

// ── Constant non-zero load ───────────────────────────────────────────────────
echo "\n[ Constant non-zero load ]\n";
$s4 = TrainingLoadCalculator::computeWeekStats([100, 100, 100, 100, 100, 100, 100]);
ok('weekly_load = 700', almostEqual($s4['weekly_load'], 700));
ok('daily_mean = 100', almostEqual($s4['daily_mean'], 100));
ok('standard_deviation = 0', almostEqual($s4['standard_deviation'], 0));
ok('monotony = null (undefined)', $s4['monotony'] === null);
ok('strain = null (undefined)', $s4['strain'] === null);
ok('calculation_status = CONSTANT_NON_ZERO_LOAD', $s4['calculation_status'] === TrainingLoadCalculator::CALC_CONSTANT_NON_ZERO_LOAD);
ok('monotony_display = "∞"', $s4['monotony_display'] === '∞');

// ── Session load formula ─────────────────────────────────────────────────────
echo "\n[ Session load ]\n";
ok('rpe 4 x 90 = 360', almostEqual(TrainingLoadCalculator::sessionLoad(4, 90), 360));
ok('decimal rpe 5.5 x 60 = 330', almostEqual(TrainingLoadCalculator::sessionLoad(5.5, 60), 330));
ok('actual duration < planned duration still multiplies actual', almostEqual(TrainingLoadCalculator::sessionLoad(3, 30), 90));
ok('missing rpe -> null', TrainingLoadCalculator::sessionLoad(null, 60) === null);
ok('missing duration -> null', TrainingLoadCalculator::sessionLoad(4, null) === null);

// ── Two sessions same day sum, not average ───────────────────────────────────
echo "\n[ Two sessions in one day (manual daily aggregation) ]\n";
$morning = TrainingLoadCalculator::sessionLoad(3, 60); // 180
$evening = TrainingLoadCalculator::sessionLoad(4, 30); // 120
ok('180 + 120 = 300, not averaged', almostEqual($morning + $evening, 300));

// ── Week bounds Monday..Sunday ───────────────────────────────────────────────
echo "\n[ Week bounds ]\n";
$b1 = TrainingLoadCalculator::weekBounds('2026-07-22', 'Africa/Kigali'); // a Wednesday
ok('week_start is Monday', $b1['week_start'] === '2026-07-20');
ok('week_end is Sunday', $b1['week_end'] === '2026-07-26');
$b2 = TrainingLoadCalculator::weekBounds('2026-07-20', 'Africa/Kigali'); // the Monday itself
ok('Monday reference resolves to itself as week_start', $b2['week_start'] === '2026-07-20');
$b3 = TrainingLoadCalculator::weekBounds('2026-07-26', 'Africa/Kigali'); // the Sunday itself
ok('Sunday reference resolves to same week', $b3['week_start'] === '2026-07-20' && $b3['week_end'] === '2026-07-26');

// ── computeWeekStats requires exactly 7 values ───────────────────────────────
echo "\n[ Input validation ]\n";
try {
    TrainingLoadCalculator::computeWeekStats([1, 2, 3]);
    ok('throws on non-7-length input', false);
} catch (InvalidArgumentException $e) {
    ok('throws on non-7-length input', true);
}

echo "\n=== Result: $pass passed, $fail failed ===\n\n";
exit($fail > 0 ? 1 : 0);
