<?php
// Body Composition / Body Fat calculation core — single source of truth.
// Used by save.php, update.php and bulk-save.php so every code path produces
// identical results. Client-side (Dart) mirrors this only for a live preview;
// whatever this file returns is what actually gets persisted.

/** Attempts with a spread over this many mm get a non-blocking "recheck" flag. */
const BC_ATTEMPT_SPREAD_LIMIT_MM = 2.0;
const BC_CALC_COMPLETE = 'COMPLETE';
const BC_CALC_INCOMPLETE_SKINFOLD = 'INCOMPLETE_SKINFOLD';
const BC_DEFAULT_REQUIRED_SITES = ['biceps', 'triceps', 'subscapular', 'suprailiac'];

/**
 * Age in whole years at the assessment date (not "today") — a player's age
 * band must reflect how old they were when measured, since historical
 * assessments are never recomputed when formulas change later.
 */
function bc_calc_age(string $dob, string $assessmentDate): ?int {
    try {
        $birth = new DateTime($dob);
        $at    = new DateTime($assessmentDate);
    } catch (Exception $e) {
        return null;
    }
    if ($at < $birth) return null;
    return $birth->diff($at)->y;
}

/**
 * Averages up to 3 skinfold attempts for one site. Returns null if none of
 * the attempts were provided (site not measured) — callers must not treat
 * that the same as a genuine zero.
 */
function bc_average_attempts(?float $a1, ?float $a2, ?float $a3): ?float {
    $vals = array_values(array_filter([$a1, $a2, $a3], fn($v) => $v !== null));
    if (!$vals) return null;
    return round(array_sum($vals) / count($vals), 1);
}

function bc_attempt_valid(?float $value): bool {
    return $value === null || ($value >= 2.0 && $value <= 60.0);
}

/**
 * True if any two provided attempts for a site differ by more than the
 * acceptable tolerance — surfaced to the caller as a non-blocking warning,
 * never blocks saving (a coach may only be able to take one attempt).
 */
function bc_attempt_spread_flag(?float $a1, ?float $a2, ?float $a3): bool {
    $vals = array_values(array_filter([$a1, $a2, $a3], fn($v) => $v !== null));
    if (count($vals) < 2) return false;
    return (max($vals) - min($vals)) > BC_ATTEMPT_SPREAD_LIMIT_MM;
}

/**
 * Selects the active formula row for the given age/gender. Returns null when
 * no age band covers this age (e.g. under 17 or over 39) — caller must not
 * calculate body fat % in that case, only store the raw measurements.
 */
function bc_select_formula(PDO $pdo, int $age, string $gender = 'male'): ?array {
    $stmt = $pdo->prepare(
        'SELECT * FROM body_composition_formulas
         WHERE gender = ? AND min_age <= ? AND max_age >= ? AND is_active = 1
         ORDER BY version DESC LIMIT 1'
    );
    $stmt->execute([$gender, $age, $age]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ?: null;
}

function bc_formula_required_sites(?array $formula): array {
    if (!$formula || empty($formula['required_sites'])) return BC_DEFAULT_REQUIRED_SITES;
    $sites = array_values(array_filter(array_map(
        fn($site) => trim((string)$site),
        explode(',', (string)$formula['required_sites'])
    )));
    return $sites ?: BC_DEFAULT_REQUIRED_SITES;
}

/**
 * @param array<string,?float> $averages
 */
function bc_skinfold_completeness(array $averages, ?array $formula): array {
    $required = bc_formula_required_sites($formula);
    $missing = [];
    foreach ($required as $site) {
        if (!array_key_exists($site, $averages) || $averages[$site] === null) {
            $missing[] = $site;
        }
    }
    return [
        'status' => $missing ? BC_CALC_INCOMPLETE_SKINFOLD : BC_CALC_COMPLETE,
        'required_sites' => $required,
        'missing_sites' => $missing,
        'measurement_completeness' => $required
            ? round((count($required) - count($missing)) / count($required), 4)
            : 0.0,
    ];
}

/**
 * BodyFat% = coefficient_a * LOG10(skinfold_sum) + coefficient_b.
 * Must use log10() — NOT log() (natural log) — to match the reference
 * Durnin & Womersley tables. Returns ['error' => ...] when no formula
 * matches this age/gender combination (age band not supported yet).
 */
function bc_calculate_body_fat(PDO $pdo, float $skinfoldSum, int $age, string $gender = 'male'): array {
    if ($skinfoldSum <= 0) {
        return ['error' => 'Skinfold sum must be positive'];
    }
    $formula = bc_select_formula($pdo, $age, $gender);
    if (!$formula) {
        return ['error' => "No body-fat formula supports age $age ($gender)"];
    }
    $bodyFatPercentage = round(
        ((float)$formula['coefficient_a']) * log10($skinfoldSum) + ((float)$formula['coefficient_b']),
        2
    );
    return [
        'body_fat_percentage' => $bodyFatPercentage,
        'formula_code'        => $formula['formula_code'],
        'age_group'           => $formula['formula_name'],
        'formula_version'     => (string)($formula['version'] ?? '1'),
    ];
}

function bc_bmi(float $weightKg, float $heightCm): float {
    $heightM = $heightCm / 100;
    return round($weightKg / ($heightM * $heightM), 2);
}

function bc_fat_mass_kg(float $weightKg, float $bodyFatPercentage): float {
    return round($weightKg * $bodyFatPercentage / 100, 2);
}

function bc_fat_free_mass_kg(float $weightKg, float $fatMassKg): float {
    return round($weightKg - $fatMassKg, 2);
}
