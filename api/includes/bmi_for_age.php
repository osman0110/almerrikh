<?php
// Approximate BMI-for-age classification for youth players (2–19 years).
//
// IMPORTANT: this is a simplified, unisex approximation of typical growth-
// chart shapes (BMI cutoffs rise through childhood/adolescence before
// levelling off around age 18-20) — it is NOT the WHO/CDC LMS percentile
// method, which requires full sex-specific reference tables. Treat the
// result as a rough screening flag, never a clinical diagnosis.
function classifyBmiForAge(float $bmi, float $ageYears): string {
    if ($ageYears >= 20) {
        if ($bmi < 18.5) return 'underweight';
        if ($bmi < 25)   return 'healthy';
        if ($bmi < 30)   return 'overweight';
        return 'obese';
    }

    // Piecewise cutoffs approximated across common age bands (2-19y)
    $bands = [
        ['max_age' => 9,   'underweight' => 14, 'healthy' => 17, 'overweight' => 19],
        ['max_age' => 13,  'underweight' => 15, 'healthy' => 19, 'overweight' => 22],
        ['max_age' => 17,  'underweight' => 16, 'healthy' => 21, 'overweight' => 25],
        ['max_age' => 19,  'underweight' => 17, 'healthy' => 23, 'overweight' => 27],
    ];

    foreach ($bands as $band) {
        if ($ageYears <= $band['max_age']) {
            if ($bmi < $band['underweight']) return 'underweight';
            if ($bmi < $band['healthy'])     return 'healthy';
            if ($bmi < $band['overweight'])  return 'overweight';
            return 'obese';
        }
    }

    return 'healthy'; // unreachable, but keeps the function total
}
