import '../../app_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OrgNavHelper — role-based tab visibility
//
// Routes and labels have moved to OrganizationConfig (organization_config.dart).
// This helper is now only responsible for OrgRole-based show/hide decisions.
//
// Permissions summary:
//   owner / admin / performanceManager / staff → all tabs
//   coach (physical coach) → players, sessions, matches and its physical
//     reports hub (management-only reports remain permission-gated).
//   tacticalCoach → all tabs except settings (sessions/matches/reports are
//     its whole job — see tactical_coach_dashboard.dart).
//   physiotherapist (covers physio & massage) → home dashboard
//     (massage_dashboard.dart) plus players/sessions/matches tabs, so the
//     roster and training schedule are reachable without leaving the shell.
//     Still no reports/settings — clubStaffCan() never granted this role
//     management_report.view.
//   nutritionist → same treatment as physiotherapist: home dashboard
//     (nutritionist_dashboard.dart) plus players/sessions/matches tabs, so
//     the roster is reachable from the shared nav like every other
//     specialist role, not just from its own Home search box. Still no
//     reports/settings — clubStaffCan() never granted nutrition.write
//     holders management_report.view.
//   analyst → Home only. Has its own focused dashboard
//     (analyst_dashboard.dart) that reaches individual players directly —
//     the generic club-wide roster/sessions/matches/reports tabs don't
//     belong to its scope. It is strictly read-only (clubStaffCan():
//     players.read/sessions.read/assessments.read/notes.read/teams.read
//     only, no writes anywhere) so it gets the focused treatment rather
//     than the full write-oriented club nav.
//   player → must NOT reach OrganizationShell; routing in main.dart
//                    sends them to /player/* before the shell is reached.
// ─────────────────────────────────────────────────────────────────────────────

class OrgNavHelper {
  OrgNavHelper._();

  /// Owner/admin navigation is intentionally limited to five primary items;
  /// secondary administration destinations live under "More".
  static bool get useCompactAdminNavigation => isOrgAdmin;

  /// True for the roles whose entire job is covered by their own focused
  /// Home dashboard, with no shared roster/sessions/matches tabs either.
  static bool get _isFocusedSpecialist => isAnalystRole;

  /// True for roles kept off the Reports tab because clubStaffCan() never
  /// granted them management_report.view — physiotherapist and nutritionist
  /// included, even though they get players/sessions/matches.
  static bool get _isReportsExcludedSpecialist =>
      _isFocusedSpecialist ||
      currentOrgRole == OrgRole.physiotherapist ||
      currentOrgRole == OrgRole.nutritionist;

  static bool get _hasClubAccess => currentOrgRole != OrgRole.staff;

  /// Players (roster) tab.
  static bool get showPlayers => _hasClubAccess && !_isFocusedSpecialist;

  /// Sessions tab.
  static bool get showSessions => _hasClubAccess && !_isFocusedSpecialist;

  /// Matches tab — tactical/match content. Physical coach can view and create
  /// matches; tactical coach keeps full edit/delete access.
  static bool get showMatches => _hasClubAccess && !_isFocusedSpecialist;

  /// Reports tab.
  static bool get showReports =>
      _hasClubAccess && !_isReportsExcludedSpecialist && !isDoctorRole;

  /// Settings tab — visible only to owner / admin.
  static bool get showSettings => _hasClubAccess && isOrgAdmin;

  /// Invites tab — visible only to owner / admin.
  static bool get showInvites => _hasClubAccess && isOrgAdmin;

  /// Teams tab.
  static bool get showTeams => _hasClubAccess && canManageTeams;
}
