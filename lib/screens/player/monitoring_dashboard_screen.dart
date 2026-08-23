import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_localizations.dart';
import '../../models/monitoring_models.dart';
import '../../services/player_monitoring_service.dart';
import '../../utils/metric_formatter.dart';

// ── Design tokens (Al Merrikh SC — light warm) ───────────────────────────────
const _bg = Color(0xFFF6F2E9);
const _bgCard = Color(0xFFFFFFFF);
const _ink = Color(0xFF1A1A1A);
const _inkSoft = Color(0xFF2E2E2E);
const _muted = Color(0xFF6B7280);
const _line = Color(0xFFE2DDD5);
const _purple = Color(0xFF8B5CF6);
const _green = Color(0xFF10B981);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFEF4444);
const _dark = Color(0xFF780115);
const _onDark = Color(0xFFFFFFFF);

// ── Typography (Cairo) ────────────────────────────────────────────────────────
TextStyle _c(double s, {FontWeight w = FontWeight.w700, Color? c, double? h}) =>
    GoogleFonts.cairo(
      fontSize: s,
      fontWeight: w,
      color: c ?? _ink,
      height: h ?? 1.3,
    );

Color _scoreColor(int score) => score >= 70
    ? _green
    : score >= 40
    ? _amber
    : _red;

String _scoreLabel(int score) => score >= 70
    ? 'جاهز للمنافسة'
    : score >= 40
    ? 'تقدم بحذر'
    : 'في خطر — خفف الحمل';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class MonitoringDashboardScreen extends StatefulWidget {
  const MonitoringDashboardScreen({super.key});

  @override
  State<MonitoringDashboardScreen> createState() =>
      _MonitoringDashboardScreenState();
}

class _MonitoringDashboardScreenState extends State<MonitoringDashboardScreen> {
  MonitoringDashboard? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final d = await PlayerMonitoringService.getDashboard();
    if (mounted)
      setState(() {
        _data = d;
        _loading = false;
      });
  }

  void _go(String route) =>
      Navigator.pushNamed(context, route).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              Container(height: 3, color: _purple),
              _buildHeader(),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: _purple,
                          strokeWidth: 2,
                        ),
                      )
                    : _data == null
                    ? _buildError()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _purple,
                        backgroundColor: _dark,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildReadiness(),
                              const SizedBox(height: 20),
                              _buildMetrics(),
                              const SizedBox(height: 20),
                              _buildLoadAnalysis(),
                              const SizedBox(height: 20),
                              _buildWeekly(),
                              if (_data!.alerts.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                _buildAlerts(),
                              ],
                              if (_data!.insights.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                _buildInsights(),
                              ],
                              if (_data!.recommendations.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                _buildRecommendations(),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: _bgCard,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: _line, shape: BoxShape.circle),
              child: const Icon(
                Icons.arrow_forward_ios_rounded,
                color: _ink,
                size: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('متابعة الجاهزية', style: _c(17, w: FontWeight.w800)),
          ),
          GestureDetector(
            onTap: _load,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.refresh_rounded, color: _purple, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ── Readiness Card ─────────────────────────────────────────────────────────

  Widget _buildReadiness() {
    final score = _data!.readinessScore;
    final color = _scoreColor(score);
    return Container(
      decoration: BoxDecoration(
        color: _dark,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                'جاهزية التدريب',
                style: _c(13, w: FontWeight.w600, c: _onDark),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$score',
                style: _c(64, w: FontWeight.w900, c: color, h: 1.0),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '%',
                  style: _c(22, w: FontWeight.w700, c: color.withOpacity(0.7)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withOpacity(0.30)),
            ),
            child: Text(_scoreLabel(score), style: _c(13, c: color)),
          ),
        ],
      ),
    );
  }

  // ── Metrics ────────────────────────────────────────────────────────────────

  Widget _buildMetrics() {
    final d = _data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow(label: 'القياسات اليومية'),
        const SizedBox(height: 12),
        _MetricCard(
          icon: Icons.monitor_weight_outlined,
          label: 'القياسات الجسدية',
          value: d.bodyMetric != null
              ? MetricFormatter.bodyFat(d.bodyMetric!.bodyFatPercent)
              : MetricFormatter.unavailable,
          unit: d.bodyMetric != null ? 'الدهون' : 'لم يُسجَّل',
          detail: d.bodyMetric?.bmi != null
              ? 'BMI ${d.bodyMetric!.bmi!.toStringAsFixed(1)}'
              : null,
          actionLabel: d.bodyMetric != null ? 'تحديث القياسات' : 'إضافة قياسات',
          onAction: () => _go('/player/monitoring/body-metrics'),
        ),
        const SizedBox(height: 10),
        _MetricCard(
          icon: Icons.psychology_outlined,
          label: 'مؤشر هوبر',
          value: d.todayHooper != null
              ? d.todayHooper!.hooperScore.toString()
              : '—',
          unit: d.todayHooper != null
              ? (d.todayHooper!.status == 'normal'
                    ? 'طبيعي'
                    : d.todayHooper!.status == 'moderate'
                    ? 'متوسط'
                    : 'خطر عالٍ')
              : 'لم يُقدَّم اليوم',
          valueColor: d.todayHooper != null
              ? (d.todayHooper!.status == 'normal'
                    ? _green
                    : d.todayHooper!.status == 'moderate'
                    ? _amber
                    : _red)
              : null,
          detail: d.todayHooper != null
              ? 'النوم ${d.todayHooper!.sleepQuality}/7  ·  الإجهاد ${d.todayHooper!.fatigue}/7'
              : null,
          actionLabel: d.todayHooper != null ? 'عرض السجل' : 'سجّل الآن',
          onAction: () => _go(
            d.todayHooper != null
                ? '/player/history'
                : '/player/monitoring/hooper',
          ),
        ),
        const SizedBox(height: 10),
        _MetricCard(
          icon: Icons.fitness_center_rounded,
          label: 'الحمل التدريبي',
          value: d.lastRpe != null
              ? MetricFormatter.load(d.lastRpe!.trainingLoad)
              : MetricFormatter.unavailable,
          unit: d.lastRpe != null ? '' : 'لا جلسة مسجلة',
          detail: d.lastRpe != null
              ? 'RPE ${MetricFormatter.rpe(d.lastRpe!.rpeScore)} × '
                    '${MetricFormatter.duration(d.lastRpe!.actualDurationMinutes ?? d.lastRpe!.durationMinutes)}'
              : null,
          actionLabel: 'عرض السجل',
          onAction: () => _go('/player/history'),
        ),
      ],
    );
  }

  // ── Load Analysis ──────────────────────────────────────────────────────────

  Widget _buildLoadAnalysis() {
    final d = _data!;
    final acwrColor = !d.hasAcwrData
        ? _muted
        : d.acwr > 1.5
        ? _red
        : d.acwr > 1.3
        ? _amber
        : _green;
    final acwrLabel = !d.hasAcwrData
        ? 'بيانات غير كافية'
        : d.acwr > 1.5
        ? 'أعلى من النطاق'
        : d.acwr > 1.3
        ? 'مراقبة'
        : 'ضمن النطاق';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow(label: 'تحليل الحمل'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نسبة الحمل (ACWR)',
                          style: _c(11, w: FontWeight.w500, c: _muted),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.hasAcwrData ? d.acwr.toStringAsFixed(2) : '—',
                          style: _c(
                            36,
                            w: FontWeight.w900,
                            c: acwrColor,
                            h: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: acwrColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: acwrColor.withOpacity(0.25)),
                    ),
                    child: Text(acwrLabel, style: _c(13, c: acwrColor)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(color: _line, height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _LoadStatItem(
                      label: 'الحمل الحاد',
                      sub: 'مجموع آخر 7 أيام',
                      value: d.hasAcwrData
                          ? d.acuteLoad.toStringAsFixed(0)
                          : '—',
                    ),
                  ),
                  Container(width: 1, height: 40, color: _line),
                  Expanded(
                    child: _LoadStatItem(
                      label: 'الحمل المزمن',
                      sub: 'المتوسط الأسبوعي لآخر 28 يوماً',
                      value: d.hasAcwrData
                          ? d.chronicLoad.toStringAsFixed(0)
                          : '—',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Weekly ─────────────────────────────────────────────────────────────────

  Widget _buildWeekly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow(label: 'الحمل الأسبوعي'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          padding: const EdgeInsets.all(16),
          child: _WeeklyBars(loads: _data!.weeklyLoads),
        ),
      ],
    );
  }

  // ── Alerts ─────────────────────────────────────────────────────────────────

  Widget _buildAlerts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow(label: 'التنبيهات', badge: '${_data!.alerts.length}'),
        const SizedBox(height: 12),
        for (int i = 0; i < _data!.alerts.length; i++) ...[
          _AlertRow(text: _data!.alerts[i]),
          if (i < _data!.alerts.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  // ── Insights ───────────────────────────────────────────────────────────────

  Widget _buildInsights() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow(label: 'رؤى الذكاء الاصطناعي'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: Column(
            children: [
              for (int i = 0; i < _data!.insights.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.lightbulb_rounded,
                        color: _amber,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _data!.insights[i],
                          style: _c(13, w: FontWeight.w500, c: _ink, h: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < _data!.insights.length - 1)
                  Divider(color: _line, height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Recommendations ────────────────────────────────────────────────────────

  Widget _buildRecommendations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow(label: 'التوصيات'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final rec in _data!.recommendations)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _purple.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _purple.withOpacity(0.25)),
                ),
                child: Text(
                  rec,
                  style: _c(12, w: FontWeight.w600, c: _purple),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _red.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, color: _red, size: 32),
          ),
          const SizedBox(height: 16),
          Text('فشل التحميل', style: _c(15, c: _ink)),
          const SizedBox(height: 6),
          Text(
            'تحقق من الاتصال وأعد المحاولة',
            style: _c(12, w: FontWeight.w500, c: _muted),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: _purple,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('إعادة المحاولة', style: _c(13, c: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label, this.badge});
  final String label;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _purple,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: _c(11, w: FontWeight.w700, c: _inkSoft),
              ),
            ],
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _red.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge!,
              style: _c(10, w: FontWeight.w700, c: _red),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.detail,
    this.valueColor,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String label, value, unit;
  final String? detail;
  final Color? valueColor;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _purple.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _purple, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: _c(11, w: FontWeight.w500, c: _muted),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          value,
                          style: _c(
                            24,
                            w: FontWeight.w900,
                            c: valueColor ?? _ink,
                          ),
                        ),
                        if (unit.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            unit,
                            style: _c(
                              12,
                              w: FontWeight.w600,
                              c: valueColor != null
                                  ? valueColor!.withOpacity(0.8)
                                  : _muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail!,
                        style: _c(11, w: FontWeight.w400, c: _muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: _line, height: 1),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onAction,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_circle_outline_rounded,
                  color: _purple,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  actionLabel,
                  style: _c(12, w: FontWeight.w700, c: _purple),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadStatItem extends StatelessWidget {
  const _LoadStatItem({
    required this.label,
    required this.sub,
    required this.value,
  });
  final String label, sub, value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: _c(22, w: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(
          label,
          style: _c(11, w: FontWeight.w600, c: _muted),
        ),
        Text(
          sub,
          style: _c(10, w: FontWeight.w400, c: _muted),
        ),
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: _red.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          right: const BorderSide(color: _red, width: 3),
          top: BorderSide(color: _line),
          bottom: BorderSide(color: _line),
          left: BorderSide(color: _line),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: _red, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: _c(13, w: FontWeight.w500, c: _ink, h: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars({required this.loads});
  final List<int?> loads;

  @override
  Widget build(BuildContext context) {
    if (loads.isEmpty) {
      return Text('لا بيانات', style: _c(13, c: _muted));
    }
    final padded = List<int?>.from(loads);
    while (padded.length < 7) padded.add(null);
    final visible = padded.take(7).toList();
    final knownLoads = visible.whereType<int>().toList();
    if (knownLoads.isEmpty) {
      return Text('بيانات غير كافية', style: _c(13, c: _muted));
    }
    final maxLoad = knownLoads
        .reduce((a, b) => a > b ? a : b)
        .toDouble()
        .clamp(1.0, double.infinity);
    const days = ['إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'];

    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final load = visible[i];
          final ratio = load == null ? 0.0 : load / maxLoad;
          final color = load == null
              ? _muted
              : ratio > 0.85
              ? _red
              : ratio > 0.65
              ? _amber
              : _purple;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (load != null)
                    Text(
                      '$load',
                      style: _c(8, w: FontWeight.w600, c: _muted),
                    ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    child: Container(
                      height: math.max(4.0, 72.0 * ratio),
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    days[i],
                    style: _c(10, w: FontWeight.w500, c: _muted),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
