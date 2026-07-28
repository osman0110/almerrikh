<?php
/**
 * Unit tests for the Body Composition calculator — verifies the 3 seeded
 * age-band formulas against hand-computed reference values, and explicitly
 * proves LOG10 (not natural log) is being used, per the spec requirement.
 *
 * Run: php api/tests/body_composition_calculator_test.php
 */
require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/body_composition_calculator.php';

$pass = 0; $fail = 0;

function ok(string $label, bool $cond, string $detail = ''): void {
    global $pass, $fail;
    if ($cond) { echo "  PASS  $label\n"; $pass++; }
    else        { echo "  FAIL  $label" . ($detail ? " — $detail" : '') . "\n"; $fail++; }
}

function almostEqual($a, $b, float $eps = 0.01): bool {
    if ($a === null || $b === null) return $a === $b;
    return abs($a - $b) < $eps;
}

echo "\n=== Body Composition Calculator Tests ===\n\n";

// ── Reference values, hand-computed from the spec's coefficients ───────────
// BodyFat% = a * LOG10(sum) + b
$skinfoldSum = 40.0; // mm
$refs = [
    'age_17_19' => 27.409 * log10($skinfoldSum) - 26.789,
    'age_20_29' => 27.775 * log10($skinfoldSum) - 27.203,
    'age_30_39' => 26.781 * log10($skinfoldSum) - 27.203,
];

$calc18 = bc_calculate_body_fat($pdo, $skinfoldSum, 18, 'male');
ok('age 17-19 band selected for age 18', ($calc18['formula_code'] ?? null) === 'age_17_19');
ok('age 17-19 body fat % matches reference', almostEqual($calc18['body_fat_percentage'] ?? null, round($refs['age_17_19'], 2)),
    "got {$calc18['body_fat_percentage']}, expected " . round($refs['age_17_19'], 2));

$calc25 = bc_calculate_body_fat($pdo, $skinfoldSum, 25, 'male');
ok('age 20-29 band selected for age 25', ($calc25['formula_code'] ?? null) === 'age_20_29');
ok('age 20-29 body fat % matches reference', almostEqual($calc25['body_fat_percentage'] ?? null, round($refs['age_20_29'], 2)),
    "got {$calc25['body_fat_percentage']}, expected " . round($refs['age_20_29'], 2));

$calc35 = bc_calculate_body_fat($pdo, $skinfoldSum, 35, 'male');
ok('age 30-39 band selected for age 35', ($calc35['formula_code'] ?? null) === 'age_30_39');
ok('age 30-39 body fat % matches reference', almostEqual($calc35['body_fat_percentage'] ?? null, round($refs['age_30_39'], 2)),
    "got {$calc35['body_fat_percentage']}, expected " . round($refs['age_30_39'], 2));

// ── LOG10 vs LN — must NOT match if natural log were used by mistake ───────
$wrongUsingLn = round(27.775 * log($skinfoldSum) - 27.203, 2);
ok('20-29 result does NOT match a natural-log calculation (proves LOG10 is used)',
    !almostEqual($calc25['body_fat_percentage'] ?? null, $wrongUsingLn, 0.01),
    "log10 result {$calc25['body_fat_percentage']} vs ln result $wrongUsingLn");

// ── Unsupported age bands ────────────────────────────────────────────────
$calcTooYoung = bc_calculate_body_fat($pdo, $skinfoldSum, 15, 'male');
ok('age 15 (unsupported) returns an error, not a fabricated result', isset($calcTooYoung['error']));

$calcTooOld = bc_calculate_body_fat($pdo, $skinfoldSum, 45, 'male');
ok('age 45 (unsupported) returns an error, not a fabricated result', isset($calcTooOld['error']));

// ── Age boundaries ───────────────────────────────────────────────────────
ok('age 17 (lower boundary) resolves to age_17_19', (bc_select_formula($pdo, 17, 'male')['formula_code'] ?? null) === 'age_17_19');
ok('age 19 (upper boundary) resolves to age_17_19', (bc_select_formula($pdo, 19, 'male')['formula_code'] ?? null) === 'age_17_19');
ok('age 20 (lower boundary) resolves to age_20_29', (bc_select_formula($pdo, 20, 'male')['formula_code'] ?? null) === 'age_20_29');
ok('age 39 (upper boundary) resolves to age_30_39', (bc_select_formula($pdo, 39, 'male')['formula_code'] ?? null) === 'age_30_39');

// ── Age calculation ──────────────────────────────────────────────────────
ok('bc_calc_age computes whole years as of assessment date, not today',
    bc_calc_age('2000-06-15', '2025-06-14') === 24);
ok('bc_calc_age rolls over on birthday', bc_calc_age('2000-06-15', '2025-06-15') === 25);

// ── Skinfold averaging & attempt-spread flag ─────────────────────────────
ok('bc_average_attempts averages 3 values', almostEqual(bc_average_attempts(10.0, 12.0, 11.0), 11.0));
ok('bc_average_attempts handles a single attempt', almostEqual(bc_average_attempts(10.0, null, null), 10.0));
ok('bc_average_attempts returns null when nothing provided', bc_average_attempts(null, null, null) === null);
ok('bc_attempt_spread_flag trips above the tolerance', bc_attempt_spread_flag(10.0, 13.5, null) === true);
ok('bc_attempt_spread_flag does not trip within tolerance', bc_attempt_spread_flag(10.0, 11.5, null) === false);

// ── BMI / fat mass / fat-free mass ────────────────────────────────────────
ok('bc_bmi computes weight/height^2', almostEqual(bc_bmi(80, 180), 24.69));
ok('bc_fat_mass_kg computes weight * bf% / 100', almostEqual(bc_fat_mass_kg(80, 15), 12.0));
ok('bc_fat_free_mass_kg is weight minus fat mass', almostEqual(bc_fat_free_mass_kg(80, 12.0), 68.0));

echo "\n$pass passed, $fail failed\n\n";
exit($fail > 0 ? 1 : 0);
