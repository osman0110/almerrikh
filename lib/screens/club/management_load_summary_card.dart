import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../models/training_load_models.dart';
import '../../utils/metric_formatter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Plain-language training-load summary. Reuses the same data source as
// TrainingLoadSection but drops Monotony/Strain, the per-day status grid,
// and per-session detail. Training load is physical-coach-exclusive data —
// the caller (ClubPlayerDetailPage) only renders this behind isCoachRole.
// ─────────────────────────────────────────────────────────────────────────────

class ManagementLoadSummaryCard extends StatefulWidget {
  const ManagementLoadSummaryCard({super.key, required this.playerId});
  final String playerId;

  @override
  State<ManagementLoadSummaryCard> createState() =>
      _ManagementLoadSummaryCardState();
}

class _ManagementLoadSummaryCardState
    extends State<ManagementLoadSummaryCard> {
  TrainingLoadWeekSummary? _report;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ApiService.getPlayerTrainingLoadWeekly(
      playerId: widget.playerId,
    );
    if (mounted) {
      setState(() {
        _report = r;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    final r = _report;
    if (r == null || r.isNoLoad) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.fitness_center_rounded, color: AppColors.muted, size: 16),
            SizedBox(width: 8),
            Text(
              'لا يوجد حمل تدريبي مسجل هذا الأسبوع',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final completedDays =
        r.days.where((d) => d.participationStatus == 'COMPLETE').length;
    final totalDays = r.days.length;

    final change = r.previousWeek?.changePercent;
    final up = change != null && change > 0;
    final trendColor = change == null
        ? AppColors.muted
        : (up ? AppColors.destructive : AppColors.success);
    final trendIcon = change == null
        ? Icons.remove_rounded
        : (up ? Icons.trending_up_rounded : Icons.trending_down_rounded);
    final trendLabel = change == null
        ? 'لا تتوفر بيانات كافية للمقارنة'
        : 'الحمل ${up ? "ارتفع" : "انخفض"} ${change.abs().toStringAsFixed(0)}٪ عن الأسبوع الماضي';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fitness_center_rounded,
                  color: AppColors.primary, size: 15),
              const SizedBox(width: 6),
              const Text(
                'الحمل التدريبي هذا الأسبوع',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat('إجمالي الحمل',
                    MetricFormatter.loadValue(r.weeklyLoad)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stat('الحصص المكتملة', '$completedDays من $totalDays'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(trendIcon, color: trendColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  trendLabel,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.muted, fontSize: 9.5)),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.foreground,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}
