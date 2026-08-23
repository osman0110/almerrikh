import 'dart:async';

import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';

import '../../api_service.dart';
import '../../services/notification_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../organization/organization_shell.dart';
import '../../models/club_models.dart';
import '../../models/coach_monitoring_models.dart';
import '../../services/club_service.dart';
import '../../services/coach_monitoring_service.dart';
import '../../services/firebase_service.dart';
import '../../storage.dart';
import 'admin_dashboard_page.dart';
import 'club_widgets.dart';
import 'match_detail_page.dart';
import 'notifications_page.dart';
import 'send_alert_page.dart';
import 'standings_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shell
// ─────────────────────────────────────────────────────────────────────────────

class ClubShell extends StatelessWidget {
  const ClubShell({
    super.key,
    required this.child,
    this.currentIndex = 0,
  });

  final Widget child;
  final int currentIndex;

  static void go(BuildContext ctx, String route) =>
      OrganizationShell.go(ctx, route);

  @override
  Widget build(BuildContext context) => OrganizationShell(
        organizationType: OrganizationType.club,
        currentIndex: currentIndex,
        child: child,
      );
}

Future<void> _confirmSidebarLogout(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final confirmed = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) => ClubConfirmDialog(
      title: AppLocalizations.get('logout_title'),
      body: AppLocalizations.get('logout_msg'),
      confirmLabel: AppLocalizations.get('logout_btn'),
    ),
  );
  if (confirmed != true) return;

  if (context.mounted) {
    Navigator.of(context).pop();
  }

  unawaited(NotificationService.unregisterPush());
  unawaited(ApiService.logout());
  unawaited(FirebaseService().signOut());
  try {
    await OnboardingStore().clearSignedIn();
  } catch (e) {
    AppLogger.w(
      'SidebarLogout',
      'Local sign-in state cleanup failed (${e.runtimeType})',
    );
  }

  currentUserName = 'Player';
  currentUserNameArabic = '';
  currentUserNameEnglish = '';
  currentUserAvatarUrl = '';
  currentUserRole = UserRole.club;
  currentOrgRole = OrgRole.staff;
  currentPlayerType = null;
  currentUserId = null;
  currentTeamId = '';
  currentTeamName = '';

  if (navigator.mounted) {
    navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
  }
}

class ClubRoleSidebarShell extends StatelessWidget {
  const ClubRoleSidebarShell({
    super.key,
    required this.child,
  });

  final Widget child;

  String get _accountName => currentUserName.isNotEmpty
      ? currentUserName
      : _currentOrgRoleLabel();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      drawer: _PhysicalCoachSidebar(
        accountName: _accountName,
        roleLabel: _currentOrgRoleLabel(),
      ),
      body: Builder(
        builder: (scaffoldContext) => PhysicalCoachSidebarScope(
          openSidebar: () => Scaffold.of(scaffoldContext).openDrawer(),
          child: child,
        ),
      ),
    );
  }
}

class _PhysicalCoachSidebar extends StatelessWidget {
  const _PhysicalCoachSidebar({
    required this.accountName,
    required this.roleLabel,
    this.extraItems = const [],
  });

  final String accountName;
  final String roleLabel;
  final List<Widget> extraItems;

  String get _clubDisplay => AppLocalizations.get('club_brand_name');

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(
          children: [
            // Header — the profile photo fills the entire card as a
            // background (not a small circular avatar), with a gradient
            // scrim behind the name/subtitle for legibility.
            Container(
              width: double.infinity,
              height: 240,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(color: AppColors.maroonDark),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (currentUserAvatarUrl.isNotEmpty)
                    Image.network(
                      currentUserAvatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.hero, AppColors.maroonDark],
                          ),
                        ),
                      ),
                    )
                  else
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.hero, AppColors.maroonDark],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.person_rounded,
                          size: 96,
                          color: Color(0x40C8A34D),
                        ),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.05),
                          Colors.black.withOpacity(0.65),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 28,
                    right: Directionality.of(context) == TextDirection.rtl
                        ? null
                        : 12,
                    left: Directionality.of(context) == TextDirection.rtl
                        ? 12
                        : null,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Column(
                      children: [
                        Text(
                          accountName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$roleLabel · $_clubDisplay',
                          style: const TextStyle(
                            color: AppColors.onDarkMuted,
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _PhysicalCoachSidebarTile(
                      icon: Icons.person_outline_rounded,
                      label: AppLocalizations.get('profile_label'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).pushNamed('/club/settings');
                      },
                    ),
                    ...extraItems,
                    _PhysicalCoachSidebarTile(
                      icon: Icons.language_rounded,
                      label: AppLocalizations.get('language_label'),
                      onTap: () {
                        Navigator.pop(context);
                        _showLanguageSheet(context);
                      },
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _currentLanguageLabel,
                          style: const TextStyle(
                            color: AppColors.maroon,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                    _PhysicalCoachSidebarTile(
                      icon: Icons.notifications_outlined,
                      label: AppLocalizations.get('notifications'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const NotificationsPage()),
                        );
                      },
                      trailing: Container(
                        width: 34,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.maroon,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsetsDirectional.only(end: 2),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _PhysicalCoachSidebarTile(
                      icon: Icons.emoji_events_outlined,
                      label: AppLocalizations.get('standings_title'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const StandingsPage()),
                        );
                      },
                    ),
                    if (canSendAlerts)
                      _PhysicalCoachSidebarTile(
                        icon: Icons.campaign_outlined,
                        label: AppLocalizations.get('send_alert'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SendAlertPage()),
                          );
                        },
                      ),
                    _PhysicalCoachSidebarTile(
                      icon: Icons.help_outline_rounded,
                      label: AppLocalizations.get('support_help'),
                      onTap: () {
                        Navigator.pop(context);
                        _showSupportSheet(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _confirmSidebarLogout(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF1EEEC), width: 0.8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, color: Color(0xFF9299A5), size: 18),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.get('logout_btn'),
                      style: const TextStyle(
                        color: Color(0xFF9299A5),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupportSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.get('support_help'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              const _SupportContactRow(
                icon: Icons.email_outlined,
                value: 'support@almerrikh-sc.com',
              ),
              const SizedBox(height: 8),
              const _SupportContactRow(
                icon: Icons.phone_outlined,
                value: '+249 900 000 000',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _currentLanguageLabel {
    switch (getAppLanguage()) {
      case 'ar':
        return 'العربية';
      case 'fr':
        return 'Français';
      default:
        return 'English';
    }
  }

  void _showLanguageSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const _PhysicalCoachLanguageSheet(),
    );
  }
}

String _currentOrgRoleLabel() {
  switch (currentOrgRole) {
    case OrgRole.owner:
      return AppLocalizations.get('role_owner');
    case OrgRole.admin:
      return AppLocalizations.get('role_admin');
    case OrgRole.coach:
      return AppLocalizations.get('role_coach');
    case OrgRole.doctor:
      return AppLocalizations.get('role_doctor');
    case OrgRole.physiotherapist:
      return AppLocalizations.get('role_physiotherapist');
    case OrgRole.nutritionist:
      return AppLocalizations.get('role_nutritionist');
    case OrgRole.tacticalCoach:
      return AppLocalizations.get('role_tactical_coach');
    case OrgRole.analyst:
      return AppLocalizations.get('role_analyst');
    case OrgRole.performanceManager:
      return AppLocalizations.get('role_performance_manager');
    case OrgRole.staff:
      return AppLocalizations.get('role_staff');
  }
}

class _PhysicalCoachSidebarTile extends StatelessWidget {
  const _PhysicalCoachSidebarTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.foreground, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _SupportContactRow extends StatelessWidget {
  const _SupportContactRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.maroon, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhysicalCoachLanguageSheet extends StatelessWidget {
  const _PhysicalCoachLanguageSheet();

  static const _languages = [
    ('العربية', 'ar'),
    ('English', 'en'),
    ('Français', 'fr'),
  ];

  Future<void> _select(BuildContext context, String code) async {
    setAppLanguage(code);
    await OnboardingStore().setLanguage(code);
    unawaited(ApiService.updateAccountLanguage(code));
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.get('choose_language_title'),
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 14),
            for (final language in _languages)
              GestureDetector(
                onTap: () => _select(context, language.$2),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.maroon.withOpacity(
                      getAppLanguage() == language.$2 ? 0.12 : 0.05,
                    ),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: AppColors.maroon.withOpacity(
                        getAppLanguage() == language.$2 ? 0.42 : 0.18,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        language.$1,
                        style: TextStyle(
                          color: getAppLanguage() == language.$2
                              ? AppColors.maroon
                              : AppColors.foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (getAppLanguage() == language.$2)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.maroon,
                          size: 19,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Club Dashboard Page
// ─────────────────────────────────────────────────────────────────────────────

class ClubDashboardPage extends StatefulWidget {
  const ClubDashboardPage({super.key});

  @override
  State<ClubDashboardPage> createState() => _ClubDashboardPageState();
}

class _ClubDashboardPageState extends State<ClubDashboardPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<ClubPlayer> _allPlayers = [];
  // ignore: unused_field
  String _clubName = '';
  bool _loading = false;
  bool _loadError = false;

  List<TrainingSession> _allSessions = [];
  List<MatchModel> _allMatches = [];
  List<ClubTeam> _teams = [];
  List<ClubSeason> _seasons = [];
  DateTime _selectedDate = DateTime.now();

  ClubSeason? get _activeSeason =>
      _seasons.where((s) => s.isActive).firstOrNull;

  /// Matches that fall inside the active season's date range — used for the
  /// small season/competition summary in the header. Purely derived from
  /// already-loaded data, no extra permission-gated calls.
  List<MatchModel> get _seasonMatches {
    final season = _activeSeason;
    if (season == null) return const [];
    return _allMatches.where((m) =>
        !m.matchDate.isBefore(season.startsOn) &&
        !m.matchDate.isAfter(season.endsOn)).toList();
  }

  int get _seasonCompetitionCount => _seasonMatches
      .map((m) => m.competitionId)
      .whereType<int>()
      .toSet()
      .length;

  // Memoized derived stats — computed once in setState, never in build().
  int _readyCount     = 0;
  int _riskCount      = 0;
  int _fatigueCount   = 0;
  int _injuredCount    = 0;
  int _recoveringCount = 0;
  int _notTrainingCount = 0;
  int _totalMinutes    = 0;
  int _totalYellow     = 0;
  int _totalRed        = 0;
  TrainingSession? _todaySession;

  MatchModel? _todayMatch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = false; });
    try {
      if (isOrgAdmin) {
        final results = await Future.wait([
          ClubService().getTeams(),
          ApiService.getMe(),
        ]);
        if (!mounted) return;
        final teams = results[0] as List<ClubTeam>;
        final me = results[1] as Map<String, dynamic>;
        if (teams.isNotEmpty && currentTeamId.isEmpty) {
          currentTeamId = teams.first.id;
          currentTeamName = teams.first.name;
        }
        setState(() {
          _teams = teams;
          _clubName =
              me['club_name'] as String? ?? me['name'] as String? ?? '';
          _loading = false;
        });
        return;
      }

      final results = await Future.wait([
        ClubService().getSessions(),
        ClubService().getPlayers(),
        CoachMonitoringService.getDashboard(),
        ClubService().getTeams(),
        ApiService.getMe(),
        ClubService().getMatches(),
        ClubService().getSeasons(),
        ClubService().getManagementReport(),
      ]);
      if (!mounted) return;
      final me       = results[4] as Map<String, dynamic>;
      final teams    = results[3] as List<ClubTeam>;
      final allP     = results[1] as List<ClubPlayer>;
      final wellness = results[2] as CoachDashboardData;
      final sessions = results[0] as List<TrainingSession>;
      final matches  = results[5] as List<MatchModel>;
      final seasons      = results[6] as List<ClubSeason>;
      final mgmtReport   = results[7] as List<PlayerManagementReportRow>;

      if (teams.isNotEmpty && currentTeamId.isEmpty) {
        currentTeamId   = teams.first.id;
        currentTeamName = teams.first.name;
      }
      // Compute derived stats once so build() never iterates lists.
      final wPlayers   = wellness.players;

      final activeNames = allP
          .where((p) => p.status == PlayerStatus.active)
          .map((p) => p.fullName.toLowerCase().trim())
          .toSet();
      final activeWellnessPlayers = wPlayers
          .where((w) => activeNames.contains(w.name.toLowerCase().trim()))
          .toList();

      setState(() {
        _allPlayers     = allP;
        _clubName       = me['club_name'] as String? ?? me['name'] as String? ?? '';
        _teams          = teams;
        _allSessions    = sessions;
        _allMatches     = matches;
        _seasons        = seasons;

        _readyCount = activeWellnessPlayers
            .where((p) => p.status == 'normal')
            .length;
        _riskCount = activeWellnessPlayers
            .where((p) => p.status == 'high_risk')
            .length;
        _fatigueCount = activeWellnessPlayers
            .where((p) => p.status == 'moderate')
            .length;
        _todaySession   = _sessionForDate(_selectedDate);
        _todayMatch     = _matchForDate(_selectedDate);

        _injuredCount    = allP.where((p) => p.status == PlayerStatus.injured).length;
        _recoveringCount = allP.where((p) => p.status == PlayerStatus.recovering).length;
        final todayTraining = _sessionForDate(DateTime.now());
        _notTrainingCount = todayTraining != null
            ? (todayTraining.playerIds.length - todayTraining.completedPlayerIds.length)
                .clamp(0, todayTraining.playerIds.length)
            : 0;
        _totalMinutes = mgmtReport.fold(0, (sum, r) => sum + r.minutes);
        _totalYellow  = mgmtReport.fold(0, (sum, r) => sum + r.yellowCards);
        _totalRed     = mgmtReport.fold(0, (sum, r) => sum + r.redCards);
      });
    } catch (e) {
      AppLogger.e('ClubDashboard', 'Load failed', e);
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  TrainingSession? _sessionForDate(DateTime d) {
    if (_allSessions.isEmpty) return null;
    for (final s in _allSessions) {
      if (s.date.year == d.year && s.date.month == d.month && s.date.day == d.day) {
        return s;
      }
    }
    return null;
  }

  MatchModel? _matchForDate(DateTime d) {
    if (_allMatches.isEmpty) return null;
    for (final m in _allMatches) {
      if (m.matchDate.year == d.year && m.matchDate.month == d.month && m.matchDate.day == d.day) {
        return m;
      }
    }
    return null;
  }

  void _changeDate(DateTime d) {
    setState(() {
      _selectedDate = d;
      _todaySession = _sessionForDate(d);
      _todayMatch   = _matchForDate(d);
    });
  }

  /// Sessions + matches from today forward, merged and sorted by date, for
  /// the "upcoming" strip — a coach should see both without hunting in two
  /// separate places.
  List<_ScheduleItem> get _upcomingEvents {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = <_ScheduleItem>[
      for (final s in _allSessions)
        if (!DateTime(s.date.year, s.date.month, s.date.day).isBefore(today))
          _ScheduleItem.session(s),
      for (final m in _allMatches)
        if (!DateTime(m.matchDate.year, m.matchDate.month, m.matchDate.day).isBefore(today))
          _ScheduleItem.match(m),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return items.take(7).toList();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ClubShell(
      currentIndex: 0,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        drawer: _buildSidebar(),
        body: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.card,
          strokeWidth: 2,
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildDateBar()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_loadError && _allPlayers.isEmpty)
                      _buildErrorState()
                    else ...[
                      if (_loadError) ...[
                        _buildOfflineBanner(),
                        const SizedBox(height: 14),
                      ],
                      if (isOrgAdmin)
                        AdminDashboardSection(
                          selectedDate: _selectedDate,
                          notTrainingCount: _isToday
                              ? _notTrainingCount
                              : null,
                        )
                      else ...[
                        _buildTodayEventHero(),
                        if (_upcomingEvents.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _buildUpcomingStrip(),
                        ],
                        const SizedBox(height: 14),
                        _buildTeamSummaryGrid(),
                      ],
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final accountName = currentUserName.isNotEmpty
        ? currentUserName
        : AppLocalizations.get('club_label');
    final roleKey = currentOrgRole == OrgRole.owner
        ? 'role_owner'
        : isOrgAdmin
            ? 'role_admin'
            : 'role_staff';

    return RoleBrandHeader(
      roleLabel: AppLocalizations.get(roleKey),
      accountName: accountName,
      onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed('/club/search'),
            child: const SizedBox(
              width: 28,
              height: 28,
              child: Icon(
                Icons.search_rounded,
                color: AppColors.muted,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const NotificationBellButton(),
        ],
      ),
    );
  }

  // ── Side menu — profile, switch team, settings, logout ──────────────────

  Widget _buildSidebar() {
    final accountName = currentUserName.isNotEmpty
        ? currentUserName
        : AppLocalizations.get('club_label');

    return _PhysicalCoachSidebar(
      accountName: accountName,
      roleLabel: _currentOrgRoleLabel(),
      extraItems: [
        if (_teams.length > 1)
          _PhysicalCoachSidebarTile(
            icon: Icons.swap_horiz_rounded,
            label: AppLocalizations.get('switch_team'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context)
                  .pushNamed('/club/teams')
                  .then((_) => _load());
            },
          ),
        _PhysicalCoachSidebarTile(
          icon: Icons.settings_outlined,
          label: AppLocalizations.get('settings'),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).pushNamed('/club/settings');
          },
        ),
      ],
    );
  }

  // ── DATE BAR ─────────────────────────────────────────────────────────────

  Widget _buildDateBar() {
    return RoleHomeDateStrip(
      selectedDate: _selectedDate,
      onDateChanged: _changeDate,
      onCalendarTap: _pickDate,
      markerOf: (date) => RoleDateMarker(
        hasMatch: _allMatches.any(
          (match) => match.matchDate.year == date.year &&
              match.matchDate.month == date.month &&
              match.matchDate.day == date.day,
        ),
        hasSession: _allSessions.any(
          (session) => session.date.year == date.year &&
              session.date.month == date.month &&
              session.date.day == date.day,
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) _changeDate(picked);
  }

  // ── A: TODAY'S EVENT (session or match) ──────────────────────────────────

  Widget _buildTodayEventHero() {
    if (_loading) {
      return _shimmer(height: 170);
    }
    final s = _todaySession;
    final m = _todayMatch;
    if (s == null && m != null) {
      return _buildMatchHero(m);
    }
    if (s == null) {
      return _buildEmptySession();
    }

    final location = (s.location != null && s.location!.isNotEmpty)
        ? s.location!
        : AppLocalizations.get('location_not_set');
    final endTime = (s.endTime != null && s.endTime!.isNotEmpty) ? s.endTime! : null;
    final timeRange = endTime != null ? '${s.startTime} – $endTime' : s.startTime;
    final expected = s.playerIds.length;
    final present  = s.completedPlayerIds.length;

    String statusKey;
    switch (s.status) {
      case 'active':    statusKey = 'status_active';    break;
      case 'completed': statusKey = 'status_completed'; break;
      case 'cancelled': statusKey = 'status_cancelled'; break;
      default:          statusKey = 'status_scheduled';
    }

    String actionKey;
    switch (s.status) {
      case 'active':    actionKey = 'open_session_btn';  break;
      case 'completed': actionKey = 'view_report_btn';   break;
      case 'cancelled': actionKey = 'view_details_btn';  break;
      default:          actionKey = 'start_session_btn';
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.maroon,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: title + status badge
          Row(
            children: [
              Text(AppLocalizations.get('today_session'),
                  style: const TextStyle(
                      color: AppColors.onDarkMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Text(AppLocalizations.get(statusKey),
                    style: const TextStyle(
                        color: AppColors.onDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(s.name,
              style: const TextStyle(
                  color: AppColors.onDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  height: 1.2),
              maxLines: 2),
          const SizedBox(height: 8),
          Row(
            children: [
              _HeroMeta(icon: Icons.schedule_rounded, label: timeRange),
              const SizedBox(width: 12),
              Expanded(child: _HeroMeta(icon: Icons.location_on_rounded, label: location, clip: true)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _HeroMeta(icon: Icons.group_rounded,
                  label: '${AppLocalizations.get('expected_players')}: $expected'),
              const SizedBox(width: 12),
              _HeroMeta(icon: Icons.check_circle_outline_rounded,
                  label: '${AppLocalizations.get('present_players')}: $present'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _HeroMeta(icon: Icons.person_outline_rounded,
                    label: s.coachName.isNotEmpty ? s.coachName : AppLocalizations.get('coach_label'),
                    clip: true),
              ),
              const SizedBox(width: 12),
              _HeroMeta(icon: Icons.fitness_center_rounded, label: s.type.label),
            ],
          ),
          const SizedBox(height: 10),
          // CTA button
          GestureDetector(
            onTap: () => _onSessionAction(s),
            child: Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.get(actionKey),
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(width: 6),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.arrow_back_rounded
                        : Icons.arrow_forward_rounded,
                    color: AppColors.foreground,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSessionAction(TrainingSession s) async {
    if (s.status == 'scheduled') {
      s.status = 'active';
      final ok = await ClubService().updateSession(s);
      if (ok) _load();
    }
    if (!mounted) return;
    Navigator.of(context).pushNamed('/club/sessions/${s.id}');
  }

  // Same hero shape as the session card above, but for a match on the
  // selected date — keeps sessions and matches visually consistent instead
  // of matches being invisible on the dashboard entirely.
  Widget _buildMatchHero(MatchModel m) {
    final timeRange = m.matchTime;
    final location = (m.location != null && m.location!.isNotEmpty)
        ? m.location!
        : AppLocalizations.get('location_not_set');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.maroon,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(AppLocalizations.get('today_match_label'),
                  style: const TextStyle(
                      color: AppColors.onDarkMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Text(m.statusLabel,
                    style: const TextStyle(
                        color: AppColors.onDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${AppLocalizations.get('vs_label')} ${m.opponent}',
              style: const TextStyle(
                  color: AppColors.onDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  height: 1.2),
              maxLines: 2),
          const SizedBox(height: 8),
          Row(
            children: [
              _HeroMeta(icon: Icons.schedule_rounded, label: timeRange),
              const SizedBox(width: 12),
              Expanded(child: _HeroMeta(icon: Icons.location_on_rounded, label: location, clip: true)),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MatchDetailPage(matchId: m.id))),
            child: Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.get('view_details_btn'),
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(width: 6),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.arrow_back_rounded
                        : Icons.arrow_forward_rounded,
                    color: AppColors.foreground,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingStrip() {
    final items = _upcomingEvents;
    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final isSelected = item.date.year == _selectedDate.year &&
              item.date.month == _selectedDate.month &&
              item.date.day == _selectedDate.day;
          return GestureDetector(
            onTap: () => _changeDate(item.date),
            child: Container(
              width: 92,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary.withOpacity(0.14) : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 1.4 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(item.isMatch ? Icons.sports_soccer_rounded : Icons.fitness_center_rounded,
                        color: item.isMatch ? AppColors.maroon : AppColors.primary, size: 13),
                    const SizedBox(width: 4),
                    Text('${item.date.day}/${item.date.month}',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.foreground, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptySession() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withOpacity(0.30)),
            ),
            child: const Icon(Icons.calendar_today_rounded,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: 12),
          Text(AppLocalizations.get('no_session_today_title'),
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          const SizedBox(height: 5),
          Text(AppLocalizations.get('tap_create_session'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).pushNamed('/club/sessions/new');
              _load();
            },
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.30),
                    blurRadius: 10, offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(AppLocalizations.get('dash_create_btn'),
                  style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Team summary grid — ready / follow-up / injured / returning / not
  // training today / total minutes / cards, all derived from data already
  // loaded (players list + management report), no new endpoints needed.
  // Anchored under the active competition (season) so the numbers read as
  // "team summary for the currently running competition".

  Widget _buildTeamSummaryGrid() {
    if (_loading) return _shimmer(height: 130);
    if (_allPlayers.isEmpty) return const SizedBox.shrink();

    final cardsValue = '$_totalYellow / $_totalRed';
    final season = _activeSeason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          icon: Icons.emoji_events_rounded,
          title: season != null
              ? '${AppLocalizations.get('team_summary_title')} · ${season.name}'
              : AppLocalizations.get('team_summary_title'),
          color: AppColors.primary,
        ),
        if (season != null) ...[
          const SizedBox(height: 4),
          Text(
            AppLocalizations.format('dashboard_season_summary', {
              'season': season.name,
              'matches': '${_seasonMatches.length}',
              'competitions': '$_seasonCompetitionCount',
            }),
            style: const TextStyle(
                color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(children: [
                Expanded(child: _summaryStat('$_readyCount', AppLocalizations.get('status_ready'), AppColors.success)),
                Expanded(child: _summaryStat('${_riskCount + _fatigueCount}', AppLocalizations.get('status_needs_followup'), AppColors.warning)),
                Expanded(child: _summaryStat('$_injuredCount', AppLocalizations.get('status_injured'), AppColors.destructive)),
                Expanded(child: _summaryStat('$_recoveringCount', AppLocalizations.get('status_recovering'), AppColors.primary)),
              ]),
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _summaryStat('$_notTrainingCount', AppLocalizations.get('status_not_training'), AppColors.textSoft)),
                Expanded(child: _summaryStat('$_totalMinutes', AppLocalizations.get('total_minutes_label'), AppColors.foreground)),
                Expanded(child: _summaryStat(cardsValue, AppLocalizations.get('total_cards_label'), AppColors.warning)),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }


  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildErrorState() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.destructive.withOpacity(0.30)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
              color: AppColors.destructive.withOpacity(0.10),
              shape: BoxShape.circle),
          child: const Icon(Icons.wifi_off_rounded,
              color: AppColors.destructive, size: 26),
        ),
        const SizedBox(height: 14),
        Text(AppLocalizations.get('error_server_connect'),
            style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 15)),
        const SizedBox(height: 6),
        Text(AppLocalizations.get('error_check_internet'),
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: _load,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.30),
                    blurRadius: 12, offset: const Offset(0, 4))
              ],
            ),
            child: Text(AppLocalizations.get('try_again'),
                style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ),
        ),
      ]),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: AppColors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.get('error_network'),
              style:
                  const TextStyle(color: AppColors.textSoft, fontSize: 11.5),
            ),
          ),
          GestureDetector(
            onTap: _load,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Text(
                AppLocalizations.get('retry_btn'),
                style: const TextStyle(
                    color: AppColors.maroon,
                    fontWeight: FontWeight.w800,
                    fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shimmer placeholder ───────────────────────────────────────────────────

  Widget _shimmer({required double height}) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FractionallySizedBox(
            widthFactor: 0.42,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const Spacer(),
          FractionallySizedBox(
            widthFactor: 0.88,
            child: Container(
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          const SizedBox(height: 5),
          FractionallySizedBox(
            widthFactor: 0.64,
            child: Container(
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label row
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.title,
    this.color = AppColors.maroon,
  });
  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 14),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title,
            style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 14)),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Tile
// ─────────────────────────────────────────────────────────────────────────────

/// A session or match, unified for the "upcoming" strip so both show up on
/// the dashboard by date instead of matches being invisible there entirely.
class _ScheduleItem {
  const _ScheduleItem._(this.date, this.title, this.isMatch);

  factory _ScheduleItem.session(TrainingSession s) =>
      _ScheduleItem._(s.date, s.name, false);

  factory _ScheduleItem.match(MatchModel m) =>
      _ScheduleItem._(m.matchDate, m.opponent, true);

  final DateTime date;
  final String title;
  final bool isMatch;
}


// ─────────────────────────────────────────────────────────────────────────────
// Hero card meta chip
// ─────────────────────────────────────────────────────────────────────────────

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.icon, required this.label, this.clip = false});
  final IconData icon;
  final String label;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.onDarkMuted, size: 11),
        const SizedBox(width: 4),
        clip
            ? Flexible(
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.onDarkMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500),
                    maxLines: 2))
            : Text(label,
                style: const TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500)),
      ],
    );
    return clip ? Expanded(child: content) : content;
  }
}
