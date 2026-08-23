import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/assessment_result_model.dart';
import '../../models/monitoring_models.dart';
import '../../services/assessment_storage_service.dart';
import '../../services/player_monitoring_service.dart';
import '../../storage.dart';
import '../../utils/metric_formatter.dart';

class PlayerHistoryScreen extends StatefulWidget {
  const PlayerHistoryScreen({super.key});

  @override
  State<PlayerHistoryScreen> createState() => _PlayerHistoryScreenState();
}

class _PlayerHistoryScreenState extends State<PlayerHistoryScreen> {
  List<AssessmentResult> _assessments = [];
  List<HooperEntry> _hooper = [];
  List<RpeEntry> _rpe = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final linkedPlayerId = await OnboardingStore().getLinkedPlayerId();
      final results = await Future.wait([
        AssessmentStorageService.instance
            .streamAssessments(linkedPlayerId)
            .first
            .catchError((_) => <AssessmentResult>[]),
        PlayerMonitoringService.getHooperHistory(
          limit: 14,
        ).catchError((_) => <HooperEntry>[]),
        PlayerMonitoringService.getRpeHistory(
          limit: 14,
        ).catchError((_) => <RpeEntry>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _assessments = results[0] as List<AssessmentResult>;
        _hooper = results[1] as List<HooperEntry>;
        _rpe = results[2] as List<RpeEntry>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: getAppLanguage() == 'ar'
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text(AppLocalizations.get('assessment_history_title')),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          backgroundColor: AppColors.card,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSectionHeader(
                      'تقييمات الأداء',
                      '${_assessments.length} تقييم',
                    ),
                    const SizedBox(height: 10),
                    if (_assessments.isEmpty)
                      _emptyState('لا توجد تقييمات بعد')
                    else
                      ..._assessments.take(20).map(_buildAssessmentTile),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      'Hooper Index',
                      '${_hooper.length} سجل',
                    ),
                    const SizedBox(height: 10),
                    if (_hooper.isEmpty)
                      _emptyState('لا توجد بيانات Hooper')
                    else ...[
                      _buildHooperChart(),
                      const SizedBox(height: 10),
                      ..._hooper.take(7).map(_buildHooperTile),
                    ],
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      'RPE — حمل التدريب',
                      '${_rpe.length} جلسة',
                    ),
                    const SizedBox(height: 10),
                    if (_rpe.isEmpty)
                      _emptyState('لا توجد بيانات RPE')
                    else
                      ..._rpe.take(7).map(_buildRpeTile),
                    const SizedBox(height: 16),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String sub) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.foreground,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            sub,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Text(
        msg,
        style: TextStyle(
          color: AppColors.foreground.withOpacity(0.35),
          fontSize: 13,
        ),
      ),
    );
  }

  // Pre-format a DateTime to 'YYYY-MM-DD' without allocating a full toString()
  static String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Widget _buildAssessmentTile(AssessmentResult r) {
    final color = r.overallScore >= 75
        ? const Color(0xff2DBF6C)
        : r.overallScore >= 50
        ? const Color(0xffF2B23B)
        : const Color(0xffFF4D2E);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${r.overallScore}',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.testType.displayName,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _fmtDate(r.createdAt),
                  style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.40),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'حركة: ${r.movementQualityScore}',
                style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.54),
                  fontSize: 11,
                ),
              ),
              Text(
                'اتزان: ${r.stabilityScore}',
                style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.54),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHooperChart() {
    if (_hooper.isEmpty) return const SizedBox();
    final max = 28.0;
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _hooper.reversed.take(14).map((e) {
          final pct = (e.hooperScore / max).clamp(0.0, 1.0);
          final c = e.hooperScore <= 10
              ? const Color(0xff2DBF6C)
              : e.hooperScore <= 16
              ? const Color(0xffF2B23B)
              : const Color(0xffFF4D2E);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: pct,
                        child: Container(
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHooperTile(HooperEntry e) {
    final c = e.hooperScore <= 10
        ? const Color(0xff2DBF6C)
        : e.hooperScore <= 16
        ? const Color(0xffF2B23B)
        : const Color(0xffFF4D2E);
    final label = e.hooperScore <= 10
        ? 'طبيعي'
        : e.hooperScore <= 16
        ? 'متوسط'
        : 'مرتفع';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${e.hooperScore}',
              style: TextStyle(
                color: c,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              e.submittedAt != null ? _fmtDate(e.submittedAt!) : '—',
              style: TextStyle(
                color: AppColors.foreground.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRpeTile(RpeEntry e) {
    final rpe = e.rpeScore;
    final c = (rpe ?? 0) >= 8
        ? const Color(0xffFF4D2E)
        : (rpe ?? 0) >= 5
        ? const Color(0xffF2B23B)
        : const Color(0xff2DBF6C);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rpe == null
                  ? MetricFormatter.unavailable
                  : '${MetricFormatter.rpe(rpe)}/10',
              style: TextStyle(
                color: c,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.sessionType ?? 'جلسة تدريب',
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'الحمل: ${MetricFormatter.load(e.trainingLoad)}',
                  style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.45),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            e.submittedAt != null ? _fmtDate(e.submittedAt!) : '—',
            style: TextStyle(
              color: AppColors.foreground.withOpacity(0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
