import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import 'club_dashboard.dart';
import 'club_widgets.dart';
import 'match_form_page.dart';
import 'match_detail_page.dart';

class MatchListPage extends StatefulWidget {
  const MatchListPage({super.key});

  @override
  State<MatchListPage> createState() => _MatchListPageState();
}

class _MatchListPageState extends State<MatchListPage> {
  List<MatchModel> _all = [];
  bool _loading = false;
  String _statusFilter = 'all';
  String? _competitionFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final matches = await ClubService().getMatches();
      if (mounted) setState(() => _all = matches);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<String> get _competitionNames {
    final names = _all
        .map((m) => m.competitionName)
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  List<MatchModel> get _filtered {
    return _all.where((m) {
      if (_statusFilter != 'all' && m.status != _statusFilter) return false;
      if (_competitionFilter != null && m.competitionName != _competitionFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final showFilters = !_loading && _all.isNotEmpty;
    return ClubShell(
      currentIndex: 3,
      child: Column(
        children: [
          const CoachBrandHeader(),
          _buildHeader(),
          if (showFilters) _buildFilters(),
          if (showFilters && _competitionNames.isNotEmpty) _buildCompetitionFilters(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.card,
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _all.isEmpty
                      ? _buildEmpty()
                      : _filtered.isEmpty
                      ? _buildNoFilterResults()
                      : _buildGroupedList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return ClubSectionTitle(
      icon: Icons.sports_soccer_rounded,
      title: AppLocalizations.format('match_list_title', {'count': _all.length}),
      trailing: canCreateMatches
          ? GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MatchFormPage()),
                );
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, color: Color(0xFF3A2A08), size: 16),
                  const SizedBox(width: 4),
                  Text(AppLocalizations.get('match_new_btn'),
                      style: const TextStyle(
                          color: Color(0xFF3A2A08),
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                ]),
              ),
            )
          : null,
    );
  }

  Widget _buildFilters() {
    final filters = [
      ('all',       AppLocalizations.get('match_filter_all')),
      ('scheduled', AppLocalizations.get('match_filter_scheduled')),
      ('completed', AppLocalizations.get('match_filter_completed')),
      ('cancelled', AppLocalizations.get('match_filter_cancelled')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: filters.map((f) {
          final active = _statusFilter == f.$1;
          final count =
              f.$1 == 'all' ? _all.length : _all.where((m) => m.status == f.$1).length;
          return GestureDetector(
            onTap: () => setState(() => _statusFilter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.primarySoft : AppColors.surface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: active ? AppColors.primary : AppColors.border,
                    width: 1.4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(f.$2,
                      style: TextStyle(
                          color: active ? AppColors.maroon : AppColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5)),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.maroon.withOpacity(0.14)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                            color: active ? AppColors.maroon : AppColors.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 9.5)),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCompetitionFilters() {
    final competitions = _competitionNames;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          _competitionChip(
            label: AppLocalizations.get('match_all_competitions'),
            active: _competitionFilter == null,
            onTap: () => setState(() => _competitionFilter = null),
          ),
          ...competitions.map(
            (name) => _competitionChip(
              label: name,
              active: _competitionFilter == name,
              onTap: () => setState(() => _competitionFilter = name),
            ),
          ),
        ],
      ),
    );
  }

  Widget _competitionChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.maroon : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: active ? AppColors.maroon : AppColors.border, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_rounded,
                color: active ? Colors.white : AppColors.muted, size: 13),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.white : AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList() {
    final noCompetitionLabel = AppLocalizations.get('match_no_competition');
    final groups = <String, List<MatchModel>>{};
    for (final m in _filtered) {
      final name = m.competitionName;
      final key = (name == null || name.trim().isEmpty) ? noCompetitionLabel : name;
      groups.putIfAbsent(key, () => []).add(m);
    }
    for (final matches in groups.values) {
      matches.sort((a, b) => b.matchDate.compareTo(a.matchDate));
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == noCompetitionLabel) return 1;
        if (b == noCompetitionLabel) return -1;
        return a.compareTo(b);
      });
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final key = keys[i];
        final matches = groups[key]!;
        final label = key;
        return Padding(
          padding: EdgeInsets.only(bottom: i == keys.length - 1 ? 0 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.emoji_events_rounded,
                        color: AppColors.maroon, size: 11),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 4),
                  Text('(${matches.length})',
                      style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 10)),
                ],
              ),
              const SizedBox(height: 9),
              ...matches.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MatchCard(
                    match: m,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => MatchDetailPage(matchId: m.id)),
                      );
                      _load();
                    },
                    onEdit: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => MatchFormPage(matchId: m.id)),
                      );
                      _load();
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return ClubEmptyState(
      icon: Icons.sports_soccer_rounded,
      title: AppLocalizations.get('match_empty_title'),
      description: AppLocalizations.get('match_empty_subtitle'),
      ctaLabel: canCreateMatches ? AppLocalizations.get('match_create_first') : null,
      onCta: canCreateMatches
          ? () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MatchFormPage()),
              );
              _load();
            }
          : null,
    );
  }

  Widget _buildNoFilterResults() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off_rounded, color: AppColors.muted, size: 40),
        const SizedBox(height: 12),
        Text(AppLocalizations.get('no_filter_match'),
            style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _statusFilter = 'all'),
          child: Text(AppLocalizations.get('clear_filters'),
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Match Card
// ─────────────────────────────────────────────────────────────────────────────

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.onTap,
    required this.onEdit,
  });

  final MatchModel match;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final statusColor = match.status == 'completed'
        ? AppColors.success
        : match.status == 'cancelled'
            ? AppColors.destructive
            : AppColors.warning;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 3))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: statusColor),
                // Date block — weekday / day / month, tinted by match status.
                Container(
                  width: 56,
                  color: statusColor.withOpacity(0.06),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(AppLocalizations.weekdayShort(match.matchDate.weekday),
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                              fontSize: 8.5)),
                      Text('${match.matchDate.day}',
                          style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              height: 1.1)),
                      Text(AppLocalizations.monthName(match.matchDate.month),
                          style: const TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w500,
                              fontSize: 8.5)),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: AppColors.card,
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                                AppLocalizations.format(
                                    'match_vs', {'opponent': match.opponent}),
                                style: const TextStyle(
                                    color: AppColors.foreground,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (canManageMatches) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: onEdit,
                              child: const Icon(Icons.edit_rounded,
                                  color: AppColors.primary, size: 15),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 5),
                        if (match.competitionName != null || match.location != null) ...[
                          Row(children: [
                            if (match.competitionName != null) ...[
                              const Icon(Icons.emoji_events_rounded,
                                  color: AppColors.muted, size: 11),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(match.competitionName!,
                                    style: const TextStyle(
                                        color: AppColors.muted, fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                            if (match.competitionName != null && match.location != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: const BoxDecoration(
                                    color: AppColors.border, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (match.location != null) ...[
                              const Icon(Icons.location_on_rounded,
                                  color: AppColors.muted, size: 11),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(match.location!,
                                    style: const TextStyle(
                                        color: AppColors.muted, fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 5),
                        ],
                        Row(children: [
                          const Icon(Icons.people_rounded,
                              color: AppColors.muted, size: 12),
                          const SizedBox(width: 4),
                          Text(
                              AppLocalizations.format('match_players_count',
                                  {'count': match.playerIds.length}),
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 10)),
                          if (match.wellnessRequired || match.rpeRequired) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.poll_rounded,
                                color: AppColors.primary, size: 12),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                  [
                                    if (match.wellnessRequired)
                                      AppLocalizations.get('match_wellness_badge'),
                                    if (match.rpeRequired)
                                      AppLocalizations.get('match_rpe_badge'),
                                  ].join(' · '),
                                  style: const TextStyle(
                                      color: AppColors.primary, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ]),
                        if (match.notes != null && match.notes!.trim().isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Row(children: [
                            const Icon(Icons.sticky_note_2_rounded,
                                color: AppColors.muted, size: 11),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(match.notes!.trim(),
                                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              const Icon(Icons.schedule_rounded,
                                  color: AppColors.muted, size: 12),
                              const SizedBox(width: 4),
                              Text(match.matchTime,
                                  style: const TextStyle(
                                      color: AppColors.foreground,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5)),
                            ]),
                            Container(
                              height: 17,
                              padding: const EdgeInsets.symmetric(horizontal: 9),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                        color: statusColor, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(match.statusLabel,
                                      style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 8.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
