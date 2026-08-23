import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import 'daily_readiness_screen.dart';

int? _nullableInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

Color _compositeColor(String status) {
  switch (status) {
    case 'ready': return AppColors.success;
    case 'ready_with_note': return AppColors.warning;
    case 'high_strain': return AppColors.destructive;
    case 'injured': return AppColors.destructive;
    case 'rehab': return AppColors.primary;
    default: return AppColors.textSoft;
  }
}

IconData _compositeIcon(String status) {
  switch (status) {
    case 'ready':
      return Icons.check_circle_rounded;
    case 'ready_with_note':
      return Icons.info_rounded;
    case 'high_strain':
      return Icons.warning_amber_rounded;
    case 'injured':
      return Icons.healing_rounded;
    case 'rehab':
      return Icons.replay_circle_filled_rounded;
    default:
      return Icons.help_rounded;
  }
}

String _compositeLabel(String status) {
  switch (status) {
    case 'ready': return AppLocalizations.get('status_ready');
    case 'ready_with_note': return AppLocalizations.get('composite_ready_with_note');
    case 'high_strain': return AppLocalizations.get('composite_high_strain');
    case 'injured': return AppLocalizations.get('status_injured');
    case 'rehab': return AppLocalizations.get('status_recovering');
    default: return AppLocalizations.get('composite_incomplete_data');
  }
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _InlineStat extends StatelessWidget {
  const _InlineStat({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

enum _Period { allTime, last30, last90 }

/// Admin/org-level dashboard section — composite player status counts,
/// medical/massage session counts, upcoming events for the selected date,
/// plus a season/competition-filterable minutes/goals/assists/cards/matches
/// breakdown where every stat tile drills down into the players and matches
/// behind it. Embedded directly in ClubDashboardPage for isOrgAdmin users
/// (no separate page/navigation — see club_dashboard.dart).
class AdminDashboardSection extends StatefulWidget {
  const AdminDashboardSection({
    super.key,
    required this.selectedDate,
    this.notTrainingCount,
  });

  final DateTime selectedDate;
  /// Players not training today — computed by ClubDashboardPage from
  /// already-loaded wellness data, passed in so this section doesn't need
  /// a redundant fetch. Rendered as an extra tile in the status grid.
  final int? notTrainingCount;

  @override
  State<AdminDashboardSection> createState() => _AdminDashboardSectionState();
}

class _AdminDashboardSectionState extends State<AdminDashboardSection> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _details;
  List<ClubSeason> _seasons = [];
  List<ClubCompetition> _competitions = [];
  int? _selectedSeasonId;
  int? _selectedCompetitionId;
  _Period _period = _Period.allTime;
  bool _loading = true;
  bool _detailsLoading = false;
  bool _loadError = false;
  bool _detailsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AdminDashboardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldDate = oldWidget.selectedDate;
    final newDate = widget.selectedDate;
    if (oldDate.year != newDate.year ||
        oldDate.month != newDate.month ||
        oldDate.day != newDate.day) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    final results = await Future.wait([
      ClubService().getAdminDashboard(date: _fmtDate(widget.selectedDate)),
      ClubService().getSeasons(),
      ClubService().getCompetitions(),
    ]);
    if (!mounted) return;
    final dashboard = results[0] as Map<String, dynamic>?;
    final seasons = results[1] as List<ClubSeason>;
    _selectedSeasonId ??= seasons.where((s) => s.isActive).firstOrNull?.id;
    setState(() {
      _data = dashboard;
      _seasons = seasons;
      _competitions = results[2] as List<ClubCompetition>;
      _loadError = dashboard == null;
      _loading = false;
    });
    if (dashboard != null) await _loadDetails();
  }

  List<ClubCompetition> get _competitionsForSelectedSeason => _selectedSeasonId == null
      ? _competitions
      : _competitions.where((c) => c.seasonId == _selectedSeasonId).toList();

  Future<void> _loadDetails() async {
    setState(() {
      _detailsLoading = true;
      _detailsError = false;
      _details = null;
    });
    String? from, to;
    if (_selectedSeasonId != null) {
      final season = _seasons.where((s) => s.id == _selectedSeasonId).firstOrNull;
      if (season != null) {
        from = _fmtDate(season.startsOn);
        to = _fmtDate(season.endsOn);
      }
    } else {
      final rangeEnd = widget.selectedDate;
      switch (_period) {
        case _Period.last30:
          from = _fmtDate(rangeEnd.subtract(const Duration(days: 30)));
          to = _fmtDate(rangeEnd);
          break;
        case _Period.last90:
          from = _fmtDate(rangeEnd.subtract(const Duration(days: 90)));
          to = _fmtDate(rangeEnd);
          break;
        case _Period.allTime:
          from = null;
          break;
      }
    }
    final res = await ClubService().getAdminDashboardDetails(
      seasonId: _selectedSeasonId,
      competitionId: _selectedCompetitionId,
      from: from,
      to: to,
    );
    if (!mounted) return;
    setState(() {
      _details = res;
      _detailsError = res == null;
      _detailsLoading = false;
    });
  }

  Future<void> _openPlayers([String? initialFilter]) async {
    await Navigator.of(context).pushNamed(
      '/club/players',
      arguments: {
        if (initialFilter != null) 'initialFilter': initialFilter,
      },
    );
    if (mounted) _load();
  }

  void _selectSeason(int? seasonId) {
    if (_selectedSeasonId == seasonId) return;
    setState(() {
      _selectedSeasonId = seasonId;
      _selectedCompetitionId = null;
    });
    _loadDetails();
  }

  void _selectCompetition(int? competitionId) {
    if (_selectedCompetitionId == competitionId) return;
    setState(() => _selectedCompetitionId = competitionId);
    _loadDetails();
  }

  void _selectPeriod(_Period period) {
    if (_period == period) return;
    setState(() => _period = period);
    _loadDetails();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
        ),
      );
    }
    if (_loadError || _data == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.destructive.withOpacity(0.35)),
        ),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppColors.destructive, size: 30),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.get('admin_data_load_failed'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.get('retry')),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUpcomingCard(),
        const SizedBox(height: 14),
        _buildCompositeGrid(),
        const SizedBox(height: 14),
        _buildQuickActions(),
        const SizedBox(height: 14),
        _buildPerformanceSection(),
      ],
    );
  }

  Widget _buildAttentionContent() {
    final items = ((_data?['attention_items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) => ((item['count'] as num?)?.toInt() ?? 0) > 0)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.gavel_rounded,
              color: AppColors.warning,
              size: 18,
            ),
            const SizedBox(width: 7),
            Text(
              AppLocalizations.get('admin_attention_title'),
              style: const TextStyle(
                color: AppColors.foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        if (items.isEmpty)
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.get('admin_no_attention'),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _attentionRow(items[i]),
                if (i != items.length - 1)
                  const Divider(height: 1, color: AppColors.border),
              ],
            ],
          ),
      ],
    );
  }

  Widget _attentionRow(Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? '';
    final count = (item['count'] as num?)?.toInt() ?? 0;
    final (icon, color, label) = switch (type) {
      'injuries' => (
          Icons.healing_rounded,
          AppColors.destructive,
          AppLocalizations.get('attention_injuries')
        ),
      'missing_check_in' => (
          Icons.assignment_late_rounded,
          AppColors.warning,
          AppLocalizations.get('attention_missing_checkin')
        ),
      'overdue_tasks' => (
          Icons.task_alt_rounded,
          AppColors.destructive,
          AppLocalizations.get('attention_overdue_tasks')
        ),
      _ => (
          Icons.medical_services_rounded,
          AppColors.primary,
          AppLocalizations.get('attention_physio_today')
        ),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        final route = item['route']?.toString() ?? '';
        final filter = item['filter']?.toString();
        if (route == '/club/players') {
          _openPlayers(filter);
        } else if (route.isNotEmpty) {
          Navigator.of(context).pushNamed(route);
        }
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPerformanceSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.muted,
        title: Text(
          AppLocalizations.get('admin_performance_section_title'),
          style: const TextStyle(
            color: AppColors.foreground,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          AppLocalizations.get('admin_performance_section_subtitle'),
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
          ),
        ),
        children: [
          _buildFilterBar(),
          const SizedBox(height: 12),
          _buildTotalsCard(),
          if (_selectedCompetitionId == null) ...[
            const SizedBox(height: 12),
            _buildCompetitionsBreakdown(),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = <(IconData, String, String, Color)>[
      (
        Icons.account_tree_rounded,
        AppLocalizations.get('team_management'),
        '/club/teams',
        AppColors.primary,
      ),
      (
        Icons.emoji_events_rounded,
        AppLocalizations.get('competition_management_title'),
        '/club/classification',
        AppColors.success,
      ),
      (
        Icons.manage_accounts_rounded,
        AppLocalizations.get('staff_title'),
        '/club/staff',
        AppColors.warning,
      ),
      (
        Icons.groups_rounded,
        AppLocalizations.get('players_title'),
        '/club/players',
        AppColors.playerAccent,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.get('quick_actions'),
          style: const TextStyle(
            color: AppColors.foreground,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 9),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 4 : 2;
            final width =
                (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: width,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        await Navigator.of(context).pushNamed(action.$3);
                        if (mounted) _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: action.$4.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: action.$4.withOpacity(0.20),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(action.$1, color: action.$4, size: 19),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                action.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(
                              Directionality.of(context) ==
                                      TextDirection.rtl
                                  ? Icons.chevron_left_rounded
                                  : Icons.chevron_right_rounded,
                              color: AppColors.muted,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child, Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(title, style: const TextStyle(
                color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _statTile(
    String value,
    String label,
    Color color, {
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final tile = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: color, size: 15),
                const SizedBox(width: 5),
              ],
              Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w600),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
    if (onTap == null) return tile;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: tile),
    );
  }

  Widget _buildCompositeGrid() {
    final counts = (_data!['composite_counts'] as Map?)?.cast<String, dynamic>() ?? {};
    final medical = (_data!['medical'] as Map?)?.cast<String, dynamic>() ?? {};
    final openCases = int.tryParse('${medical['open_injury_cases'] ?? 0}') ?? 0;
    final physioSessions =
        int.tryParse('${medical['physio_sessions_today'] ?? 0}') ?? 0;
    const order = ['ready', 'ready_with_note', 'high_strain', 'injured', 'rehab', 'incomplete_data'];
    return _sectionCard(
      title: AppLocalizations.get('team_status_today'),
      trailing: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DailyReadinessScreen(),
          ),
        ),
        child: Text(AppLocalizations.get('view_details_btn')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 700
                  ? 4
                  : constraints.maxWidth >= 330
                  ? 3
                  : 2;
              final tileWidth =
                  (constraints.maxWidth - (columns - 1) * 6) / columns;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...order.map((key) {
                    final count = int.tryParse('${counts[key] ?? 0}') ?? 0;
                    final color = _compositeColor(key);
                    return SizedBox(
                      width: tileWidth,
                      child: _statusTile(
                        count: count,
                        label: _compositeLabel(key),
                        color: color,
                        icon: _compositeIcon(key),
                        onTap: () {
                          final filter = switch (key) {
                            'ready' => 'ready',
                            'high_strain' => 'high_strain',
                            'injured' || 'rehab' => 'injured',
                            'incomplete_data' => 'missing_wellness',
                            _ => null,
                          };
                          _openPlayers(filter);
                        },
                      ),
                    );
                  }),
                  if (widget.notTrainingCount != null)
                    SizedBox(
                      width: tileWidth,
                      child: _statusTile(
                        count: widget.notTrainingCount!,
                        label: AppLocalizations.get('status_not_training'),
                        color: AppColors.textSoft,
                        icon: Icons.person_off_rounded,
                      ),
                    ),
                  SizedBox(
                    width: tileWidth,
                    child: _statusTile(
                      count: openCases,
                      label: AppLocalizations.get('open_injury_cases_label'),
                      color: AppColors.destructive,
                      icon: Icons.healing_rounded,
                      onTap: () => _openPlayers('injured'),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _statusTile(
                      count: physioSessions,
                      label: AppLocalizations.get('physio_sessions_today_label'),
                      color: AppColors.primary,
                      icon: Icons.medical_services_rounded,
                      onTap: () =>
                          Navigator.of(context).pushNamed('/club/reports'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          _buildAttentionContent(),
        ],
      ),
    );
  }

  Widget _statusTile({
    required int count,
    required String label,
    required Color color,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.16)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
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

  // ── Season / competition / period filter bar ─────────────────────────────

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
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
              const Icon(Icons.tune_rounded, color: AppColors.primary, size: 16),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.get('reports_filters_label'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildChipRow<int?>(
            selected: _selectedSeasonId,
            onSelect: _selectSeason,
            items: [
              (null, AppLocalizations.get('all_seasons_label')),
              for (final s in _seasons) (s.id, s.name),
            ],
          ),
          const SizedBox(height: 8),
          _buildChipRow<int?>(
            selected: _selectedCompetitionId,
            onSelect: _selectCompetition,
            items: [
              (null, AppLocalizations.get('all_competitions_label')),
              for (final c in _competitionsForSelectedSeason) (c.id, c.name),
            ],
          ),
          if (_selectedSeasonId == null) ...[
            const SizedBox(height: 8),
            _buildChipRow<_Period>(
              selected: _period,
              onSelect: _selectPeriod,
              items: [
                (_Period.allTime, AppLocalizations.get('all_time_label')),
                (_Period.last30, AppLocalizations.get('last_30_days_label')),
                (_Period.last90, AppLocalizations.get('last_90_days_label')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChipRow<T>({
    required T selected,
    required void Function(T) onSelect,
    required List<(T, String)> items,
  }) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (value, label) = items[i];
          final isSelected = value == selected;
          return GestureDetector(
            onTap: () => onSelect(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary.withOpacity(0.14) : AppColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 1.4 : 1),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: isSelected ? AppColors.primary : AppColors.muted,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600)),
            ),
          );
        },
      ),
    );
  }

  // ── Tappable totals ───────────────────────────────────────────────────────

  Widget _buildTotalsCard() {
    if (_detailsLoading && _details == null) {
      return const SizedBox(
        height: 110,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (_detailsError) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.destructive.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.destructive.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.destructive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.get('admin_performance_load_failed'),
                style: const TextStyle(color: AppColors.foreground),
              ),
            ),
            TextButton(
              onPressed: _loadDetails,
              child: Text(AppLocalizations.get('retry')),
            ),
          ],
        ),
      );
    }
    final totals = (_details?['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    final byPlayer = (_details?['by_player'] as List?)?.cast<dynamic>() ?? [];
    final matches = (_details?['matches'] as List?)?.cast<dynamic>() ?? [];

    final minutes = totals['total_minutes'] ?? 0;
    final goals   = totals['goals'] ?? 0;
    final assists = totals['assists'] ?? 0;
    final yellow  = totals['yellow_cards'] ?? 0;
    final red     = totals['red_cards'] ?? 0;
    final matchCount = totals['matches'] ?? 0;
    final matchesWithData = totals['matches_with_player_data'] ?? 0;

    void openBreakdown(String sortKey, String title) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PlayerBreakdownPage(
          title: title,
          players: byPlayer,
          matches: matches,
          sortKey: sortKey,
        ),
      ));
    }

    return _sectionCard(
      title: AppLocalizations.get('team_summary_title'),
      trailing: _detailsLoading
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.format('admin_match_data_coverage', {
              'complete': '$matchesWithData',
              'total': '$matchCount',
            }),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 620 ? 3 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
              SizedBox(
                width: width,
                child: _statTile('$minutes', AppLocalizations.get('total_minutes_label'), AppColors.foreground,
                    icon: Icons.timer_outlined,
                    onTap: () => openBreakdown('total_minutes', AppLocalizations.get('total_minutes_label'))),
              ),
              SizedBox(
                width: width,
                child: _statTile('$goals', AppLocalizations.get('match_goals_label'), AppColors.primary,
                    icon: Icons.sports_soccer_rounded,
                    onTap: () => openBreakdown('goals', AppLocalizations.get('match_goals_label'))),
              ),
              SizedBox(
                width: width,
                child: _statTile('$assists', AppLocalizations.get('match_assists_label'), AppColors.success,
                    icon: Icons.share_rounded,
                    onTap: () => openBreakdown('assists', AppLocalizations.get('match_assists_label'))),
              ),
              SizedBox(
                width: width,
                child: _statTile('$yellow', AppLocalizations.get('yellow_cards_label'), AppColors.warning,
                    icon: Icons.style_rounded,
                    onTap: () => openBreakdown('yellow_cards', AppLocalizations.get('yellow_cards_label'))),
              ),
              SizedBox(
                width: width,
                child: _statTile('$red', AppLocalizations.get('red_cards_label'), AppColors.destructive,
                    icon: Icons.style_rounded,
                    onTap: () => openBreakdown('red_cards', AppLocalizations.get('red_cards_label'))),
              ),
              SizedBox(
                width: width,
                child: _statTile('$matchCount', AppLocalizations.get('total_matches_label'), AppColors.primary,
                    icon: Icons.event_rounded,
                    onTap: () => openBreakdown('matches', AppLocalizations.get('total_matches_label'))),
              ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompetitionsBreakdown() {
    final rows = (_details?['by_competition'] as List?)?.cast<dynamic>() ?? [];
    if (rows.isEmpty) return const SizedBox.shrink();

    return _sectionCard(
      title: AppLocalizations.get('all_competitions_label'),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Builder(
              builder: (context) {
                final row = (rows[i] as Map).cast<String, dynamic>();
                final name = (row['competition_name'] as String?)?.trim();
                final label = (name == null || name.isEmpty)
                    ? AppLocalizations.get('competition_label')
                    : name;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _selectCompetition(
                    _nullableInt(row['competition_id']),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.emoji_events_rounded,
                                color: AppColors.primary,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: AppColors.foreground,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 3,
                                    children: [
                                      _InlineStat(
                                        icon: Icons.event_rounded,
                                        value: '${row['matches'] ?? 0}',
                                        color: AppColors.muted,
                                      ),
                                      _InlineStat(
                                        icon: Icons.timer_outlined,
                                        value: '${row['total_minutes'] ?? 0}′',
                                        color: AppColors.foreground,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Directionality.of(context) == TextDirection.rtl
                                  ? Icons.chevron_left_rounded
                                  : Icons.chevron_right_rounded,
                              color: AppColors.muted,
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _competitionMetric(
                              icon: Icons.sports_soccer_rounded,
                              value: '${row['goals'] ?? 0}',
                              label: AppLocalizations.get('match_goals_label'),
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            _competitionMetric(
                              icon: Icons.share_rounded,
                              value: '${row['assists'] ?? 0}',
                              label: AppLocalizations.get('match_assists_label'),
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 6),
                            _competitionMetric(
                              icon: Icons.style_rounded,
                              value: '${row['yellow_cards'] ?? 0}',
                              label: AppLocalizations.get('yellow_cards_label'),
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: 6),
                            _competitionMetric(
                              icon: Icons.style_rounded,
                              value: '${row['red_cards'] ?? 0}',
                              label: AppLocalizations.get('red_cards_label'),
                              color: AppColors.destructive,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (i != rows.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _competitionMetric({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 13),
                const SizedBox(width: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingCard() {
    final upcoming = (_data!['upcoming'] as List?)?.cast<Map>() ?? [];
    return _sectionCard(
      title: AppLocalizations.get('upcoming_events_label'),
      child: upcoming.isEmpty
          ? Text(AppLocalizations.get('no_upcoming_events'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12))
          : Column(
              children: upcoming.map((e) {
                final isMatch = e['type'] == 'match';
                final eventDate =
                    DateTime.tryParse(e['event_date']?.toString() ?? '');
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).pushNamed(
                    isMatch
                        ? '/club/matches/${e['id']}'
                        : '/club/sessions/${e['id']}',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(children: [
                      Icon(isMatch ? Icons.sports_soccer_rounded : Icons.fitness_center_rounded,
                          color: isMatch ? AppColors.maroon : AppColors.primary, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${e['name']}',
                            style: const TextStyle(color: AppColors.foreground, fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                          eventDate == null
                              ? '${e['event_date']}'
                              : AppLocalizations.formatDate(eventDate),
                          style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      const SizedBox(width: 4),
                      Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        color: AppColors.muted,
                        size: 16,
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drill-down level 1 — players behind a tapped stat tile, sorted by it.
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerBreakdownPage extends StatelessWidget {
  const _PlayerBreakdownPage({
    required this.title,
    required this.players,
    required this.matches,
    required this.sortKey,
  });

  final String title;
  final List<dynamic> players;
  final List<dynamic> matches;
  final String sortKey;

  @override
  Widget build(BuildContext context) {
    final rows = players.map((p) => (p as Map).cast<String, dynamic>()).toList()
      ..sort((a, b) => ((b[sortKey] as num?) ?? 0).compareTo((a[sortKey] as num?) ?? 0));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                        color: AppColors.surface2, shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border)),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.foreground, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('${AppLocalizations.get('player_breakdown_title')} · $title',
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w900, fontSize: 16),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(AppLocalizations.get('no_players_yet'),
                      style: const TextStyle(color: AppColors.muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _PlayerMatchesPage(
                              playerId: row['player_id']?.toString() ?? '',
                              playerName: row['name'] as String? ?? '',
                              matches: matches,
                            ),
                          )),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Text(row['name'] as String? ?? '',
                                    style: const TextStyle(
                                        color: AppColors.foreground,
                                        fontWeight: FontWeight.w700, fontSize: 13),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              Flexible(
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 7,
                                  runSpacing: 3,
                                  children: [
                                    _InlineStat(
                                      icon: Icons.event_rounded,
                                      value: '${row['matches'] ?? 0}',
                                      color: AppColors.muted,
                                    ),
                                    _InlineStat(
                                      icon: Icons.timer_outlined,
                                      value: '${row['total_minutes'] ?? 0}′',
                                      color: AppColors.foreground,
                                    ),
                                    _InlineStat(
                                      icon: Icons.sports_soccer_rounded,
                                      value: '${row['goals'] ?? 0}',
                                      color: AppColors.primary,
                                    ),
                                    _InlineStat(
                                      icon: Icons.share_rounded,
                                      value: '${row['assists'] ?? 0}',
                                      color: AppColors.success,
                                    ),
                                    _InlineStat(
                                      icon: Icons.style_rounded,
                                      value: '${row['yellow_cards'] ?? 0}',
                                      color: AppColors.warning,
                                    ),
                                    _InlineStat(
                                      icon: Icons.style_rounded,
                                      value: '${row['red_cards'] ?? 0}',
                                      color: AppColors.destructive,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 16),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drill-down level 2 — one player's matches: opponent, competition, date,
// minutes, goals, assists, and cards. Pure client-side filter of matches[].
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerMatchesPage extends StatelessWidget {
  const _PlayerMatchesPage({
    required this.playerId,
    required this.playerName,
    required this.matches,
  });

  final String playerId;
  final String playerName;
  final List<dynamic> matches;

  @override
  Widget build(BuildContext context) {
    final rows = matches
        .map((m) => (m as Map).cast<String, dynamic>())
        .where((m) => (m['players'] as Map?)?.containsKey(playerId) == true)
        .toList()
      ..sort((a, b) => '${b['match_date']}'.compareTo('${a['match_date']}'));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                        color: AppColors.surface2, shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border)),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.foreground, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(playerName,
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w900, fontSize: 16),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(AppLocalizations.get('no_session_today_title'),
                      style: const TextStyle(color: AppColors.muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final m = rows[i];
                        final stats = ((m['players'] as Map)[playerId] as Map).cast<String, dynamic>();
                        final competitionName = (m['competition_name'] as String?)?.trim();
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(
                                      '${AppLocalizations.get('vs_label')} ${m['opponent'] ?? ''}',
                                      style: const TextStyle(
                                          color: AppColors.foreground,
                                          fontWeight: FontWeight.w800, fontSize: 13),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                Text('${m['match_date'] ?? ''}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              ]),
                              if (competitionName != null && competitionName.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(competitionName,
                                    style: const TextStyle(
                                        color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                              ],
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 9,
                                runSpacing: 4,
                                children: [
                                  _InlineStat(
                                    icon: Icons.timer_outlined,
                                    value: '${stats['minutes'] ?? 0}′',
                                    color: AppColors.foreground,
                                  ),
                                  _InlineStat(
                                    icon: Icons.sports_soccer_rounded,
                                    value: '${stats['goals'] ?? 0}',
                                    color: AppColors.primary,
                                  ),
                                  _InlineStat(
                                    icon: Icons.share_rounded,
                                    value: '${stats['assists'] ?? 0}',
                                    color: AppColors.success,
                                  ),
                                  _InlineStat(
                                    icon: Icons.style_rounded,
                                    value: '${stats['yellow'] ?? 0}',
                                    color: AppColors.warning,
                                  ),
                                  _InlineStat(
                                    icon: Icons.style_rounded,
                                    value: '${stats['red'] ?? 0}',
                                    color: AppColors.destructive,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
