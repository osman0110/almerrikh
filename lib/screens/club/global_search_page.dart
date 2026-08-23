import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../app_state.dart';
import 'club_player_profile_page.dart';
import 'club_widgets.dart';
import 'injury_case_screen.dart';
import 'match_detail_page.dart';
import 'session_detail_page.dart';

/// Unified search across players, sessions, and matches — one text field
/// instead of hunting through separate tabs for each. Reuses the same
/// ClubService lists already loaded elsewhere in the app; this screen just
/// fetches its own copy so it works as a standalone destination.
class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final _controller = TextEditingController();
  String _query = '';
  bool _loading = true;
  bool _error = false;

  List<ClubPlayer> _players = [];
  List<TrainingSession> _sessions = [];
  List<MatchModel> _matches = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      final results = await Future.wait([
        ClubService().getPlayers(),
        ClubService().getSessions(),
        ClubService().getMatches(),
      ]);
      if (!mounted) return;
      setState(() {
        _players  = results[0] as List<ClubPlayer>;
        _sessions = results[1] as List<TrainingSession>;
        _matches  = results[2] as List<MatchModel>;
      });
    } catch (e) {
      AppLogger.e('GlobalSearch', 'Load failed', e);
      if (mounted) setState(() => _error = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<ClubPlayer> get _matchedPlayers {
    final q = _query.toLowerCase();
    return _players.where((p) =>
        p.fullName.toLowerCase().contains(q) ||
        p.position.toLowerCase().contains(q) ||
        p.number.toLowerCase().contains(q)).toList();
  }

  List<TrainingSession> get _matchedSessions {
    final q = _query.toLowerCase();
    return _sessions.where((s) =>
        s.name.toLowerCase().contains(q) ||
        s.coachName.toLowerCase().contains(q) ||
        (s.location ?? '').toLowerCase().contains(q)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<MatchModel> get _matchedMatches {
    final q = _query.toLowerCase();
    return _matches.where((m) =>
        m.opponent.toLowerCase().contains(q) ||
        (m.location ?? '').toLowerCase().contains(q)).toList()
      ..sort((a, b) => b.matchDate.compareTo(a.matchDate));
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.trim().isNotEmpty;
    final players = hasQuery ? _matchedPlayers : const <ClubPlayer>[];
    final sessions = hasQuery ? _matchedSessions : const <TrainingSession>[];
    final matches = hasQuery ? _matchedMatches : const <MatchModel>[];
    final totalResults = players.length + sessions.length + matches.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            ClubPageHeader(
              title: AppLocalizations.get('global_search_title'),
              onBack: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                decoration: InputDecoration(
                  hintText: AppLocalizations.get('global_search_hint'),
                  hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
                  suffixIcon: hasQuery
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.muted, size: 18),
                          onPressed: () => setState(() {
                            _controller.clear();
                            _query = '';
                          }),
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _error
                      ? _buildErrorState()
                      : !hasQuery
                          ? _buildPrompt()
                          : totalResults == 0
                              ? _buildNoResults()
                              : _buildResults(players, sessions, matches),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_rounded, color: AppColors.muted, size: 40),
            const SizedBox(height: 12),
            Text(AppLocalizations.get('global_search_prompt'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, color: AppColors.muted, size: 40),
            const SizedBox(height: 12),
            Text(AppLocalizations.get('global_search_no_results'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.destructive, size: 32),
            const SizedBox(height: 10),
            Text(AppLocalizations.get('error_server_connect'),
                style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: Text(AppLocalizations.get('try_again'),
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(
    List<ClubPlayer> players,
    List<TrainingSession> sessions,
    List<MatchModel> matches,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (players.isNotEmpty) ...[
          _sectionHeader(AppLocalizations.format('global_search_players_section', {'count': '${players.length}'})),
          ...players.map(_buildPlayerTile),
          const SizedBox(height: 16),
        ],
        if (sessions.isNotEmpty) ...[
          _sectionHeader(AppLocalizations.format('global_search_sessions_section', {'count': '${sessions.length}'})),
          ...sessions.map(_buildSessionTile),
          const SizedBox(height: 16),
        ],
        if (matches.isNotEmpty) ...[
          _sectionHeader(AppLocalizations.format('global_search_matches_section', {'count': '${matches.length}'})),
          ...matches.map(_buildMatchTile),
        ],
      ],
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(
              color: AppColors.maroon, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(
              color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      );

  Widget _resultTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _buildPlayerTile(ClubPlayer p) {
    return _resultTile(
      icon: Icons.person_rounded,
      color: AppColors.coachAccent,
      title: p.fullName,
      subtitle: p.position.isEmpty ? '—' : p.position,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => isDoctorRole
            ? InjuryCaseScreen(playerId: p.id, playerName: p.fullName)
            : ClubPlayerProfilePage(playerId: p.id),
      )),
    );
  }

  Widget _buildSessionTile(TrainingSession s) {
    return _resultTile(
      icon: Icons.fitness_center_rounded,
      color: AppColors.primary,
      title: s.name,
      subtitle: '${_fmtDate(s.date)} · ${s.startTime}',
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SessionDetailPage(sessionId: s.id))),
    );
  }

  Widget _buildMatchTile(MatchModel m) {
    return _resultTile(
      icon: Icons.sports_soccer_rounded,
      color: AppColors.maroon,
      title: '${AppLocalizations.get('vs_label')} ${m.opponent}',
      subtitle: '${_fmtDate(m.matchDate)} · ${m.matchTime}',
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MatchDetailPage(matchId: m.id))),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
