import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/monitoring_models.dart';
import '../../models/training_load_models.dart';
import '../../services/player_monitoring_service.dart';
import '../../services/report_service.dart';
import '../../utils/crash_reporter.dart';
import 'club_widgets.dart' show CoachBrandHeader;

// ─────────────────────────────────────────────────────────────────────────────
// Team Training Load Report — Excel-style table (RPE APR Rwanda layout):
// one row per player, Mon-Sun RPE/Duration/Load columns, then
// Weekly/Mean/SD/Monotony/Strain. Sourced from api/club/team-wellness.php's
// players_training_load[], itself built from TrainingLoadCalculator — the
// same single source of truth used by the per-player weekly report.
// Route: /club/reports/training-load
// ─────────────────────────────────────────────────────────────────────────────

const _bg = AppColors.background;
const _card = AppColors.card;
const _fg = AppColors.foreground;
const _muted = AppColors.muted;
const _border = AppColors.border;
const _lime = AppColors.primary;
const _maroon = AppColors.maroon;
const _undertrainingBlue = AppColors.parentAccent;

// Design-system card look (Physical Coach Dashboard / load-report mock):
// white rounded card + soft shadow, replacing the old flat bordered boxes.
BoxDecoration _softCard({double radius = 16}) => BoxDecoration(
  color: _card,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: const [
    BoxShadow(color: Color(0x0D161616), blurRadius: 16, offset: Offset(0, 4)),
  ],
);

Color _acwrColor(String classification) {
  switch (classification) {
    case 'BELOW_TARGET':
      return _undertrainingBlue;
    case 'IN_TARGET':
      return AppColors.success;
    case 'CAUTION':
      return AppColors.warning;
    case 'ABOVE_TARGET':
      return AppColors.destructive;
    default:
      return _muted;
  }
}

String _acwrShortLabel(String classification) {
  switch (classification) {
    case 'BELOW_TARGET':
      return AppLocalizations.get('acwr_below_target');
    case 'IN_TARGET':
      return AppLocalizations.get('acwr_in_target');
    case 'CAUTION':
      return AppLocalizations.get('acwr_caution');
    case 'ABOVE_TARGET':
      return AppLocalizations.get('acwr_above_target');
    default:
      return AppLocalizations.get('acwr_incomplete');
  }
}

String _acwrReason(String classification) {
  switch (classification) {
    case 'BELOW_TARGET':
      return AppLocalizations.get('tls_acwr_below');
    case 'IN_TARGET':
      return AppLocalizations.get('tls_acwr_in_target');
    case 'CAUTION':
      return AppLocalizations.get('tls_acwr_caution');
    case 'ABOVE_TARGET':
      return AppLocalizations.get('tls_acwr_above');
    default:
      return AppLocalizations.get('tls_acwr_insufficient');
  }
}

const Map<String, String> _positionArabic = {
  'Goalkeeper': 'حارس مرمى',
  'Centre-Back': 'قلب دفاع',
  'Right-Back': 'ظهير أيمن',
  'Left-Back': 'ظهير أيسر',
  'Defensive Mid': 'ارتكاز',
  'Central Mid': 'وسط ميدان',
  'Attacking Mid': 'وسط هجومي',
  'Right Wing': 'جناح أيمن',
  'Left Wing': 'جناح أيسر',
  'Striker': 'مهاجم',
};

String _positionLabel(String? position) {
  if (position == null || position.trim().isEmpty) {
    return AppLocalizations.get('no_data');
  }
  final ar = _positionArabic[position];
  return getAppLanguage() == 'ar' && ar != null ? ar : position;
}

class TeamTrainingLoadReportScreen extends StatefulWidget {
  const TeamTrainingLoadReportScreen({
    super.key,
    this.acwrReport = false,
    this.initialRangeFrom,
    this.initialRangeTo,
    this.initialPeriodDays,
  });

  final bool acwrReport;
  final DateTime? initialRangeFrom;
  final DateTime? initialRangeTo;
  final int? initialPeriodDays;

  @override
  State<TeamTrainingLoadReportScreen> createState() =>
      _TeamTrainingLoadReportScreenState();
}

class _TeamTrainingLoadReportScreenState
    extends State<TeamTrainingLoadReportScreen> {
  List<PlayerTrainingLoadRow> _rows = [];
  bool _loading = true;
  bool _error = false;
  late DateTime _rangeFrom;
  late DateTime _rangeTo;
  String _playerQuery = '';
  String? _positionFilter;
  String? _teamFilter;
  String? _sessionTypeFilter;
  String? _acwrStatusFilter;
  Map<String, dynamic>? _activeSeason;
  late int _periodDays;
  bool _detailed = true;
  bool _exporting = false;
  int _loadGeneration = 0;
  final Set<String> _selectedPlayerIds = {};
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _rangeTo = widget.initialRangeTo ??
        DateTime(today.year, today.month, today.day);
    _rangeFrom = widget.initialRangeFrom ??
        _rangeTo.subtract(const Duration(days: 6));
    _periodDays = widget.initialPeriodDays ??
        _rangeTo.difference(_rangeFrom).inDays + 1;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    final today = DateTime.now();
    _searchController.clear();
    setState(() {
      _rangeTo = DateTime(today.year, today.month, today.day);
      _rangeFrom = _rangeTo.subtract(const Duration(days: 6));
      _playerQuery = '';
      _positionFilter = null;
      _teamFilter = null;
      _sessionTypeFilter = null;
      _periodDays = 7;
    });
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final TeamWellness? w = await PlayerMonitoringService.getTeamWellness(
        from: _rangeFrom,
        to: _rangeTo,
        throwOnError: true,
      );
      if (!mounted || generation != _loadGeneration) return;
      final rowsByPlayer = <String, PlayerTrainingLoadRow>{
        for (final row in w?.playersTrainingLoad ?? <PlayerTrainingLoadRow>[])
          if (row.playerId.isNotEmpty) row.playerId: row,
      };
      final rows = rowsByPlayer.values.toList()
        ..sort(
          (a, b) => (a.playerName ?? '').compareTo(b.playerName ?? ''),
        );
      setState(() {
        _rows = rows;
        _activeSeason = w?.activeSeason;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration)
        setState(() {
          _loading = false;
          _error = true;
        });
    }
  }

  String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

  String get _seasonLabel {
    final from = _activeSeason?['starts_on']?.toString();
    final to = _activeSeason?['ends_on']?.toString();
    return from != null && to != null ? '$from — $to' : AppLocalizations.get('no_data');
  }

  List<PlayerTrainingLoadRow> get _filteredRows {
    final query = _playerQuery.trim().toLowerCase();
    return _rows.where((row) {
      if (query.isNotEmpty &&
          !(row.playerName ?? '').toLowerCase().contains(query))
        return false;
      if (_positionFilter != null && row.position != _positionFilter)
        return false;
      if (_teamFilter != null && row.teamName != _teamFilter) return false;
      if (_sessionTypeFilter != null &&
          !row.days28.any(
            (day) => day.sessions.any(
              (session) => session.sessionType == _sessionTypeFilter,
            ),
          )) {
        return false;
      }
      return true;
    }).toList();
  }

  List<PlayerTrainingLoadRow> get _acwrFilteredRows {
    final query = _playerQuery.trim().toLowerCase();
    return _rows.where((row) {
      if (query.isNotEmpty &&
          !(row.playerName ?? '').toLowerCase().contains(query)) {
        return false;
      }
      if (_teamFilter != null && row.teamName != _teamFilter) return false;
      if (_acwrStatusFilter != null &&
          row.acwrClassification != _acwrStatusFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  bool get _allFilteredSelected {
    final filtered = _filteredRows;
    return filtered.isNotEmpty &&
        filtered.every((row) => _selectedPlayerIds.contains(row.playerId));
  }

  void _toggleSelectPlayer(String playerId) {
    setState(() {
      if (_selectedPlayerIds.contains(playerId)) {
        _selectedPlayerIds.remove(playerId);
      } else {
        _selectedPlayerIds.add(playerId);
      }
    });
  }

  void _toggleSelectAllFiltered() {
    final filtered = _filteredRows;
    setState(() {
      if (_allFilteredSelected) {
        for (final row in filtered) {
          _selectedPlayerIds.remove(row.playerId);
        }
      } else {
        for (final row in filtered) {
          _selectedPlayerIds.add(row.playerId);
        }
      }
    });
  }

  Future<void> _exportSelectedPdf() async {
    if (_exporting) return;
    final rows = _filteredRows
        .where((row) => _selectedPlayerIds.contains(row.playerId))
        .toList();
    if (rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final created = await Printing.layoutPdf(
        onLayout: (format) =>
            ReportService.instance.generateTrainingLoadReportPdf(
              rows,
              metadata: ReportMetadata(
                team: _teamFilter ?? AppLocalizations.get('session_team_label'),
                season: _seasonLabel,
                period: '${_shortDate(_rangeFrom)} — ${_shortDate(_rangeTo)}',
                issuedBy: currentUserName,
              ),
              periodDays: _periodDays,
              rangeFrom: _rangeFrom,
              rangeTo: _rangeTo,
            ),
      );
      if (mounted && created) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.get('selected_report_created'))),
        );
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'TeamTrainingLoadReport.exportSelected');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.get('report_create_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickRangeDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _rangeFrom : _rangeTo,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _periodDays = 0;
      if (from) {
        _rangeFrom = picked;
        if (_rangeFrom.isAfter(_rangeTo)) _rangeTo = picked;
      } else {
        _rangeTo = picked;
        if (_rangeTo.isBefore(_rangeFrom)) _rangeFrom = picked;
      }
    });
    _load();
  }

  void _setPeriod(int days) {
    final end = DateTime.now();
    setState(() {
      _periodDays = days;
      _rangeTo = DateTime(end.year, end.month, end.day);
      _rangeFrom = _rangeTo.subtract(Duration(days: days - 1));
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            const CoachBrandHeader(),
            _header(context),
            Expanded(
              child: widget.acwrReport ? _acwrBody() : _body(),
            ),
          ],
        ),
      ),
    );
  }

  // Fixed-height header — back button + title only. The export actions used
  // to live here too, but that made the header grow/shrink with _rows; they
  // now live in _buildActionsBar(), inside the scrollable body instead.
  Widget _header(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    decoration: BoxDecoration(
      color: _card,
      border: Border(bottom: BorderSide(color: _border, width: 0.8)),
    ),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_rounded, color: _fg, size: 17),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            widget.acwrReport
                ? AppLocalizations.get('acwr_report_title')
                : AppLocalizations.get('training_load_report_action'),
            style: const TextStyle(
              color: _fg,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 2,
          ),
        ),
      ],
    ),
  );

  // Horizontally scrollable — mirrors the design mock's overflow-x:auto
  // action row, so long localized labels (e.g. "مشاركة تقارير اللاعبين")
  // never overflow a fixed three-column layout.
  Widget _buildActionsBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _headerAction(
            AppLocalizations.get('export_pdf_label'),
            Icons.picture_as_pdf_outlined,
            null,
            menu: true,
          ),
          _headerAction(
            AppLocalizations.get('download_label'),
            Icons.download_outlined,
            _downloadTeamPdf,
          ),
          _headerAction(
            AppLocalizations.get('share_reports'),
            Icons.share_outlined,
            _shareTeamPdf,
          ),
        ],
      ),
    ),
  );

  Widget _headerAction(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    bool menu = false,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_exporting)
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: _lime),
          )
        else
          Icon(icon, color: _lime, size: 15),
        const SizedBox(width: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _lime,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    if (!menu) {
      return InkWell(
        onTap: _exporting ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: child,
        ),
      );
    }
    return PopupMenuButton<int>(
      enabled: !_exporting,
      onSelected: (value) => value == 0 ? _exportPdf() : _exportCompactPdf(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 0,
          child: Text(AppLocalizations.get('full_report_label')),
        ),
        PopupMenuItem(
          value: 1,
          child: Text(AppLocalizations.get('compact_report_label')),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: child,
      ),
    );
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    final rows = _filteredRows;
    if (rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final created = await Printing.layoutPdf(
        onLayout: (format) =>
            ReportService.instance.generateTrainingLoadReportPdf(
              rows,
              metadata: ReportMetadata(
                team: _teamFilter ?? AppLocalizations.get('session_team_label'),
                season: _seasonLabel,
                period: '${_shortDate(_rangeFrom)} — ${_shortDate(_rangeTo)}',
                issuedBy: currentUserName,
              ),
              periodDays: _periodDays,
              rangeFrom: _rangeFrom,
              rangeTo: _rangeTo,
            ),
      );
      if (mounted && created) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.get('training_report_created'))),
        );
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'TeamTrainingLoadReport.exportPdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.get('report_create_failed')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCompactPdf() async {
    if (_exporting) return;
    final rows = _filteredRows;
    if (rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final created = await Printing.layoutPdf(
        onLayout: (format) => _compactTeamPdfBytes(),
      );
      if (mounted && created) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.get('compact_report_created'))),
        );
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'TeamTrainingLoadReport.exportCompact');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.get('report_create_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<Uint8List> _teamPdfBytes() =>
      ReportService.instance.generateTrainingLoadReportPdf(
        _filteredRows,
        metadata: ReportMetadata(
          team: _teamFilter ?? AppLocalizations.get('session_team_label'),
          season: _seasonLabel,
          period: '${_shortDate(_rangeFrom)} — ${_shortDate(_rangeTo)}',
          issuedBy: currentUserName,
        ),
        periodDays: _periodDays,
        rangeFrom: _rangeFrom,
        rangeTo: _rangeTo,
      );

  Future<Uint8List> _compactTeamPdfBytes() =>
      ReportService.instance.generateCompactTrainingLoadReportPdf(
        _filteredRows,
        metadata: ReportMetadata(
          team: _teamFilter ?? AppLocalizations.get('session_team_label'),
          season: _seasonLabel,
          period: '${_shortDate(_rangeFrom)} — ${_shortDate(_rangeTo)}',
          issuedBy: currentUserName,
        ),
      );

  Future<void> _shareTeamPdf() async {
    if (_exporting || _filteredRows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      await Printing.sharePdf(
        bytes: await _teamPdfBytes(),
        filename: 'team_training_load.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.get('report_ready_to_share'))),
        );
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'TeamTrainingLoadReport.share');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.get('report_share_failed')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _downloadTeamPdf() async {
    if (_exporting || _filteredRows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: AppLocalizations.get('download_report_title'),
        fileName: 'team_training_load.pdf',
        bytes: await _teamPdfBytes(),
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.get('report_saved')}: $path')));
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'TeamTrainingLoadReport.download');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.get('report_download_failed')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<Uint8List> _acwrPdfBytes() =>
      ReportService.instance.generateAcwrReportPdf(
        _acwrFilteredRows,
        metadata: ReportMetadata(
          team: _teamFilter ?? AppLocalizations.get('all_teams_label'),
          season: _seasonLabel,
          period: '${AppLocalizations.get('until_label')} ${_shortDate(_rangeTo)}',
          issuedBy: currentUserName,
        ),
      );

  Future<void> _exportAcwrPdf() async {
    if (_exporting || _acwrFilteredRows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      await Printing.layoutPdf(onLayout: (_) => _acwrPdfBytes());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.get('report_acwr_create_failed')}: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareAcwrPdf() async {
    if (_exporting || _acwrFilteredRows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      await Printing.sharePdf(
        bytes: await _acwrPdfBytes(),
        filename: 'team_acwr_report.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.get('report_acwr_share_failed')}: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _downloadAcwrPdf() async {
    if (_exporting || _acwrFilteredRows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: AppLocalizations.get('report_acwr_download_title'),
        fileName: 'team_acwr_report.pdf',
        bytes: await _acwrPdfBytes(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.get('report_acwr_download_failed')}: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickAcwrDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeTo,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _rangeTo = DateTime(picked.year, picked.month, picked.day);
      _rangeFrom = _rangeTo.subtract(const Duration(days: 27));
    });
    await _load();
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _lime, strokeWidth: 2),
      );
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _muted, size: 40),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.get('error_load_failed'),
              style: TextStyle(color: _fg, fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _load,
              child: Text(AppLocalizations.get('retry_btn')),
            ),
          ],
        ),
      );
    }
    final rows = _filteredRows;
    // A single scrollable (filters + summary + list) rather than a fixed
    // Column-with-Expanded — a tall filters card (custom date range, more
    // filters, etc.) must never be able to overflow the results area.
    return RefreshIndicator(
      color: _lime,
      backgroundColor: _card,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_rows.isNotEmpty) SliverToBoxAdapter(child: _buildActionsBar()),
          SliverToBoxAdapter(child: _buildReportControls()),
          if (rows.isNotEmpty) SliverToBoxAdapter(child: _buildSummary(rows)),
          if (rows.isNotEmpty) SliverToBoxAdapter(child: _buildSelectionBar()),
          if (rows.isNotEmpty) SliverToBoxAdapter(child: _buildViewModeBar()),
          if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(top: 56),
                child: Center(
                  child: Text(
                    AppLocalizations.get('report_no_data'),
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index.isOdd) return const SizedBox(height: 10);
                  final row = rows[index ~/ 2];
                  return _PlayerLoadCard(
                    row: row,
                    detailed: _detailed,
                    exporting: _exporting,
                    periodDays: _periodDays,
                    rangeFrom: _rangeFrom,
                    rangeTo: _rangeTo,
                    selected: _selectedPlayerIds.contains(row.playerId),
                    onToggleSelect: () => _toggleSelectPlayer(row.playerId),
                    onShowDays: () => _showDayDetails(row),
                    onExportPdf: () => _exportPlayerPdf(row),
                  );
                }, childCount: rows.length * 2 - 1),
              ),
            ),
          if (rows.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              sliver: SliverToBoxAdapter(child: _buildTeamOverview(rows)),
            ),
        ],
      ),
    );
  }

  Widget _buildTeamOverview(List<PlayerTrainingLoadRow> rows) {
    final acwrValues = rows.map((row) => row.acwr).whereType<double>().toList();
    final avgAcwr = acwrValues.isEmpty
        ? null
        : acwrValues.reduce((a, b) => a + b) / acwrValues.length;
    final weekTotals = <DateTime, double>{};
    for (final row in rows) {
      for (final day in row.days28) {
        final weekStart = day.date.subtract(Duration(days: day.date.weekday - 1));
        final key = DateTime(weekStart.year, weekStart.month, weekStart.day);
        weekTotals[key] = (weekTotals[key] ?? 0) + day.dailyLoad;
      }
    }
    final sortedWeeks = weekTotals.keys.toList()..sort();
    final points = sortedWeeks
        .map((key) => _MiniBarPoint('${key.day}/${key.month}', weekTotals[key]!))
        .toList();
    final acuteValues = rows.map((row) => row.acuteLoad7d).whereType<double>().toList();
    final chronicValues =
        rows.map((row) => row.chronicLoadWeeklyAverage).whereType<double>().toList();
    final rpeValues = rows.map((row) => row.averageRpe7d).whereType<double>().toList();
    final sessionsTotal = rows.fold<int>(0, (sum, row) => sum + row.sessionsCount7d);
    return Column(
      children: [
        if (avgAcwr != null) ...[
          _AcwrHeroCard(value: avgAcwr, seasonLabel: _seasonLabel),
          const SizedBox(height: 12),
        ],
        _TeamMetricsGrid(
          acuteLoad: acuteValues.isEmpty
              ? null
              : acuteValues.reduce((a, b) => a + b),
          chronicLoad: chronicValues.isEmpty
              ? null
              : chronicValues.reduce((a, b) => a + b),
          averageRpe: rpeValues.isEmpty
              ? null
              : rpeValues.reduce((a, b) => a + b) / rpeValues.length,
          sessionsCount: sessionsTotal,
        ),
        const SizedBox(height: 12),
        if (points.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _softCard(radius: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.get('training_load_weekly_trend'),
                  style: const TextStyle(
                    color: _fg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _MiniBarChart(
                  points: points,
                  barColor: const Color(0x333E6FD9),
                  highlightLastColor: AppColors.gold,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _acwrBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _lime, strokeWidth: 2),
      );
    }
    if (_error) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: Text(AppLocalizations.get('retry_btn')),
        ),
      );
    }

    final rows = _acwrFilteredRows;
    final teams =
        _rows.map((row) => row.teamName).whereType<String>().toSet().toList()
          ..sort();
    final below = rows
        .where((row) => row.acwrClassification == 'BELOW_TARGET')
        .length;
    final ideal = rows
        .where((row) => row.acwrClassification == 'IN_TARGET')
        .length;
    final caution = rows
        .where((row) => row.acwrClassification == 'CAUTION')
        .length;
    final danger = rows
        .where((row) => row.acwrClassification == 'ABOVE_TARGET')
        .length;
    final acwrValues = rows.map((row) => row.acwr).whereType<double>().toList();
    final avgAcwr = acwrValues.isEmpty
        ? null
        : acwrValues.reduce((a, b) => a + b) / acwrValues.length;

    return RefreshIndicator(
      color: _lime,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: _softCard(radius: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerAction(
                    AppLocalizations.get('share_reports'),
                    Icons.share_outlined,
                    _shareAcwrPdf,
                  ),
                  _headerAction(
                    AppLocalizations.get('download_label'),
                    Icons.download_outlined,
                    _downloadAcwrPdf,
                  ),
                  _headerAction(
                    AppLocalizations.get('export_pdf_label'),
                    Icons.picture_as_pdf_outlined,
                    _exportAcwrPdf,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (avgAcwr != null) ...[
            _AcwrHeroCard(value: avgAcwr, seasonLabel: _seasonLabel),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.all(10),
            decoration: _softCard(radius: 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _labeledDropdown(
                    AppLocalizations.get('session_team_label'),
                        _teamFilter,
                        teams,
                        (value) => setState(() => _teamFilter = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _labeledDropdown(
                    AppLocalizations.get('status_label'),
                        _acwrStatusFilter,
                        const [
                          'BELOW_TARGET',
                          'IN_TARGET',
                          'CAUTION',
                          'ABOVE_TARGET',
                        ],
                        (value) =>
                            setState(() => _acwrStatusFilter = value),
                        labelOf: _acwrShortLabel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _playerQuery = value),
                        decoration: InputDecoration(
                          hintText: AppLocalizations.get('player_name'),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _muted,
                            size: 18,
                          ),
                          filled: true,
                          fillColor: AppColors.surface2,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _pickAcwrDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              color: _undertrainingBlue,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _shortDate(_rangeTo),
                              style: const TextStyle(
                                color: _fg,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AcwrSummaryTile(
                  value: below,
                  label: AppLocalizations.get('acwr_below_target'),
                  color: _undertrainingBlue,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _AcwrSummaryTile(
                  value: ideal,
                  label: AppLocalizations.get('acwr_in_target'),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _AcwrSummaryTile(
                  value: caution,
                  label: AppLocalizations.get('acwr_caution'),
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _AcwrSummaryTile(
                  value: danger,
                  label: AppLocalizations.get('acwr_above_target'),
                  color: AppColors.destructive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: Text(
                  AppLocalizations.get('no_data'),
                  style: TextStyle(color: _muted),
                ),
              ),
            )
          else
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AcwrPlayerCard(row: row),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReportControls() {
    final positions =
        _rows.map((row) => row.position).whereType<String>().toSet().toList()
          ..sort();
    final teams =
        _rows.map((row) => row.teamName).whereType<String>().toSet().toList()
          ..sort();
    final sessionTypes =
        _rows
            .expand((row) => row.days28)
            .expand((day) => day.sessions)
            .map((session) => session.sessionType)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.all(12),
      decoration: _softCard(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time_rounded, color: _maroon, size: 14),
              const SizedBox(width: 5),
              Expanded(child: _sectionLabel(AppLocalizations.get('period_filter'))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${AppLocalizations.get('season_label')} $_seasonLabel',
                  style: const TextStyle(
                    color: _maroon,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _periodSegmented(),
          if (_periodDays == 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _dateField(
                    AppLocalizations.get('from_label'),
                    _rangeFrom,
                    () => _pickRangeDate(from: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dateField(
                    AppLocalizations.get('to_label'),
                    _rangeTo,
                    () => _pickRangeDate(from: false),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterPill(
                  AppLocalizations.get('session_team_label'),
                  _teamFilter,
                  teams,
                  (value) => setState(() => _teamFilter = value),
                ),
                const SizedBox(width: 6),
                _filterPill(
                  AppLocalizations.get('position_label'),
                  _positionFilter,
                  positions,
                  (value) => setState(() => _positionFilter = value),
                  labelOf: _positionLabel,
                ),
                const SizedBox(width: 6),
                _filterPill(
                  AppLocalizations.get('session_type'),
                  _sessionTypeFilter,
                  sessionTypes,
                  (value) => setState(() => _sessionTypeFilter = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) =>
                        setState(() => _playerQuery = value),
                    style: const TextStyle(fontSize: 12.5, color: _fg),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.get('search_players'),
                      hintStyle: const TextStyle(color: _muted, fontSize: 11.5),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _muted,
                        size: 17,
                      ),
                      filled: true,
                      fillColor: _bg,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: _maroon, width: 1.4),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 28,
                height: 28,
                child: Material(
                  color: AppColors.primarySoft,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _loading ? null : _resetFilters,
                    child: const Icon(
                      Icons.restart_alt_rounded,
                      color: _maroon,
                      size: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Pill-style filter chip (label + current value + chevron) matching the
  // Training Load Report design mock's horizontal filter row — tap opens a
  // popup menu of the available values for that filter.
  Widget _filterPill(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> onChanged, {
    String Function(String)? labelOf,
  }) {
    final displayValue = value != null
        ? (labelOf != null ? labelOf(value) : value)
        : AppLocalizations.get('all_label');
    return PopupMenuButton<String?>(
      onSelected: onChanged,
      color: _card,
      itemBuilder: (_) => [
        PopupMenuItem<String?>(
          value: null,
          child: Text(AppLocalizations.get('all_label')),
        ),
        ...values.map(
          (item) => PopupMenuItem<String?>(
            value: item,
            child: Text(labelOf != null ? labelOf(item) : item),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: _bg,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 72),
              child: Text(
                displayValue,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _fg,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, color: _muted, size: 13),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: const TextStyle(
      color: _fg,
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _periodSegmented() {
    final options = <(String, int)>[
      (AppLocalizations.get('period_today'), 1),
      (AppLocalizations.get('period_7_days'), 7),
      (AppLocalizations.get('period_28_days'), 28),
      (AppLocalizations.get('period_custom'), 0),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: options.map((option) {
          final (label, days) = option;
          final selected = _periodDays == days;
          return Expanded(
            child: GestureDetector(
              onTap: () =>
                  days == 0 ? setState(() => _periodDays = 0) : _setPeriod(days),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _maroon : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : _fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fullArabicDate(DateTime date) => AppLocalizations.formatFullDate(date);

  Widget _dateField(String label, DateTime date, VoidCallback onTap) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _fullArabicDate(date),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.calendar_today_rounded,
                    color: _lime,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _labeledDropdown(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> onChanged, {
    String Function(String)? labelOf,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButtonFormField<String>(
            value: values.contains(value) ? value : null,
            isExpanded: true,
            isDense: true,
            dropdownColor: _card,
            icon: const Icon(
              Icons.expand_more_rounded,
              color: _maroon,
              size: 20,
            ),
            style: const TextStyle(
              color: _fg,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 9),
            ),
            items: [
              DropdownMenuItem<String>(
                value: null,
                child: Text(AppLocalizations.get('all_label')),
              ),
              ...values.map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    labelOf != null ? labelOf(item) : item,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    ],
  );

  Widget _buildSelectionBar() {
    final selectedCount = _selectedPlayerIds.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleSelectAllFiltered,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _allFilteredSelected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: _allFilteredSelected ? _maroon : _muted,
                  size: 19,
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.get('select_all_filtered'),
                  style: TextStyle(
                    color: _fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (selectedCount > 0) ...[
            Text(
              AppLocalizations.format('session_selected_count', {
                'count': selectedCount,
              }),
              style: const TextStyle(
                color: _muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _exporting ? null : _exportSelectedPdf,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _maroon,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_exporting)
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(
                        Icons.picture_as_pdf_outlined,
                        color: Colors.white,
                        size: 14,
                      ),
                    const SizedBox(width: 5),
                    Text(
                      AppLocalizations.get('export_selected_report'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewModeBar() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    child: Row(
      children: [
        Text(
          AppLocalizations.get('view_mode'),
          style: TextStyle(
            color: _muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        _viewModePill(
          AppLocalizations.get('compact_view'),
          !_detailed,
          () => setState(() => _detailed = false),
        ),
        const SizedBox(width: 6),
        _viewModePill(
          AppLocalizations.get('detailed_view'),
          _detailed,
          () => setState(() => _detailed = true),
        ),
      ],
    ),
  );

  Widget _viewModePill(String label, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? _maroon.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? _maroon.withOpacity(0.5) : _border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _maroon : _muted,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ),
      );

  double? _loadForPeriod(PlayerTrainingLoadRow row) =>
      computePeriodLoad(row, _periodDays, _rangeFrom, _rangeTo);

  Widget _buildSummary(List<PlayerTrainingLoadRow> rows) {
    final loads = rows.map(_loadForPeriod).whereType<double>().toList();
    final total = loads.fold<double>(0, (sum, value) => sum + value);
    final hasIncompletePeriod = rows.any(
      (row) => isPeriodDataIncomplete(row, _rangeFrom, _rangeTo),
    );
    final completeness = rows
        .map(
          (row) =>
              computePeriodDataCompleteness(row, _rangeFrom, _rangeTo),
        )
        .toList();
    final inside = rows
        .where((row) => row.acwrClassification == 'IN_TARGET')
        .length;
    final caution = rows
        .where((row) => row.acwrClassification == 'CAUTION')
        .length;
    final danger = rows
        .where((row) => row.acwrClassification == 'ABOVE_TARGET')
        .length;
    final below = rows
        .where((row) => row.acwrClassification == 'BELOW_TARGET')
        .length;
    final missingRpe = rows.fold<int>(
      0,
      (sum, row) =>
          sum +
          trainingLoadDaysInPeriod(row, _rangeFrom, _rangeTo)
              .expand((day) => day.dataQualityIssues)
              .where((issue) => issue.contains('RPE'))
              .length,
    );
    final missingDuration = rows.fold<int>(
      0,
      (sum, row) =>
          sum +
          trainingLoadDaysInPeriod(row, _rangeFrom, _rangeTo)
              .expand((day) => day.dataQualityIssues)
              .where((issue) => issue.contains('DURATION'))
              .length,
    );
    final completenessValue = hasIncompletePeriod
        ? AppLocalizations.get('status_missing_data')
        : completeness.isEmpty
        ? AppLocalizations.get('no_data')
        : '${(completeness.fold<double>(0, (a, b) => a + b) / completeness.length * 100).toStringAsFixed(0)}%';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SizedBox(
        height: 74,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _summaryCard(
              AppLocalizations.get('load_total'),
              loads.isEmpty ? AppLocalizations.get('no_data') : total.toStringAsFixed(0),
              unit: loads.isEmpty ? null : 'AU',
            ),
            _summaryCard(
              AppLocalizations.get('load_average'),
              loads.isEmpty
                  ? AppLocalizations.get('no_data')
                  : (total / loads.length).toStringAsFixed(0),
              unit: loads.isEmpty ? null : 'AU',
            ),
            _summaryCard(
              AppLocalizations.get('load_highest'),
              loads.isEmpty
                  ? AppLocalizations.get('no_data')
                  : loads.reduce((a, b) => a > b ? a : b).toStringAsFixed(0),
              unit: loads.isEmpty ? null : 'AU',
            ),
            _summaryCard(AppLocalizations.get('period_completeness_short'), completenessValue),
            _summaryCard(
              AppLocalizations.get('load_lowest'),
              loads.isEmpty
                  ? AppLocalizations.get('no_data')
                  : loads.reduce((a, b) => a < b ? a : b).toStringAsFixed(0),
              unit: loads.isEmpty ? null : 'AU',
            ),
            _summaryCard(
              AppLocalizations.get('missing_rpe_short'),
              '$missingRpe',
            ),
            _summaryCard(
              AppLocalizations.get('missing_duration_short'),
              '$missingDuration',
            ),
            _summaryCard(
              AppLocalizations.get('acwr_in_target'),
              '$inside',
              valueColor: AppColors.success,
            ),
            _summaryCard(
              AppLocalizations.get('acwr_caution'),
              '$caution',
              valueColor: AppColors.warning,
            ),
            _summaryCard(
              AppLocalizations.get('acwr_above_target'),
              '$danger',
              valueColor: AppColors.destructive,
            ),
            _summaryCard(
              AppLocalizations.get('acwr_below_target'),
              '$below',
              valueColor: _undertrainingBlue,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(
    String label,
    String value, {
    String? unit,
    Color valueColor = _lime,
    bool isLast = false,
  }) => Container(
    width: 108,
    margin: EdgeInsetsDirectional.only(end: isLast ? 0 : 8),
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: _softCard(radius: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: _muted, fontSize: 10.5)),
      ],
    ),
  );

  Future<void> _exportPlayerPdf(PlayerTrainingLoadRow row) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final created = await Printing.layoutPdf(
        onLayout: (format) =>
            ReportService.instance.generatePlayerTrainingLoadReportPdf(
              row: row,
              periodDays: _periodDays,
              rangeFrom: _rangeFrom,
              rangeTo: _rangeTo,
              metadata: ReportMetadata(
                team: row.teamName ?? _teamFilter ?? AppLocalizations.get('session_team_label'),
                season: _seasonLabel,
                period: '${_shortDate(_rangeFrom)} — ${_shortDate(_rangeTo)}',
                issuedBy: currentUserName,
              ),
            ),
      );
      if (mounted && created) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.get('report_saved'))),
        );
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'TeamTrainingLoadReport.exportPlayer');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.get('player_report_create_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showDayDetails(PlayerTrainingLoadRow r) {
    final visibleDays = trainingLoadDaysInPeriod(r, _rangeFrom, _rangeTo);
    final periodCompleteness = computePeriodDataCompleteness(
      r,
      _rangeFrom,
      _rangeTo,
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Column(
                children: [
                  Text(
                    r.playerName ?? '—',
                    style: const TextStyle(
                      color: _fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DetailMetric(
                          label: periodLoadLabel(_periodDays),
                          value:
                              _formatLoad(
                                computePeriodLoad(
                                  r,
                                  _periodDays,
                                  _rangeFrom,
                                  _rangeTo,
                                ),
                              ) ??
                              AppLocalizations.get('no_data'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DetailMetric(
                          label: AppLocalizations.get('period_completeness_short'),
                          value:
                              '${(periodCompleteness * 100).toStringAsFixed(0)}%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      AppLocalizations.get('daily_load'),
                      style: TextStyle(
                        color: _fg,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _DailyLoadChart(days: visibleDays),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _CompactChartCard(
                          title: AppLocalizations.get('week_comparison'),
                          child: _WeeklyLoadChart(days: visibleDays),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactChartCard(
                          title: AppLocalizations.get('load_by_activity'),
                          child: _ActivityLoadChart(days: visibleDays),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _UnavailableComparison(
                          title: AppLocalizations.get('load_vs_hooper'),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: _UnavailableComparison(
                          title: AppLocalizations.get('load_vs_readiness'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _border),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: visibleDays.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = visibleDays[i];
                  final dayComplete = isTrainingLoadDayCompleteForPeriod(d);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                '${d.date.day}/${d.date.month}',
                                style: const TextStyle(
                                  color: _fg,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'RPE ${_rpeCellFor(d) ?? AppLocalizations.get('no_data')}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${_durationCellFor(d) ?? AppLocalizations.get('no_data')} ${AppLocalizations.get('minute_unit')}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'sRPE ${_dailyLoadCellFor(d)}',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: _lime,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (d.sessions.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ...d.sessions.map(
                            (session) => Text(
                              '${session.sessionName ?? session.sessionType ?? AppLocalizations.get('session_label')} · '
                              '${session.actualDurationMinutes?.toString() ?? AppLocalizations.get('duration_unavailable')} · '
                              'RPE ${session.rpe?.toStringAsFixed(1) ?? AppLocalizations.get('no_data')}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 5),
                        Text(
                          '${AppLocalizations.get('attendance_label')}: ${_participationLabel(d.participationStatus)} · '
                          '${AppLocalizations.get('data_status_label')}: ${dayComplete ? AppLocalizations.get('complete_label') : AppLocalizations.get('incomplete_label')}',
                          style: const TextStyle(color: _muted, fontSize: 10),
                        ),
                        if (!dayComplete) ...[
                          const SizedBox(height: 5),
                          Text(
                          '${AppLocalizations.get('missing_reasons_label')}: ${d.dataQualityIssues.map(_issueLabel).join('، ')}',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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

  String? _formatLoad(double? load) {
    if (load == null) return null;
    if (load == 0) return '0';
    return load.toStringAsFixed(0);
  }

  // A day can have more than one session (see TrainingLoadCalculator) — show
  // the single value when there's exactly one, otherwise be explicit that
  // it's a multi-session day rather than silently showing only the first.
  String? _rpeCellFor(TrainingLoadDay? d) {
    if (d == null || d.sessions.isEmpty) return null;
    return d.sessions
        .map((session) => session.rpe?.toStringAsFixed(1) ?? AppLocalizations.get('no_data'))
        .join('+');
  }

  String? _durationCellFor(TrainingLoadDay? d) {
    if (d == null || d.sessions.isEmpty) return null;
    return d.sessions
        .map(
          (session) => session.actualDurationMinutes?.toString() ?? AppLocalizations.get('duration_unavailable'),
        )
        .join('+');
  }

  String _dailyLoadCellFor(TrainingLoadDay day) {
    if (day.sessions.isEmpty && day.participationStatus != 'REST') {
      return AppLocalizations.get('no_data');
    }
    return _formatLoad(day.dailyLoad) ?? AppLocalizations.get('no_data');
  }

  String _issueLabel(String issue) {
    switch (issue) {
      case 'MISSING_RPE':
        return AppLocalizations.get('missing_rpe');
      case 'MISSING_DURATION':
      case 'PARTIAL_SESSION_MISSING_DURATION':
        return AppLocalizations.get('missing_duration');
      case 'SCHEDULED_SESSION_MISSING_RECORD':
        return AppLocalizations.get('missing_session_record');
      case 'MATCH_MISSING_RPE':
        return '${AppLocalizations.get('missing_rpe')} (match)';
      case 'UNRESOLVED_ATTENDANCE':
        return AppLocalizations.get('unresolved_attendance');
      case 'DUPLICATE_RPE':
        return AppLocalizations.get('duplicate_rpe');
      case 'INVALID_DURATION':
        return AppLocalizations.get('invalid_duration');
      case 'INVALID_RPE':
        return AppLocalizations.get('invalid_rpe');
      case 'HISTORICAL_STATUS_UNKNOWN':
      case 'UNKNOWN_DAY_STATUS':
        return AppLocalizations.get('historical_status_unknown');
      default:
        return issue;
    }
  }

  String _participationLabel(String status) {
    switch (status) {
      case 'COMPLETE':
        return AppLocalizations.get('attendance_present');
      case 'REST':
        return AppLocalizations.get('attendance_rest');
      case 'ABSENT':
        return AppLocalizations.get('attendance_absent');
      case 'UNAVAILABLE':
        return AppLocalizations.get('attendance_unavailable');
      case 'MISSING_RPE':
      case 'MATCH_MISSING_RPE':
        return AppLocalizations.get('missing_rpe');
      case 'MISSING_DURATION':
        return AppLocalizations.get('missing_duration');
      default:
        return AppLocalizations.get('no_data');
    }
  }
}

String _loadValueLabel(double? load, bool incomplete) {
  if (load == null) return AppLocalizations.get('no_data');
  if (load == 0 && incomplete) {
    return '0 — ${AppLocalizations.get('preliminary_data')}';
  }
  return load.toStringAsFixed(0);
}

// Design-mock hero card for the team's average ACWR — matches the
// isLoadDetail gradient hero in the Physical Coach Dashboard mock.
class _AcwrHeroCard extends StatelessWidget {
  const _AcwrHeroCard({required this.value, required this.seasonLabel});

  final double value;
  final String seasonLabel;

  // Fixed blue gradient — matches the Training Load Report design mock's
  // hero card exactly (not risk-color-graded like the dashboard's variant).
  static const _heroStart = Color(0xFF2E4E9E);
  static const _heroEnd = Color(0xFF1B2F63);

  @override
  Widget build(BuildContext context) {
    final classification = _classificationForValue(value);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_heroStart, _heroEnd],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seasonLabel,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'ACWR',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _acwrReason(classification),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _acwrShortLabel(classification),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _classificationForValue(double v) {
    if (v < 0.8) return 'BELOW_TARGET';
    if (v <= 1.3) return 'IN_TARGET';
    if (v <= 1.5) return 'CAUTION';
    return 'ABOVE_TARGET';
  }
}

// Team-level 2x2 metrics grid (icon chip + value/unit + label) — matches
// the Training Load Report design mock's metrics cards, sitting between the
// ACWR hero card and the weekly trend chart.
class _TeamMetricsGrid extends StatelessWidget {
  const _TeamMetricsGrid({
    required this.acuteLoad,
    required this.chronicLoad,
    required this.averageRpe,
    required this.sessionsCount,
  });

  final double? acuteLoad;
  final double? chronicLoad;
  final double? averageRpe;
  final int sessionsCount;

  static const _iconBg = Color(0xFFEAF0FB);
  static const _iconColor = Color(0xFF3E6FD9);

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        Icons.speed_rounded,
        acuteLoad?.toStringAsFixed(0) ?? '—',
        'AU',
        '${AppLocalizations.get('acute_load')} (7d)',
      ),
      (
        Icons.bar_chart_rounded,
        chronicLoad?.toStringAsFixed(0) ?? '—',
        'AU',
        '${AppLocalizations.get('chronic_load')} (4w)',
      ),
      (
        Icons.bolt_rounded,
        averageRpe?.toStringAsFixed(1) ?? '—',
        '/10',
        AppLocalizations.get('average_rpe'),
      ),
      (
        Icons.event_available_rounded,
        '$sessionsCount',
        '',
        AppLocalizations.get('sessions_label'),
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.85,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.all(11),
              decoration: _softCard(radius: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _iconBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.$1, color: _iconColor, size: 13),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        item.$2,
                        style: const TextStyle(
                          color: _fg,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (item.$3.isNotEmpty) ...[
                        const SizedBox(width: 3),
                        Text(
                          item.$3,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    item.$4,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _AcwrSummaryTile extends StatelessWidget {
  const _AcwrSummaryTile({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.30)),
    ),
    child: Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _AcwrPlayerCard extends StatelessWidget {
  const _AcwrPlayerCard({required this.row});

  final PlayerTrainingLoadRow row;

  @override
  Widget build(BuildContext context) {
    final color = _acwrColor(row.acwrClassification);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x0D161616), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                color: _card,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.playerName ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _fg,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _acwrShortLabel(row.acwrClassification),
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatBlock(
                            label: AppLocalizations.get('acute_load'),
                            value:
                                row.acuteLoad7d?.toStringAsFixed(0) ?? '—',
                            color: _fg,
                          ),
                        ),
                        Expanded(
                          child: _StatBlock(
                            label: AppLocalizations.get('chronic_load'),
                            value: row.chronicLoadWeeklyAverage
                                    ?.toStringAsFixed(0) ??
                                '—',
                            color: _fg,
                          ),
                        ),
                        Expanded(
                          child: _StatBlock(
                            label: 'ACWR',
                            value: row.acwr?.toStringAsFixed(2) ?? '—',
                            color: color,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Player Load Card — weekly summary first; daily breakdown is one tap away.
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerLoadCard extends StatelessWidget {
  const _PlayerLoadCard({
    required this.row,
    required this.detailed,
    required this.exporting,
    required this.periodDays,
    required this.rangeFrom,
    required this.rangeTo,
    required this.selected,
    required this.onToggleSelect,
    required this.onShowDays,
    required this.onExportPdf,
  });
  final PlayerTrainingLoadRow row;
  final bool detailed;
  final bool exporting;
  final int periodDays;
  final DateTime rangeFrom;
  final DateTime rangeTo;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onShowDays;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    final incomplete = isPeriodDataIncomplete(row, rangeFrom, rangeTo);
    final periodCompleteness = computePeriodDataCompleteness(
      row,
      rangeFrom,
      rangeTo,
    );
    final acwrLabel = row.acwr == null
        ? AppLocalizations.get('acwr_requires_complete_28')
        : row.acwr!.toStringAsFixed(2);
    final classification = _classificationLabel(row.acwrClassification);
    final acwrColor = _acwrColor(row.acwrClassification);
    final selectedDays = trainingLoadDaysInPeriod(row, rangeFrom, rangeTo);
    final selectedSessions = selectedDays
        .expand((day) => day.sessions)
        .toList();
    final selectedMinutes = selectedSessions.fold<int>(
      0,
      (sum, session) => sum + (session.actualDurationMinutes ?? 0),
    );
    final selectedRpes = selectedSessions
        .map((session) => session.rpe)
        .whereType<double>()
        .toList();
    final selectedAverageRpe = selectedRpes.isEmpty
        ? null
        : selectedRpes.reduce((a, b) => a + b) / selectedRpes.length;
    // The ACWR/data-quality accent is drawn as a separate sibling bar rather
    // than a per-side BorderSide, because
    // Flutter's Border painter requires a uniform border when a borderRadius
    // is set — a thicker/colored single side + radius throws at paint time.
    final card = Container(
      padding: const EdgeInsets.all(14),
      color: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onToggleSelect,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Icon(
                    selected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: selected ? _maroon : _muted,
                    size: 21,
                  ),
                ),
              ),
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surface2,
                backgroundImage:
                    row.playerPhotoUrl != null && row.playerPhotoUrl!.isNotEmpty
                    ? NetworkImage(row.playerPhotoUrl!)
                    : null,
                child: row.playerPhotoUrl == null || row.playerPhotoUrl!.isEmpty
                    ? const Icon(Icons.person_rounded, color: _muted, size: 20)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.playerName ?? '—',
                      style: const TextStyle(
                        color: _fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _positionLabel(row.position),
                      style: const TextStyle(color: _muted, fontSize: 10.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    acwrLabel,
                    style: TextStyle(
                      color: acwrColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'ACWR',
                    style: TextStyle(color: _muted, fontSize: 8),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: exporting ? null : onExportPdf,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: exporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(
                          Icons.picture_as_pdf_outlined,
                          color: _lime,
                          size: 16,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: periodLoadLabel(periodDays),
                  value: _loadValueLabel(
                    computePeriodLoad(row, periodDays, rangeFrom, rangeTo),
                    incomplete,
                  ),
                  color: _lime,
                ),
              ),
              Expanded(
                child: _StatBlock(
                  label: AppLocalizations.get('acwr'),
                  value: acwrLabel,
                  color: acwrColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (periodDays != 1)
            Row(
              children: [
                Expanded(
                  child: _StatBlock(
                    label: '${AppLocalizations.get('acute_load')} (7d)',
                    value: _loadValueLabel(row.acuteLoad7d, incomplete),
                    color: _fg,
                  ),
                ),
                Expanded(
                  child: _StatBlock(
                    label: '${AppLocalizations.get('chronic_load')} (4w avg)',
                    value: _loadValueLabel(
                      row.chronicLoadWeeklyAverage,
                      incomplete,
                    ),
                    color: _fg,
                  ),
                ),
              ],
            ),
          if (detailed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                child: _StatBlock(
                  label: AppLocalizations.get('sessions_label'),
                  value: '${selectedSessions.length}',
                  color: _fg,
                ),
                ),
                Expanded(
                child: _StatBlock(
                  label: AppLocalizations.get('duration_minutes'),
                  value: '$selectedMinutes',
                  color: _fg,
                ),
                ),
                Expanded(
                child: _StatBlock(
                  label: AppLocalizations.get('average_rpe'),
                  value: selectedAverageRpe?.toStringAsFixed(1) ??
                      AppLocalizations.get('no_data'),
                  color: _fg,
                ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${AppLocalizations.get('classification_title')}: $classification · '
              '${AppLocalizations.get('period_completeness')}: '
              '${incomplete
                  ? AppLocalizations.get('status_missing_data')
                  : '${(periodCompleteness * 100).toStringAsFixed(0)}%'}',
              style: TextStyle(color: acwrColor, fontSize: 10.5),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onShowDays,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.calendar_view_week_rounded,
                      color: _lime,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.get('days_details'),
                      style: TextStyle(
                        color: _fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0D161616), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      // IntrinsicHeight gives the Row a real (bounded) height to stretch
      // its children to — without it, a sliver list item has unbounded
      // height, and CrossAxisAlignment.stretch on an unbounded Row fails
      // layout for the whole list, not just this card.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              color: incomplete ? AppColors.destructive : acwrColor,
            ),
            Expanded(child: card),
          ],
        ),
      ),
      ),
    );
  }

  String _classificationLabel(String value) {
    switch (value) {
      case 'IN_TARGET':
        return AppLocalizations.get('acwr_in_target');
      case 'BELOW_TARGET':
        return AppLocalizations.get('acwr_below_target');
      case 'ABOVE_TARGET':
        return AppLocalizations.get('acwr_above_target');
      case 'CAUTION':
        return AppLocalizations.get('acwr_caution');
      case 'NO_CHRONIC_LOAD':
        return AppLocalizations.get('acwr_no_chronic_load');
      default:
        return AppLocalizations.get('acwr_insufficient_data');
    }
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _muted, fontSize: 10.5)),
      ],
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _lime,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

class _CompactChartCard extends StatelessWidget {
  const _CompactChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _fg,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _UnavailableComparison extends StatelessWidget {
  const _UnavailableComparison({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _fg,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppLocalizations.get('server_unavailable'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 8.5),
          ),
        ],
      ),
    );
  }
}

class _WeeklyLoadChart extends StatelessWidget {
  const _WeeklyLoadChart({required this.days});

  final List<TrainingLoadDay> days;

  @override
  Widget build(BuildContext context) {
    final points = <_MiniBarPoint>[];
    for (var index = 0; index < days.length; index += 7) {
      final end = (index + 7).clamp(0, days.length);
      final load = days
          .sublist(index, end)
          .fold<double>(0, (sum, day) => sum + day.dailyLoad);
      points.add(_MiniBarPoint('W${points.length + 1}', load));
    }
    return _MiniBarChart(points: points);
  }
}

class _ActivityLoadChart extends StatelessWidget {
  const _ActivityLoadChart({required this.days});

  final List<TrainingLoadDay> days;

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    for (final day in days) {
      for (final session in day.sessions) {
        final load = session.sessionLoad;
        if (load == null) continue;
        final type = (session.sessionType?.trim().isNotEmpty ?? false)
            ? session.sessionType!.trim()
            : AppLocalizations.get('undefined_label');
        totals[type] = (totals[type] ?? 0) + load;
      }
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final points = entries
        .take(5)
        .map((entry) => _MiniBarPoint(entry.key, entry.value))
        .toList();
    return _MiniBarChart(points: points);
  }
}

class _MiniBarPoint {
  const _MiniBarPoint(this.label, this.value);

  final String label;
  final double value;
}

class _MiniBarChart extends StatelessWidget {
  const _MiniBarChart({
    required this.points,
    this.barColor = _lime,
    this.highlightLastColor,
  });

  final List<_MiniBarPoint> points;
  final Color barColor;
  final Color? highlightLastColor;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty || !points.any((point) => point.value > 0)) {
      return SizedBox(
        height: 52,
        child: Center(
          child: Text(
            AppLocalizations.get('no_data'),
            style: TextStyle(color: _muted, fontSize: 9),
          ),
        ),
      );
    }
    final maxValue = points.fold<double>(
      0,
      (value, point) => point.value > value ? point.value : value,
    );
    return SizedBox(
      height: 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.asMap().entries.map((entry) {
          final point = entry.value;
          final isLast = entry.key == points.length - 1;
          final ratio = (point.value / maxValue).clamp(0.08, 1.0);
          return Expanded(
            child: Tooltip(
              message: '${point.label}: ${point.value.toStringAsFixed(0)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: ratio,
                          child: Container(
                            width: 18,
                            decoration: BoxDecoration(
                              color: isLast && highlightLastColor != null
                                  ? highlightLastColor
                                  : barColor,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      point.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 7.5),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DailyLoadChart extends StatelessWidget {
  const _DailyLoadChart({required this.days});
  final List<TrainingLoadDay> days;

  @override
  Widget build(BuildContext context) {
    final visible = days.length > 14 ? days.sublist(days.length - 14) : days;
    final maxLoad = visible.fold<double>(
      0,
      (max, day) => day.dailyLoad > max ? day.dailyLoad : max,
    );
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: visible.map((day) {
          final ratio = maxLoad <= 0
              ? 0.05
              : (day.dailyLoad / maxLoad).clamp(0.05, 1.0);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Tooltip(
                message:
                    '${day.date.day}/${day.date.month}: ${day.dailyLoad.toStringAsFixed(0)}',
                child: FractionallySizedBox(
                  heightFactor: ratio,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    decoration: BoxDecoration(
                      color: day.dataQualityIssues.isEmpty
                          ? _lime
                          : AppColors.warning,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
