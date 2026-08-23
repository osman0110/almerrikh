import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../models/coach_monitoring_models.dart';
import '../../models/sessions_models.dart' hide SessionType;
import '../../services/club_service.dart';
import '../../services/coach_monitoring_service.dart';
import '../../services/sessions_service.dart';
import '../../widgets/common_widgets.dart' show RoleAccessDeniedPage;
import 'club_widgets.dart';
import 'club_dashboard.dart' show ClubShell;
import 'body_composition_list_page.dart';
import 'body_composition_team_screen.dart';
import 'daily_readiness_screen.dart';
import 'team_training_load_report_screen.dart';
import 'team_performance_report_screen.dart';
import 'fms_assessment_screen.dart';
import 'fms_history_screen.dart';
import '../player/body_composition_entry_screen.dart';
import 'match_detail_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Physical Coach Dashboard — focused Home tab for the "coach" org role.
// The home stays concise: session card plus recording and report shortcuts.
// ─────────────────────────────────────────────────────────────────────────────

class PhysicalCoachDashboardPage extends StatefulWidget {
  const PhysicalCoachDashboardPage({super.key});

  @override
  State<PhysicalCoachDashboardPage> createState() =>
      _PhysicalCoachDashboardPageState();
}

class _PhysicalCoachDashboardPageState
    extends State<PhysicalCoachDashboardPage> {
  bool _loading = true;
  bool _loadError = false;
  final Set<String> _runningActions = {};
  final Set<String> _startingSessionIds = {};
  int _loadRequestId = 0;
  String _clubName = '';

  List<ClubPlayer> _allPlayers = [];

  // Upcoming session/match — same widget as the admin dashboard.
  List<TrainingSession> _allSessions = [];
  List<MatchModel> _allMatches = [];
  DateTime _selectedDate = DateTime.now();
  TeamReadiness? _readiness;
  Map<String, dynamic> _disciplineSummary = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_loadRequestId;
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final dashboard = await ClubService().getPhysicalCoachDashboard();
      if (dashboard == null) {
        throw StateError('Physical coach dashboard response is unavailable');
      }
      if (!mounted || requestId != _loadRequestId) return;
      final profile = Map<String, dynamic>.from(
        dashboard['profile'] as Map? ?? const {},
      );
      final allP = _uniqueById(
        (dashboard['players'] as List? ?? const [])
            .map((item) => ClubPlayer.fromJson(
                  Map<String, dynamic>.from(item as Map),
                )),
        (player) => player.id,
      )..sort((a, b) => a.fullName.compareTo(b.fullName));
      final sessions = _uniqueById(
        (dashboard['sessions'] as List? ?? const [])
            .map((item) => TrainingSession.fromJson(
                  Map<String, dynamic>.from(item as Map),
                )),
        (session) => session.id,
      )..sort(_compareSessions);
      final matches = _uniqueById(
        (dashboard['matches'] as List? ?? const [])
            .map((item) => MatchModel.fromJson(
                  Map<String, dynamic>.from(item as Map),
                )),
        (match) => match.id,
      )..sort(_compareMatches);

      setState(() {
        _clubName = profile['club_name']?.toString() ?? '';
        currentClubName = _clubName;
        _allPlayers = allP;
        _allSessions = sessions;
        _allMatches = matches;
        _disciplineSummary = dashboard['discipline_summary'] is Map
            ? Map<String, dynamic>.from(dashboard['discipline_summary'] as Map)
            : {};
      });
      currentTeamId = profile['team_id']?.toString() ?? '';
      currentTeamName = profile['team_name']?.toString() ?? '';
      final profileName = profile['name']?.toString() ?? '';
      if (profileName.isNotEmpty) currentUserName = profileName;

      try {
        final readiness = await CoachMonitoringService.getTeamReadiness();
        if (mounted && requestId == _loadRequestId) {
          setState(() => _readiness = readiness);
        }
      } catch (e) {
        AppLogger.w('PhysicalCoachDashboard', 'Readiness load failed');
      }
    } catch (e) {
      AppLogger.e('PhysicalCoachDashboard', 'Load failed', e);
      if (mounted && requestId == _loadRequestId) {
        setState(() => _loadError = true);
      }
    }
    if (mounted && requestId == _loadRequestId) {
      setState(() => _loading = false);
    }
  }

  List<T> _uniqueById<T>(Iterable<T> items, String Function(T) idOf) {
    final byId = <String, T>{};
    for (final item in items) {
      final id = idOf(item).trim();
      if (id.isNotEmpty) byId[id] = item;
    }
    return byId.values.toList();
  }

  int _compareSessions(TrainingSession a, TrainingSession b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    final byTime = a.startTime.compareTo(b.startTime);
    return byTime != 0 ? byTime : a.name.compareTo(b.name);
  }

  int _compareMatches(MatchModel a, MatchModel b) {
    final byDate = a.matchDate.compareTo(b.matchDate);
    if (byDate != 0) return byDate;
    final byTime = a.matchTime.compareTo(b.matchTime);
    return byTime != 0 ? byTime : a.opponent.compareTo(b.opponent);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<TrainingSession> get _selectedDateSessions =>
      _allSessions.where((session) => _sameDay(session.date, _selectedDate)).toList();

  List<MatchModel> get _selectedDateMatches =>
      _allMatches.where((match) => _sameDay(match.matchDate, _selectedDate)).toList();

  void _changeDate(DateTime d) {
    setState(() => _selectedDate = d);
  }

  /// Sessions + matches from today forward, merged and sorted by date.
  List<_CoachScheduleItem> get _upcomingEvents {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = <_CoachScheduleItem>[
      for (final s in _allSessions)
        if (!DateTime(s.date.year, s.date.month, s.date.day).isBefore(today))
          _CoachScheduleItem.session(s),
      for (final m in _allMatches)
        if (!DateTime(m.matchDate.year, m.matchDate.month, m.matchDate.day).isBefore(today))
          _CoachScheduleItem.match(m),
    ]..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.title.compareTo(b.title);
    });
    return items.take(7).toList();
  }

  Future<void> _pickDate() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CalendarSheet(
        initialMonth: DateTime(_selectedDate.year, _selectedDate.month),
        selectedDate: _selectedDate,
        markerOf: _dayMarker,
      ),
    );
    if (picked != null) _changeDate(picked);
  }

  Future<void> _onSessionAction(TrainingSession s) async {
    if (_startingSessionIds.contains(s.id)) return;
    setState(() => _startingSessionIds.add(s.id));
    if (s.status == 'scheduled') {
      final previousStatus = s.status;
      s.status = 'active';
      final ok = await ClubService().updateSession(s);
      if (!ok) {
        s.status = previousStatus;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.get('quick_action_failed'))),
          );
          setState(() => _startingSessionIds.remove(s.id));
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() => _startingSessionIds.remove(s.id));
    Navigator.of(context).pushNamed('/club/sessions/${s.id}');
  }

  // ── Date bar + today's session/match hero — same widget as the admin
  // dashboard, so the physical coach sees the upcoming session/match too.

  // Design shows 5 day pills (weekday name + sub label) instead of a plain
  // date string. We keep the real arbitrary-date navigation (paging arrows +
  // a date picker) but render the window as day pills like the mockup.

  Widget _buildDateBar(BuildContext context) {
    return RoleHomeDateStrip(
      selectedDate: _selectedDate,
      onDateChanged: _changeDate,
      onCalendarTap: _pickDate,
      markerOf: (date) {
        final marker = _dayMarker(date);
        return RoleDateMarker(
          hasMatch: marker.hasMatch,
          hasSession: marker.hasSession,
          accentColor: marker.specialTextColor,
        );
      },
    );
  }

  // Shared by the day pills and the custom calendar sheet, so both mark
  // sessions/matches the same way: match (soccer icon, maroon), rehab
  // session (purple text), physical-assessment session (green text),
  // any other session (gold dumbbell icon).
  _DayMarker _dayMarker(DateTime d) {
    final daySessions = _allSessions.where((s) => _sameDay(s.date, d)).toList();
    final hasMatch = _allMatches.any((m) => _sameDay(m.matchDate, d));
    Color? specialTextColor;
    if (daySessions.any((s) => s.type == SessionType.rehab)) {
      specialTextColor = AppColors.playerAccent;
    } else if (daySessions.any((s) => s.type == SessionType.physicalAssessment)) {
      specialTextColor = AppColors.success;
    }
    return _DayMarker(
      hasMatch: hasMatch,
      hasSession: daySessions.isNotEmpty,
      specialTextColor: specialTextColor,
    );
  }

  Widget _buildTodayEventHero(BuildContext context) {
    final events = <_CoachDayEvent>[
      for (final session in _selectedDateSessions)
        _CoachDayEvent.session(session),
      for (final match in _selectedDateMatches) _CoachDayEvent.match(match),
    ]..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    if (events.isEmpty) return _buildEmptySession(context);

    return Column(
      children: [
        for (var index = 0; index < events.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          if (events[index].session != null)
            _buildSessionHero(context, events[index].session!)
          else
            _buildMatchHero(context, events[index].match!),
        ],
      ],
    );
  }

  // Watermark scales with the card's actual height (via the Stack's own
  // constraints) so it stays proportional whether the card is short (match)
  // or tall (session, which has more rows of content).
  Widget _heroLogoWatermark() {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxHeight.isFinite
              ? (constraints.maxHeight * 1.15).clamp(120.0, 220.0)
              : 140.0;
          return Align(
            alignment: Alignment.bottomLeft,
            child: Transform.translate(
              offset: Offset(-size * 0.22, size * 0.18),
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.10,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                    child: Image.asset('assets/images/logo.png',
                        width: size, height: size, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionHero(BuildContext context, TrainingSession s) {
    final locationUnset = s.location == null || s.location!.isEmpty;
    final location = locationUnset
        ? AppLocalizations.get('location_not_set')
        : s.location!;
    final endTime = (s.endTime != null && s.endTime!.isNotEmpty) ? s.endTime! : null;
    final timeRange = endTime != null ? '${s.startTime} – $endTime' : s.startTime;
    final rosterIds = s.playerIds.toSet();
    final expected = rosterIds.length;
    final present = s.attendancePresentCount.clamp(0, expected);

    String statusKey;
    switch (s.status) {
      case 'active': statusKey = 'status_active'; break;
      case 'completed': statusKey = 'status_completed'; break;
      case 'cancelled': statusKey = 'status_cancelled'; break;
      default: statusKey = 'status_scheduled';
    }

    String actionKey;
    switch (s.status) {
      case 'active': actionKey = 'open_session_btn'; break;
      case 'completed': actionKey = 'view_report_btn'; break;
      case 'cancelled': actionKey = 'view_details_btn'; break;
      default: actionKey = 'start_session_btn';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.hero, AppColors.maroonDark],
          ),
        ),
        child: Stack(
          children: [
            _heroLogoWatermark(),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(AppLocalizations.get('today_session'),
                          style: const TextStyle(
                              color: AppColors.onDarkMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AppColors.hero.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                        ),
                        child: Text(AppLocalizations.get(statusKey),
                            style: const TextStyle(
                                color: AppColors.onDarkMuted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(s.name,
                      style: const TextStyle(
                          color: AppColors.onDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.25),
                      maxLines: 2),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _CoachHeroMeta(icon: Icons.schedule_rounded, label: timeRange),
                      const SizedBox(width: 5),
                      Container(width: 3, height: 3, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      _CoachHeroMeta(
                          icon: Icons.location_on_rounded,
                          label: location,
                          clip: true,
                          iconColor: locationUnset ? AppColors.warning : AppColors.gold,
                          textColor: locationUnset ? AppColors.warning : AppColors.onDarkMuted),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _HeroStat(value: '$expected', label: AppLocalizations.get('expected_players')),
                      Container(
                          width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 10),
                          color: AppColors.gold.withOpacity(0.35)),
                      _HeroStat(value: '$present', label: AppLocalizations.get('present_players')),
                      Container(
                          width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 10),
                          color: AppColors.gold.withOpacity(0.35)),
                      _CoachHeroMeta(
                          icon: Icons.fitness_center_rounded,
                          label: s.type.label,
                          clip: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _CoachHeroMeta(
                            icon: Icons.person_outline_rounded,
                            label: s.coachName.isNotEmpty ? s.coachName : AppLocalizations.get('coach_label'),
                            textColor: AppColors.gold.withOpacity(0.85),
                            fontSize: 9.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _onSessionAction(s),
                    child: Container(
                      width: double.infinity,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(AppLocalizations.get(actionKey),
                              style: const TextStyle(
                                  color: AppColors.maroonDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5)),
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: AppColors.gold,
                            size: 17,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchHero(BuildContext context, MatchModel m) {
    final timeRange = m.matchTime;
    final location = (m.location != null && m.location!.isNotEmpty)
        ? m.location!
        : AppLocalizations.get('location_not_set');

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.hero, AppColors.maroonDark],
          ),
        ),
        child: Stack(
          children: [
            _heroLogoWatermark(),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(AppLocalizations.get('today_match_label'),
                          style: const TextStyle(
                              color: AppColors.onDarkMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AppColors.hero.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                        ),
                        child: Text(m.statusLabel,
                            style: const TextStyle(
                                color: AppColors.onDarkMuted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text('${AppLocalizations.get('vs_label')} ${m.opponent}',
                      style: const TextStyle(
                          color: AppColors.onDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          height: 1.2),
                      maxLines: 2),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _CoachHeroMeta(icon: Icons.schedule_rounded, label: timeRange),
                      const SizedBox(width: 12),
                      _CoachHeroMeta(icon: Icons.location_on_rounded, label: location, clip: true),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => MatchDetailPage(matchId: m.id))),
                    child: Container(
                      width: double.infinity,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(AppLocalizations.get('view_details_btn'),
                              style: const TextStyle(
                                  color: AppColors.maroonDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5)),
                          const SizedBox(width: 5),
                          Icon(
                            Directionality.of(context) == TextDirection.rtl
                                ? Icons.arrow_back_rounded
                                : Icons.arrow_forward_rounded,
                            color: AppColors.gold,
                            size: 17,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
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
                color: isSelected ? AppColors.primarySoft : AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isSelected ? AppColors.maroon : AppColors.border,
                    width: isSelected ? 1.4 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(item.isMatch ? Icons.sports_soccer_rounded : Icons.fitness_center_rounded,
                        color: item.isMatch ? AppColors.maroon : AppColors.gold, size: 13),
                    const SizedBox(width: 4),
                    Text('${item.date.day}/${item.date.month}',
                        style: TextStyle(
                            color: isSelected ? AppColors.maroon : AppColors.muted,
                            fontSize: 10, fontWeight: FontWeight.w700)),
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

  Widget _buildEmptySession(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    // Admin/owner never enter the physical coach's operational interface —
    // the read-only management policy limits them to the aggregated reports.
    if (isOrgAdmin) return const RoleAccessDeniedPage();
    return ClubShell(
      currentIndex: 0,
      child: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.card,
        strokeWidth: 2,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(child: _buildDateBar(context)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_loadError)
                    ClubErrorState(
                      title: AppLocalizations.get('error_load_failed'),
                      description: AppLocalizations.get('error_check_internet'),
                      retryLabel: AppLocalizations.get('retry_btn'),
                      onRetry: _load,
                    )
                  else ...[
                    _buildTodayEventHero(context),
                    const SizedBox(height: 10),
                    _buildQuickAccessSection(context),
                    const SizedBox(height: 10),
                    _buildDisciplineSummary(context),
                    const SizedBox(height: 10),
                    _buildPrimaryActions(context),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick access row — direct shortcuts to the roster, sessions, and
  // matches lists (already reachable via the bottom nav, but surfaced here
  // too so the coach doesn't have to hunt for them on the crowded home tab).

  Widget _buildQuickAccessSection(BuildContext context) {
    return _primaryActionSection(
      title: AppLocalizations.get('quick_access'),
      actions: [
        _primaryAction(
          icon: Icons.group_rounded,
          label: AppLocalizations.get('nav_players'),
          color: AppColors.primary,
          onTap: () => Navigator.of(context).pushNamed('/club/players'),
        ),
        _primaryAction(
          icon: Icons.calendar_month_rounded,
          label: AppLocalizations.get('admin_nav_schedule'),
          color: AppColors.coachAccent,
          onTap: () => Navigator.of(context).pushNamed('/club/sessions'),
        ),
        _primaryAction(
          icon: Icons.sports_soccer_rounded,
          label: AppLocalizations.get('nav_matches'),
          color: AppColors.maroon,
          onTap: () => Navigator.of(context).pushNamed('/club/matches'),
        ),
      ],
    );
  }

  Widget _buildDisciplineSummary(BuildContext context) {
    if (_disciplineSummary.isEmpty) return const SizedBox.shrink();
    final threatened = _disciplineSummary['threatened_players'] ?? 0;
    final active = _disciplineSummary['active_suspensions'] ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.style_rounded, color: AppColors.warning, size: 17),
          const SizedBox(width: 7),
          const Expanded(child: Text('البطاقات والإيقافات', style: TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800))),
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/club/players'),
            child: const Text('عرض اللاعبين'),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 18, runSpacing: 8, children: [
          _disciplineStat('الصفراء', _disciplineSummary['yellow_cards'], AppColors.warning),
          _disciplineStat('الحمراء', _disciplineSummary['red_cards'], AppColors.destructive),
          _disciplineStat('مهددون بالإيقاف', threatened, AppColors.warning),
          _disciplineStat('إيقافات نشطة', active, AppColors.destructive),
        ]),
      ]),
    );
  }

  Widget _disciplineStat(String label, dynamic value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          Text('${value ?? 0}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      );

  // ── HEADER — club logo, coach name, notification bell, profile avatar
  // (opens profile/settings/logout menu) — mirrors the admin header so every
  // role has the same branded top bar.

  Widget _buildHeader(BuildContext context) {
    return RoleBrandHeader(
      roleLabel: AppLocalizations.get('role_coach'),
    );
  }

  // ── Today's stat cards — attendance + readiness, matching the design's
  // "X of Y" progress cards. Attendance reuses the same roster/present counts
  // as the hero card; readiness reuses the existing team-readiness summary
  // (already fetched elsewhere in the app). Missing data shows "-", never a
  // hidden tile.

  Widget _buildTodayStatsRow(BuildContext context) {
    final rosterIds = <String>{};
    for (final s in _selectedDateSessions) {
      rosterIds.addAll(s.playerIds);
    }
    final expected = rosterIds.isNotEmpty ? rosterIds.length : null;
    final present = _selectedDateSessions.isEmpty
        ? null
        : _selectedDateSessions.fold<int>(
            0, (sum, s) => sum + s.attendancePresentCount);

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.fact_check_rounded,
            caption: AppLocalizations.get('record_attendance_caption'),
            value: present,
            total: expected,
            onTap: _showAttendanceForSelectedDate,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            icon: Icons.favorite_rounded,
            caption: AppLocalizations.get('complete_readiness_caption'),
            value: _readiness?.ready,
            total: _readiness?.squadTotal,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DailyReadinessScreen(initialDate: _selectedDate),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String caption,
    required int? value,
    required int? total,
    required VoidCallback onTap,
  }) {
    final hasData = value != null && total != null && total > 0;
    final pct = hasData ? (value / total).clamp(0.0, 1.0) : 0.0;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.foreground.withOpacity(0.05),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.maroon, size: 13),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(hasData ? '$value' : '-',
                          style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w800,
                              fontSize: 17)),
                      if (hasData) ...[
                        const SizedBox(width: 4),
                        Text(
                            '${AppLocalizations.get('of_label')} $total',
                            style: const TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w500,
                                fontSize: 9.5)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w400,
                          fontSize: 9.5)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: hasData ? pct : 0,
                      minHeight: 3.5,
                      backgroundColor: AppColors.surface2,
                      valueColor: const AlwaysStoppedAnimation(AppColors.maroon),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryActions(BuildContext context) {
    // Attendance + readiness are already surfaced as the stat cards in
    // _buildTodayStatsRow above — kept out of this icon row so the two
    // functions aren't duplicated on screen.
    final recordingActions = [
      _primaryAction(
        icon: Icons.videocam_rounded,
        label: AppLocalizations.get('start_ai_test'),
        color: AppColors.maroon,
        onTap: () => Navigator.of(context).pushNamed('/club/players'),
      ),
      _primaryAction(
        icon: Icons.checklist_rtl_rounded,
        label: AppLocalizations.get('quick_record_fms'),
        color: AppColors.coachAccent,
        onTap: () async {
          final player = await _pickPlayer(context);
          if (player == null || !mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FmsAssessmentScreen(
              playerId: player.id,
              playerName: player.fullName,
            ),
          ));
        },
      ),
      _primaryAction(
        icon: Icons.monitor_weight_rounded,
        label: AppLocalizations.get('quick_record_body_fat'),
        color: AppColors.warning,
        onTap: () async {
          final player = await _pickPlayer(context);
          if (player == null || !mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BodyCompositionEntryScreen(playerId: player.id),
          ));
        },
      ),
    ];
    final reportActions = [
      _primaryAction(
        icon: Icons.insights_rounded,
        label: AppLocalizations.get('session_performance_report_action'),
        color: AppColors.maroon,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const TeamPerformanceReportScreen(),
        )),
      ),
      _primaryAction(
        icon: Icons.bar_chart_rounded,
        label: AppLocalizations.get('training_load_report_action'),
        color: AppColors.primary,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const TeamTrainingLoadReportScreen(),
        )),
      ),
      _primaryAction(
        icon: Icons.monitor_weight_outlined,
        label: AppLocalizations.get('body_composition_report_action'),
        color: AppColors.warning,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const BodyCompositionListPage(),
        )),
      ),
      _primaryAction(
        icon: Icons.assessment_outlined,
        label: AppLocalizations.get('fms_report_action'),
        color: AppColors.coachAccent,
        onTap: () async {
          final player = await _pickPlayer(context);
          if (player == null || !mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FmsHistoryScreen(
              playerId: player.id,
              playerName: player.fullName,
            ),
          ));
        },
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTodayStatsRow(context),
        const SizedBox(height: 18),
        _primaryActionSection(
          title: AppLocalizations.get('dashboard_recordings_section'),
          actions: recordingActions,
        ),
        const SizedBox(height: 18),
        _primaryActionSection(
          title: AppLocalizations.get('reports_page_title'),
          actions: reportActions,
        ),
      ],
    );
  }

  // ── Flat icon-row section — matches the design's ungrouped layout: a small
  // gold-dot title, then a plain row of icon buttons (no bordered container).

  Widget _primaryActionSection({
    required String title,
    required List<Widget> actions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: actions[i]),
            ],
          ],
        ),
      ],
    );
  }

  Widget _primaryAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final effectiveColor = enabled ? color : AppColors.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? onTap : null,
      child: Container(
        height: 94,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.foreground.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: effectiveColor.withOpacity(0.16),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: effectiveColor, size: 18),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: enabled ? AppColors.foreground : AppColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAttendanceSheet(TrainingSession? session) async {
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('no_session_today_title'))),
      );
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SessionAttendanceSheet(
        sessionId: session.id,
        sessionName: session.name,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _showAttendanceForSelectedDate() async {
    final sessions = _selectedDateSessions;
    if (sessions.isEmpty) {
      await _showAttendanceSheet(null);
      return;
    }
    if (sessions.length == 1) {
      await _showAttendanceSheet(sessions.first);
      return;
    }

    final selected = await showModalBottomSheet<TrainingSession>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.get('choose_session_title'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              for (final session in sessions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.fitness_center_rounded,
                    color: AppColors.coachAccent,
                  ),
                  title: Text(
                    session.name,
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    session.startTime,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  onTap: () => Navigator.pop(sheetContext, session),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) await _showAttendanceSheet(selected);
  }

  // ignore: unused_element
  void _showRecordingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.get('physical_recordings_title'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              _linkCard(
                icon: Icons.videocam_rounded,
                color: AppColors.maroon,
                title: AppLocalizations.get('start_ai_test'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).pushNamed('/club/players');
                },
              ),
              const SizedBox(height: 8),
              _linkCard(
                icon: Icons.checklist_rtl_rounded,
                color: AppColors.coachAccent,
                title: AppLocalizations.get('quick_record_fms'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final player = await _pickPlayer(context);
                  if (player == null || !mounted) return;
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FmsAssessmentScreen(
                      playerId: player.id,
                      playerName: player.fullName,
                    ),
                  ));
                },
              ),
              const SizedBox(height: 8),
              _linkCard(
                icon: Icons.monitor_weight_rounded,
                color: AppColors.warning,
                title: AppLocalizations.get('quick_record_body_fat'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final player = await _pickPlayer(context);
                  if (player == null || !mounted) return;
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BodyCompositionEntryScreen(playerId: player.id),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  void _showReportsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.get('physical_reports_title'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.get('physical_reports_hint'),
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              _linkCard(
                icon: Icons.bar_chart_rounded,
                color: AppColors.primary,
                title: AppLocalizations.get('training_load'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TeamTrainingLoadReportScreen(),
                  ));
                },
              ),
              const SizedBox(height: 8),
              _linkCard(
                icon: Icons.monitor_weight_rounded,
                color: AppColors.warning,
                title: AppLocalizations.get('report_tile_body_comp_title'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const BodyCompositionListPage(),
                  ));
                },
              ),
              const SizedBox(height: 8),
              _linkCard(
                icon: Icons.checklist_rtl_rounded,
                color: AppColors.coachAccent,
                title: 'FMS',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final player = await _pickPlayer(context);
                  if (player == null || !mounted) return;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FmsHistoryScreen(
                      playerId: player.id,
                      playerName: player.fullName,
                    ),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Quick actions: start AI test, record FMS, record body fat ────────────
  // Moved here from the admin dashboard — the physical coach owns AI
  // assessments, FMS scoring, and body composition entry; admin only views
  // reports.

  // ignore: unused_element
  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      ClubActionTile(
        icon: Icons.videocam_rounded,
        label: AppLocalizations.get('start_ai_test'),
        subtitle: AppLocalizations.get('quick_ai_assessment_hint'),
        accent: AppColors.maroon,
        isLoading: _runningActions.contains('ai_test'),
        onTap: () => _runQuickAction(context, 'ai_test', () async {
          await Navigator.of(context).pushNamed('/club/players');
        }),
      ),
      ClubActionTile(
        icon: Icons.checklist_rtl_rounded,
        label: AppLocalizations.get('quick_record_fms'),
        subtitle: AppLocalizations.get('quick_record_fms_hint'),
        accent: AppColors.coachAccent,
        isLoading: _runningActions.contains('fms'),
        onTap: () => _runQuickAction(context, 'fms', () async {
          final player = await _pickPlayer(context);
          if (player == null || !context.mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FmsAssessmentScreen(
                playerId: player.id, playerName: player.fullName),
          ));
        }),
      ),
      ClubActionTile(
        icon: Icons.monitor_weight_rounded,
        label: AppLocalizations.get('quick_record_body_fat'),
        subtitle: AppLocalizations.get('quick_record_body_fat_hint'),
        accent: AppColors.warning,
        isLoading: _runningActions.contains('body_fat'),
        onTap: () => _runQuickAction(context, 'body_fat', () async {
          final player = await _pickPlayer(context);
          if (player == null || !context.mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BodyCompositionEntryScreen(playerId: player.id),
          ));
        }),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClubSectionLabel(AppLocalizations.get('quick_actions')),
        const SizedBox(height: 8),
        ...List.generate(
          actions.length,
          (index) => Padding(
            padding: EdgeInsets.only(
                bottom: index == actions.length - 1 ? 0 : 8),
            child: actions[index],
          ),
        ),
      ],
    );
  }

  /// Bottom-sheet player picker shared by the FMS / body-fat quick actions.
  Future<ClubPlayer?> _pickPlayer(BuildContext context) {
    String query = '';
    return showModalBottomSheet<ClubPlayer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = _allPlayers.where((p) =>
              query.isEmpty || p.fullName.toLowerCase().contains(query.toLowerCase())).toList();
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.get('reports_choose_player_title'),
                    style: const TextStyle(
                        color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 12),
                TextField(
                  autofocus: true,
                  onChanged: (v) => setSheetState(() => query = v),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.get('search_players'),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted, size: 18),
                    filled: true,
                    fillColor: AppColors.surface2,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(AppLocalizations.get('reports_no_matching_player'),
                              style: const TextStyle(color: AppColors.muted)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final p = filtered[i];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.coachAccent.withOpacity(0.12),
                                child: Text(p.initials,
                                    style: const TextStyle(
                                        color: AppColors.coachAccent,
                                        fontWeight: FontWeight.w700, fontSize: 11)),
                              ),
                              title: Text(p.fullName,
                                  style: const TextStyle(
                                      color: AppColors.foreground,
                                      fontWeight: FontWeight.w600, fontSize: 13)),
                              subtitle: Text(p.position.isEmpty ? '—' : p.position,
                                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              onTap: () => Navigator.pop(ctx, p),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _runQuickAction(
      BuildContext context, String key, Future<void> Function() action) async {
    if (_runningActions.contains(key)) return;
    setState(() => _runningActions.add(key));
    try {
      await action();
    } catch (e) {
      if (mounted) {
        final message = e is StateError
            ? e.message.toString()
            : AppLocalizations.get('quick_action_failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.destructive),
        );
      }
    } finally {
      if (mounted) setState(() => _runningActions.remove(key));
    }
  }

  // ── Quick links to existing physical-monitoring screens ─────────────────

  // ignore: unused_element
  Widget _buildQuickLinks(BuildContext context) {
    return Column(
      children: [
        _linkCard(
          icon: Icons.bar_chart_rounded,
          color: AppColors.primary,
          title: AppLocalizations.get('training_load'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const TeamTrainingLoadReportScreen(),
          )),
        ),
        const SizedBox(height: 10),
        _linkCard(
          icon: Icons.monitor_weight_rounded,
          color: AppColors.coachAccent,
          title: AppLocalizations.get('bc_team_kpi_title'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const BodyCompositionTeamScreen(),
          )),
        ),
        if (canViewDailyReadiness) ...[
          const SizedBox(height: 10),
          _linkCard(
            icon: Icons.checklist_rounded,
            color: AppColors.success,
            title: AppLocalizations.get('daily_readiness_title'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const DailyReadinessScreen(),
            )),
          ),
        ],
      ],
    );
  }

  Widget _linkCard({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
            const Icon(Icons.chevron_left_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

}

class _SessionAttendanceSheet extends StatefulWidget {
  const _SessionAttendanceSheet({
    required this.sessionId,
    required this.sessionName,
  });

  final String sessionId;
  final String sessionName;

  @override
  State<_SessionAttendanceSheet> createState() => _SessionAttendanceSheetState();
}

class _SessionAttendanceSheetState extends State<_SessionAttendanceSheet> {
  List<SessionParticipant> _participants = [];
  final Map<String, String> _attendance = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final participants = await SessionsService.getParticipants(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _participants = participants;
      for (final player in participants) {
        if (player.attendanceStatus != 'pending') {
          _attendance[player.id] = player.attendanceStatus;
        }
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_attendance.isEmpty || _saving) return;
    setState(() => _saving = true);
    final ok = await SessionsService.saveAttendance(widget.sessionId, _attendance);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.get('attendance_save_failed')),
        backgroundColor: AppColors.destructive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.48,
      maxChildSize: 0.94,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.fact_check_rounded,
                    color: AppColors.success,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.get('session_attendance_label'),
                        style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        widget.sessionName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_participants.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      for (final player in _participants) {
                        _attendance[player.id] = 'present';
                      }
                    }),
                    child: Text(AppLocalizations.get('attendance_mark_all_present')),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _participants.isEmpty
                    ? Center(
                        child: Text(
                          AppLocalizations.get('no_players_session'),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        itemCount: _participants.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final player = _participants[index];
                          final selected = _attendance[player.id];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: AppColors.coachAccent.withOpacity(0.12),
                                      child: Text(
                                        player.number > 0
                                            ? '${player.number}'
                                            : player.name.isNotEmpty
                                                ? player.name.substring(0, 1)
                                                : '—',
                                        style: const TextStyle(
                                          color: AppColors.coachAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        player.name,
                                        style: const TextStyle(
                                          color: AppColors.foreground,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      player.position,
                                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 9),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _attendanceChoice(
                                        player.id,
                                        'present',
                                        AppLocalizations.get('attendance_present'),
                                        AppColors.success,
                                        selected,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _attendanceChoice(
                                        player.id,
                                        'late',
                                        AppLocalizations.get('attendance_late'),
                                        AppColors.warning,
                                        selected,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _attendanceChoice(
                                        player.id,
                                        'absent',
                                        AppLocalizations.get('attendance_absent'),
                                        AppColors.destructive,
                                        selected,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          if (!_loading && _participants.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: _attendance.isEmpty || _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(AppLocalizations.get('save_btn')),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _attendanceChoice(
    String playerId,
    String value,
    String label,
    Color color,
    String? selected,
  ) {
    final active = selected == value;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() => _attendance[playerId] = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.14) : AppColors.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? color : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : AppColors.muted,
            fontWeight: FontWeight.w700,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session/match marker for a single day — shared by the day pills and the
// custom calendar sheet so both mark days the same way.
// ─────────────────────────────────────────────────────────────────────────────

class _DayMarker {
  const _DayMarker({
    required this.hasMatch,
    required this.hasSession,
    required this.specialTextColor,
  });
  final bool hasMatch;
  final bool hasSession;
  final Color? specialTextColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom month-calendar bottom sheet — mirrors the day-pill markers (match
// icon, rehab/physical-assessment text colors) that the stock
// showDatePicker() can't render per-day.
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarSheet extends StatefulWidget {
  const _CalendarSheet({
    required this.initialMonth,
    required this.selectedDate,
    required this.markerOf,
  });

  final DateTime initialMonth;
  final DateTime selectedDate;
  final _DayMarker Function(DateTime) markerOf;

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // ISO weekday (1=Mon..7=Sun); AppLocalizations._days order starts Monday.
    final leadingBlanks = firstOfMonth.weekday - 1;
    final totalCells = ((leadingBlanks + daysInMonth) / 7).ceil() * 7;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38, height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1)),
                  child: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      color: AppColors.muted, size: 22),
                ),
                Expanded(
                  child: Text(
                    '${AppLocalizations.monthName(_month.month)} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 15),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1)),
                  child: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      color: AppColors.muted, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var w = 1; w <= 7; w++)
                  Expanded(
                    child: Text(
                      AppLocalizations.weekdayShort(w),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: totalCells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.85,
              ),
              itemBuilder: (context, i) {
                final dayNum = i - leadingBlanks + 1;
                if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox();
                final d = DateTime(_month.year, _month.month, dayNum);
                final isSelected = _sameDay(d, widget.selectedDate);
                final isToday = _sameDay(d, DateTime.now());
                final marker = widget.markerOf(d);
                return GestureDetector(
                  onTap: () => Navigator.pop(context, d),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primarySoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$dayNum',
                            style: TextStyle(
                                color: marker.specialTextColor ??
                                    (isSelected
                                        ? AppColors.maroon
                                        : isToday
                                            ? AppColors.gold
                                            : AppColors.foreground),
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        const SizedBox(height: 2),
                        SizedBox(
                          height: 8,
                          child: marker.hasMatch
                              ? const Icon(Icons.sports_soccer_rounded,
                                  size: 8, color: AppColors.maroon)
                              : marker.hasSession
                                  ? Icon(Icons.fitness_center_rounded,
                                      size: 8,
                                      color: marker.specialTextColor ?? AppColors.gold)
                                  : null,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A session or match, unified for the "upcoming" strip.
// ─────────────────────────────────────────────────────────────────────────────

class _CoachScheduleItem {
  const _CoachScheduleItem._(this.date, this.title, this.isMatch);

  factory _CoachScheduleItem.session(TrainingSession s) =>
      _CoachScheduleItem._(s.date, s.name, false);

  factory _CoachScheduleItem.match(MatchModel m) =>
      _CoachScheduleItem._(m.matchDate, m.opponent, true);

  final DateTime date;
  final String title;
  final bool isMatch;
}

class _CoachDayEvent {
  const _CoachDayEvent._({
    required this.dateTime,
    this.session,
    this.match,
  });

  factory _CoachDayEvent.session(TrainingSession session) =>
      _CoachDayEvent._(
        dateTime: _dateWithTime(session.date, session.startTime),
        session: session,
      );

  factory _CoachDayEvent.match(MatchModel match) => _CoachDayEvent._(
        dateTime: _dateWithTime(match.matchDate, match.matchTime),
        match: match,
      );

  final DateTime dateTime;
  final TrainingSession? session;
  final MatchModel? match;

  static DateTime _dateWithTime(DateTime date, String time) {
    final parts = time.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card meta chip
// ─────────────────────────────────────────────────────────────────────────────

class _CoachHeroMeta extends StatelessWidget {
  const _CoachHeroMeta({
    required this.icon,
    required this.label,
    this.clip = false,
    this.iconColor = AppColors.gold,
    this.textColor = AppColors.onDarkMuted,
    // ignore: unused_element_parameter
    this.iconSize = 12,
    this.fontSize = 10.5,
  });
  final IconData icon;
  final String label;
  final bool clip;
  final Color iconColor;
  final Color textColor;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: iconSize),
        const SizedBox(width: 4),
        clip
            ? Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: textColor,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500),
                    maxLines: 2))
            : Text(label,
                style: TextStyle(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500)),
      ],
    );
    return clip ? Expanded(child: content) : content;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card big stat number (expected/present players)
// ─────────────────────────────────────────────────────────────────────────────

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(
                color: AppColors.onDark,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                height: 1.1)),
        const SizedBox(height: 1),
        Text(label,
            style: const TextStyle(
                color: AppColors.onDarkMuted,
                fontSize: 9,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}
