import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import 'club_widgets.dart';
import 'club_dashboard.dart' show ClubShell;
import 'session_detail_page.dart';
import 'match_detail_page.dart';
import 'team_performance_report_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tactical Coach Dashboard — focused Home tab for the "tactical_coach" org
// role. Shows upcoming sessions/matches and the team performance report —
// no medical/physio/nutrition, no team roster edits, no club settings.
// (Players/Sessions/Matches/Reports tabs stay on the shared bottom nav.)
// ─────────────────────────────────────────────────────────────────────────────

class TacticalCoachDashboardPage extends StatefulWidget {
  const TacticalCoachDashboardPage({super.key});

  @override
  State<TacticalCoachDashboardPage> createState() =>
      _TacticalCoachDashboardPageState();
}

class _TacticalCoachDashboardPageState
    extends State<TacticalCoachDashboardPage> {
  bool _loading = true;
  bool _loadError = false;
  List<_ScheduleItem> _upcoming = [];
  int _upcomingSessionsCount = 0;
  int _upcomingMatchesCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final results = await Future.wait([
        ClubService().getSessions(),
        ClubService().getMatches(),
      ]);
      if (!mounted) return;
      final sessions = results[0] as List<TrainingSession>;
      final matches = results[1] as List<MatchModel>;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final items = <_ScheduleItem>[
        for (final s in sessions)
          if (!DateTime(s.date.year, s.date.month, s.date.day).isBefore(today))
            _ScheduleItem.session(s),
        for (final m in matches)
          if (!DateTime(m.matchDate.year, m.matchDate.month, m.matchDate.day)
              .isBefore(today))
            _ScheduleItem.match(m),
      ]..sort((a, b) => a.date.compareTo(b.date));

      setState(() {
        _upcoming = items.take(7).toList();
        _upcomingSessionsCount = items.where((i) => i.session != null).length;
        _upcomingMatchesCount = items.where((i) => i.match != null).length;
      });
    } catch (e) {
      AppLogger.e('TacticalCoachDashboard', 'Load failed', e);
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ClubShell(
      currentIndex: 0,
      child: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.card,
        strokeWidth: 2,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ClubPageHeader(
                title: AppLocalizations.get('role_tactical_coach'),
                subtitle: AppLocalizations.get('nav_dashboard'),
                trailing: const NotificationBellButton(),
              ),
            ),
            SliverToBoxAdapter(
              child: RoleHomeDateStrip(
                markerOf: (date) => RoleDateMarker(
                  hasMatch: _upcoming.any(
                    (item) => item.match != null && _sameDay(item.date, date),
                  ),
                  hasSession: _upcoming.any(
                    (item) => item.session != null && _sameDay(item.date, date),
                  ),
                ),
              ),
            ),
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
                    _buildMetricsRow(),
                    const SizedBox(height: 16),
                    _linkCard(
                      icon: Icons.leaderboard_rounded,
                      color: AppColors.coachAccent,
                      title: AppLocalizations.get('report_tile_assessments_title'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const TeamPerformanceReportScreen(),
                      )),
                    ),
                    const SizedBox(height: 16),
                    _buildUpcomingSection(context),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── KPI row ──────────────────────────────────────────────────────────────

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  Widget _buildMetricsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ClubMetricCard(
            icon: Icons.sports_rounded,
            value: '$_upcomingSessionsCount',
            label: AppLocalizations.get('nav_sessions_tab'),
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          ClubMetricCard(
            icon: Icons.sports_soccer_rounded,
            value: '$_upcomingMatchesCount',
            label: AppLocalizations.get('nav_matches'),
            color: AppColors.coachAccent,
          ),
        ],
      ),
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

  // ── Upcoming sessions + matches ──────────────────────────────────────────

  Widget _buildUpcomingSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClubSectionLabel(AppLocalizations.get('upcoming_title')),
          if (_upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                AppLocalizations.get('no_upcoming_events'),
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            )
          else
            ..._upcoming.map((i) => _upcomingRow(context, i)),
        ],
      ),
    );
  }

  Widget _upcomingRow(BuildContext context, _ScheduleItem item) {
    final isMatch = item.match != null;
    final title = isMatch ? item.match!.opponent : item.session!.name;
    final time = isMatch ? item.match!.matchTime : item.session!.startTime;
    final dateStr =
        '${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => isMatch
            ? MatchDetailPage(matchId: item.match!.id)
            : SessionDetailPage(sessionId: item.session!.id),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              isMatch ? Icons.sports_soccer_rounded : Icons.sports_rounded,
              color: isMatch ? AppColors.coachAccent : AppColors.primary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text('$dateStr · $time',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: AppColors.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ScheduleItem {
  _ScheduleItem.session(this.session) : match = null, date = session!.date;
  _ScheduleItem.match(this.match) : session = null, date = match!.matchDate;

  final TrainingSession? session;
  final MatchModel? match;
  final DateTime date;
}
