<?php
// Pure regression test — no DB required. Locks the authorization boundary
// for the 'sessions.write' capability (RB2 fix: api/sessions.php attendance
// update). Guards against a future change accidentally granting/removing
// sessions.write for a role without anyone noticing.
require_once dirname(__DIR__) . '/includes/club_auth.php';

$expected = [
    'owner'               => true,
    'admin'               => true,
    'coach'               => true,
    'performance_manager' => true,
    'tactical_coach'      => true,
    'doctor'              => false,
    'analyst'             => false,
    'physiotherapist'     => false,
    'massage_specialist'  => false,
    'nutritionist'        => false,
    'player'              => false,
];

$failures = [];
foreach ($expected as $role => $shouldAllow) {
    $actual = clubStaffCan($role, 'sessions.write');
    if ($actual !== $shouldAllow) {
        $failures[] = "$role: expected " . var_export($shouldAllow, true) . ", got " . var_export($actual, true);
    }
}

if ($failures) {
    fwrite(STDERR, "p0_sessions_write_permission_test: FAIL\n" . implode("\n", $failures) . "\n");
    exit(1);
}

echo "p0_sessions_write_permission_test: OK\n";
