import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Match output, including goals and assists, filterable by season/competition.
// Shown in the unified club player profile for roles allowed to read sessions
// and competitions; not shown on clinical-only views or coach report screens.
// ─────────────────────────────────────────────────────────────────────────────

class CompetitionStatsSection extends StatefulWidget {
  const CompetitionStatsSection({super.key, required this.playerId});
  final String playerId;

  @override
  State<CompetitionStatsSection> createState() =>
      _CompetitionStatsSectionState();
}

class _CompetitionStatsSectionState extends State<CompetitionStatsSection>
    with AutomaticKeepAliveClientMixin {
  List<PlayerCompetitionStats> _stats = [];
  List<ClubSeason> _seasons = [];
  List<ClubCompetition> _competitions = [];
  int? _selectedSeasonId;
  int? _selectedCompetitionId;
  bool _loading = true;
  bool _initialized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ClubService();
    final results = await Future.wait([
      service.getSeasons(),
      service.getCompetitions(),
    ]);
    final seasons = results[0] as List<ClubSeason>;
    final competitions = results[1] as List<ClubCompetition>;
    final selectedSeasonId =
        seasons.where((season) => season.isActive).firstOrNull?.id;
    final stats = await _fetchStats(
      seasons: seasons,
      seasonId: selectedSeasonId,
    );
    if (mounted) {
      setState(() {
        _seasons = seasons;
        _competitions = competitions;
        _selectedSeasonId = selectedSeasonId;
        _stats = stats;
        _loading = false;
        _initialized = true;
      });
    }
  }

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<List<PlayerCompetitionStats>> _fetchStats({
    required List<ClubSeason> seasons,
    int? seasonId,
    int? competitionId,
  }) {
    final season = seasonId == null
        ? null
        : seasons.where((item) => item.id == seasonId).firstOrNull;
    return ClubService().getPlayerMatchStatsByCompetition(
      widget.playerId,
      seasonId: seasonId,
      competitionId: competitionId,
      from: season == null ? '2000-01-01' : _date(season.startsOn),
      to: season == null ? _date(DateTime.now()) : _date(season.endsOn),
    );
  }

  Future<void> _selectSeason(int? seasonId) async {
    if (_selectedSeasonId == seasonId) return;
    setState(() {
      _selectedSeasonId = seasonId;
      _selectedCompetitionId = null;
      _loading = true;
    });
    final stats = await _fetchStats(seasons: _seasons, seasonId: seasonId);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _selectCompetition(int? competitionId) async {
    if (_selectedCompetitionId == competitionId) return;
    setState(() {
      _selectedCompetitionId = competitionId;
      _loading = true;
    });
    final stats = await _fetchStats(
      seasons: _seasons,
      seasonId: _selectedSeasonId,
      competitionId: competitionId,
    );
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  List<ClubCompetition> get _visibleCompetitions =>
      _selectedSeasonId == null
      ? _competitions
      : _competitions
            .where((item) => item.seasonId == _selectedSeasonId)
            .toList();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_initialized) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildFilters(),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          )
        else if (_stats.isEmpty)
          _emptyState()
        else
          ..._stats.map(
            (stats) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _competitionCard(stats),
            ),
          ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_month_rounded,
                color: AppColors.primary,
                size: 14,
              ),
              const SizedBox(width: 5),
              Text(
                AppLocalizations.get('season_label'),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _filterRow(
            selectedId: _selectedSeasonId,
            allLabel: AppLocalizations.get('all_seasons_label'),
            items: _seasons.map((item) => (item.id, item.name)).toList(),
            onSelect: _selectSeason,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: AppColors.primary,
                size: 14,
              ),
              const SizedBox(width: 5),
              Text(
                AppLocalizations.get('competition_label'),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _filterRow(
            selectedId: _selectedCompetitionId,
            allLabel: AppLocalizations.get('all_competitions_label'),
            items: _visibleCompetitions
                .map((item) => (item.id, item.name))
                .toList(),
            onSelect: _selectCompetition,
          ),
        ],
      ),
    );
  }

  Widget _filterRow({
    required int? selectedId,
    required String allLabel,
    required List<(int, String)> items,
    required ValueChanged<int?> onSelect,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(
            label: allLabel,
            selected: selectedId == null,
            onTap: () => onSelect(null),
          ),
          for (final item in items) ...[
            const SizedBox(width: 7),
            _filterChip(
              label: item.$2,
              selected: selectedId == item.$1,
              onTap: () => onSelect(item.$1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.13)
              : AppColors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.muted,
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.emoji_events_outlined,
            color: AppColors.muted,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.get('match_empty_title'),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _competitionCard(PlayerCompetitionStats s) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded,
                  color: AppColors.primary, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.competitionName,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${s.appearances} مباراة',
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat(
                  'الدقائق',
                  '${s.totalMinutes}',
                  icon: Icons.timer_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stat(
                  'أساسي',
                  '${s.starts}',
                  icon: Icons.play_circle_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stat(
                  'بديل',
                  '${s.subAppearances}',
                  icon: Icons.swap_horiz_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _stat(
                  AppLocalizations.get('match_goals_label'),
                  '${s.goals}',
                  icon: Icons.sports_soccer_rounded,
                  color: s.goals > 0 ? AppColors.primary : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stat(
                  AppLocalizations.get('match_assists_label'),
                  '${s.assists}',
                  icon: Icons.share_rounded,
                  color: s.assists > 0 ? AppColors.success : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _stat('كروت صفراء', '${s.yellowCards}',
                    icon: Icons.style_rounded,
                    color: s.yellowCards > 0 ? AppColors.warning : null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stat('كروت حمراء', '${s.redCards}',
                    icon: Icons.style_rounded,
                    color: s.redCards > 0 ? AppColors.destructive : null),
              ),
            ],
          ),
          if (s.activeSuspensions > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.destructive.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.destructive.withOpacity(0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.block_rounded, color: AppColors.destructive, size: 15),
                const SizedBox(width: 6),
                Text('إيقاف نشط: ${s.matchesRemaining} مباراة متبقية',
                    style: const TextStyle(color: AppColors.destructive, fontSize: 11, fontWeight: FontWeight.w800)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(
    String label,
    String value, {
    IconData? icon,
    Color? color,
  }) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: color ?? AppColors.muted, size: 12),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                color: color ?? AppColors.foreground,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}
