import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import 'club_widgets.dart';
import 'club_dashboard.dart' show ClubShell;
import 'club_player_profile_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Analyst Dashboard — focused Home tab for the "analyst" org role.
// Strictly read-only (matches api/includes/club_auth.php's clubStaffCan():
// players.read, sessions.read, assessments.read, notes.read, teams.read —
// no *.write anywhere). Team-wide stats plus a searchable roster leading
// into each player's profile in view-only mode — no player/team management,
// no session/match creation, no club settings.
// ─────────────────────────────────────────────────────────────────────────────

class AnalystDashboardPage extends StatefulWidget {
  const AnalystDashboardPage({super.key});

  @override
  State<AnalystDashboardPage> createState() => _AnalystDashboardPageState();
}

class _AnalystDashboardPageState extends State<AnalystDashboardPage> {
  bool _loading = true;
  bool _loadError = false;
  DashboardStats _stats = DashboardStats();
  List<ClubPlayer> _players = [];
  List<TrainingSession> _allSessions = [];
  List<MatchModel> _allMatches = [];
  String _query = '';

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
        ClubService().getDashboardStats(),
        ClubService().getPlayers(),
        ClubService().getSessions(),
        ClubService().getMatches(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as DashboardStats;
        _players = (results[1] as List<ClubPlayer>)
            .where((p) => p.status == PlayerStatus.active)
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
        _allSessions = results[2] as List<TrainingSession>;
        _allMatches = results[3] as List<MatchModel>;
      });
    } catch (e) {
      AppLogger.e('AnalystDashboard', 'Load failed', e);
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<ClubPlayer> get _filtered {
    if (_query.trim().isEmpty) return _players;
    final q = _query.toLowerCase().trim();
    return _players.where((p) => p.fullName.toLowerCase().contains(q)).toList();
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
                title: AppLocalizations.get('role_analyst'),
                subtitle: AppLocalizations.get('nav_dashboard'),
                trailing: const NotificationBellButton(),
              ),
            ),
            SliverToBoxAdapter(
              child: RoleHomeDateStrip(
                markerOf: (date) => RoleDateMarker(
                  hasMatch: _allMatches.any((m) => _sameDay(m.matchDate, date)),
                  hasSession: _allSessions.any((s) => _sameDay(s.date, date)),
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
                    ClubSectionLabel(AppLocalizations.get('nav_players')),
                    const SizedBox(height: 8),
                    _buildSearchField(),
                    const SizedBox(height: 10),
                    ..._filtered.map((p) => _playerRow(context, p)),
                    if (_filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            AppLocalizations.get('no_players_found'),
                            style: const TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ),
                      ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ClubMetricCard(
            icon: Icons.group_rounded,
            value: '${_stats.totalPlayers}',
            label: AppLocalizations.get('nav_players'),
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          ClubMetricCard(
            icon: Icons.sports_rounded,
            value: '${_stats.sessionsToday}',
            label: AppLocalizations.get('session_today_label'),
            color: AppColors.coachAccent,
          ),
          const SizedBox(width: 8),
          ClubMetricCard(
            icon: Icons.assignment_turned_in_rounded,
            value: '${_stats.assessmentsToday}',
            label: AppLocalizations.get('report_tile_assessments_title'),
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          ClubMetricCard(
            icon: Icons.medical_information_rounded,
            value: '${_stats.injuredPlayers}',
            label: AppLocalizations.get('injury_file'),
            color: AppColors.destructive,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(color: AppColors.foreground, fontSize: 14),
      decoration: InputDecoration(
        hintText: AppLocalizations.get('search_players'),
        hintStyle: const TextStyle(color: AppColors.muted),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _playerRow(BuildContext context, ClubPlayer p) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ClubPlayerProfilePage(playerId: p.id),
      )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.bar_chart_rounded, color: AppColors.coachAccent, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.fullName,
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  if ((p.teamName ?? '').isNotEmpty)
                    Text(p.teamName!,
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
