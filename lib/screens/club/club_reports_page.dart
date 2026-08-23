import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/body_composition_models.dart';
import '../../models/club_models.dart';
import '../../models/monitoring_models.dart';
import '../../services/body_composition_service.dart';
import '../../services/club_service.dart';
import '../../services/player_monitoring_service.dart';
import 'club_dashboard.dart';
import 'club_widgets.dart';
import 'body_composition_list_page.dart';
import 'admin_executive_report_screen.dart';
import 'team_training_load_report_screen.dart';
import 'team_performance_report_screen.dart';
import 'team_wellness_screen.dart';

/// Team report hub. It links to the detailed report screens and lists completed
/// periods that are recalculated from the current source data when opened.
class ClubReportsPage extends StatefulWidget {
  const ClubReportsPage({super.key});

  @override
  State<ClubReportsPage> createState() => _ClubReportsPageState();
}

class _ClubReportsPageState extends State<ClubReportsPage> {
  List<ReportArchiveEntry> _reportArchive = [];
  bool _loading = true;
  _ReportDataState _archiveState = _ReportDataState.loading;
  String? _archiveTypeFilter;

  _ReportCardSnapshot _performanceSnapshot =
      const _ReportCardSnapshot.loading();
  _ReportCardSnapshot _trainingLoadSnapshot =
      const _ReportCardSnapshot.loading();
  _ReportCardSnapshot _bodyCompositionSnapshot =
      const _ReportCardSnapshot.loading();
  _ReportCardSnapshot _readinessSnapshot =
      const _ReportCardSnapshot.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _archiveState = _ReportDataState.loading;
      _performanceSnapshot = const _ReportCardSnapshot.loading();
      _trainingLoadSnapshot = const _ReportCardSnapshot.loading();
      _bodyCompositionSnapshot = const _ReportCardSnapshot.loading();
      _readinessSnapshot = const _ReportCardSnapshot.loading();
    });

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekFrom = today.subtract(const Duration(days: 6));
    final results = await Future.wait<dynamic>([
      _capture(ClubService().getPlayers(throwOnError: true)),
      _capture(ClubService().getReportArchive(throwOnError: true)),
      _capture(PlayerMonitoringService.getTeamWellness(
        from: weekFrom,
        to: today,
        throwOnError: true,
      )),
      _capture(BodyCompositionService.getTeamSummary(throwOnError: true)),
      _capture(BodyCompositionService.getList(
        allHistory: true,
        page: 1,
        perPage: 1,
        throwOnError: true,
      )),
      _capture(PlayerMonitoringService.getPlayerWellnessList(
        throwOnError: true,
      )),
    ]);
    if (!mounted) return;

    final playersResult = results[0] as _LoadResult<List<ClubPlayer>>;
    final archiveResult =
        results[1] as _LoadResult<List<ReportArchiveEntry>>;
    final wellnessResult = results[2] as _LoadResult<TeamWellness?>;
    final bodyResult =
        results[3] as _LoadResult<TeamBodyCompositionSummary?>;
    final bodyListResult =
        results[4] as _LoadResult<Map<String, dynamic>>;
    final readinessResult =
        results[5] as _LoadResult<List<PlayerWellnessEntry>>;

    final players = playersResult.data ?? const <ClubPlayer>[];
    final archiveEntries = (archiveResult.data ?? const <ReportArchiveEntry>[])
        .where((entry) => (entry.playerCount ?? 0) > 0 || entry.dataCount > 0)
        .toList();
    final readinessPlayers =
        readinessResult.data ?? const <PlayerWellnessEntry>[];
    setState(() {
      _reportArchive = archiveEntries;
      _archiveState = archiveResult.unavailable
          ? _ReportDataState.unavailable
          : archiveResult.failed
              ? _ReportDataState.error
              : _reportArchive.isEmpty
                  ? _ReportDataState.empty
                  : _ReportDataState.available;
      _performanceSnapshot = _performanceCardSnapshot(playersResult);
      _trainingLoadSnapshot = _trainingLoadCardSnapshot(wellnessResult);
      _bodyCompositionSnapshot = _bodyCompositionCardSnapshot(
        bodyResult,
        bodyListResult,
      );
      _readinessSnapshot = _readinessCardSnapshot(
        wellnessResult,
        readinessResult,
        players.length,
        readinessPlayers,
        playersResult.failed,
      );
      _loading = false;
    });
  }

  Future<_LoadResult<T>> _capture<T>(Future<T> request) async {
    try {
      return _LoadResult<T>.success(await request);
    } on ReportArchiveUnavailableException {
      return _LoadResult<T>.unavailable();
    } catch (e) {
      AppLogger.e('ClubReports', 'Report source failed', e);
      return _LoadResult<T>.failure();
    }
  }

  _ReportCardSnapshot _performanceCardSnapshot(
    _LoadResult<List<ClubPlayer>> result,
  ) {
    if (result.failed) return const _ReportCardSnapshot.error();
    final players = result.data ?? const <ClubPlayer>[];
    if (players.isEmpty) return const _ReportCardSnapshot.empty();
    final assessed = players.where((player) => player.latestScore != null).length;
    if (assessed == 0) return const _ReportCardSnapshot.empty();
    return _ReportCardSnapshot.fromCoverage(
      assessed / players.length,
      _latestDate(players.map((player) => player.lastAssessmentAt)),
    );
  }

  _ReportCardSnapshot _trainingLoadCardSnapshot(
    _LoadResult<TeamWellness?> result,
  ) {
    if (result.failed || result.data == null) {
      return const _ReportCardSnapshot.error();
    }
    final rows = result.data!.playersTrainingLoad;
    final hasData = rows.any((row) {
      final days = row.daysRange.isNotEmpty ? row.daysRange : row.days;
      return days.any(
        (day) => day.sessionsCount > 0 || day.expectedRecords > 0,
      );
    });
    if (!hasData) return const _ReportCardSnapshot.empty();
    final completeness = rows
        .map((row) => row.periodDataCompleteness ?? row.dataCompleteness)
        .whereType<double>()
        .map(_normalizeCompletion)
        .toList();
    final updates = rows
        .expand((row) => row.daysRange.isNotEmpty ? row.daysRange : row.days)
        .expand((day) => [
          if (day.sessionsCount > 0) day.date,
          ...day.sessions.map((session) => session.lastEditedAt),
        ]);
    return _ReportCardSnapshot.fromCoverage(
      completeness.isEmpty
          ? 0
          : completeness.reduce((a, b) => a + b) / completeness.length,
      _latestDate(updates),
    );
  }

  _ReportCardSnapshot _bodyCompositionCardSnapshot(
    _LoadResult<TeamBodyCompositionSummary?> summaryResult,
    _LoadResult<Map<String, dynamic>> listResult,
  ) {
    if (summaryResult.failed || listResult.failed || summaryResult.data == null) {
      return const _ReportCardSnapshot.error();
    }
    final summary = summaryResult.data!;
    if (summary.rosterSize == 0 || summary.measuredThisMonth == 0) {
      return const _ReportCardSnapshot.empty();
    }
    return _ReportCardSnapshot.fromCoverage(
      summary.measuredThisMonth / summary.rosterSize,
      _bodyCompositionLastUpdate(listResult.data),
    );
  }

  _ReportCardSnapshot _readinessCardSnapshot(
    _LoadResult<TeamWellness?> wellnessResult,
    _LoadResult<List<PlayerWellnessEntry>> readinessResult,
    int rosterCount,
    List<PlayerWellnessEntry> players,
    bool rosterFailed,
  ) {
    if (rosterFailed ||
        wellnessResult.failed ||
        readinessResult.failed ||
        wellnessResult.data == null) {
      return const _ReportCardSnapshot.error();
    }
    final completed = wellnessResult.data!.totalCheckedIn;
    if (rosterCount == 0 || completed == 0) {
      return const _ReportCardSnapshot.empty();
    }
    return _ReportCardSnapshot.fromCoverage(
      completed / rosterCount,
      _latestDate(players.map((player) => player.submittedAt)),
    );
  }

  double _normalizeCompletion(double value) =>
      (value > 1 ? value / 100 : value).clamp(0.0, 1.0).toDouble();

  DateTime? _latestDate(Iterable<DateTime?> dates) {
    DateTime? latest;
    for (final date in dates.whereType<DateTime>()) {
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    return latest;
  }

  DateTime? _bodyCompositionLastUpdate(Map<String, dynamic>? data) {
    final assessments = data?['assessments'];
    if (assessments is! List || assessments.isEmpty) return null;
    final first = assessments.first;
    if (first is! Map) return null;
    return DateTime.tryParse(
      (first['assessment_date'] ?? first['measured_at'] ?? first['created_at'])
              ?.toString() ??
          '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClubShell(
      currentIndex: 4,
      child: Column(
        children: [
          const CoachBrandHeader(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.coachAccent,
              backgroundColor: AppColors.card,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _buildHeader(),
                  if (isOrgAdmin)
                    _buildAdminReportsSection()
                  else ...[
                    _buildTeamReportsSection(),
                    const SizedBox(height: 24),
                    _buildArchiveSection(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return ClubSectionTitle(
      icon: Icons.bar_chart_rounded,
      title: AppLocalizations.get('reports_page_title'),
    );
  }

  // Direct team-report destinations with explicit source states and periods.

  // Admin/owner executive report — final approved statuses only (never raw
  // Hooper/RPE/daily measurements), matching the read-only management
  // policy. The per-player comprehensive report is reached from the player
  // profile screen instead, since it's already scoped to one player there.
  Widget _buildAdminReportsSection() {
    return _buildSection(
      title: AppLocalizations.get('admin_executive_report_title'),
      subtitle: AppLocalizations.get('admin_executive_report_subtitle'),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdminExecutiveReportScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.maroon.withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.dashboard_rounded,
                  color: AppColors.maroon, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.get('admin_executive_report_cta'),
                style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.muted, size: 13),
          ]),
        ),
      ),
    );
  }

  Widget _buildTeamReportsSection() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final entries = <_TeamReportEntry>[
      if (_canViewDetailedPerformanceReports)
        _TeamReportEntry(
          icon: Icons.show_chart_rounded,
          color: AppColors.maroon,
          label: AppLocalizations.get('report_tile_performance_title'),
          description:
              AppLocalizations.get('reports_hub_performance_description'),
          period: AppLocalizations.get('reports_period_latest_assessment'),
          snapshot: _performanceSnapshot,
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const TeamPerformanceReportScreen())),
        ),
      if (_canViewTrainingLoadReports)
        _TeamReportEntry(
          icon: Icons.bar_chart_rounded,
          color: const Color(0xFF3E6FD9),
          label: AppLocalizations.get('training_load_report_action'),
          description:
              AppLocalizations.get('reports_hub_training_load_description'),
          period: AppLocalizations.get('period_7_days'),
          snapshot: _trainingLoadSnapshot,
          onTap: () => Navigator.of(context)
              .pushNamed('/club/reports/training-load'),
        ),
      if (_canViewBodyCompositionReports)
        _TeamReportEntry(
          icon: Icons.monitor_weight_outlined,
          color: AppColors.warning,
          label: AppLocalizations.get('report_tile_body_comp_title'),
          description:
              AppLocalizations.get('reports_hub_body_composition_description'),
          period: AppLocalizations.get('reports_period_current_month'),
          snapshot: _bodyCompositionSnapshot,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BodyCompositionListPage(
                initialDateFrom: monthStart,
                initialDateTo: now,
              ),
            ),
          ),
        ),
      if (canViewDailyReadiness)
        _TeamReportEntry(
          icon: Icons.favorite_outline_rounded,
          color: AppColors.success,
          label: AppLocalizations.get('report_tile_readiness_title'),
          description:
              AppLocalizations.get('reports_hub_readiness_description'),
          period: AppLocalizations.get('period_today'),
          snapshot: _readinessSnapshot,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TeamWellnessScreen()),
          ),
        ),
    ];

    if (entries.isEmpty) return const SizedBox.shrink();
    return _buildSection(
      title: AppLocalizations.get('reports_team_section_title'),
      subtitle: AppLocalizations.get('reports_hub_section_subtitle'),
      child: Column(
        children: entries
            .map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TeamReportCard(entry: entry, loading: _loading),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildArchiveSection() {
    final types = _reportArchive.map((e) => e.reportType).toSet().toList();
    final filtered = _archiveTypeFilter == null
        ? _reportArchive
        : _reportArchive
            .where((e) => e.reportType == _archiveTypeFilter)
            .toList();
    final visible = filtered.take(3).toList();
    return _buildSection(
      title: AppLocalizations.get('reports_previous_periods_title'),
      subtitle: AppLocalizations.get('reports_previous_periods_subtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_archiveState == _ReportDataState.available && types.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _archiveFilterChip(
                      label: AppLocalizations.get('reports_filter_all'),
                      selected: _archiveTypeFilter == null,
                      onTap: () => setState(() => _archiveTypeFilter = null),
                    ),
                    const SizedBox(width: 8),
                    ...types.map(
                      (type) => Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: _archiveFilterChip(
                          label: _archiveTypeLabel(type),
                          selected: _archiveTypeFilter == type,
                          onTap: () =>
                              setState(() => _archiveTypeFilter = type),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_archiveState != _ReportDataState.available)
            _buildArchiveStateCard()
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                AppLocalizations.get('report_archive_empty'),
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            )
          else
            ...visible.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _buildArchiveCard(entry),
              ),
            ),
          if (_archiveState == _ReportDataState.available &&
              filtered.length > 3)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _showAllArchivePeriods,
                icon: const Icon(Icons.history_rounded, size: 17),
                label: Text(
                  AppLocalizations.get('reports_show_all_periods'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildArchiveStateCard() {
    final text = switch (_archiveState) {
      _ReportDataState.loading => AppLocalizations.get('loading'),
      _ReportDataState.empty => AppLocalizations.get('report_archive_empty'),
      _ReportDataState.error => AppLocalizations.get('reports_status_error'),
      _ReportDataState.unavailable =>
        AppLocalizations.get('reports_status_unavailable'),
      _ => '',
    };
    final icon = switch (_archiveState) {
      _ReportDataState.loading => Icons.hourglass_top_rounded,
      _ReportDataState.empty => Icons.inbox_outlined,
      _ReportDataState.error => Icons.cloud_off_rounded,
      _ReportDataState.unavailable => Icons.power_settings_new_rounded,
      _ => Icons.history_rounded,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.muted, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          ),
          if (_archiveState == _ReportDataState.error) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _load,
              child: Text(AppLocalizations.get('retry_btn')),
            ),
          ],
        ],
      ),
    );
  }

  void _showAllArchivePeriods() {
    final types = _reportArchive.map((e) => e.reportType).toSet().toList();
    String? selectedType = _archiveTypeFilter;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final filtered = selectedType == null
              ? _reportArchive
              : _reportArchive
                  .where((e) => e.reportType == selectedType)
                  .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        AppLocalizations.get('reports_previous_periods_title'),
                        style: const TextStyle(
                          color: AppColors.foreground,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (types.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _archiveFilterChip(
                            label: AppLocalizations.get('reports_filter_all'),
                            selected: selectedType == null,
                            onTap: () => setSheetState(() => selectedType = null),
                          ),
                          const SizedBox(width: 8),
                          ...types.map(
                            (type) => Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: _archiveFilterChip(
                                label: _archiveTypeLabel(type),
                                selected: selectedType == type,
                                onTap: () =>
                                    setSheetState(() => selectedType = type),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (types.isNotEmpty) const SizedBox(height: 6),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              AppLocalizations.get('report_archive_empty'),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 9),
                            itemBuilder: (_, index) => _buildArchiveCard(
                              filtered[index],
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _openArchivedReport(filtered[index]);
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _archiveFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.maroon : AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.maroon : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildArchiveCard(
    ReportArchiveEntry entry, {
    VoidCallback? onTap,
  }) {
    final isBody = entry.reportType == 'body_composition_monthly';
    final isWeekly = entry.reportType == 'training_load_weekly';
    final color = isBody ? AppColors.warning : const Color(0xFF3E6FD9);
    final icon = isBody
        ? Icons.monitor_weight_outlined
        : isWeekly
            ? Icons.date_range_rounded
            : Icons.insights_rounded;
    return InkWell(
      onTap: onTap ?? () => _openArchivedReport(entry),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _archiveTypeLabel(entry.reportType),
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _archivePeriodLabel(entry),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 10,
                    runSpacing: 3,
                    children: [
                      Text(
                        AppLocalizations.format(
                          'reports_period_players_count',
                          {'count': entry.playerCount ?? 0},
                        ),
                        style: const TextStyle(
                          color: AppColors.textSoft,
                          fontSize: 10.5,
                        ),
                      ),
                      Text(
                        '${AppLocalizations.get('reports_current_roster_coverage')}: '
                        '${entry.dataCompleteness == null ? '—' : '${(_normalizeCompletion(entry.dataCompleteness!) * 100).round()}%'}',
                        style: const TextStyle(
                          color: AppColors.textSoft,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _archiveTypeLabel(String type) {
    switch (type) {
      case 'training_load_weekly':
        return AppLocalizations.get('report_archive_weekly_load');
      case 'training_load_28d':
        return AppLocalizations.get('report_archive_28d_load');
      case 'body_composition_monthly':
        return AppLocalizations.get('report_archive_body_monthly');
      default:
        return AppLocalizations.get('reports_page_title');
    }
  }

  String _archivePeriodLabel(ReportArchiveEntry entry) {
    if (entry.periodKind == 'month') {
      return '${AppLocalizations.monthName(entry.periodStart.month)} '
          '${entry.periodStart.year}';
    }
    return '${AppLocalizations.formatDate(entry.periodStart, withYear: true)} — '
        '${AppLocalizations.formatDate(entry.periodEnd, withYear: true)}';
  }

  void _openArchivedReport(ReportArchiveEntry entry) {
    if (entry.reportType == 'body_composition_monthly') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BodyCompositionListPage(
            initialDateFrom: entry.periodStart,
            initialDateTo: entry.periodEnd,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamTrainingLoadReportScreen(
          initialRangeFrom: entry.periodStart,
          initialRangeTo: entry.periodEnd,
          initialPeriodDays:
              entry.reportType == 'training_load_28d' ? 28 : 7,
        ),
      ),
    );
  }

  // ── Section wrapper — every group on this page has the same shape ────────

  Widget _buildSection({required String title, required String subtitle, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3, height: 16,
                decoration: BoxDecoration(color: AppColors.maroon, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 11, top: 2),
            child: Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  bool get _canViewAssessmentReports =>
      canRunAssessments || isAnalystRole || isTacticalCoachRole;

  bool get _canViewTrainingLoadReports =>
      isOrgAdmin ||
      isCoachRole ||
      isDoctorRole ||
      isNutritionistRole ||
      isAnalystRole ||
      isTacticalCoachRole ||
      currentOrgRole == OrgRole.performanceManager;

  bool get _canViewBodyCompositionReports =>
      isOrgAdmin ||
      isCoachRole ||
      isDoctorRole ||
      isNutritionistRole ||
      currentOrgRole == OrgRole.performanceManager;

  bool get _canViewDetailedPerformanceReports =>
      _canViewAssessmentReports && _canViewTrainingLoadReports;
}

enum _ReportDataState {
  loading,
  available,
  incomplete,
  empty,
  error,
  unavailable,
}

class _LoadResult<T> {
  const _LoadResult.success(this.data)
      : failed = false,
        unavailable = false;
  const _LoadResult.failure()
      : data = null,
        failed = true,
        unavailable = false;
  const _LoadResult.unavailable()
      : data = null,
        failed = false,
        unavailable = true;

  final T? data;
  final bool failed;
  final bool unavailable;
}

class _ReportCardSnapshot {
  const _ReportCardSnapshot._({
    required this.state,
    this.completion,
    this.updatedAt,
  });

  const _ReportCardSnapshot.loading()
      : this._(state: _ReportDataState.loading);
  const _ReportCardSnapshot.empty()
      : this._(state: _ReportDataState.empty);
  const _ReportCardSnapshot.error()
      : this._(state: _ReportDataState.error);

  factory _ReportCardSnapshot.fromCoverage(
    double completion,
    DateTime? updatedAt,
  ) {
    final normalized = completion.clamp(0.0, 1.0).toDouble();
    return _ReportCardSnapshot._(
      state: normalized >= 0.999
          ? _ReportDataState.available
          : _ReportDataState.incomplete,
      completion: normalized,
      updatedAt: updatedAt,
    );
  }

  final _ReportDataState state;
  final double? completion;
  final DateTime? updatedAt;
}

class _TeamReportEntry {
  const _TeamReportEntry({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
    required this.period,
    required this.snapshot,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String description;
  final String period;
  final _ReportCardSnapshot snapshot;
  final VoidCallback onTap;
}

class _TeamReportCard extends StatelessWidget {
  const _TeamReportCard({required this.entry, required this.loading});

  final _TeamReportEntry entry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final state = loading ? _ReportDataState.loading : entry.snapshot.state;
    final statusColor = _statusColor(state);
    final updatedAt = entry.snapshot.updatedAt;
    final completion = entry.snapshot.completion;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: entry.color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(entry.icon, color: entry.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.description,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(state),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 7,
            children: [
              _meta(Icons.date_range_rounded, entry.period),
              _meta(
                Icons.update_rounded,
                updatedAt == null
                    ? AppLocalizations.get('admin_data_not_updated')
                    : '${AppLocalizations.get('ai_last_updated')}: '
                        '${AppLocalizations.formatDate(updatedAt, withYear: true)}',
              ),
              _meta(
                Icons.fact_check_outlined,
                '${AppLocalizations.get('period_completeness_short')}: '
                '${completion == null ? '—' : '${(completion * 100).round()}%'}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: entry.onTap,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: Text(AppLocalizations.get('view_details_btn')),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.muted, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(color: AppColors.textSoft, fontSize: 10.5),
          ),
        ],
      );

  static Color _statusColor(_ReportDataState state) => switch (state) {
        _ReportDataState.available => AppColors.success,
        _ReportDataState.incomplete => AppColors.warning,
        _ReportDataState.empty => AppColors.muted,
        _ReportDataState.error => AppColors.destructive,
        _ReportDataState.unavailable => AppColors.muted,
        _ReportDataState.loading => AppColors.coachAccent,
      };

  static String _statusLabel(_ReportDataState state) => switch (state) {
        _ReportDataState.available =>
          AppLocalizations.get('reports_status_available'),
        _ReportDataState.incomplete =>
          AppLocalizations.get('reports_status_incomplete'),
        _ReportDataState.empty => AppLocalizations.get('reports_status_empty'),
        _ReportDataState.error => AppLocalizations.get('reports_status_error'),
        _ReportDataState.unavailable =>
          AppLocalizations.get('reports_status_unavailable'),
        _ReportDataState.loading => AppLocalizations.get('loading'),
      };
}

// Legacy card retained temporarily for source compatibility; it is not shown
// by the team reports hub.
// ignore: unused_element
class _QuickReportEntry {
  const _QuickReportEntry({
    required this.typeKey,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
    required this.onTap,
    // ignore: unused_element_parameter
    this.trendPct,
    // ignore: unused_element_parameter
    this.decimals = 0,
  });

  final String typeKey;
  final IconData icon;
  final Color color;
  final String label;
  final double? value;
  final String unit;
  final double? trendPct;
  final int decimals;
  final VoidCallback onTap;
}

// ignore: unused_element
class _QuickReportCard extends StatelessWidget {
  const _QuickReportCard({required this.entry});
  final _QuickReportEntry entry;

  @override
  Widget build(BuildContext context) {
    final hasData = entry.value != null;
    final trendUp = (entry.trendPct ?? 0) > 0;
    final trendColor = !hasData || entry.trendPct == null
        ? const Color(0xFF9299A5)
        : trendUp
            ? AppColors.success
            : AppColors.maroon;
    final trendBg = trendColor.withOpacity(0.10);

    return InkWell(
      onTap: entry.onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 3)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: entry.color),
                Container(
                  width: 56,
                  color: entry.color.withOpacity(0.06),
                  alignment: Alignment.center,
                  child: Icon(entry.icon, color: entry.color, size: 20),
                ),
                Expanded(
                  child: Container(
                    color: AppColors.card,
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.label,
                            style: const TextStyle(
                                color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        if (!hasData)
                          Text(AppLocalizations.get('reports_no_data_short'),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11.5))
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(entry.value!.toStringAsFixed(entry.decimals),
                                      style: const TextStyle(
                                          color: AppColors.foreground,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16)),
                                  const SizedBox(width: 3),
                                  Text(entry.unit,
                                      style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                                ],
                              ),
                              if (entry.trendPct != null)
                                Container(
                                  height: 17,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: trendBg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(trendUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                          color: trendColor, size: 10),
                                      const SizedBox(width: 2),
                                      Text('${entry.trendPct!.abs().toStringAsFixed(0)}%',
                                          style: TextStyle(
                                              color: trendColor, fontWeight: FontWeight.w700, fontSize: 9)),
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

