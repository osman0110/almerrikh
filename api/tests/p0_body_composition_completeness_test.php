<?php
require_once dirname(__DIR__) . '/includes/body_composition_calculator.php';

function bcP0Assert($condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}

$formula = ['required_sites' => 'biceps,triceps,subscapular,suprailiac'];
$complete = bc_skinfold_completeness([
    'biceps' => 5.0,
    'triceps' => 8.0,
    'subscapular' => 10.0,
    'suprailiac' => 9.0,
], $formula);
bcP0Assert($complete['status'] === BC_CALC_COMPLETE, 'Four sites must be complete');
bcP0Assert($complete['measurement_completeness'] === 1.0, 'Complete ratio must be 1');

$oneMissing = bc_skinfold_completeness([
    'biceps' => 5.0,
    'triceps' => null,
    'subscapular' => 10.0,
    'suprailiac' => 9.0,
], $formula);
bcP0Assert($oneMissing['status'] === BC_CALC_INCOMPLETE_SKINFOLD, 'Missing site must block calculation');
bcP0Assert($oneMissing['missing_sites'] === ['triceps'], 'Missing site list mismatch');

$manyMissing = bc_skinfold_completeness([
    'biceps' => null,
    'triceps' => null,
    'subscapular' => 10.0,
    'suprailiac' => null,
], $formula);
bcP0Assert(count($manyMissing['missing_sites']) === 3, 'Three missing sites expected');

bcP0Assert(bc_attempt_valid(2.0) === true, 'Lower boundary must be valid');
bcP0Assert(bc_attempt_valid(60.0) === true, 'Upper boundary must be valid');
bcP0Assert(bc_attempt_valid(70.0) === false, 'Irrational skinfold value must be rejected');
echo "p0_body_composition_completeness_test: OK\n";
