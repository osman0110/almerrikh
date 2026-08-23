import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../utils/app_logger.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../services/report_service.dart';
import '../../shared/club_ui_tokens.dart';
import '../../widgets/common_widgets.dart';

/// The team's AI-assessment performance report — score distribution,
/// per-player table, risk analysis, attendance, position averages.
/// Pulled out of the reports hub (ClubReportsPage) into its own screen so
/// the hub stays a plain list of destinations and this stays a plain report,
/// instead of both jobs fighting for space on one page.
class TeamPerformanceReportScreen extends StatefulWidget {
  const TeamPerformanceReportScreen({super.key});

  @override
  State<TeamPerformanceReportScreen> createState() => _TeamPerformanceReportScreenState();
}

class _TeamPerformanceReportScreenState extends State<TeamPerformanceReportScreen> {
  List<ClubPlayer> _players = [];
  List<TrainingSession> _sessions = [];
  bool _loading = false;
  bool _error = false;
  int _loadGeneration = 0;

  // ── Filters ────────────────────────────────────────────────────────────
  String _filterStatus = 'all'; // 'all', 'active', 'injured', 'inactive'
  DateTimeRange? _dateRange;
  String _sortBy = 'score_desc'; // score_desc, score_asc, name, position

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() { _loading = true; _error = false; });
    try {
      final results = await Future.wait([
        ClubService().getPlayers(throwOnError: true),
        ClubService().getSessions(throwOnError: true),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final playersById = <String, ClubPlayer>{
        for (final player in results[0] as List<ClubPlayer>)
          if (player.id.isNotEmpty) player.id: player,
      };
      final sessionsById = <String, TrainingSession>{
        for (final session in results[1] as List<TrainingSession>)
          if (session.id.isNotEmpty) session.id: session,
      };
      setState(() {
        _players = playersById.values.toList();
        _sessions = sessionsById.values.toList();
      });
    } catch (e) {
      AppLogger.e('TeamPerformanceReport', 'Load failed', e);
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = true);
      }
    }
    if (mounted && generation == _loadGeneration) {
      setState(() => _loading = false);
    }
  }

  // ── Computed data ──────────────────────────────────────────────────────────

  List<ClubPlayer> get _filteredPlayers {
    var players = _players.where((p) {
      if (_filterStatus != 'all') {
        final status = p.status.name;
        if (status != _filterStatus) return false;
      }
      if (_dateRange != null) {
        final last = p.lastAssessmentAt;
        if (last == null) return false;
        final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
        final end = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day, 23, 59, 59);
        if (last.isBefore(start) || last.isAfter(end)) return false;
      }
      return true;
    }).toList();

    switch (_sortBy) {
      case 'score_asc':
        players.sort((a, b) => (a.latestScore ?? 0).compareTo(b.latestScore ?? 0));
        break;
      case 'name':
        players.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case 'position':
        players.sort((a, b) => a.position.compareTo(b.position));
        break;
      default: // score_desc
        players.sort((a, b) => (b.latestScore ?? 0).compareTo(a.latestScore ?? 0));
    }

    return players;
  }

  List<ClubPlayer> get _scoredPlayers =>
      _players.where((p) => p.latestScore != null).toList()
        ..sort((a, b) => (b.latestScore ?? 0).compareTo(a.latestScore ?? 0));

  int get _totalAssessments =>
      _sessions.fold(0, (sum, s) => sum + s.assessmentCount);

  List<int> get _scoreBuckets {
    final b = [0, 0, 0, 0]; // <60, 60-75, 75-90, 90+
    for (final p in _scoredPlayers) {
      final s = p.latestScore!;
      if (s >= 90) b[3]++;
      else if (s >= 75) b[2]++;
      else if (s >= 60) b[1]++;
      else b[0]++;
    }
    return b;
  }

  List<TrainingSession> get _recentSessionsWithPlayers =>
      (_sessions.where((s) => s.playerIds.isNotEmpty).toList()
        ..sort((a, b) => b.date.compareTo(a.date)))
      .take(8)
      .toList();

  Map<String, double> get _avgByPosition {
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (final p in _scoredPlayers) {
      if (p.position.isEmpty) continue;
      final pos = p.position;
      sums[pos] = (sums[pos] ?? 0) + p.latestScore!;
      counts[pos] = (counts[pos] ?? 0) + 1;
    }
    final result = <String, double>{
      for (final e in sums.entries) e.key: e.value / counts[e.key]!
    };
    final sorted = result.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(5));
  }

  int get _weeklyAssessed {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return _players.where((p) =>
        p.lastAssessmentAt != null &&
        !p.lastAssessmentAt!.isBefore(weekStart)).length;
  }

  int get _weeklyTotal => _players.where((p) => p.status == PlayerStatus.active).length;

  Future<void> _exportTeamPdf() async {
    await Printing.layoutPdf(
      onLayout: (format) => ReportService.instance.generateTeamReportPdf(
        players: _filteredPlayers,
        totalSessions: _sessions.length,
        totalAssessments: _totalAssessments,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.foreground, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(AppLocalizations.get('performance_table_title'),
            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          if (!_loading && !_error)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.coachAccent),
              onPressed: _exportTeamPdf,
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.coachAccent,
        backgroundColor: AppColors.card,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator(
                    color: AppColors.coachAccent, strokeWidth: 2)),
              )
            else if (_error)
              _buildErrorCard()
            else ...[
              const SizedBox(height: 14),
              _buildFiltersBar(),
              const SizedBox(height: 16),
              _buildStatsRow(),
              const SizedBox(height: 20),
              _buildWeeklyCompletion(),
              const SizedBox(height: 20),
              _buildScoreDistribution(),
              const SizedBox(height: 20),
              _buildPerformanceTable(),
              const SizedBox(height: 20),
              _buildRiskAnalysis(),
              const SizedBox(height: 20),
              _buildAttendanceTrend(),
              const SizedBox(height: 20),
              _buildPositionChart(),
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }

  // ── Filters Bar ───────────────────────────────────────────────────────────

  Widget _buildFiltersBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secHeader(AppLocalizations.get('reports_filters_label')),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(AppLocalizations.get('status_label'), _filterStatus,
                    ['all', 'active', 'injured', 'inactive'],
                    (val) => setState(() => _filterStatus = val)),
                const SizedBox(width: 8),
                _buildFilterChip(AppLocalizations.get('sort_by_label'), _sortBy,
                    ['score_desc', 'score_asc', 'name', 'position'],
                    (val) => setState(() => _sortBy = val)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                      initialDateRange: _dateRange,
                    );
                    if (range != null) setState(() => _dateRange = range);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.date_range_rounded, color: AppColors.muted, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          _dateRange == null
                              ? AppLocalizations.get('date_range_label')
                              : '${_dateRange!.start.day}/${_dateRange!.start.month}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                if (_dateRange != null || _filterStatus != 'all' || _sortBy != 'score_desc')
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _filterStatus = 'all';
                        _dateRange = null;
                        _sortBy = 'score_desc';
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.maroon.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.maroon.withOpacity(0.20)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.close_rounded, color: AppColors.maroon, size: 12),
                            const SizedBox(width: 4),
                            Text(AppLocalizations.get('clear_filters_label'), style: const TextStyle(
                                color: AppColors.maroon,
                                fontSize: 10, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, List<String> options, Function(String) onSelect) {
    final labels = <String, String>{
      'all':        AppLocalizations.get('reports_filter_all'),
      'active':     AppLocalizations.get('reports_filter_active'),
      'injured':    AppLocalizations.get('reports_filter_injured'),
      'inactive':   AppLocalizations.get('reports_filter_inactive'),
      'score_desc': AppLocalizations.get('reports_sort_score_desc'),
      'score_asc':  AppLocalizations.get('reports_sort_score_asc'),
      'name':       AppLocalizations.get('reports_sort_name'),
      'position':   AppLocalizations.get('reports_sort_position'),
    };

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: AppColors.card,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 14),
                ...options.map((opt) => GestureDetector(
                  onTap: () { onSelect(opt); Navigator.pop(ctx); },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 18, height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: value == opt ? AppColors.maroon : AppColors.border,
                              width: 2,
                            ),
                          ),
                          child: value == opt
                              ? Center(child: Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle, color: AppColors.maroon)))
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Text(labels[opt] ?? opt, style: const TextStyle(
                            color: AppColors.foreground, fontSize: 13)),
                      ],
                    ),
                  ),
                )),
              ],
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(labels[value] ?? label, style: const TextStyle(
                color: AppColors.textSoft,
                fontWeight: FontWeight.w600, fontSize: 11)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, color: AppColors.muted, size: 14),
          ],
        ),
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────

  Widget _buildErrorCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.destructive.withOpacity(0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.destructive, size: 32),
            const SizedBox(height: 12),
            Text(AppLocalizations.get('reports_load_error'),
                style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _load,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.coachAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(AppLocalizations.get('try_again'),
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Performance Table ────────────────────────────────────────────────────────

  Widget _buildPerformanceTable() {
    final players = _filteredPlayers;
    final withScore = players.where((p) => p.latestScore != null).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: AppColors.coachAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.person_rounded, color: AppColors.coachAccent, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(AppLocalizations.get('performance_table_title'),
                      style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
                Text(AppLocalizations.format('players_count', {'count': withScore.length}),
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ]),
            ),
            if (withScore.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: _emptyChartState(AppLocalizations.get('no_results_label'), AppLocalizations.get('run_assessments_first')),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    dataRowHeight: 50,
                    headingRowHeight: 40,
                    columnSpacing: 12,
                    columns: [
                      DataColumn(label: Text(AppLocalizations.get('rank'), style: _tableHeaderStyle())),
                      DataColumn(label: Text(AppLocalizations.get('player_name'), style: _tableHeaderStyle())),
                      DataColumn(label: Text(AppLocalizations.get('player_position_label'), style: _tableHeaderStyle())),
                      DataColumn(label: Text(AppLocalizations.get('score_column'), style: _tableHeaderStyle())),
                      DataColumn(label: Text(AppLocalizations.get('note_column'), style: _tableHeaderStyle())),
                      DataColumn(label: Text(AppLocalizations.get('status_label'), style: _tableHeaderStyle())),
                    ],
                    rows: List.generate(withScore.length, (i) {
                      final p = withScore[i];
                      final score = p.latestScore!;
                      final color = score >= 80 ? AppColors.success
                          : score >= 60 ? AppColors.warning : AppColors.destructive;
                      final statusLabel = p.status.localizedLabel;

                      return DataRow(
                        cells: [
                          DataCell(Text('${i + 1}', style: const TextStyle(
                              color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 11))),
                          DataCell(
                            InkWell(
                              onTap: () => Navigator.of(context).pushNamed(
                                '/club/reports/assessments',
                                arguments: {'player_id': p.id, 'player_name': p.fullName},
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle, color: color.withOpacity(0.10),
                                      border: Border.all(color: color.withOpacity(0.35), width: 1)),
                                    child: Center(child: Text(p.initials,
                                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 9))),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 80,
                                    child: Text(p.fullName,
                                        style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w600, fontSize: 11),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(Text(p.position.isEmpty ? '—' : p.position,
                              style: const TextStyle(color: AppColors.muted, fontSize: 10))),
                          DataCell(Text('${score.toStringAsFixed(0)}',
                              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12))),
                          DataCell(SizedBox(width: 30, child: _ScoreRing(score: score))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(p.status).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _statusColor(p.status).withOpacity(0.25)),
                              ),
                              child: Text(statusLabel,
                                  style: TextStyle(color: _statusColor(p.status), fontWeight: FontWeight.w700, fontSize: 9)),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  TextStyle _tableHeaderStyle() {
    return const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 10);
  }

  Color _statusColor(PlayerStatus status) {
    switch (status) {
      case PlayerStatus.active:     return AppColors.success;
      case PlayerStatus.injured:    return AppColors.destructive;
      case PlayerStatus.recovering: return AppColors.warning;
      case PlayerStatus.inactive:   return AppColors.muted;
      case PlayerStatus.suspended:  return AppColors.destructive;
    }
  }

  // ── Risk Analysis ──────────────────────────────────────────────────────────

  Widget _buildRiskAnalysis() {
    final injuredCount = _players.where((p) => p.status == PlayerStatus.injured).length;
    final recoveringCount = _players.where((p) => p.status == PlayerStatus.recovering).length;
    final lowScoreCount = _scoredPlayers.where((p) => (p.latestScore ?? 0) < 60).length;
    final riskPlayers = _scoredPlayers.where((p) => (p.latestScore ?? 0) < 60).take(5).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secHeader(AppLocalizations.get('risk_injury_analysis_label')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildRiskCard(AppLocalizations.get('active_injuries_label'), '$injuredCount', AppColors.destructive, Icons.medical_services_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildRiskCard(AppLocalizations.get('recovering_label'), '$recoveringCount', AppColors.warning, Icons.healing_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildRiskCard(AppLocalizations.get('low_performance_label'), '$lowScoreCount', AppColors.danger, Icons.trending_down_rounded),
              ),
            ],
          ),
          if (riskPlayers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.destructive.withOpacity(0.2)),
                boxShadow: [BoxShadow(color: AppColors.destructive.withOpacity(0.05), blurRadius: 8)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                          color: AppColors.destructive.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.warning_rounded, color: AppColors.destructive, size: 14),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(AppLocalizations.get('players_needing_attention'),
                          style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  ...riskPlayers.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.destructive.withOpacity(0.10)),
                          child: Center(child: Text(p.initials,
                              style: const TextStyle(color: AppColors.destructive, fontWeight: FontWeight.w700, fontSize: 9))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.fullName,
                                  style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w600, fontSize: 11)),
                              Text('#${p.number} • ${p.position.isEmpty ? "—" : p.position}',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 9)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.destructive.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(AppLocalizations.format('score_pts_label', {'score': (p.latestScore ?? 0).toStringAsFixed(0)}),
                              style: const TextStyle(color: AppColors.destructive, fontWeight: FontWeight.w700, fontSize: 9)),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(
              color: color, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(
              color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Stats Row ──────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    final injuredCount = _players.where((p) =>
        p.status == PlayerStatus.injured ||
        p.status == PlayerStatus.recovering).length;
    final statData = [
      _Stat(AppLocalizations.get('players_label'),
          '${_players.length}',
          Icons.people_rounded, AppColors.maroon),
      _Stat(AppLocalizations.get('sessions_label'), '${_sessions.length}',
          Icons.sports_rounded, AppColors.coachAccent),
      _Stat(AppLocalizations.get('assessments_label'), '$_totalAssessments',
          Icons.assignment_turned_in_rounded, AppColors.primary),
      _Stat(AppLocalizations.get('injuries_label'), '$injuredCount',
          Icons.personal_injury_rounded,
          injuredCount > 0 ? AppColors.destructive : AppColors.muted),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secHeader(AppLocalizations.get('overview_label')),
          const SizedBox(height: 10),
          Row(
            children: statData.map((s) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: s.color.withOpacity(0.15)),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: s.color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(s.icon, color: s.color, size: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(s.value, style: TextStyle(
                        color: s.color,
                        fontWeight: FontWeight.w900, fontSize: 22, height: 1)),
                    const SizedBox(height: 3),
                    Text(s.label,
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 9.5, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ── Weekly Completion ──────────────────────────────────────────────────────

  Widget _buildWeeklyCompletion() {
    final assessed  = _weeklyAssessed;
    final total     = _weeklyTotal;
    final pct       = total > 0 ? (assessed / total).clamp(0.0, 1.0) : 0.0;
    final pctInt    = (pct * 100).round();
    final remaining = (total - assessed).clamp(0, total);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(ClubUiTokens.cardRadius),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_turned_in_rounded,
                      color: AppColors.maroon, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.get('weekly_assessments'),
                          style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(AppLocalizations.get('this_week_label'),
                          style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 10)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: pctInt == 100
                        ? AppColors.success.withOpacity(0.12)
                        : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: pctInt == 100
                          ? AppColors.success.withOpacity(0.35)
                          : AppColors.primary.withOpacity(0.35),
                    ),
                  ),
                  child: Text('$pctInt%',
                      style: TextStyle(
                          color: pctInt == 100 ? AppColors.success : AppColors.maroon,
                          fontWeight: FontWeight.w900, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$assessed',
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w900, fontSize: 32, height: 1)),
                const SizedBox(width: 6),
                Text(AppLocalizations.format('weekly_of_total_completed', {'total': total}),
                    style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13)),
              ],
            ),
            if (remaining > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(AppLocalizations.format('players_need_assessment_count', {'count': remaining}),
                    style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11)),
              ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: AppColors.surface2,
                valueColor: AlwaysStoppedAnimation(
                    pctInt == 100 ? AppColors.success : AppColors.primary),
              ),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: AppLocalizations.get('start_assessments_label'),
              icon: Icons.play_arrow_rounded,
              onTap: () => Navigator.of(context).pushNamed('/club/sessions'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Score Distribution Chart ───────────────────────────────────────────────

  Widget _buildScoreDistribution() {
    final buckets = _scoreBuckets;
    final maxVal  = buckets.reduce(math.max).toDouble();
    final labels  = ['< 60', '60–75', '75–90', '90+'];
    final colors  = [AppColors.destructive, AppColors.warning, AppColors.success, AppColors.coachAccent];
    final hasData = buckets.any((b) => b > 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.bar_chart_rounded, color: AppColors.maroon, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(AppLocalizations.get('player_score_distribution'),
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              Text(AppLocalizations.format('players_count', {'count': _scoredPlayers.length}),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
            const SizedBox(height: 16),
            if (!hasData)
              _emptyChartState(AppLocalizations.get('no_results_yet'), AppLocalizations.get('run_ai_chart_hint'))
            else
              SizedBox(
                height: 130,
                child: BarChart(
                  BarChartData(
                    maxY: (maxVal * 1.25).ceilToDouble().clamp(4, double.infinity),
                    barGroups: List.generate(4, (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: buckets[i].toDouble(),
                          color: colors[i],
                          width: 32,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: (maxVal * 1.25).ceilToDouble().clamp(4, double.infinity),
                            color: AppColors.surface2,
                          ),
                        ),
                      ],
                    )),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, m) => Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(labels[v.toInt()],
                                style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => AppColors.foreground,
                        tooltipRoundedRadius: 8,
                        getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                          '${rod.toY.toInt()} ${AppLocalizations.get('players_unit_label')}',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (hasData) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(labels[i],
                        style: const TextStyle(color: AppColors.muted, fontSize: 9.5)),
                  ]),
                )),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Session Attendance Trend ───────────────────────────────────────────────

  Widget _buildAttendanceTrend() {
    final sessions = _recentSessionsWithPlayers;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                    color: AppColors.coachAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.people_alt_rounded, color: AppColors.coachAccent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(AppLocalizations.get('session_assessment_rate'),
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              Text(AppLocalizations.format('last_n_sessions', {'count': sessions.length}),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
            const SizedBox(height: 14),
            if (sessions.isEmpty)
              _emptyChartState(AppLocalizations.get('no_sessions_chart'), AppLocalizations.get('create_session_chart_hint'))
            else
              ...sessions.map((s) {
                final total = s.playerIds.toSet().length;
                final done = math.min(s.assessmentCount, total);
                final pct = total == 0 ? 0.0 : done / total;
                final pctInt = (pct * 100).round();
                final color  = pctInt == 100 ? AppColors.success
                    : pctInt >= 50 ? AppColors.coachAccent : AppColors.warning;
                final dateStr = AppLocalizations.formatDate(s.date);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed('/club/sessions/${s.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(s.name,
                                style: const TextStyle(
                                    color: AppColors.foreground,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Text(dateStr,
                              style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                          const SizedBox(width: 8),
                          _AttendanceBadge(
                            pctInt: pctInt,
                            done: done,
                            total: total,
                          ),
                        ]),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: pct.clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: AppColors.surface2,
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ── Position Comparison Chart ──────────────────────────────────────────────

  Widget _buildPositionChart() {
    final avgMap = _avgByPosition;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.sports_soccer_rounded, color: AppColors.gold, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(AppLocalizations.get('avg_score_by_position'),
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 14),
            if (avgMap.isEmpty)
              _emptyChartState(AppLocalizations.get('not_enough_results'),
                  AppLocalizations.get('position_chart_hint'))
            else
              ...avgMap.entries.map((e) {
                final pct   = e.value / 100;
                final color = e.value >= 80 ? AppColors.success
                    : e.value >= 60 ? AppColors.coachAccent : AppColors.warning;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    SizedBox(
                      width: 88,
                      child: Text(e.key,
                          style: const TextStyle(
                              color: AppColors.textSoft,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: AppColors.surface2,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 32,
                      child: Text('${e.value.toStringAsFixed(0)}',
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _secHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3, height: 14,
          decoration: BoxDecoration(
            color: AppColors.maroon,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: AppColors.textSoft,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.3)),
      ],
    );
  }

  Widget _emptyChartState(String title, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.insert_chart_outlined_rounded, color: AppColors.border, size: 28),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(
            color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 3),
        Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score Ring (circular progress indicator)
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 80 ? AppColors.success
        : score >= 60 ? AppColors.warning : AppColors.destructive;
    return SizedBox(
      width: 32, height: 32,
      child: CircularProgressIndicator(
        value: score / 100,
        strokeWidth: 3,
        backgroundColor: AppColors.surface2,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attendance Badge
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceBadge extends StatelessWidget {
  const _AttendanceBadge({required this.pctInt, required this.done, required this.total});
  final int pctInt, done, total;

  @override
  Widget build(BuildContext context) {
    final color = pctInt == 100 ? AppColors.success
        : pctInt >= 50 ? AppColors.coachAccent : AppColors.warning;
    final label = total == 0
        ? AppLocalizations.get('session_badge_not_started')
        : pctInt == 100
            ? AppLocalizations.get('session_badge_completed')
            : '$done/$total';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal data classes
// ─────────────────────────────────────────────────────────────────────────────

class _Stat {
  const _Stat(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
}
