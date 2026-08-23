<?php
// Pure regression test — no DB required. Locks the club_auth.php capability
// matrix (api/includes/club_auth.php) for the roles and actions that matter
// most for data-sensitivity and remediation (RB2/RB3 touched sessions and
// competitions; the broader audit flagged medical-detail exposure as the
// highest-sensitivity RBAC boundary in the app). This is the "Authorization
// tests: Admin, Coach, Analyst, Medical, Unauthorized roles" coverage from
// the remediation request — same-club/different-club isolation itself is
// covered by the DB-backed p0_scope_integration_test.php and
// p0_attendance_scope_test.php, since that requires seeded rows.
require_once dirname(__DIR__) . '/includes/club_auth.php';

$failures = [];

function checkMatrix(array $expected, string $action, array &$failures): void {
    foreach ($expected as $role => $shouldAllow) {
        $actual = clubStaffCan($role, $action);
        if ($actual !== $shouldAllow) {
            $failures[] = "$action / $role: expected " . var_export($shouldAllow, true)
                . ', got ' . var_export($actual, true);
        }
    }
}

// Clinical injury/diagnosis detail — must stay restricted to medical staff.
// A coach or analyst reaching this would leak diagnosis-level text (see
// api/club/injuries.php, which gates on exactly this capability).
checkMatrix([
    'owner'               => true,
    'admin'               => true,
    'doctor'              => true,
    'physiotherapist'     => true,
    'massage_specialist'  => true,
    'coach'               => false,
    'performance_manager' => false,
    'analyst'             => false,
    'nutritionist'        => false,
    'tactical_coach'      => false,
    'player'              => false,
], 'medical_detail.read', $failures);

checkMatrix([
    'doctor'              => true,
    'physiotherapist'     => true,
    'massage_specialist'  => true,
    'coach'               => false,
    'analyst'             => false,
    'performance_manager' => false,
], 'medical_detail.write', $failures);

// Analyst is documented as strictly read-only everywhere (see comment in
// club_auth.php) — assert it has zero write-shaped capabilities among the
// ones defined for it, not just spot-checks.
foreach ([
    'players.write', 'sessions.write', 'matches.create', 'notes.write',
    'medical.write', 'teams.write', 'daily_readiness.write', 'tasks.manage',
] as $writeAction) {
    if (clubStaffCan('analyst', $writeAction)) {
        $failures[] = "analyst unexpectedly has write capability: $writeAction";
    }
}

// COACH_ONLY_ACTIONS carve-out: FMS/body-composition entry is the physical
// coach's own tool — deliberately NOT granted to owner/admin's normal '*'
// wildcard, and NOT to performance_manager despite its otherwise broad
// write access. This is the most subtle rule in club_auth.php and the
// easiest for a future refactor to silently break.
checkMatrix([
    'coach'               => true,
    'owner'               => false,
    'admin'               => false,
    'performance_manager' => false,
    'doctor'              => false,
], 'fms.write', $failures);
checkMatrix([
    'coach'               => true,
    'owner'               => false,
    'admin'               => false,
    'performance_manager' => false,
], 'fitness.body_composition.create', $failures);

// Player deletion — destructive, must stay limited to management roles.
checkMatrix([
    'owner'               => true,
    'admin'               => true,
    'performance_manager' => true,
    'coach'               => false,
    'analyst'             => false,
    'tactical_coach'      => false,
    'physiotherapist'     => false,
], 'players.delete', $failures);

// Unknown/unrecognized role must never fall through to an allow.
foreach (['guest', 'unknown', '', 'Owner', 'ADMIN'] as $badRole) {
    if (clubStaffCan($badRole, 'players.read')) {
        $failures[] = "unrecognized role '$badRole' unexpectedly allowed players.read";
    }
}

if ($failures) {
    fwrite(STDERR, "p0_rbac_capability_matrix_test: FAIL\n" . implode("\n", $failures) . "\n");
    exit(1);
}

echo "p0_rbac_capability_matrix_test: OK\n";
