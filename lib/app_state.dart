enum UserRole   { club, player }
enum PlayerType { independent, club }

/// Role of the current user *within* their club organization.
/// Applies only when [currentUserRole] is [UserRole.club].
/// Defaults to [staff] (least privilege) when the API hasn't returned org_role.
enum OrgRole    {
  owner, admin, coach, doctor, analyst, staff,
  performanceManager, physiotherapist, nutritionist,
  tacticalCoach,
}

String currentUserName    = 'Player';
String currentUserNameArabic = '';
String currentUserNameEnglish = '';
String currentUserAvatarUrl = '';
UserRole currentUserRole  = UserRole.club;
OrgRole  currentOrgRole   = OrgRole.staff;
PlayerType? currentPlayerType;
int? currentUserId;

// Fixed team — set once after login from the club's first registered team
String currentTeamId   = '';
String currentTeamName = '';

// Club display name — populated after the physical coach dashboard's first
// load, then reused by CoachBrandHeader on other club pages so they don't
// need their own profile fetch just for the logo/name in the top header.
String currentClubName = '';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// True when logged in as a club (organization user).
bool get isOrgUser => currentUserRole == UserRole.club;

/// True when the org role has full admin access.
bool get isOrgAdmin =>
    currentOrgRole == OrgRole.owner || currentOrgRole == OrgRole.admin;

/// True when the org role is coach (limited view, no settings/invites/teams).
bool get isCoachRole => currentOrgRole == OrgRole.coach;

/// True when the org role is doctor — gets the focused medical dashboard.
bool get isDoctorRole => currentOrgRole == OrgRole.doctor;

/// True when the org role is physiotherapist — covers physiotherapy AND
/// massage (one job at this club; there is no separate massage role), gets
/// the focused physio/massage-session dashboard.
bool get isPhysiotherapistRole => currentOrgRole == OrgRole.physiotherapist;

/// True when the org role is nutritionist — gets the focused roster-search
/// dashboard for managing per-player nutrition plans.
bool get isNutritionistRole => currentOrgRole == OrgRole.nutritionist;

/// True when the org role is tactical coach — gets the focused
/// sessions/matches dashboard.
bool get isTacticalCoachRole => currentOrgRole == OrgRole.tacticalCoach;

/// May send a custom alert notification to a player/team/club (mirrors
/// 'alerts.send' in api/includes/club_auth.php's clubStaffCan()).
bool get canSendAlerts =>
    isCoachRole ||
    isTacticalCoachRole ||
    currentOrgRole == OrgRole.performanceManager ||
    isOrgAdmin;

/// May create/edit a player profile (mirrors 'players.write' in
/// api/includes/club_auth.php's clubStaffCan()).
bool get canManagePlayers =>
    isCoachRole || currentOrgRole == OrgRole.performanceManager || isOrgAdmin;

/// May permanently delete a player ('players.delete' — narrower than
/// write; physical coach doesn't have this).
bool get canDeletePlayers =>
    currentOrgRole == OrgRole.performanceManager || isOrgAdmin;

/// May create/edit teams & categories ('teams.write' in club_auth.php's
/// clubStaffCan() — owner/admin/performance_manager only).
bool get canManageTeams =>
    currentOrgRole == OrgRole.performanceManager || isOrgAdmin;

/// May create/edit training sessions. Deliberately excludes admin/owner —
/// per the club's read-only management policy, sessions are physical-coach
/// operational data ("إنشاء جلسة" is on the explicit hidden-buttons list),
/// so management sees the session list but never creates or edits one.
bool get canManageSessions =>
    isCoachRole || currentOrgRole == OrgRole.performanceManager;

/// May enter/edit the league standings table ('competitions.write' in
/// club_auth.php's clubStaffCan() — owner/admin/performance_manager only,
/// same role set as [canManageTeams]). Every role can still read standings.
bool get canManageStandings =>
    currentOrgRole == OrgRole.performanceManager || isOrgAdmin;

/// May view the management report (minutes/attendance/cards rollup) —
/// 'management_report.view' in club_auth.php's clubStaffCan(). Deliberately
/// narrower than the other team reports — physical-coach-detail reports
/// (training load, performance) stay visible to everyone as before.
bool get canViewManagementReport =>
    currentOrgRole == OrgRole.performanceManager || isOrgAdmin;

/// Shared club pages mirror the backend's club-scoped capabilities.
bool get canViewClubPlayers => currentOrgRole != OrgRole.staff;

bool get canViewClubSessions =>
    isCoachRole ||
    isDoctorRole ||
    isAnalystRole ||
    isTacticalCoachRole ||
    currentOrgRole == OrgRole.performanceManager ||
    isOrgAdmin;

bool get canViewClubReports => currentOrgRole != OrgRole.staff;

/// May start a new AI physical assessment ('assessments.write').
/// Deliberately excludes admin/owner — per the club's read-only management
/// policy, running an assessment is physical-coach operational data entry,
/// not something management records.
bool get canRunAssessments =>
    isCoachRole || currentOrgRole == OrgRole.performanceManager;

/// May add a new FMS assessment — physical coach only. Deliberately
/// narrower than [canRunAssessments] (which also covers owner/admin/
/// performance_manager for the AI camera assessment flow): FMS is the
/// physical coach's own screening tool, hidden from physiotherapist and
/// management. Matches 'fms.write' in api/includes/club_auth.php's
/// clubStaffCan(), which coach-only overrides even the owner/admin wildcard.
bool get canManageFms => isCoachRole;

/// May add/edit/import body-composition entries — physical coach only, for
/// the same reason as [canManageFms]. Matches 'fitness.body_composition.
/// create'/'.update'/'.import' in club_auth.php's clubStaffCan(), which
/// coach-only overrides even the owner/admin wildcard. Viewing stays
/// broader (doctor/performance_manager/nutritionist/admin keep '.view').
bool get canManageBodyComposition => isCoachRole;

/// True when the org role is a medical/physical staff role that may view
/// and edit injury & medical notes (doctor, physiotherapist, coach,
/// performance manager). Matches 'medical.read'/'medical.write' in
/// club_auth.php's clubStaffCan() — narrower than [canManageInjuryCases],
/// which gates the clinical diagnosis detail. Deliberately excludes
/// admin/owner: sensitive medical detail is off-limits to management, who
/// only see the non-clinical participation-status summary.
bool get canViewMedicalNotes =>
    currentOrgRole == OrgRole.doctor ||
    currentOrgRole == OrgRole.physiotherapist ||
    currentOrgRole == OrgRole.coach ||
    currentOrgRole == OrgRole.performanceManager;

/// True when the org role is dedicated medical/treatment staff
/// (doctor, physiotherapist — covers physio & massage).
bool get isMedicalStaff =>
    currentOrgRole == OrgRole.doctor ||
    currentOrgRole == OrgRole.physiotherapist;

/// True when the org role may view/manage the clinical injury/RTP file
/// (doctor, physiotherapist). Stricter than [canViewMedicalNotes] — coach
/// is deliberately excluded here, since the injury file carries diagnosis/
/// exam detail, not just participation status. Also excludes admin/owner:
/// management never creates/edits medical reports or injury records, only
/// the read-only injury/rehab-status summary in reports.
bool get canManageInjuryCases =>
    currentOrgRole == OrgRole.doctor ||
    currentOrgRole == OrgRole.physiotherapist;

/// True when the org role is read-only performance analysis (no writes).
bool get isAnalystRole => currentOrgRole == OrgRole.analyst;

/// True when the org role may book/manage physiotherapy & massage sessions
/// (doctor, physiotherapist — covers physio & massage, performance manager).
/// Matches 'physio_sessions.write' in api/includes/club_auth.php's
/// clubStaffCan() — performance_manager has it there too. Deliberately
/// excludes admin/owner: management never books/edits treatment sessions,
/// only sees the per-player session count in reports.
bool get canManagePhysioSessions =>
    currentOrgRole == OrgRole.doctor ||
    currentOrgRole == OrgRole.physiotherapist ||
    currentOrgRole == OrgRole.performanceManager;

/// True when the org role may view (but not necessarily book/edit) the
/// physio/massage sessions schedule — everyone canManagePhysioSessions can,
/// plus the physical coach (physio_sessions.read only in club_auth.php, so
/// the shared club Sessions list can show physio sessions alongside
/// training sessions).
bool get canViewPhysioSessions =>
    canManagePhysioSessions || currentOrgRole == OrgRole.coach;

/// True when the org role may manage nutrition/hydration/supplement plans
/// (doctor, nutritionist, performance manager). Matches 'nutrition.write' in
/// api/includes/club_auth.php's clubStaffCan() — performance_manager has it
/// there too. Deliberately excludes admin/owner under the read-only
/// management policy.
bool get canManageNutrition =>
    currentOrgRole == OrgRole.doctor ||
    currentOrgRole == OrgRole.nutritionist ||
    currentOrgRole == OrgRole.performanceManager;

/// True when the org role may view the unified daily readiness dashboard
/// Includes every active technical/medical/read-only staff role; write access
/// remains narrower in [canSetDailyDecision].
bool get canViewDailyReadiness =>
    isCoachRole ||
    currentOrgRole == OrgRole.doctor ||
    currentOrgRole == OrgRole.physiotherapist ||
    currentOrgRole == OrgRole.nutritionist ||
    isAnalystRole ||
    isTacticalCoachRole ||
    currentOrgRole == OrgRole.performanceManager ||
    isOrgAdmin;

/// True when the org role may log today's participation decision
/// (coach, doctor, performance manager) — matches the roles that actually
/// make the call, per [canViewDailyReadiness] which is broader. Deliberately
/// excludes admin/owner under the read-only management policy: management
/// sees the readiness dashboard but never sets the decision.
bool get canSetDailyDecision =>
    isCoachRole ||
    currentOrgRole == OrgRole.doctor ||
    currentOrgRole == OrgRole.performanceManager;

/// May view/create/comment on tasks and update their own tasks' status
/// ('tasks.manage' in club_auth.php's clubStaffCan()) — every role except
/// analyst (view-only, matches its read-only design everywhere else) and
/// staff (generic placeholder role with no capabilities granted yet).
bool get canManageTasks =>
    !isAnalystRole && currentOrgRole != OrgRole.staff;

/// May assign a task to someone other than themselves ('tasks.assign_others'
/// — coach, doctor, performance manager, plus admin/owner).
bool get canAssignTasksToOthers =>
    isCoachRole ||
    currentOrgRole == OrgRole.doctor ||
    currentOrgRole == OrgRole.performanceManager ||
    isOrgAdmin;

/// May create a new match. The physical coach can add the match schedule so
/// wellness/RPE workflows have the correct match context, while broader match
/// management remains restricted through [canManageMatches].
bool get canCreateMatches => isCoachRole || canManageMatches;

/// May edit/delete existing matches (tactical coach, performance manager,
/// plus admin/owner). Creating a match is intentionally checked separately.
bool get canManageMatches =>
    isTacticalCoachRole ||
    currentOrgRole == OrgRole.performanceManager ||
    isOrgAdmin;

/// May operate the live player clock and record match events. This is narrower
/// than full match editing, but includes the physical coach working pitch-side.
bool get canControlActivityClock =>
    isCoachRole ||
    isTacticalCoachRole ||
    currentOrgRole == OrgRole.performanceManager ||
    isOrgAdmin;

/// Maps server `staff_role` strings (snake_case) to [OrgRole] values that
/// don't share their Dart enum name (e.g. `performance_manager` → performanceManager).
/// `massage_specialist` is a legacy alias only — the app no longer has a
/// separate massage role (physiotherapy and massage are the same job at
/// this club), so any account still carrying that server string is treated
/// as [OrgRole.physiotherapist] with no data migration needed.
const Map<String, OrgRole> _orgRoleServerNames = {
  'performance_manager': OrgRole.performanceManager,
  'massage_specialist':  OrgRole.physiotherapist,
  'tactical_coach':      OrgRole.tacticalCoach,
};

/// Parses a string into [OrgRole]. Falls back to [OrgRole.staff] — the
/// narrowest role with no admin/manage permissions — when the server sends
/// no role or an unrecognized one, so a missing/garbled `org_role` can never
/// silently grant admin access. Real owners always get an explicit 'owner'
/// string from the server (see api/includes/club_auth.php resolveClubContext).
OrgRole orgRoleFromString(String? s) {
  if (s == null) return OrgRole.staff;
  if (_orgRoleServerNames.containsKey(s)) return _orgRoleServerNames[s]!;
  return OrgRole.values.firstWhere((r) => r.name == s, orElse: () => OrgRole.staff);
}
