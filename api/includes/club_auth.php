<?php
// ─────────────────────────────────────────────────────────────────────────────
// Club staff context + permission checks.
//
// Single choke point for "which club does this caller belong to, and what
// are they allowed to do" — replaces ad hoc in_array($user['role'], [...])
// checks scattered per-endpoint. New/migrated endpoints should call
// resolveClubContext() once and use can() for capability checks instead of
// re-deriving role logic locally.
// ─────────────────────────────────────────────────────────────────────────────
require_once __DIR__ . '/fitness/SchemaInspector.php';

// Resolves { club_id, staff_role } for an authenticated user.
// Falls back to users.club_id + 'owner' for legacy accounts that predate
// the club_staff table, so existing single-owner clubs keep working.
function resolveClubContext(PDO $pdo, array $user): array {
    $hasTeamScope = SchemaInspector::hasColumn($pdo, 'club_staff', 'team_id');
    $stmt = $pdo->prepare(
        'SELECT club_id, staff_role' . ($hasTeamScope ? ', team_id' : '') . " FROM club_staff
         WHERE user_id = ? AND status = 'active' LIMIT 1"
    );
    $stmt->execute([$user['id']]);
    $row = $stmt->fetch();
    if ($row) {
        return [
            'club_id' => (int)$row['club_id'],
            'staff_role' => $row['staff_role'],
            'team_id' => $hasTeamScope && $row['team_id'] !== null ? (int)$row['team_id'] : null,
        ];
    }

    $legacy = $pdo->prepare("SELECT club_id, COALESCE(role, 'club') AS role FROM users WHERE id = ?");
    $legacy->execute([$user['id']]);
    $legacyRow = $legacy->fetch() ?: [];
    $clubId = $legacyRow['club_id'] ?? null;
    // Only legacy club-owner accounts may use users.club_id as a fallback.
    // Suspended staff keep that column, so treating every such user as owner
    // would bypass the active club_staff membership check above.
    if ($clubId && ($legacyRow['role'] ?? '') === 'club') {
        return ['club_id' => (int)$clubId, 'staff_role' => 'owner', 'team_id' => null];
    }

    return ['club_id' => null, 'staff_role' => null, 'team_id' => null];
}

// Coach-exclusive actions: only the physical coach may perform these, even
// though owner/admin normally bypass every other check via the '*'
// wildcard, and performance_manager otherwise has broad write access.
// FMS assessments and body-composition entries are the physical coach's
// own measurement tools — deliberately kept out of management's hands.
const COACH_ONLY_ACTIONS = [
    'fms.write',
    'fitness.body_composition.create',
    'fitness.body_composition.update',
    'fitness.body_composition.import',
];

// Capability map. Keep this the single source of truth for what each staff
// role can do — do not duplicate role checks inline in endpoints.
// Full clinical/medical detail (diagnosis, exam notes, free-text medical and
// injury notes, attachments, rehab file) is NOT covered by the owner/admin
// '*' wildcard (decision 2026-09-19): being club management does not grant
// medical access. Only roles that list these actions explicitly (doctor,
// physiotherapist, massage_specialist) get them.
const EXPLICIT_ONLY_ACTIONS = [
    'medical_detail.read',
    'medical_detail.write',
];

function clubStaffCan(string $staffRole, string $action): bool {
    if (in_array($action, COACH_ONLY_ACTIONS, true)) {
        return $staffRole === 'coach';
    }

    $capabilities = [
        'owner'   => ['*'],
        'admin'   => ['*'],
        // Player is not a club_staff row; this entry documents the one
        // fitness capability enforced directly by self-service endpoints.
        'player'  => ['fitness.rpe.create_for_self'],
        // Physical coach — focused on training load/RPE/Hooper/readiness.
        // No injury-file edits, no team management, no player deletion
        // (owner/admin/performance_manager keep those).
        'coach'   => [
            'players.read', 'players.write',
            'sessions.read', 'sessions.write',
            'matches.create', 'matches.live',
            'assessments.read', 'assessments.write',
            'fms.write',
            'notes.read', 'notes.write',
            'medical.read',
            'medical_summary.read',
            'teams.read',
            'seasons.read', 'competitions.read',
            'physio_sessions.read',
            'daily_readiness.read', 'daily_readiness.write',
            'tasks.view', 'tasks.manage', 'tasks.assign_others',
            'fitness.body_composition.view',
            'fitness.body_composition.create',
            'fitness.body_composition.update',
            'fitness.body_composition.approve',
            'fitness.body_composition.import',
            'fitness.training_load.view',
            'fitness.training_load.adjust',
            'fitness.training_load.approve',
            'fitness.rpe.create_for_player',
            'fitness.rpe.update',
            'fitness.rpe.resolve_duplicates',
            'fitness.audit.view',
            'alerts.send',
        ],
        'doctor'  => [
            'players.read',
            'sessions.read',
            'competitions.read',
            'notes.read', 'notes.write',
            'medical.read', 'medical.write',
            'medical_detail.read', 'medical_detail.write',
            'physio_sessions.read', 'physio_sessions.write',
            'nutrition.read', 'nutrition.write',
            'daily_readiness.read', 'daily_readiness.write',
            'tasks.view', 'tasks.manage', 'tasks.assign_others',
            'fitness.body_composition.view',
            'fitness.training_load.view',
        ],
        // Analyst is strictly read-only everywhere else, so tasks are
        // view-only too — no create/assign (matches isAnalystRole in
        // lib/app_state.dart, which gates no write action anywhere).
        'analyst' => [
            'players.read',
            'sessions.read',
            'assessments.read',
            'notes.read',
            'teams.read',
            'seasons.read', 'competitions.read',
            'daily_readiness.read',
            'fitness.training_load.view',
            'tasks.view',
        ],
        'performance_manager' => [
            'players.read', 'players.write', 'players.delete',
            'sessions.read', 'sessions.write',
            'matches.create', 'matches.update', 'matches.delete', 'matches.live',
            'assessments.read', 'assessments.write',
            'notes.read', 'notes.write',
            'medical.read', 'medical.write',
            'medical_summary.read',
            'teams.read', 'teams.write',
            'seasons.read', 'seasons.write', 'competitions.read', 'competitions.write',
            'management_report.view',
            'physio_sessions.read', 'physio_sessions.write',
            'nutrition.read', 'nutrition.write',
            'daily_readiness.read', 'daily_readiness.write',
            'tasks.view', 'tasks.manage', 'tasks.assign_others',
            'fitness.body_composition.view',
            'fitness.training_load.view',
            'fitness.audit.view',
            'alerts.send',
        ],
        // Physiotherapist covers physiotherapy AND massage — one job at
        // this club, not two. 'massage_specialist' is kept as an alias to
        // the exact same capability list below purely so pre-existing
        // club_staff rows with that legacy staff_role keep working; new
        // invites only ever create 'physiotherapist' (see staff_screen.dart).
        'physiotherapist' => [
            'players.read',
            'competitions.read',
            'sessions.read',
            'notes.read', 'notes.write',
            'medical.read', 'medical.write',
            'medical_detail.read', 'medical_detail.write',
            'physio_sessions.read', 'physio_sessions.write',
            'daily_readiness.read',
            'tasks.view', 'tasks.manage',
        ],
        'massage_specialist' => [
            'players.read',
            'competitions.read',
            'sessions.read',
            'notes.read', 'notes.write',
            'medical.read', 'medical.write',
            'medical_detail.read', 'medical_detail.write',
            'physio_sessions.read', 'physio_sessions.write',
            'daily_readiness.read',
            'tasks.view', 'tasks.manage',
        ],
        'nutritionist' => [
            'players.read',
            'competitions.read',
            'notes.read', 'notes.write',
            'nutrition.read', 'nutrition.write',
            'daily_readiness.read',
            'tasks.view', 'tasks.manage',
            'fitness.body_composition.view',
            'fitness.training_load.view',
        ],
        // Tactical coach — full sessions/matches management, no
        // medical/physio/nutrition or team roster edits
        // (owner/admin/performance_manager keep those).
        'tactical_coach' => [
            'players.read',
            'sessions.read', 'sessions.write',
            'matches.create', 'matches.update', 'matches.delete', 'matches.live',
            'assessments.read',
            'notes.read',
            'teams.read',
            'seasons.read', 'competitions.read',
            'daily_readiness.read',
            'tasks.view', 'tasks.manage',
            'fitness.training_load.view',
            'alerts.send',
        ],
    ];

    $allowed = $capabilities[$staffRole] ?? [];
    // Full medical access always includes the summary level.
    if ($action === 'medical_summary.read' && in_array('medical_detail.read', $allowed, true)) {
        return true;
    }
    if (in_array($action, EXPLICIT_ONLY_ACTIONS, true)) {
        return in_array($action, $allowed, true);
    }
    return in_array('*', $allowed, true) || in_array($action, $allowed, true);
}

// Convenience guard: resolves club context and 403s if the caller isn't a
// member of any club, or isn't allowed to perform $action.
function requireClubPermission(PDO $pdo, array $user, string $action): array {
    $ctx = resolveClubContext($pdo, $user);
    if (!$ctx['club_id']) {
        http_response_code(403);
        echo json_encode(['error' => 'Not a member of a club'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    if (!clubStaffCan($ctx['staff_role'], $action)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden — insufficient staff role'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    return $ctx;
}

// ── Record ownership (sessions, assessments) ─────────────────────────────────
// Business rule (2026-09-19): a training session / assessment belongs to the
// coach who created it (its user_id); the club is only the tenant boundary.
// Another coach in the same club does NOT get write access automatically —
// only the record's creator or a club owner/admin (the '*' roles) may change
// it. Reads stay club-scoped.
function isClubAdminRole(?string $staffRole): bool {
    return in_array($staffRole, ['owner', 'admin'], true);
}

function canManageOwnedRecord(array $ctx, array $user, array $record): bool {
    if ((int)($record['club_id'] ?? 0) !== (int)($ctx['club_id'] ?? -1)) return false;
    if (isClubAdminRole($ctx['staff_role'] ?? null)) return true;
    return (int)($record['user_id'] ?? 0) === (int)$user['id'];
}

// Loads a club_sessions row for a write and enforces ownership:
//   not in the caller's club → 404 (never confirm another club's data exists)
//   in the club, not owner   → 403
function requireManageableSession(PDO $pdo, array $user, array $ctx, string $sessionId): array {
    $stmt = $pdo->prepare('SELECT * FROM club_sessions WHERE id = ? AND club_id = ?');
    $stmt->execute([$sessionId, $ctx['club_id']]);
    $session = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$session) {
        http_response_code(404);
        echo json_encode(['error' => 'Session not found'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    if (!canManageOwnedRecord($ctx, $user, $session)) {
        http_response_code(403);
        echo json_encode([
            'error' => 'Forbidden — only the coach who owns this session can change it',
            'code'  => 'not_session_owner',
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
    return $session;
}

// ── Medical information: two levels ──────────────────────────────────────────
// Full medical text (club_players.medical_notes / injury_notes, injury-case
// diagnosis & exam notes) is only for roles with 'medical_detail.read'
// (doctor, physiotherapist — NOT owner/admin, see EXPLICIT_ONLY_ACTIONS). Everyone else — including the
// physical coach — gets availability fields only (status,
// unavailable_reason, expected_return_date, player_daily_decisions
// restrictions) plus a boolean saying notes exist. Enforced server-side:
// the text never leaves the API for those roles.
function canReadMedicalDetail(array $ctx): bool {
    return clubStaffCan((string)($ctx['staff_role'] ?? ''), 'medical_detail.read');
}

// Injury/treatment SUMMARY (decision 2026-09-20): the physical coach and
// performance manager need the injury picture to plan training — body
// location, injury type, severity, return-to-play stage, physio schedule and
// status, and the short injury note. They still never get the clinical
// content: doctor diagnosis, exam notes, specialist notes or medical_notes.
function canReadMedicalSummary(array $ctx): bool {
    return canReadMedicalDetail($ctx)
        || clubStaffCan((string)($ctx['staff_role'] ?? ''), 'medical_summary.read');
}

function redactMedicalFields(array &$row, array $ctx): void {
    if (canReadMedicalDetail($ctx)) {
        $row['medical_detail_hidden'] = false;
        return;
    }
    $row['has_injury_notes'] = trim((string)($row['injury_notes'] ?? '')) !== '';
    // Summary roles keep the short injury note; everyone else loses it too.
    if (!canReadMedicalSummary($ctx)) $row['injury_notes'] = null;
    $row['medical_notes'] = null;
    $row['medical_detail_hidden'] = true;
}
