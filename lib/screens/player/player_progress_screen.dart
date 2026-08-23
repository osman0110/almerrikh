import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../api_service.dart';
import '../../models/report_models.dart';
import '../../widgets/report_charts.dart';

const _bg     = AppColors.background;
const _card   = AppColors.card;
const _surf   = AppColors.surface2;
const _purple = Color(0xff7C3AED);
const _fg     = AppColors.foreground;
const _muted  = AppColors.muted;
const _border = AppColors.border;
const _green  = AppColors.success;
const _amber  = AppColors.warning;
const _red    = AppColors.destructive;

class PlayerProgressScreen extends StatefulWidget {
  const PlayerProgressScreen({super.key});
  @override
  State<PlayerProgressScreen> createState() => _PlayerProgressScreenState();
}

class _PlayerProgressScreenState extends State<PlayerProgressScreen> {
  MyProgressReport? _report;
  bool _loading = true;
  bool _forbidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _forbidden = false; });
    final r = await ApiService.getMyProgressReport();
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
                  color: _surf,
                  shape: BoxShape.circle,
                  border: Border.all(color: _border)),
              child: const Icon(Icons.arrow_back_rounded, color: _fg, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text('تقدمي الشخصي',
                style: TextStyle(
                    color: _fg, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _purple.withOpacity(0.30)),
            ),
            child: const Text('30 يوم',
                style: TextStyle(
                    color: _purple, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: _purple, strokeWidth: 2));
    }
    if (_forbidden || _report == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_rounded, color: _muted, size: 40),
          SizedBox(height: 12),
          Text('غير مصرح بالوصول',
              style: TextStyle(color: _fg, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      );
    }
    final r = _report!;
    return RefreshIndicator(
      onRefresh: _load,
      color: _purple,
      backgroundColor: _card,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Session completion
          CompletionRateCard(
            completed: r.sessionCompletion30d.completed,
            assigned:  r.sessionCompletion30d.assigned,
            rate:      r.sessionCompletion30d.completionRate,
          ),
          const SizedBox(height: 20),
          // Hooper trend
          _section('Hooper Index (14 يوم أخيرة)'),
          HooperLineChart(
            data: r.hooperTrend.length > 14
                ? r.hooperTrend.sublist(r.hooperTrend.length - 14)
                : r.hooperTrend,
          ),
          const SizedBox(height: 20),
          // RPE trend
          _section('RPE قبل / بعد التدريب'),
          RpeLineChart(
            data: r.rpeTrend.length > 14
                ? r.rpeTrend.sublist(r.rpeTrend.length - 14)
                : r.rpeTrend,
          ),
          const SizedBox(height: 20),
          // Weekly load
          if (r.weeklyLoad.isNotEmpty) ...[
            _section('الحمل الأسبوعي'),
            WeeklyLoadBarChart(data: r.weeklyLoad),
            const SizedBox(height: 20),
          ],
          // Assessment history chart
          _section('منحنى التقييمات'),
          AssessmentHistoryChart(data: r.assessmentHistory),
          const SizedBox(height: 20),
          // Assessment history list
          _section('تاريخ التقييمات (${r.assessmentHistory.length})'),
          ...r.assessmentHistory.isEmpty
              ? [_empty('لا توجد تقييمات مسجلة')]
              : r.assessmentHistory.take(5).map((a) => _assessmentRow(a)),
          const SizedBox(height: 20),
          // Body metrics history
          if (r.bodyMetricsHistory.isNotEmpty) ...[
            _section('القياسات الجسدية'),
            ...r.bodyMetricsHistory.take(5).map((b) => _bodyRow(b)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label,
            style: const TextStyle(
                color: _fg, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _assessmentRow(AssessmentHistoryItem a) {
    final c = a.overallScore >= 70 ? _green
        : a.overallScore >= 50 ? _amber : _red;
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
                style: const TextStyle(
                    color: _fg, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(a.date, style: const TextStyle(color: _muted, fontSize: 11)),
          ]),
        ),
        Text('${a.overallScore}',
            style: TextStyle(
                color: c, fontSize: 22, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _bodyRow(BodyMetricPoint b) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Expanded(
            child: Text(b.date,
                style: const TextStyle(color: _muted, fontSize: 12)),
          ),
          if (b.weightKg != null)
            Text('${b.weightKg!.toStringAsFixed(1)} kg',
                style: const TextStyle(
                    color: _fg, fontSize: 13, fontWeight: FontWeight.w600)),
          if (b.bmi != null) ...[
            const SizedBox(width: 12),
            Text('BMI ${b.bmi!.toStringAsFixed(1)}',
                style: const TextStyle(color: _purple, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ]),
      );

  Widget _empty(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg, style: const TextStyle(color: _muted, fontSize: 12)),
      );
}
