import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../app_colors.dart';
import '../../api_service.dart';
import '../../models/report_models.dart';
import '../../services/report_service.dart';
import '../../widgets/report_charts.dart';

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

class CoachAssessmentReportScreen extends StatefulWidget {
  const CoachAssessmentReportScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });
  final String playerId;
  final String playerName;

  @override
  State<CoachAssessmentReportScreen> createState() =>
      _CoachAssessmentReportScreenState();
}

class _CoachAssessmentReportScreenState
    extends State<CoachAssessmentReportScreen> {
  CoachAssessmentReport? _report;
  bool _loading = true;
  bool _forbidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _forbidden = false; });
    final r = await ApiService.getCoachAssessmentReport(widget.playerId);
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
        child: Column(children: [
          _header(context),
          Expanded(child: _body()),
        ]),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.playerName,
                  style: const TextStyle(
                      color: _fg, fontSize: 16, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis),
              const Text('تقرير التقييمات',
                  style: TextStyle(color: _muted, fontSize: 11)),
            ]),
          ),
          if (_report != null)
            GestureDetector(
              onTap: () => Printing.layoutPdf(
                onLayout: (format) =>
                    ReportService.instance.generatePlayerAssessmentPdf(_report!),
              ),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: _surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: _border)),
                child: const Icon(Icons.picture_as_pdf_rounded, color: _lime, size: 18),
              ),
            ),
        ]),
      );

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _lime, strokeWidth: 2));
    }
    if (_forbidden || _report == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_rounded, color: _muted, size: 40),
          const SizedBox(height: 12),
          const Text('لا يمكن الوصول لهذا التقرير',
              style: TextStyle(color: _fg, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('اللاعب خارج نطاق صلاحياتك',
              style: TextStyle(color: _muted, fontSize: 13)),
        ]),
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
          _summaryCard(r.summary),
          const SizedBox(height: 20),
          _section('منحنى الأداء'),
          AssessmentScoreChart(data: r.assessments),
          const SizedBox(height: 20),
          _section('التقييمات (${r.assessments.length})'),
          ...r.assessments.isEmpty
              ? [_empty('لا توجد تقييمات مسجلة')]
              : r.assessments.map((a) => _assessmentCard(a)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _summaryCard(AssessmentReportSummary s) {
    final trendColor = s.trend == 'improving' ? _green
        : s.trend == 'declining' ? _red : _amber;
    final trendLabel = s.trend == 'improving' ? 'تحسن ↑'
        : s.trend == 'declining' ? 'تراجع ↓'
        : s.trend == 'stable' ? 'مستقر →' : 'بيانات غير كافية';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _lime.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('ملخص التقييمات',
                style: TextStyle(
                    color: _fg, fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: trendColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: trendColor.withOpacity(0.30)),
              ),
              child: Text(trendLabel,
                  style: TextStyle(
                      color: trendColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _ScoreStat(label: 'الأفضل',
                value: s.bestScore != null ? '${s.bestScore}' : '—',
                color: _green)),
            Expanded(child: _ScoreStat(label: 'الأسوأ',
                value: s.worstScore != null ? '${s.worstScore}' : '—',
                color: _red)),
            Expanded(child: _ScoreStat(label: 'المتوسط',
                value: s.averageScore != null
                    ? s.averageScore!.toStringAsFixed(1)
                    : '—',
                color: _lime)),
          ]),
        ],
      ),
    );
  }

  Widget _assessmentCard(FullAssessmentItem a) {
    final c = a.overallScore >= 70 ? _green
        : a.overallScore >= 50 ? _amber : _red;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.assessmentType,
                  style: const TextStyle(
                      color: _fg, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(a.date, style: const TextStyle(color: _muted, fontSize: 11)),
            ]),
          ),
          Text('${a.overallScore}',
              style: TextStyle(
                  color: c, fontSize: 28, fontWeight: FontWeight.w900,
                  height: 1)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _ScoreChip('حركة', a.movementScore),
          const SizedBox(width: 8),
          _ScoreChip('اتزان', a.stabilityScore),
          const SizedBox(width: 8),
          _ScoreChip('تناسق', a.symmetryScore),
          const SizedBox(width: 8),
          _ScoreChip('تحكم', a.controlScore),
        ]),
      ]),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label,
            style: const TextStyle(
                color: _fg, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _empty(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg, style: const TextStyle(color: _muted, fontSize: 12)),
      );
}

class _ScoreStat extends StatelessWidget {
  const _ScoreStat(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      );
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip(this.label, this.value);
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) {
    final c = value >= 70 ? _green : value >= 50 ? _amber : _red;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$value',
              style: TextStyle(
                  color: c, fontSize: 14, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: _muted, fontSize: 9)),
        ]),
      ),
    );
  }
}
