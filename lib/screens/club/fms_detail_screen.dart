import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/fms_model.dart';
import 'fms_movement_view_card.dart';

/// Read-only view of one past FMS assessment — the 7 movement cards with
/// icons/descriptions/scores, plus a comparison against the assessment right
/// before it (if provided) and a general recommendation summary.
class FmsDetailScreen extends StatelessWidget {
  const FmsDetailScreen({
    super.key,
    required this.assessment,
    this.previous,
  });

  final FmsAssessment assessment;
  final FmsAssessment? previous;

  int? _previousScoreFor(FmsMovement m) {
    if (previous == null) return null;
    for (final s in previous!.movements) {
      if (s.movement == m) return s.finalScore;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final byMovement = {for (final s in assessment.movements) s.movement: s};
    final needsAttention = assessment.movements.where((s) => s.finalScore <= 1 || s.pain).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text('تقييم FMS — ${assessment.playerName}',
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _headerCard(),
              const SizedBox(height: 16),
              if (previous != null) ...[
                _comparisonBanner(),
                const SizedBox(height: 16),
              ],
              ...FmsMovement.values.map((m) {
                final s = byMovement[m];
                if (s == null) return const SizedBox.shrink();
                return FmsMovementViewCard(score: s, previousFinalScore: _previousScoreFor(m));
              }),
              if (needsAttention.isNotEmpty) ...[
                const SizedBox(height: 8),
                _recommendationSummary(needsAttention),
              ],
              if (assessment.notes != null && assessment.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('ملاحظات عامة', style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10)),
                  child: Text(assessment.notes!, style: const TextStyle(color: AppColors.foreground, fontSize: 12.5)),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    final d = assessment.createdAt;
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final statusColor = assessment.status == 'مكتمل' ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('المجموع الكلي', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                  Text('${assessment.totalScore} / 21',
                      style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 28)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(assessment.status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const Divider(height: 20, color: AppColors.border),
          Row(children: [
            Expanded(child: _metaItem('تاريخ التقييم', dateStr)),
            Expanded(child: _metaItem('المقيّم', assessment.assessorName ?? '—')),
          ]),
        ],
      ),
    );
  }

  Widget _metaItem(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(color: AppColors.foreground, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _comparisonBanner() {
    final diff = assessment.totalScore - previous!.totalScore;
    final improved = <String>[];
    final declined = <String>[];
    final byPrev = {for (final s in previous!.movements) s.movement: s.finalScore};
    for (final s in assessment.movements) {
      final prev = byPrev[s.movement];
      if (prev == null || prev == s.finalScore) continue;
      if (s.finalScore > prev) {
        improved.add('${s.movement.nameAr}: $prev ← ${s.finalScore}');
      } else {
        declined.add('${s.movement.nameAr}: $prev ← ${s.finalScore}');
      }
    }
    final color = diff > 0 ? AppColors.success : (diff < 0 ? AppColors.destructive : AppColors.muted);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.compare_arrows_rounded, color: color, size: 16),
            const SizedBox(width: 6),
            Text('مقارنة بالتقييم السابق (${previous!.totalScore} / 21)',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${diff > 0 ? '+' : ''}$diff', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900)),
          ]),
          if (improved.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('تحسّن: ${improved.join('، ')}', style: const TextStyle(color: AppColors.success, fontSize: 11)),
          ],
          if (declined.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('تراجع: ${declined.join('، ')}', style: const TextStyle(color: AppColors.destructive, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _recommendationSummary(List<FmsMovementScore> needsAttention) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lightbulb_outline_rounded, color: AppColors.primary, size: 16),
            SizedBox(width: 6),
            Text('ملخص التوصيات العامة', style: TextStyle(color: AppColors.foreground, fontSize: 13, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          ...needsAttention.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${s.movement.nameAr}: ${s.movement.recommendationFor(s.finalScore, s.pain)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
              )),
        ],
      ),
    );
  }
}
