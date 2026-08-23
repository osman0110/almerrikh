import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../app_colors.dart';
import '../../api_service.dart';
import '../../models/report_models.dart';
import '../../services/report_service.dart';
import '../../services/settings_service.dart';
import '../club/club_widgets.dart' show ReportDateRangeChip, showReportSectionsSheet;

const _bg      = AppColors.background;
const _card    = AppColors.card;
const _surface = AppColors.surface2;
const _lime    = AppColors.primary;
const _fg      = AppColors.foreground;
const _muted   = AppColors.muted;
const _border  = AppColors.border;
const _green   = AppColors.success;
const _amber   = AppColors.warning;
const _red     = AppColors.destructive;

class CoachTeamReportScreen extends StatefulWidget {
  const CoachTeamReportScreen({super.key, this.teamName});
  final String? teamName;
  @override
  State<CoachTeamReportScreen> createState() => _CoachTeamReportScreenState();
}

class _CoachTeamReportScreenState extends State<CoachTeamReportScreen> {
  CoachTeamReport? _report;
  bool _loading = true;
  bool _forbidden = false;
  DateTimeRange? _dateRange;
  Set<String> _sections = SettingsService.getReportSections('team_indicators_sections');

  static const _sectionOptions = <(String, String)>[
    ('kpi_row', 'مؤشرات الفريق'),
    ('at_risk', 'لاعبون في خطر'),
    ('all_players', 'جميع اللاعبين'),
  ];

  void _showCustomizeSheet() {
    showReportSectionsSheet(
      context: context,
      options: _sectionOptions,
      initial: _sections,
      onSave: (sel) {
        setState(() => _sections = sel);
        SettingsService.setReportSections('team_indicators_sections', sel);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _forbidden = false; });
    final r = await ApiService.getCoachTeamReport(
      teamName: widget.teamName,
      from: _dateRange?.start,
      to: _dateRange?.end,
    );
    if (!mounted) return;
    setState(() {
      _report = r;
      _forbidden = (r == null);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        decoration: BoxDecoration(
          color: _card,
          border: Border(bottom: BorderSide(color: _border, width: 0.8)),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: _surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: _border)),
              child: const Icon(Icons.arrow_back_rounded, color: _fg, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.teamName != null && widget.teamName!.isNotEmpty
                  ? widget.teamName!
                  : 'تقرير الفريق',
              style: const TextStyle(
                  color: _fg, fontSize: 17, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _showCustomizeSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.tune_rounded, color: _muted, size: 16),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed('/club/reports/training-load'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _lime.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.fitness_center_rounded, color: _lime, size: 14),
                SizedBox(width: 6),
                Text('الحمل التدريبي', style: TextStyle(color: _lime, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          if (_report != null)
            GestureDetector(
              onTap: _exportPdf,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _lime.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.picture_as_pdf_rounded, color: _lime, size: 14),
                  SizedBox(width: 4),
                  Text('PDF', style: TextStyle(color: _lime, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
        ]),
      );

  Future<void> _exportPdf() async {
    final r = _report;
    if (r == null) return;
    await Printing.layoutPdf(
      onLayout: (format) => ReportService.instance.generateCoachTeamReportPdf(r),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _lime, strokeWidth: 2));
    }
    if (_forbidden || _report == null) {
      return const Center(
        child: Text('لا يمكن تحميل التقرير',
            style: TextStyle(color: _muted, fontSize: 14)),
      );
    }
    final r = _report!;
    return RefreshIndicator(
      onRefresh: _load,
      color: _lime,
      backgroundColor: _card,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ReportDateRangeChip(
              value: _dateRange,
              onChanged: (range) {
                setState(() => _dateRange = range);
                _load();
              },
            ),
          ),
          if (_sections.contains('kpi_row')) ...[
            const SizedBox(height: 14),
            _kpiRow(r.teamAverages),
            const SizedBox(height: 20),
          ],
          if (_sections.contains('at_risk') && r.atRiskPlayers.isNotEmpty) ...[
            _sectionHeader('لاعبون في خطر', _red, r.atRiskPlayers.length),
            ...r.atRiskPlayers.map((p) => _playerRow(p, highlight: _red)),
            const SizedBox(height: 20),
          ],
          if (_sections.contains('all_players')) ...[
            _sectionHeader('جميع اللاعبين', _muted, r.players.length),
            if (r.players.isEmpty)
              _emptyState('لا يوجد لاعبون في هذا الفريق')
            else
              ...r.players.map((p) => _playerRow(p, highlight: null)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _kpiRow(TeamAverages a) => Column(
        children: [
          Row(children: [
            Expanded(child: _KpiCard(
              label: 'حجم الفريق',
              value: '${a.squadSize}',
              color: _lime,
            )),
            const SizedBox(width: 8),
            Expanded(child: _KpiCard(
              label: 'متوسط Hooper',
              value: a.avgHooper != null ? a.avgHooper!.toStringAsFixed(1) : '—',
              color: _avgHooperColor(a.avgHooper),
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _KpiCard(
              label: 'متوسط RPE',
              value: a.avgPostRpe != null ? a.avgPostRpe!.toStringAsFixed(1) : '—',
              color: _avgRpeColor(a.avgPostRpe),
            )),
            const SizedBox(width: 8),
            Expanded(child: _KpiCard(
              label: 'الإتمام',
              value: '${a.completionRate}%',
              color: a.completionRate >= 70 ? _green : a.completionRate >= 40 ? _amber : _red,
            )),
          ]),
          const SizedBox(height: 8),
          _KpiCard(
            label: _loadLabel(a),
            value: '${a.trainingLoadPeriod}',
            color: _lime,
          ),
        ],
      );

  String _loadLabel(TeamAverages averages) {
    if (_report?.rangeFrom == null || _report?.rangeTo == null) {
      return 'الحمل 7d (متوسط/لاعب)';
    }
    final days = averages.trainingLoadPeriodDays;
    return 'حمل الفترة ($days يوم/أيام)';
  }

  Color _avgHooperColor(double? v) =>
      v == null ? _muted : v > 14 ? _red : v > 10 ? _amber : _green;

  Color _avgRpeColor(double? v) =>
      v == null ? _muted : v >= 8 ? _red : v >= 6 ? _amber : _green;

  Widget _sectionHeader(String label, Color color, int count) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(width: 3, height: 16,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  color: _fg, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('$count', style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
      );

  Widget _playerRow(TeamPlayerRow p, {Color? highlight}) {
    final isAtRisk = p.status == 'at_risk';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: highlight != null ? highlight.withOpacity(0.25) : _border),
      ),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(p.name,
                    style: const TextStyle(
                        color: _fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(p.position ?? '—',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              ]),
            ),
            if (isAtRisk) _badge('خطر', _red),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _MiniStat('Hooper',
                p.avgHooper != null ? p.avgHooper!.toStringAsFixed(1) : '—',
                _avgHooperColor(p.avgHooper)),
            const SizedBox(width: 16),
            _MiniStat('RPE',
                p.avgPostRpe != null ? p.avgPostRpe!.toStringAsFixed(1) : '—',
                _avgRpeColor(p.avgPostRpe)),
            const SizedBox(width: 16),
            _MiniStat('الإتمام', '${p.completionRate}%',
                p.completionRate >= 70 ? _green : _amber),
            const Spacer(),
            _MiniStat(
              _report?.rangeFrom == null
                  ? 'حمل 7d'
                  : 'حمل الفترة (${p.trainingLoadPeriodDays} يوم)',
              '${p.trainingLoadPeriod}',
              _lime,
            ),
          ]),
          // At-risk badges
          if (isAtRisk) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (p.avgHooper != null && p.avgHooper! > 14)
                _badge('Hooper عالٍ', _red),
              if (p.avgPostRpe != null && p.avgPostRpe! >= 8)
                _badge('RPE مرتفع', _amber),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.30)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 9.5, fontWeight: FontWeight.w700)),
      );

  Widget _emptyState(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg, style: const TextStyle(color: _muted, fontSize: 12)),
      );

}

class _KpiCard extends StatelessWidget {
  const _KpiCard(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.20)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: _muted, fontSize: 11)),
          ),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 9.5)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      );
}
