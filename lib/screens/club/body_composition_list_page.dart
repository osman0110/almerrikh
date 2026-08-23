import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/body_composition_models.dart';
import '../../models/club_models.dart';
import '../../services/body_composition_service.dart';
import '../../services/club_service.dart';
import '../../services/report_service.dart';
import '../../utils/crash_reporter.dart';
import '../../utils/metric_formatter.dart';
import '../player/body_composition_entry_screen.dart';
import 'body_composition_bulk_import_page.dart';

class BodyCompositionListPage extends StatefulWidget {
  const BodyCompositionListPage({
    super.key,
    this.initialDateFrom,
    this.initialDateTo,
  });

  final DateTime? initialDateFrom;
  final DateTime? initialDateTo;

  @override
  State<BodyCompositionListPage> createState() =>
      _BodyCompositionListPageState();
}

class _BodyCompositionListPageState extends State<BodyCompositionListPage> {
  List<BodyCompositionEntry> _all = [];
  List<Map<String, dynamic>> _missingPlayers = [];
  Map<String, dynamic>? _activeSeason;
  bool _loading = true;
  bool _error = false;
  int _loadGeneration = 0;
  bool _exporting = false;
  bool _canCreate = false;
  bool _canUpdate = false;
  bool _canImport = false;
  final Set<String> _exportingPlayerPdfs = {};
  String? _positionFilter;
  String? _goalStatusFilter;
  String? _teamFilter;
  String? _dataFilter;
  String? _trendFilter;
  String _playerQuery = '';
  late DateTime _dateFrom;
  late DateTime _dateTo;
  bool _detailed = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _dateTo = widget.initialDateTo ?? today;
    _dateFrom = widget.initialDateFrom ??
        today.subtract(const Duration(days: 90));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    final now = DateTime.now();
    _searchController.clear();
    setState(() {
      _positionFilter = null;
      _goalStatusFilter = null;
      _teamFilter = null;
      _dataFilter = null;
      _trendFilter = null;
      _playerQuery = '';
      _dateTo = now;
      _dateFrom = now.subtract(const Duration(days: 90));
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
      final results = await Future.wait<dynamic>([
        BodyCompositionService.getList(
          position: _positionFilter,
          team: _teamFilter,
          goalStatus: _goalStatusFilter,
          dateFrom: _isoDate(_dateFrom),
          dateTo: _isoDate(_dateTo),
          allHistory:
              widget.initialDateFrom != null || widget.initialDateTo != null,
          perPage: 100,
          throwOnError: true,
        ),
        BodyCompositionService.getActiveSeason(),
      ]);
      final res = results[0] as Map<String, dynamic>;
      final list =
          (res['assessments'] as List?)
              ?.map(
                (e) => BodyCompositionEntry.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [];
      final missing = (res['players_without_data'] as List<dynamic>? ?? [])
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
      final permissions = res['permissions'] as Map<String, dynamic>? ?? const {};
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _all = list;
          _missingPlayers = missing;
          _canCreate = permissions['can_create'] == true;
          _canUpdate = permissions['can_update'] == true;
          _canImport = permissions['can_import'] == true;
          _activeSeason = results[1] as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  // "+" must ask which player the measurement is for first — the entry
  // screen itself has no player picker, so pushing it with no playerId used
  // to silently fail to save (the backend requires player_id for a coach).
  Future<void> _startNewEntry() async {
    final player = await _pickPlayer();
    if (player == null || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BodyCompositionEntryScreen(playerId: player.id),
      ),
    );
    if (saved == true) _load();
  }

  Future<ClubPlayer?> _pickPlayer() async {
    final players = await ClubService().getPlayers();
    if (!mounted) return null;
    if (players.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد لاعبون في الفريق')),
      );
      return null;
    }
    return showModalBottomSheet<ClubPlayer>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final filtered = players
                .where(
                  (p) => p.fullName.toLowerCase().contains(
                    query.trim().toLowerCase(),
                  ),
                )
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.75,
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'اختر اللاعب',
                            style: TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            autofocus: false,
                            onChanged: (value) =>
                                setSheetState(() => query = value),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'ابحث باسم اللاعب',
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: AppColors.muted,
                                size: 18,
                              ),
                              filled: true,
                              fillColor: AppColors.surface2,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'لا يوجد لاعب مطابق',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, index) {
                                final player = filtered[index];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () =>
                                      Navigator.of(sheetContext).pop(player),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface2,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: AppColors.card,
                                          backgroundImage:
                                              player.profileImageUrl != null &&
                                                  player
                                                      .profileImageUrl!
                                                      .isNotEmpty
                                              ? NetworkImage(
                                                  player.profileImageUrl!,
                                                )
                                              : null,
                                          child:
                                              player.profileImageUrl == null ||
                                                  player
                                                      .profileImageUrl!
                                                      .isEmpty
                                              ? const Icon(
                                                  Icons.person_rounded,
                                                  color: AppColors.muted,
                                                  size: 18,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                player.fullName,
                                                style: const TextStyle(
                                                  color: AppColors.foreground,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '${player.teamName ?? ''} · ${player.position}',
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 11,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_left_rounded,
                                          color: AppColors.muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<String> get _positions => _allDistinct((e) => e.position);
  List<String> get _teams => _allDistinct((e) => e.teamName);
  List<BodyCompositionEntry> get _visibleEntries => _all.where((entry) {
    final query = _playerQuery.trim().toLowerCase();
    if (query.isNotEmpty &&
        !(entry.playerName ?? '').toLowerCase().contains(query))
      return false;
    if (_dataFilter == 'without_data') return false;
    final delta = entry.delta?.bodyFatPercentage;
    if (_trendFilter == 'up' && (delta == null || delta <= 0)) return false;
    if (_trendFilter == 'down' && (delta == null || delta >= 0)) return false;
    return true;
  }).toList();
  // Approval gating removed — a coach-recorded measurement is usable in
  // reports the moment it's saved, no separate approval step.
  List<BodyCompositionEntry> get _approvedVisibleEntries => _visibleEntries;
  List<Map<String, dynamic>> get _visibleMissingPlayers {
    if (_dataFilter == 'with_data') return const [];
    final query = _playerQuery.trim().toLowerCase();
    return _missingPlayers.where((player) {
      if (query.isNotEmpty &&
          !(player['name']?.toString() ?? '').toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickRangeDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _dateFrom : _dateTo,
      firstDate: DateTime.now().subtract(const Duration(days: 1825)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _dateFrom = picked;
        if (_dateFrom.isAfter(_dateTo)) _dateTo = picked;
      } else {
        _dateTo = picked;
        if (_dateTo.isBefore(_dateFrom)) _dateFrom = picked;
      }
    });
    _load();
  }

  List<String> _allDistinct(String? Function(BodyCompositionEntry) f) {
    final set = <String>{};
    for (final e in _all) {
      final v = f(e);
      if (v != null && v.isNotEmpty) set.add(v);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    final entries = _approvedVisibleEntries;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد قياسات لإصدار التقرير')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final created = await Printing.layoutPdf(
        onLayout: (format) =>
            ReportService.instance.generateTeamBodyCompositionReportPdf(
              entries: entries,
              excludedPlayersCount: _visibleMissingPlayers.length,
              metadata: ReportMetadata(
                team: _teamFilter ?? 'الفريق',
                season: _seasonLabel,
                period: '${_isoDate(_dateFrom)} — ${_isoDate(_dateTo)}',
                issuedBy: currentUserName,
              ),
            ),
      );
      if (mounted && created) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء تقرير الدهون بنجاح')),
        );
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'BodyCompositionList.exportPdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إنشاء تقرير الدهون: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<Uint8List> _teamPdfBytes() =>
      ReportService.instance.generateTeamBodyCompositionReportPdf(
        entries: _approvedVisibleEntries,
        excludedPlayersCount: _visibleMissingPlayers.length,
        metadata: ReportMetadata(
          team: _teamFilter ?? 'الفريق',
          season: _seasonLabel,
          period: '${_isoDate(_dateFrom)} — ${_isoDate(_dateTo)}',
          issuedBy: currentUserName,
        ),
      );

  Future<void> _sharePdf() async {
    if (_exporting || _approvedVisibleEntries.isEmpty) return;
    setState(() => _exporting = true);
    try {
      await Printing.sharePdf(
        bytes: await _teamPdfBytes(),
        filename: 'team_body_composition.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تجهيز التقرير للمشاركة')),
        );
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'BodyCompositionList.share');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر مشاركة التقرير: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _downloadPdf() async {
    if (_exporting || _approvedVisibleEntries.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'تنزيل تقرير الدهون',
        fileName: 'team_body_composition.pdf',
        bytes: await _teamPdfBytes(),
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تم حفظ التقرير: $path')));
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'BodyCompositionList.download');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تنزيل التقرير: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String get _seasonLabel {
    final from = _activeSeason?['starts_on']?.toString();
    final to = _activeSeason?['ends_on']?.toString();
    return from != null && to != null ? '$from — $to' : 'غير متوفر';
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        floatingActionButton: _canCreate
            ? FloatingActionButton(
                onPressed: _startNewEntry,
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.add, color: AppColors.foreground),
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      )
                    : _error
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.cloud_off_rounded,
                                  color: AppColors.destructive,
                                  size: 38,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  AppLocalizations.get('reports_status_error'),
                                  style: const TextStyle(
                                    color: AppColors.foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _load,
                                  child: Text(
                                    AppLocalizations.get('retry_btn'),
                                  ),
                                ),
                              ],
                            ),
                          )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        backgroundColor: AppColors.card,
                        child: ListView(
                          padding: const EdgeInsets.all(14),
                          children: [
                            _buildActionsBar(),
                            const SizedBox(height: 12),
                            _buildFilters(),
                            const SizedBox(height: 12),
                            _buildSummary(),
                            const SizedBox(height: 14),
                            if (_averageBodyFat != null) ...[
                              _buildHeroCard(),
                              const SizedBox(height: 8),
                            ],
                            _buildMetricsGrid(),
                            const SizedBox(height: 16),
                            _viewModeBar(),
                            const SizedBox(height: 10),
                            if (_visibleEntries.isEmpty &&
                                _visibleMissingPlayers.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 40),
                                child: Center(
                                  child: Text(
                                    AppLocalizations.get('bc_no_history'),
                                    style: TextStyle(
                                      color: AppColors.foreground.withOpacity(0.45),
                                    ),
                                  ),
                                ),
                              )
                            else ...[
                              ..._visibleEntries.map((e) => _buildRow(e)),
                              ..._visibleMissingPlayers.map(_buildMissingPlayerRow),
                            ],
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

  // Fixed-height header — back button + title, matches the other pushed
  // report screens (e.g. team_training_load_report_screen.dart).
  Widget _header(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
    ),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.surface2,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_rounded, color: AppColors.foreground, size: 17),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            AppLocalizations.get('bc_list_title'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  // Actions live here, in the scrollable body, instead of the AppBar — so
  // they never affect the fixed header's height (mirrors the training-load
  // report screen's _buildActionsBar).
  Widget _buildActionsBar() => Center(
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 22,
      runSpacing: 8,
      children: [
        _actionButton(
          'تصدير PDF',
          Icons.picture_as_pdf_outlined,
          _exporting ? null : _exportPdf,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionIconButton(Icons.download_outlined, _exporting ? null : _downloadPdf, tooltip: 'تنزيل'),
            const SizedBox(width: 10),
            _actionIconButton(Icons.share_outlined, _exporting ? null : _sharePdf, tooltip: 'مشاركة'),
          ],
        ),
        if (_canImport)
          _actionButton(
            AppLocalizations.get('bc_action_bulk_entry'),
            Icons.upload_file_rounded,
            () async {
              final imported = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const BodyCompositionBulkImportPage(),
                ),
              );
              if (imported == true) _load();
            },
          ),
      ],
    ),
  );

  Widget _actionButton(String label, IconData icon, VoidCallback? onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
            _exporting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(icon, color: AppColors.primary, size: 17),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          ),
        ),
      );

  // Icon-only variant — used for "تنزيل"/"مشاركة" so they sit side by side
  // as a compact pair instead of full labeled buttons.
  Widget _actionIconButton(IconData icon, VoidCallback? onTap, {required String tooltip}) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: _exporting
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                  )
                : Icon(icon, color: AppColors.primary, size: 19),
          ),
        ),
      );

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, color: AppColors.warning, size: 12),
                  const SizedBox(width: 5),
                  _sectionLabel('الفترة'),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBF1DD),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _seasonLabel,
                  style: const TextStyle(color: Color(0xFF8A6A28), fontSize: 8.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  label: 'من',
                  value: _isoDate(_dateFrom),
                  onTap: () => _pickRangeDate(from: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateButton(
                  label: 'إلى',
                  value: _isoDate(_dateTo),
                  onTap: () => _pickRangeDate(from: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeledDropdown('الفريق', _teamFilter, _teams, (v) {
                  setState(() => _teamFilter = v);
                  _load();
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _labeledDropdown(
                  AppLocalizations.get('bc_filter_position'),
                  _positionFilter,
                  _positions,
                  (v) {
                    setState(() => _positionFilter = v);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _labeledDropdown(
                  AppLocalizations.get('bc_filter_goal_status'),
                  _goalStatusFilter,
                  const ['on_track', 'needs_follow_up', 'behind', 'achieved'],
                  (v) {
                    setState(() => _goalStatusFilter = v);
                    _load();
                  },
                  labelOf: _filterLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeledDropdown(
                  'وجود البيانات',
                  _dataFilter,
                  const ['with_data', 'without_data'],
                  (v) => setState(() => _dataFilter = v),
                  labelOf: _filterLabel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _labeledDropdown(
                  'تغير نسبة الدهون',
                  _trendFilter,
                  const ['up', 'down'],
                  (v) => setState(() => _trendFilter = v),
                  labelOf: _filterLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) =>
                        setState(() => _playerQuery = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'البحث عن لاعب',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.muted,
                        size: 18,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
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
                        borderSide: const BorderSide(
                          color: AppColors.maroon,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _loading ? null : _resetFilters,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFBF1DD),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.restart_alt_rounded, color: Color(0xFF8A6A28), size: 19),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: const TextStyle(
      color: AppColors.foreground,
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _viewModeBar() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Expanded(
        child: Text(
          'قياسات تكوين الجسم حسب اللاعب',
          style: TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(999)),
        child: Row(
          children: [
            _viewModeSegment('كامل', _detailed, () => setState(() => _detailed = true)),
            _viewModeSegment('مختصر', !_detailed, () => setState(() => _detailed = false)),
          ],
        ),
      ),
    ],
  );

  Widget _viewModeSegment(String label, bool selected, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.maroon : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppColors.muted,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    ),
  );

  // Compact pill filter — "label   value ▾" on one line, matching the design
  // exactly (was a stacked label-above-dropdown-box; the pasted feedback was
  // specifically about this shape).
  Widget _labeledDropdown(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> onChanged, {
    String Function(String)? labelOf,
  }) {
    final resolvedValue = values.contains(value) ? value : null;
    final displayValue = resolvedValue == null
        ? 'الكل'
        : (labelOf != null ? labelOf(resolvedValue) : resolvedValue);
    return PopupMenuButton<String?>(
      onSelected: onChanged,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        const PopupMenuItem<String?>(value: null, child: Text('الكل')),
        ...values.map(
          (item) => PopupMenuItem<String?>(
            value: item,
            child: Text(labelOf != null ? labelOf(item) : item),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 8.5, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    displayValue,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.foreground, fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.expand_more_rounded, color: AppColors.muted, size: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.date_range_rounded,
              color: AppColors.primary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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

  String _filterLabel(String value) {
    const labels = {
      'with_data': 'لديه بيانات',
      'without_data': 'دون بيانات',
      'up': 'ارتفاع الدهون',
      'down': 'انخفاض الدهون',
      'on_track': 'داخل الهدف',
      'needs_follow_up': 'يحتاج متابعة',
      'behind': 'خارج الهدف',
      'achieved': 'حقق الهدف',
    };
    return labels[value] ?? value;
  }

  Widget _buildRow(BodyCompositionEntry e) {
    final status = e.goalStatus?.status;
    final statusColor = status == 'achieved' || status == 'on_track'
        ? AppColors.success
        : status == 'needs_follow_up'
        ? AppColors.warning
        : status == 'behind'
        ? AppColors.destructive
        : AppColors.muted;

    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: statusColor.withOpacity(0.08),
                backgroundImage:
                    e.playerPhotoUrl != null && e.playerPhotoUrl!.isNotEmpty
                    ? NetworkImage(e.playerPhotoUrl!)
                    : null,
                child: e.playerPhotoUrl == null || e.playerPhotoUrl!.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        color: statusColor.withOpacity(0.5),
                        size: 21,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.playerName ?? '—',
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${e.teamName ?? ''} · ${e.position ?? ''} · ${e.assessmentDate}',
                      style: TextStyle(
                        color: AppColors.foreground.withOpacity(0.5),
                        fontSize: 11.5,
                      ),
                    ),
                    if (e.isLegacy)
                      Text(
                        'سجل قديم · للقراءة فقط',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    MetricFormatter.bodyFat(e.bodyFatPercentage),
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if (status != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        AppLocalizations.get('bc_goal_status_$status'),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (_detailed) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _metricPill('الوزن', MetricFormatter.weight(e.weightKg)),
                _metricPill('BMI', MetricFormatter.bmi(e.bmi)),
                _metricPill(
                  'كتلة الدهون',
                  MetricFormatter.fatMass(e.fatMassKg),
                ),
                _metricPill(
                  'الكتلة الخالية من الدهون',
                  MetricFormatter.fatFreeMass(e.fatFreeMassKg),
                ),
                _metricPill(
                  'مجموع الثنايا',
                  MetricFormatter.skinfold(e.skinfoldSumMm),
                ),
                _metricPill(
                  'القياس السابق',
                  e.delta?.previousDate ?? 'غير متوفر',
                ),
                _metricPill(
                  'تغير الدهون',
                  e.delta?.bodyFatPercentage == null
                      ? 'غير متوفر'
                      : MetricFormatter.delta(
                          e.delta!.bodyFatPercentage,
                          digits: 2,
                          unit: '%',
                        ),
                ),
                _metricPill(
                  'الهدف',
                  e.goalStatus?.targetBodyFatPercentage == null
                      ? 'غير متوفر'
                      : MetricFormatter.bodyFat(
                          e.goalStatus!.targetBodyFatPercentage,
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
                if (_canCreate)
                _rowActionLink(
                  'إضافة قياس',
                  Icons.add_chart_rounded,
                  e.linkedPlayerId == null
                      ? null
                      : () async {
                          final saved = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => BodyCompositionEntryScreen(
                                playerId: e.linkedPlayerId,
                              ),
                            ),
                          );
                          if (saved == true) _load();
                        },
                ),
                if (_canUpdate && !e.readOnly)
                  _rowActionLink(
                    'تعديل',
                    Icons.edit_outlined,
                    () async {
                      final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => BodyCompositionEntryScreen(
                            playerId: e.linkedPlayerId,
                            assessment: e,
                          ),
                        ),
                      );
                      if (saved == true) _load();
                    },
                  ),
                _rowActionLink(
                  'PDF اللاعب',
                  Icons.picture_as_pdf_outlined,
                  e.linkedPlayerId == null || _exportingPlayerPdfs.contains(e.id)
                      ? null
                      : () => _exportPlayerPdf(e),
                  loading: _exportingPlayerPdfs.contains(e.id),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: Material(
                  color: AppColors.card,
                  child: InkWell(
                    onTap: e.linkedPlayerId == null
                        ? null
                        : () => Navigator.of(context)
                            .pushNamed('/club/players/${e.linkedPlayerId}'),
                    child: content,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportPlayerPdf(BodyCompositionEntry entry) async {
    final playerId = entry.linkedPlayerId;
    if (playerId == null || _exportingPlayerPdfs.contains(entry.id)) return;
    setState(() => _exportingPlayerPdfs.add(entry.id));
    try {
      final history = await BodyCompositionService.getHistory(
        playerId: playerId,
        limit: 100,
      );
      if (!mounted || history.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يوجد قياس لإصدار التقرير')),
          );
        }
        return;
      }
      final created = await Printing.layoutPdf(
        onLayout: (format) =>
            ReportService.instance.generateBodyCompositionReportPdf(
              playerName: entry.playerName ?? 'اللاعب',
              history: history,
              metadata: ReportMetadata(
                team: entry.teamName ?? 'غير متوفر',
                season: _seasonLabel,
                period:
                    '${history.last.assessmentDate} — ${history.first.assessmentDate}',
                issuedBy: currentUserName,
              ),
            ),
      );
      if (mounted && created) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء تقرير اللاعب بنجاح')),
        );
      }
    } catch (e, st) {
      CrashReporter.captureError(e, st, tag: 'BodyCompositionList.exportPlayer');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إنشاء تقرير اللاعب: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exportingPlayerPdfs.remove(entry.id));
      }
    }
  }

  Widget _buildMissingPlayerRow(Map<String, dynamic> player) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4)),
      ],
    ),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: AppColors.surface2,
          child: Icon(Icons.person_outline_rounded, color: AppColors.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player['name']?.toString() ?? '—',
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${player['team_name'] ?? ''} · ${player['position'] ?? ''}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              const Text(
                'لا توجد قياسات في الفترة المحددة',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (_canCreate)
          TextButton(
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => BodyCompositionEntryScreen(
                    playerId: player['id']?.toString(),
                  ),
                ),
              );
              if (saved == true) _load();
            },
            child: const Text('إضافة قياس'),
          ),
      ],
    ),
  );

  // Shared average helper — real data only, 'غير متوفر' when nothing to average.
  double? _average(double? Function(BodyCompositionEntry) pick) {
    final values = _visibleEntries.map(pick).whereType<double>().toList();
    if (values.isEmpty) return null;
    return values.fold<double>(0, (sum, value) => sum + value) / values.length;
  }

  double? get _averageBodyFat => _average((entry) => entry.bodyFatPercentage);

  // Real trend — average of each player's own delta vs their previous
  // measurement (no fabricated historical time series).
  double? get _avgFatTrendPct {
    final deltas = _visibleEntries
        .map((entry) => entry.delta?.bodyFatPercentage)
        .whereType<double>()
        .toList();
    if (deltas.isEmpty) return null;
    return deltas.fold<double>(0, (sum, value) => sum + value) / deltas.length;
  }

  Widget _buildHeroCard() {
    final trend = _avgFatTrendPct;
    final trendUp = (trend ?? 0) > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB8862E), Color(0xFF7A5A1C)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_seasonLabel,
                    style: const TextStyle(
                        color: Color(0xFFF3DFAF), fontSize: 10.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(_averageBodyFat!.toStringAsFixed(1),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    const Text('% دهون (متوسط)',
                        style: TextStyle(color: Color(0xFFF3DFAF), fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          if (trend != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (trendUp ? AppColors.destructive : AppColors.success).withOpacity(0.18),
                border: Border.all(
                    color: (trendUp ? AppColors.destructive : AppColors.success).withOpacity(0.4)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(trendUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: trendUp ? const Color(0xFFFF9E9E) : const Color(0xFF6FCB8E), size: 12),
                  const SizedBox(width: 4),
                  Text('${trend.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: trendUp ? const Color(0xFFFF9E9E) : const Color(0xFF6FCB8E),
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    final metrics = <(IconData, double?, String, String)>[
      (Icons.monitor_weight_outlined, _average((e) => e.weightKg), 'كغ', 'متوسط الوزن'),
      (Icons.fitness_center_rounded, _average((e) => e.fatFreeMassKg), 'كغ', 'الكتلة الخالية من الدهون'),
      (Icons.pie_chart_outline_rounded, _average((e) => e.bodyFatPercentage), '%', 'نسبة الدهون'),
      (Icons.scale_outlined, _average((e) => e.fatMassKg), 'كغ', 'كتلة الدهون'),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        // Fixed pixel height (not aspect-ratio-derived) so the icon + value
        // row + label never overflow regardless of card width.
        mainAxisExtent: 86,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final (icon, value, unit, label) = metrics[index];
        return Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: const Color(0xFFFBF1DD), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: AppColors.warning, size: 12),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value == null ? '—' : value.toStringAsFixed(1),
                      style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(width: 3),
                  Text(unit, style: const TextStyle(color: AppColors.muted, fontSize: 9)),
                ],
              ),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 9)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummary() {
    final entries = _visibleEntries;
    String average(double? Function(BodyCompositionEntry) pick) {
      final value = _average(pick);
      return value == null ? 'غير متوفر' : value.toStringAsFixed(1);
    }

    final dates =
        entries
            .map((entry) => entry.assessmentDate)
            .where((date) => date.isNotEmpty)
            .toList()
          ..sort();
    final inGoal = entries.where((entry) {
      final status = entry.goalStatus?.status;
      return status == 'on_track' || status == 'achieved';
    }).length;
    final outGoal = entries.where((entry) {
      final status = entry.goalStatus?.status;
      return status == 'needs_follow_up' || status == 'behind';
    }).length;
    final cards = <MapEntry<String, String>>[
      MapEntry('لديهم قياسات', '${entries.length}'),
      MapEntry('دون قياسات', '${_visibleMissingPlayers.length}'),
      MapEntry('متوسط الوزن', average((entry) => entry.weightKg)),
      MapEntry('متوسط الدهون', average((entry) => entry.bodyFatPercentage)),
      MapEntry(
        'متوسط الكتلة الخالية من الدهون',
        average((entry) => entry.fatFreeMassKg),
      ),
      MapEntry('داخل الهدف', '$inGoal'),
      MapEntry('خارج الهدف', '$outGoal'),
      MapEntry('آخر قياس', dates.isEmpty ? 'غير متوفر' : dates.last),
    ];
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: cards
            .map(
              (item) => Container(
                constraints: const BoxConstraints(minWidth: 68),
                margin: const EdgeInsetsDirectional.only(end: 7),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.value,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.key,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _metricPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(
                color: AppColors.foreground,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }

  // Gold inline icon+text link — matches the design's player-card action
  // row (not a Material TextButton, which renders in the default theme color).
  Widget _rowActionLink(String label, IconData icon, VoidCallback? onTap, {bool loading = false}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                loading
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                      )
                    : Icon(icon, color: AppColors.primary, size: 14),
                const SizedBox(width: 5),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 11.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
