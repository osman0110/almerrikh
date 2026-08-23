import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import 'club_widgets.dart';
import 'club_dashboard.dart' show ClubShell;
import 'nutrition_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Nutritionist Dashboard — Home tab for the "nutritionist" org role, same
// shell/header/sidebar/bottom-nav pattern as every other club role. The
// full roster is also reachable via the shared Players tab (like
// physiotherapist), but Home keeps its own searchable shortcut straight
// into each player's nutrition file since that's this role's most common
// action. No injury file, no physio sessions, no club settings — no
// team-wide nutrition data source exists yet (api/club/nutrition.php is
// strictly per-player).
// ─────────────────────────────────────────────────────────────────────────────

class NutritionistDashboardPage extends StatefulWidget {
  const NutritionistDashboardPage({super.key});

  @override
  State<NutritionistDashboardPage> createState() =>
      _NutritionistDashboardPageState();
}

class _NutritionistDashboardPageState
    extends State<NutritionistDashboardPage> {
  bool _loading = true;
  bool _loadError = false;
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
        ClubService().getPlayers(),
        ClubService().getSessions(),
        ClubService().getMatches(),
      ]);
      if (!mounted) return;
      setState(() {
        _players = (results[0] as List<ClubPlayer>)
            .where((p) => p.status == PlayerStatus.active)
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
        _allSessions = results[1] as List<TrainingSession>;
        _allMatches = results[2] as List<MatchModel>;
      });
    } catch (e) {
      AppLogger.e('NutritionistDashboard', 'Load failed', e);
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
                title: AppLocalizations.get('role_nutritionist'),
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
                    ClubMetricCard(
                      icon: Icons.group_rounded,
                      value: '${_players.length}',
                      label: AppLocalizations.get('nav_players'),
                      color: AppColors.primary,
                      width: double.infinity,
                    ),
                    const SizedBox(height: 14),
                    _buildSearchField(),
                    const SizedBox(height: 14),
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
        builder: (_) => NutritionScreen(playerId: p.id, playerName: p.fullName),
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
            const Icon(Icons.restaurant_menu_rounded, color: AppColors.coachAccent, size: 18),
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
