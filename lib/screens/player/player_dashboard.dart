import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_colors.dart';
import '../../app_constants.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../utils/crash_reporter.dart';
import '../../utils/metric_formatter.dart';
import '../../models/assessment_result_model.dart';
import '../../models/monitoring_models.dart';
import '../../models/session_models.dart';
import '../../models/club_models.dart'
    show TrainingSession, MatchModel, ClubPlayer;
import '../../api_service.dart';
import '../../services/assessment_storage_service.dart';
import '../../services/player_monitoring_service.dart'
    show PlayerMonitoringService;
import '../../services/survey_reminder_service.dart';
import '../../storage.dart';
import '../../shared/club_status_color.dart';
import '../club/club_widgets.dart'
    show
        ClubConfirmDialog,
        PhysicalCoachSidebarScope,
        RoleBrandHeader,
        RoleDateMarker,
        RoleHomeDateStrip;
import '../club/notifications_page.dart';
import '../club/standings_page.dart';
import 'independent_ai_plan_screen.dart';
import 'join_club_screen.dart';
import 'player_history_screen.dart';
import 'player_progress_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shell
// ─────────────────────────────────────────────────────────────────────────────

class PlayerShell extends StatelessWidget {
  const PlayerShell({super.key, required this.child, this.currentIndex = 0});

  final Widget child;
  final int currentIndex;

  static void go(BuildContext ctx, String route) =>
      Navigator.of(ctx).pushNamedAndRemoveUntil(route, (_) => false);

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme:
              GoogleFonts.alexandriaTextTheme(Theme.of(context).textTheme),
        ),
        child: Scaffold(
          backgroundColor: AppColors.background,
          drawer: const _PlayerSidebar(),
          body: Builder(
            builder: (scaffoldContext) => SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
                  child: Column(
                    children: [
                      Container(height: 2, color: AppColors.gold),
                      Expanded(
                        child: PhysicalCoachSidebarScope(
                          openSidebar: () =>
                              Scaffold.of(scaffoldContext).openDrawer(),
                          child: child,
                        ),
                      ),
                      _PlayerBottomNav(currentIndex: currentIndex),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerBottomNav extends StatelessWidget {
  const _PlayerBottomNav({required this.currentIndex});
  final int currentIndex;

  List<_Tab> _tabs() {
    final isIndependent =
        currentPlayerType == PlayerType.independent ||
        currentPlayerType == null;
    return [
      _Tab(
        '/player',
        Icons.home_rounded,
        AppLocalizations.get('nav_dashboard'),
      ),
      if (!isIndependent) ...[
        _Tab(
          '/player/sessions',
          Icons.event_note_rounded,
          AppLocalizations.get('profile_my_sessions'),
        ),
        _Tab(
          '/player/matches',
          Icons.sports_soccer_rounded,
          AppLocalizations.get('profile_my_matches'),
        ),
      ],
      _Tab(
        '/player/health',
        Icons.medication_rounded,
        AppLocalizations.get('wellness_label'),
      ),
      _Tab(
        '/player/profile',
        Icons.person_rounded,
        AppLocalizations.get('nav_my_profile'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final bottom = MediaQuery.of(context).padding.bottom;
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, math.max(14, bottom)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.card.withOpacity(0.94),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.foreground.withOpacity(0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(tabs.length, (i) {
                  final tab = tabs[i];
                  final active = i == currentIndex;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!active) PlayerShell.go(context, tab.route);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 2.5,
                            width: active ? 16 : 0,
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: AppColors.maroon,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? AppColors.maroon.withOpacity(0.12)
                                  : Colors.transparent,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              tab.icon,
                              size: 22,
                              color: active
                                  ? AppColors.maroon
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerSidebar extends StatelessWidget {
  const _PlayerSidebar();

  String get _accountName =>
      currentUserName.isNotEmpty ? currentUserName : AppLocalizations.get('role_player');

  Future<void> _confirmLogout(BuildContext context) async {
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
    if (context.mounted) Navigator.of(context).pop();

    await OnboardingStore().clearSignedIn();
    CrashReporter.clearContext();
    currentUserNameArabic = '';
    currentUserNameEnglish = '';

    if (navigator.mounted) {
      navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
    }
  }

  void _showLangSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PlayerLangSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 190,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(color: AppColors.maroonDark),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (currentUserAvatarUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: currentUserAvatarUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget: (_, __, ___) => const DecoratedBox(
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
                          size: 76,
                          color: Color(0x40C8A34D),
                        ),
                      ),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 20,
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
                    bottom: 16,
                    child: Column(
                      children: [
                        Text(
                          _accountName,
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
                          '${AppLocalizations.get('role_player')} · ${AppLocalizations.get('club_brand_name')}',
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
                    _PlayerSidebarTile(
                      icon: Icons.person_outline_rounded,
                      label: AppLocalizations.get('nav_my_profile'),
                      onTap: () {
                        Navigator.pop(context);
                        PlayerShell.go(context, '/player/profile');
                      },
                    ),
                    _PlayerSidebarTile(
                      icon: Icons.history_rounded,
                      label: AppLocalizations.get('assessment_history_title'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PlayerHistoryScreen(),
                          ),
                        );
                      },
                    ),
                    _PlayerSidebarTile(
                      icon: Icons.emoji_events_outlined,
                      label: AppLocalizations.get('standings_title'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const StandingsPage()),
                        );
                      },
                    ),
                    _PlayerSidebarTile(
                      icon: Icons.notifications_outlined,
                      label: AppLocalizations.get('notifications'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const NotificationsPage()),
                        );
                      },
                    ),
                    _PlayerSidebarTile(
                      icon: Icons.language_rounded,
                      label: AppLocalizations.get('profile_language'),
                      onTap: () {
                        Navigator.pop(context);
                        _showLangSheet(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _confirmLogout(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, color: Colors.red, size: 18),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.get('logout_btn'),
                      style: const TextStyle(
                        color: Colors.red,
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
}

class _PlayerSidebarTile extends StatelessWidget {
  const _PlayerSidebarTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Row(
            children: [
              Icon(icon, color: AppColors.foreground, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab {
  _Tab(this.route, this.icon, this.label);
  final String route;
  final IconData icon;
  final String label;
}

class _PendingCheck {
  const _PendingCheck({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final void Function(BuildContext context) onTap;
}

// ─────────────────────────────────────────────────────────────────────────────
// Player Dashboard Page
// ─────────────────────────────────────────────────────────────────────────────

class PlayerDashboardPage extends StatefulWidget {
  const PlayerDashboardPage({super.key});

  @override
  State<PlayerDashboardPage> createState() => _PlayerDashboardPageState();
}

class _PlayerDashboardPageState extends State<PlayerDashboardPage> {
  AssessmentResult? _latestAssessment;
  HooperEntry? _latestHooper;
  MonitoringDashboard? _dashboard;
  PlayerSessionData? _todaySession;
  List<TrainingSession> _clubSessions = [];
  List<MatchModel> _clubMatches = [];
  ClubPlayer? _player;
  Map<String, dynamic>? _discipline;
  List<Map<String, dynamic>> _disciplineByCompetition = [];
  Map<String, dynamic>? _nutritionProfile;
  List<Map<String, dynamic>> _coachNotes = [];
  bool _loading = true;
  bool _profileMissing = false;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted)
      setState(() {
        _loading = true;
        _profileMissing = false;
        _loadError = false;
      });
    try {
      final linkedPlayerId = await OnboardingStore().getLinkedPlayerId();

      // SECURITY: never fetch assessments without a valid linked_player_id
      if (linkedPlayerId == null || linkedPlayerId.isEmpty) {
        // Try to recover by re-fetching profile from server
        await _refreshProfileFromServer();
        return;
      }

      final results = await Future.wait([
        AssessmentStorageService.instance
            .getLatestAssessment(linkedPlayerId)
            .catchError((_) => null),
        PlayerMonitoringService.getDashboard().catchError((_) => null),
        ApiService.getTodaySession().catchError((_) => null),
        ApiService.getMyClubSessions().catchError((_) => <TrainingSession>[]),
        ApiService.getMyMatches().catchError((_) => <MatchModel>[]),
        ApiService.getMyPlayerProfile().catchError((_) => <String, dynamic>{}),
        ApiService.getMyNutritionProfile().catchError((_) => null),
        ApiService.getMyCoachNotes().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      final clubSessions = results[3] as List<TrainingSession>;
      final clubMatches = results[4] as List<MatchModel>;
      setState(() {
        _latestAssessment = results[0] as AssessmentResult?;
        final dash = results[1] as MonitoringDashboard?;
        _dashboard = dash;
        _latestHooper = dash?.todayHooper;
        _todaySession = results[2] as PlayerSessionData?;
        _clubSessions = clubSessions;
        _clubMatches = clubMatches;
        final profile = results[5] as Map<String, dynamic>;
        final playerJson = profile['player'] as Map<String, dynamic>?;
        final player = playerJson != null ? ClubPlayer.fromJson(playerJson) : null;
        _player = player;
        currentUserNameArabic = player?.nameArabic ?? '';
        currentUserNameEnglish = player?.nameEnglish ?? '';
        _discipline = profile['discipline'] is Map
            ? Map<String, dynamic>.from(profile['discipline'] as Map)
            : null;
        _disciplineByCompetition = profile['discipline_by_competition'] is List
            ? (profile['discipline_by_competition'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : [];
        _loadError = profile.isEmpty;
        _nutritionProfile = results[6] as Map<String, dynamic>?;
        _coachNotes = results[7] as List<Map<String, dynamic>>;
        _loading = false;
      });
      SurveyReminderService.sync(
        sessions: clubSessions,
        matches: clubMatches,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  Future<void> _refreshProfileFromServer() async {
    try {
      final profile = await ApiService.getMyPlayerProfile();
      final linkedId = profile['player'] != null
          ? (profile['player'] as Map<String, dynamic>)['id'] as String?
          : null;
      if (linkedId != null && linkedId.isNotEmpty) {
        await OnboardingStore().setLinkedPlayerId(linkedId);
        _loadData(); // retry with recovered id
        return;
      }
    } catch (_) {}
    if (mounted)
      setState(() {
        _loading = false;
        _profileMissing = true;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_profileMissing) {
      return PlayerShell(
        currentIndex: 0,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.link_off_rounded, color: AppColors.muted, size: 48),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.get('profile_link_missing'),
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.get('login_again_hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/auth', (_) => false),
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: Text(AppLocalizations.get('login_again_btn')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PlayerShell(
      currentIndex: 0,
      child: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        backgroundColor: AppColors.card,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(
              child: RoleHomeDateStrip(
                markerOf: (date) => RoleDateMarker(
                  hasMatch: _clubMatches.any(
                    (match) => _sameDay(match.matchDate, date),
                  ),
                  hasSession: _clubSessions.any(
                    (session) => _sameDay(session.date, date),
                  ),
                ),
              ),
            ),
            if (_loadError)
              SliverToBoxAdapter(child: _buildLoadErrorBanner()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _buildHeroCard(),
              ),
            ),
            SliverToBoxAdapter(child: _buildPendingChecksBanner()),
            SliverToBoxAdapter(child: _buildQuickSummaryCard()),
            SliverToBoxAdapter(child: _buildTodaySessionCard()),
            SliverToBoxAdapter(child: _buildDisciplineCard()),
            SliverToBoxAdapter(child: _buildTrainingList(context)),
            SliverToBoxAdapter(child: _buildQuickActions(context)),
            SliverToBoxAdapter(child: _buildNutritionCard()),
            SliverToBoxAdapter(child: _buildCoachNotesCard()),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.destructive.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.destructive.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.destructive,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.get('error_connection'),
              style: const TextStyle(
                color: AppColors.destructive,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadData,
            child: Text(AppLocalizations.get('retry_btn')),
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  // ── Hero Card — player photo as the full card background, stats overlaid
  // on top of it with a dark scrim for legibility (jersey/position/
  // nationality/status on one row, age/height/weight/foot on the next).
  Widget _buildHeroCard() {
    final p = _player;
    final name = (p != null && p.fullName.isNotEmpty)
        ? p.fullName
        : currentUserName;
    final statusColor = p != null ? clubStatusColor(p.status) : AppColors.muted;
    final statusLabel = p != null
        ? AppLocalizations.get('roster_status_${p.status.name}')
        : AppLocalizations.get('status_missing_readiness');
    final initials = (p != null && p.fullName.isNotEmpty)
        ? p.initials
        : (currentUserName.isNotEmpty ? currentUserName[0].toUpperCase() : 'P');
    final hasPhoto = p?.profileImageUrl?.isNotEmpty ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 380,
        decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            hasPhoto
                ? CachedNetworkImage(
                    imageUrl: p!.profileImageUrl!,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: (_, __, ___) => _heroBgPlaceholder(initials),
                  )
                : _heroBgPlaceholder(initials),
            // Scrim — subtle at top, dark at bottom where the stats sit.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54, Colors.black87],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (p != null &&
                          p.teamName != null &&
                          p.teamName!.isNotEmpty)
                        _heroPill(p.teamName!),
                      const Spacer(),
                      if (p != null && p.number.isNotEmpty)
                        _heroJerseyBadge(p.number),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                          border: Border.all(
                            color: AppColors.onDark,
                            width: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.onDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusLabel,
                    style: const TextStyle(
                      color: AppColors.onDarkMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _onPhotoStat(
                          icon: Icons.numbers_rounded,
                          label: AppLocalizations.get('jersey_number'),
                          value: p != null && p.number.isNotEmpty
                              ? '#${p.number}'
                              : '—',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _onPhotoStat(
                          icon: Icons.sports_soccer_rounded,
                          label: AppLocalizations.get('position_label'),
                          value: p != null && p.position.isNotEmpty
                              ? p.position
                              : '—',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _onPhotoStat(
                          icon: Icons.cake_rounded,
                          label: AppLocalizations.get('bio_age'),
                          value: (p != null && p.age > 0) ? '${p.age}' : '—',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _onPhotoStat(
                          icon: Icons.height_rounded,
                          label: AppLocalizations.get('bio_height'),
                          value: MetricFormatter.height(p?.height),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _onPhotoStat(
                          icon: Icons.monitor_weight_rounded,
                          label: AppLocalizations.get('bio_weight'),
                          value: MetricFormatter.weight(p?.weight),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _onPhotoStat(
                          icon: Icons.directions_run_rounded,
                          label: AppLocalizations.get('bio_foot'),
                          value: p != null && p.dominantFoot.isNotEmpty
                              ? p.dominantFoot[0].toUpperCase() +
                                    p.dominantFoot.substring(1)
                              : '—',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Maroon backdrop with giant initials — used when the player has no
  /// profile photo, or the photo URL fails to load.
  Widget _heroBgPlaceholder(String initials) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.maroonDark, AppColors.hero],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.onDark.withOpacity(0.18),
          fontWeight: FontWeight.w900,
          fontSize: 140,
          height: 1,
        ),
      ),
    );
  }

  Widget _heroPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.onDark,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _heroJerseyBadge(String number) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '#$number',
        style: const TextStyle(
          color: AppColors.maroonDark,
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }

  /// Stat chip designed to sit on top of the background photo — translucent
  /// dark backing + white text so it stays legible over any photo.
  Widget _onPhotoStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: AppColors.primary),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.onDark,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Participation Decision — today's readiness decision, shown right with
  // the stats card on Home instead of buried as a Health Hub sub-page.
  Widget _buildDisciplineCard() {
    if (currentPlayerType == PlayerType.independent || currentPlayerType == null) {
      return const SizedBox.shrink();
    }
    // One row per active competition when available; falls back to the
    // club-wide total when no competitions are configured yet.
    final rows = _disciplineByCompetition.isNotEmpty
        ? _disciplineByCompetition
        : (_discipline != null ? [_discipline!] : <Map<String, dynamic>>[]);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: rows.map(_disciplineCompetitionCard).toList(),
      ),
    );
  }

  Widget _disciplineCompetitionCard(Map<String, dynamic> d) {
    final suspended = d['status'] == 'suspended';
    final warning = d['status'] == 'available_warning';
    final color = suspended ? AppColors.destructive : warning ? AppColors.warning : AppColors.success;
    final label = AppLocalizations.get(suspended
        ? 'discipline_status_suspended'
        : warning
            ? 'discipline_status_warning'
            : 'discipline_status_available');
    final competitionName = d['competition_name'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.style_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            competitionName != null && competitionName.isNotEmpty
                ? competitionName
                : AppLocalizations.get('discipline_card_title'),
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 18, runSpacing: 8, children: [
          _disciplineValue(AppLocalizations.get('discipline_yellow_total'), d['yellow_cards_total']),
          _disciplineValue(AppLocalizations.get('discipline_yellow_current'), d['current_yellow_cards']),
          _disciplineValue(AppLocalizations.get('discipline_red_total'), d['red_cards_total']),
          _disciplineValue(AppLocalizations.get('discipline_matches_remaining'), d['matches_remaining']),
        ]),
      ]),
    );
  }

  Widget _disciplineValue(String label, dynamic value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          Text('${value ?? 0}', style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
        ],
      );

  // ── Pending Hooper/RPE reminders — stays visible until submitted ────────────
  bool _hooperAvailable(DateTime eventStart) {
    final now = DateTime.now();
    final dayBefore = DateTime(eventStart.year, eventStart.month, eventStart.day - 1);
    return !now.isBefore(dayBefore) && now.isBefore(eventStart);
  }

  DateTime _matchStart(MatchModel m) {
    final parts = m.matchTime.split(':');
    return DateTime(
      m.matchDate.year,
      m.matchDate.month,
      m.matchDate.day,
      int.tryParse(parts.first) ?? 16,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  List<_PendingCheck> _pendingChecks() {
    final items = <_PendingCheck>[];
    final session = _todaySession;
    if (session != null && session.needsPreCheck) {
      items.add(_PendingCheck(
        icon: Icons.self_improvement_rounded,
        label: AppLocalizations.get('pending_hooper_session'),
        onTap: (context) => Navigator.of(context)
            .pushNamed('/player/session/pre-check', arguments: session),
      ));
    }
    for (final match in _clubMatches) {
      final now = DateTime.now();
      final start = _matchStart(match);
      final end = start.add(const Duration(minutes: 105));
      final today = DateTime(now.year, now.month, now.day);
      final matchDay = DateTime(match.matchDate.year, match.matchDate.month, match.matchDate.day);
      final withinRpeWindow = today.difference(matchDay).inDays >= 0 &&
          today.difference(matchDay).inDays <= 1;
      if (match.status == 'cancelled') continue;
      if (match.wellnessRequired &&
          !match.wellnessDone &&
          match.status != 'completed' &&
          _hooperAvailable(start)) {
        items.add(_PendingCheck(
          icon: Icons.self_improvement_rounded,
          label: AppLocalizations.get('pending_hooper_match'),
          onTap: (context) => Navigator.of(context)
              .pushNamed('/player/monitoring/hooper?sessionId=${match.id}')
              .then((_) => _loadData()),
        ));
      }
      if (match.rpeRequired &&
          !match.rpeDone &&
          match.myMinutes != null &&
          match.myMinutes! > 0 &&
          withinRpeWindow &&
          now.isAfter(end)) {
        items.add(_PendingCheck(
          icon: Icons.speed_rounded,
          label: AppLocalizations.get('pending_rpe_match'),
          onTap: (context) => Navigator.of(context)
              .pushNamed(
                  '/player/monitoring/rpe?sessionId=${match.id}&durationMinutes=${match.myMinutes}')
              .then((_) => _loadData()),
        ));
      }
    }
    return items;
  }

  Widget _buildPendingChecksBanner() {
    if (_loading) return const SizedBox.shrink();
    final items = _pendingChecks();
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: items
            .map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => item.onTap(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(item.icon, color: AppColors.warning, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.label,
                              style: const TextStyle(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: AppColors.warning, size: 18),
                        ],
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ── Today Session Card ──────────────────────────────────────────────────────
  Widget _buildTodaySessionCard() {
    if (_loading) return const SizedBox.shrink();
    final s = _todaySession;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: s == null ? _NoSessionCard() : _TodaySessionCard(session: s),
    );
  }

  Widget _buildHeader() {
    return PlayerPageHeader(
      title: AppLocalizations.format('hello_greeting', {
        'name': _localizedPlayerHeaderName(),
      }),
      subtitle: AppLocalizations.get('performance_dashboard'),
    );
  }

  Widget _buildQuickSummaryCard() {
    final load = _dashboard?.lastRpe?.trainingLoad;
    final bodyFat = _dashboard?.bodyMetric?.bodyFatPercent;
    final fms = _latestAssessment?.overallScore;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MiniStat(
            AppLocalizations.get('training_load'),
            load != null ? MetricFormatter.load(load) : '—',
            const Color(0xffF2B23B),
          ),
          _MiniStat(
            AppLocalizations.get('body_fat'),
            bodyFat != null ? MetricFormatter.bodyFat(bodyFat) : '—',
            const Color(0xff8B5CF6),
          ),
          _MiniStat(
            'FMS',
            fms != null ? '$fms' : '—',
            fms == null
                ? AppColors.muted
                : fms >= 75
                ? const Color(0xff2DBF6C)
                : fms >= 50
                ? const Color(0xffF2B23B)
                : const Color(0xffFF4D2E),
          ),
        ],
      ),
    );
  }

  // ── Training list — AI plan for independent players only. Sessions/Matches
  // moved to their own bottom-nav tabs; "Start Assessment" removed per request.
  Widget _buildTrainingList(BuildContext context) {
    final isIndependent =
        currentPlayerType == PlayerType.independent ||
        currentPlayerType == null;
    if (!isIndependent) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _ProfileAction(
        icon: Icons.auto_awesome_rounded,
        label: AppLocalizations.get('ai_plan_title'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const IndependentAIPlanScreen()),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final isIndependent =
        currentPlayerType == PlayerType.independent ||
        currentPlayerType == null;
    // Only the independent-player "join a club" CTA stays on Home — it's a
    // one-time onboarding action with no natural home in Training/Health.
    // Everything else (assessments, sessions, matches, AI plan, wellness,
    // physio, nutrition, progress) now lives in the Training/Health tabs.
    if (!isIndependent) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GestureDetector(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const JoinClubScreen())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xff1565C0).withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xff1565C0).withOpacity(0.35),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.sports_soccer_rounded,
                color: Color(0xff42A5F5),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'انضم لناديك',
                      style: TextStyle(
                        color: Color(0xff42A5F5),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'أدخل كود الدعوة لربط حسابك بالنادي',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.muted,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNutritionCard() {
    final profile = _nutritionProfile;
    final hasTargets = profile != null &&
        (profile['calorie_target'] != null ||
            profile['protein_target_g'] != null ||
            profile['carb_target_g'] != null ||
            profile['fluid_target_ml'] != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.get('nutrition_title'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (!hasTargets)
            _emptySectionCard(Icons.restaurant_outlined, AppLocalizations.get('no_nutrition_info'))
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  if (profile['calorie_target'] != null)
                    _nutritionStat(AppLocalizations.get('calorie_target'), '${profile['calorie_target']} ${AppLocalizations.get('kcal_unit')}'),
                  if (profile['protein_target_g'] != null)
                    _nutritionStat(AppLocalizations.get('protein_target_g'), '${profile['protein_target_g']} g'),
                  if (profile['carb_target_g'] != null)
                    _nutritionStat(AppLocalizations.get('carb_target_g'), '${profile['carb_target_g']} g'),
                  if (profile['fluid_target_ml'] != null)
                    _nutritionStat(AppLocalizations.get('fluid_target_ml'), '${profile['fluid_target_ml']} ml'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _nutritionStat(String label, String value) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppColors.foreground.withOpacity(0.5), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildCoachNotesCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.get('coach_notes_title'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (_coachNotes.isEmpty)
            _emptySectionCard(Icons.sticky_note_2_outlined, AppLocalizations.get('no_coach_notes'))
          else
            ..._coachNotes.take(5).map(_buildCoachNoteTile),
        ],
      ),
    );
  }

  Widget _buildCoachNoteTile(Map<String, dynamic> note) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (note['authorName'] as String?) ?? '',
                  style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Text(
                ((note['date'] as String?) ?? '').split(' ').first,
                style: TextStyle(color: AppColors.foreground.withOpacity(0.4), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (note['text'] as String?) ?? '',
            style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _emptySectionCard(IconData icon, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(icon, color: AppColors.foreground.withOpacity(0.18), size: 48),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.color);
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
String _localizedPlayerHeaderName() {
  final isArabic = getAppLanguage() == 'ar';
  final preferred = isArabic
      ? currentUserNameArabic.trim()
      : currentUserNameEnglish.trim();
  return preferred.isNotEmpty ? preferred : currentUserName.trim();
}

// Shared page header — club logo, title/subtitle, player name, notification
// bell. Used by every player-facing page (Home, Health, My Sessions, My
// Matches, Profile) so the top bar looks and behaves the same everywhere.
// ─────────────────────────────────────────────────────────────────────────────

class PlayerPageHeader extends StatelessWidget {
  const PlayerPageHeader({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final playerName = _localizedPlayerHeaderName();
    return RoleBrandHeader(
      roleLabel: AppLocalizations.get('role_player'),
      accountName: playerName,
      pageTitle: title,
      subtitle: subtitle,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Player Profile Page
// ─────────────────────────────────────────────────────────────────────────────

class PlayerProfilePage extends StatelessWidget {
  const PlayerProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isIndependent =
        currentPlayerType == PlayerType.independent ||
        currentPlayerType == null;
    return PlayerShell(
      currentIndex: isIndependent ? 2 : 4,
      child: _PlayerProfileBody(),
    );
  }
}

class _PlayerProfileBody extends StatefulWidget {
  @override
  State<_PlayerProfileBody> createState() => _PlayerProfileBodyState();
}

class _PlayerProfileBodyState extends State<_PlayerProfileBody> {
  Map<String, dynamic>? _account;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    final results = await Future.wait([
      ApiService.getMyPlayerProfile(),
      ApiService.getMe(),
    ]);
    if (!mounted) return;
    final profile = results[0];
    final accountResponse = results[1];
    final playerJson = profile['player'] as Map<String, dynamic>?;
    final accountJson = accountResponse['user'] as Map<String, dynamic>?;
    final player = playerJson != null ? ClubPlayer.fromJson(playerJson) : null;
    currentUserNameArabic = player?.nameArabic ?? '';
    currentUserNameEnglish = player?.nameEnglish ?? '';
    setState(() {
      _account = accountJson;
      _loadFailed = accountJson == null;
      _loading = false;
    });
  }

  Future<void> _editAccount() async {
    final account = _account;
    if (account == null) return;
    final nameController = TextEditingController(
      text: account['name']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: account['phone']?.toString() ?? '',
    );
    var saving = false;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(AppLocalizations.get('edit_profile')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                enabled: !saving,
                decoration: InputDecoration(
                  labelText: AppLocalizations.get('player_name'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                enabled: !saving,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: AppLocalizations.get('phone'),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.destructive,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: Text(AppLocalizations.get('cancel')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final phone = phoneController.text.trim();
                      if (name.isEmpty) return;
                      final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
                      if (phone.isNotEmpty &&
                          (phoneDigits.length < 8 ||
                              phoneDigits.length > 15)) {
                        setDialogState(
                          () => error = AppLocalizations.get(
                            'error_invalid_phone',
                          ),
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      final result = await ApiService.updateAccountProfile(
                        name: name,
                        phone: phone,
                        avatarUrl: account['avatar_url']?.toString(),
                      );
                      if (!dialogContext.mounted) return;
                      if (result['success'] == true) {
                        final updated =
                            result['user'] as Map<String, dynamic>? ?? account;
                        currentUserName = updated['name']?.toString() ?? name;
                        currentUserAvatarUrl =
                            updated['avatar_url']?.toString() ?? '';
                        await OnboardingStore().setUserName(currentUserName);
                        await OnboardingStore().setUserAvatarUrl(
                          currentUserAvatarUrl,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                        return;
                      }
                      setDialogState(() {
                        saving = false;
                        error =
                            result['error']?.toString() ??
                            AppLocalizations.get('error_connection');
                      });
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppLocalizations.get('save_changes')),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    phoneController.dispose();
    if (saved == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.get('profile_updated_success')),
        ),
      );
    }
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    var saving = false;
    String? error;

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(AppLocalizations.get('change_password')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in [
                (currentController, 'current_password'),
                (newController, 'new_password'),
                (confirmController, 'confirm_password'),
              ]) ...[
                TextField(
                  controller: field.$1,
                  enabled: !saving,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.get(field.$2),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.destructive,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: Text(AppLocalizations.get('cancel')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (newController.text.length < 6) {
                        setDialogState(
                          () => error = AppLocalizations.get(
                            'error_password_short',
                          ),
                        );
                        return;
                      }
                      if (newController.text != confirmController.text) {
                        setDialogState(
                          () => error = AppLocalizations.get(
                            'password_mismatch',
                          ),
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      final result = await ApiService.changePassword(
                        currentPassword: currentController.text,
                        newPassword: newController.text,
                      );
                      if (!dialogContext.mounted) return;
                      if (result['success'] == true) {
                        Navigator.of(dialogContext).pop(true);
                        return;
                      }
                      setDialogState(() {
                        saving = false;
                        error = result['error']?.toString() ==
                                'Current password is incorrect'
                            ? AppLocalizations.get(
                                'current_password_incorrect',
                              )
                            : result['error']?.toString() ??
                                  AppLocalizations.get('error_connection');
                      });
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppLocalizations.get('change_password')),
            ),
          ],
        ),
      ),
    );
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.get('password_changed_success')),
        ),
      );
    }
  }

  Widget _buildAccountCard() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_loadFailed || _account == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.destructive.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                AppLocalizations.get('error_connection'),
                style: const TextStyle(color: AppColors.destructive),
              ),
            ),
            TextButton(
              onPressed: _load,
              child: Text(AppLocalizations.get('retry_btn')),
            ),
          ],
        ),
      );
    }
    final account = _account!;
    final name = account['name']?.toString() ?? currentUserName;
    final email = account['email']?.toString() ?? '';
    final phone = account['phone']?.toString() ?? '';
    final avatar = account['avatar_url']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            backgroundImage:
                avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'P',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11.5,
                    ),
                  ),
                if (phone.isNotEmpty)
                  Text(
                    phone,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.get('edit_profile'),
            onPressed: _editAccount,
            icon: const Icon(Icons.edit_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  void _showLangSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PlayerLangSheet(),
    );
  }

  void _showAboutDialog(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            AppLocalizations.get('club_brand_name'),
            style: TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.get('app_subtitle'),
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              const Text(
                'v1.0.0',
                style: TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                AppLocalizations.get('ok'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return PlayerPageHeader(
      title: AppLocalizations.get('profile_page_title'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    _buildAccountCard(),
                    const SizedBox(height: 10),
                    _ProfileAction(
                      icon: Icons.lock_outline_rounded,
                      label: AppLocalizations.get('change_password'),
                      onTap: _changePassword,
                    ),
                    const SizedBox(height: 10),
                    _ProfileAction(
                      icon: Icons.history_rounded,
                      label: AppLocalizations.get('assessment_history_title'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PlayerHistoryScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ProfileAction(
                      icon: Icons.show_chart_rounded,
                      label: AppLocalizations.get('profile_progress_title'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PlayerProgressScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ProfileAction(
                      icon: Icons.language_rounded,
                      label: AppLocalizations.get('profile_language'),
                      onTap: () => _showLangSheet(context),
                    ),
                    const SizedBox(height: 10),
                    _ProfileAction(
                      icon: Icons.info_outline_rounded,
                      label: AppLocalizations.get('about_app'),
                      onTap: () => _showAboutDialog(context),
                    ),
                    const SizedBox(height: 10),
                    _ProfileAction(
                      icon: Icons.logout_rounded,
                      label: AppLocalizations.get('logout_btn'),
                      color: Colors.red,
                      onTap: () async {
                        await OnboardingStore().clearSignedIn();
                        CrashReporter.clearContext();
                        currentUserNameArabic = '';
                        currentUserNameEnglish = '';
                        if (!context.mounted) return;
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/auth', (_) => false);
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Profile Widgets ───────────────────────────────────────────────────

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Language Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerLangSheet extends StatelessWidget {
  const _PlayerLangSheet();

  static const _langs = [
    ('العربية', 'ar'),
    ('English', 'en'),
    ('Français', 'fr'),
  ];

  Future<void> _pick(BuildContext ctx, String code) async {
    setAppLanguage(code);
    await OnboardingStore().setLanguage(code);
    unawaited(ApiService.updateAccountLanguage(code));
    if (ctx.mounted) {
      Navigator.of(ctx).pushNamedAndRemoveUntil('/player', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              AppLocalizations.get('choose_language_title'),
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 16),
            for (final lang in _langs)
              GestureDetector(
                onTap: () => _pick(context, lang.$2),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: getAppLanguage() == lang.$2
                        ? AppColors.maroon.withOpacity(0.06)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: getAppLanguage() == lang.$2
                          ? AppColors.maroon.withOpacity(0.35)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        lang.$1,
                        style: TextStyle(
                          color: getAppLanguage() == lang.$2
                              ? AppColors.maroon
                              : AppColors.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      if (getAppLanguage() == lang.$2)
                        const Icon(
                          Icons.check_rounded,
                          color: AppColors.maroon,
                          size: 18,
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
// Today Session Card Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _NoSessionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Icon(Icons.calendar_today_rounded, color: AppColors.muted, size: 18),
        const SizedBox(width: 10),
        Text(
          AppLocalizations.get('no_session_today'),
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      ],
    ),
  );
}

class _TodaySessionCard extends StatelessWidget {
  const _TodaySessionCard({required this.session});
  final PlayerSessionData session;

  @override
  Widget build(BuildContext context) {
    final (btnLabel, btnColor, route, usePreCheck) = _btnConfig(session);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.get('todays_session_label'),
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              _StatusBadge(status: session.playerStatus),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            session.title,
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          // Metadata row
          Row(
            children: [
              _MetaChip(
                icon: Icons.timer_outlined,
                label:
                    '${session.durationMinutes} ${AppLocalizations.get('min_suffix')}',
              ),
              const SizedBox(width: 8),
              _MetaChip(
                icon: Icons.sports_rounded,
                label: session.objectiveLabel,
              ),
              if (session.exerciseCount > 0) ...[
                const SizedBox(width: 8),
                _MetaChip(
                  icon: Icons.list_rounded,
                  label:
                      '${session.exerciseCount} ${AppLocalizations.get('exercises_count_suffix')}',
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // Action button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: session.isMissed
                  ? null
                  : () {
                      if (session.isCompleted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PlayerHistoryScreen(),
                          ),
                        );
                        return;
                      }
                      Navigator.of(
                        context,
                      ).pushNamed(route, arguments: session);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: session.isCompleted
                    ? Colors.white.withOpacity(0.08)
                    : btnColor,
                disabledBackgroundColor: Colors.white.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Text(
                btnLabel,
                style: TextStyle(
                  color: session.isCompleted ? AppColors.muted : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static (String, Color, String, bool) _btnConfig(PlayerSessionData s) {
    if (s.isCompleted)
      return (
        AppLocalizations.get('assessment_history_title'),
        AppColors.success,
        '/player/history',
        false,
      );
    if (s.isMissed)
      return (
        AppLocalizations.get('missed_label'),
        Colors.grey,
        '/player',
        false,
      );
    if (s.isStarted)
      return (
        AppLocalizations.get('continue_session_label'),
        AppColors.primary,
        '/player/session/run',
        false,
      );
    if (s.canStart)
      return (
        AppLocalizations.get('start_session_label'),
        AppColors.primary,
        '/player/session/run',
        false,
      );
    // needs pre-check
    return (
      AppLocalizations.get('start_precheck_btn'),
      const Color(0xfff59e0b),
      '/player/session/pre-check',
      true,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'assigned' => (
        AppLocalizations.get('precheck_required_label'),
        const Color(0xfff59e0b),
      ),
      'pre_checked' => (AppLocalizations.get('ready_label'), AppColors.success),
      'started' => (
        AppLocalizations.get('in_progress_label'),
        AppColors.primary,
      ),
      'completed' => (
        AppLocalizations.get('session_completed_label'),
        AppColors.success,
      ),
      'missed' => (AppLocalizations.get('missed_label'), Colors.grey),
      _ => (AppLocalizations.get('assigned_label'), AppColors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: AppColors.muted, size: 13),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
    ],
  );
}
