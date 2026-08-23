import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../app_colors.dart';
import '../../api_service.dart';
import '../../models/report_models.dart';
import '../../services/report_service.dart';
import '../../widgets/report_charts.dart';
import '../club/training_load_section.dart';

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

class CoachPlayerReportScreen extends StatefulWidget {
  const CoachPlayerReportScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });
  final String playerId;
  final String playerName;

  @override
  State<CoachPlayerReportScreen> createState() =>
      _CoachPlayerReportScreenState();
}

class _CoachPlayerReportScreenState extends State<CoachPlayerReportScreen> {
  CoachPlayerReport? _report;
  bool _loading = true;
  bool _forbidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _forbidden = false; });
    final r = await ApiService.getCoachPlayerReport(widget.playerId);
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
              child:
                  const Icon(Icons.arrow_back_rounded, color: _fg, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(widget.playerName,
                style: const TextStyle(
                    color: _fg, fontSize: 17, fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis),
          ),
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
            )
          else
            const Text('تقرير لاعب', style: TextStyle(color: _muted, fontSize: 11)),
        ]),
      );

  Future<void> _exportPdf() async {
    final r = _report;
    if (r == null) return;
    await Printing.layoutPdf(
      onLayout: (format) => ReportService.instance.generatePlayerReportPdf(r),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _lime, strokeWidth: 2));
    }
    if (_forbidden || _report == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, color: _muted, size: 40),
            const SizedBox(height: 12),
            const Text('لا يمكن الوصول لهذا التقرير',
                style: TextStyle(color: _fg, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('اللاعب خارج نطاق صلاحياتك',
                style: TextStyle(color: _muted, fontSize: 13)),
          ],
        ),
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
          _playerHeader(r.player),
          const SizedBox(height: 14),
          _bodyMetricsRow(r.bodyMetrics),
          const SizedBox(height: 16),
          _summaryGrid(r.summary),
          const SizedBox(height: 20),
          _section('Hooper Index (30 يوم)'),
          HooperLineChart(data: r.hooperTrend),
          const SizedBox(height: 20),
          _section('RPE قبل / بعد التدريب'),
          RpeLineChart(data: r.rpeTrend),
          const SizedBox(height: 20),
          _section('الحمل التدريبي وRPE (الأسبوع الحالي)'),
          TrainingLoadSection(playerId: widget.playerId),
          const SizedBox(height: 20),
          _section('منحنى التقييمات'),
          AssessmentHistoryChart(data: r.assessmentHistory),
          const SizedBox(height: 20),
          _section('آخر الجلسات'),
          ...r.sessionHistory.isEmpty
              ? [_emptyState('لا توجد جلسات مسجلة')]
              : r.sessionHistory.map((s) => _sessionRow(s)),
          const SizedBox(height: 20),
          _section('تاريخ التقييمات'),
          ...r.assessmentHistory.isEmpty
              ? [_emptyState('لا توجد تقييمات مسجلة')]
              : r.assessmentHistory.map((a) => _assessmentRow(a)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _playerHeader(PlayerInfo p) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _lime.withOpacity(0.20)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: _lime.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: _lime, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name,
                  style: const TextStyle(
                      color: _fg, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${p.position ?? '—'}  ·  ${p.teamName ?? '—'}',
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ]),
          ),
        ]),
      );

  Widget _bodyMetricsRow(ReportBodyMetrics m) {
    final hasData = m.latestWeight != null || m.latestHeight != null;
    if (!hasData) return const SizedBox.shrink();
    return Row(children: [
      if (m.latestWeight != null)
        Expanded(child: _MetricChip(label: 'الوزن', value: '${m.latestWeight!.toStringAsFixed(1)} kg')),
      if (m.latestHeight != null) ...[
        const SizedBox(width: 8),
        Expanded(child: _MetricChip(label: 'الطول', value: '${m.latestHeight!.toStringAsFixed(0)} cm')),
      ],
      if (m.latestBmi != null) ...[
        const SizedBox(width: 8),
        Expanded(child: _MetricChip(label: 'BMI', value: m.latestBmi!.toStringAsFixed(1))),
      ],
    ]);
  }

  Widget _summaryGrid(Phase6Summary s) {
    final avgH = s.averageHooper30d;
    final avgR = s.averagePostRpe30d;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        _SummaryCard(
          label: 'Hooper 30d',
          value: avgH != null ? avgH.toStringAsFixed(1) : '—',
          color: avgH == null ? _muted : avgH > 14 ? _red : avgH > 10 ? _amber : _green,
        ),
        _SummaryCard(
          label: 'RPE 30d',
          value: avgR != null ? avgR.toStringAsFixed(1) : '—',
          color: avgR == null ? _muted : avgR >= 8 ? _red : avgR >= 6 ? _amber : _green,
        ),
        _SummaryCard(
          label: 'الإتمام',
          value: '${s.completionRate30d}%',
          color: s.completionRate30d >= 70 ? _green : s.completionRate30d >= 40 ? _amber : _red,
        ),
        _SummaryCard(
          // Rolling 7-day sum (same window as ACWR) — distinct from the
          // calendar-week (Mon-Sun) load shown below in "الحمل التدريبي وRPE".
          label: 'الحمل المتحرك 7 أيام',
          value: '${s.trainingLoad7d}',
          color: _lime,
        ),
        _SummaryCard(
          label: 'آلام 30d',
          value: '${s.painReports30d}',
          color: s.painReports30d > 0 ? _red : _green,
        ),
        _SummaryCard(
          label: 'أفضل تقييم',
          value: s.bestAssessmentScore != null ? '${s.bestAssessmentScore}' : '—',
          color: _lime,
        ),
      ],
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label,
            style: const TextStyle(
                color: _fg, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _sessionRow(SessionHistoryItem s) {
    final statusColor = s.status == 'completed' ? _green
        : s.status == 'missed' ? _red : _amber;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title,
                style: const TextStyle(color: _fg, fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${s.date}  ·  ${s.durationMinutes} min',
                style: const TextStyle(color: _muted, fontSize: 11)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(s.status,
              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _assessmentRow(AssessmentHistoryItem a) {
    final c = a.overallScore >= 70 ? _green : a.overallScore >= 50 ? _amber : _red;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.assessmentType,
                style: const TextStyle(color: _fg, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(a.date, style: const TextStyle(color: _muted, fontSize: 11)),
          ]),
        ),
        Text('${a.overallScore}',
            style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _emptyState(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg, style: const TextStyle(color: _muted, fontSize: 12)),
      );
}

// ── Small sub-widgets ─────────────────────────────────────────────────────────

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: _fg, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.20)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1)),
            const SizedBox(height: 5),
            Text(label,
                style: const TextStyle(color: _muted, fontSize: 9.5),
                textAlign: TextAlign.center,
                maxLines: 2),
          ],
        ),
      );
}
