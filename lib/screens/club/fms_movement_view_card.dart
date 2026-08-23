import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/fms_model.dart';

/// Read-only FMS movement card — shared by the FMS detail/history views.
/// Shows the exercise icon/description, left/right or single score, final
/// score badge, pain flag, notes, and a deterministic coaching recommendation.
class FmsMovementViewCard extends StatelessWidget {
  const FmsMovementViewCard({
    super.key,
    required this.score,
    this.previousFinalScore,
  });

  final FmsMovementScore score;
  /// Final score of the same movement in the previous assessment, if any —
  /// used to render a small "2 ← 3" delta indicator.
  final int? previousFinalScore;

  Color _scoreColor(int s, bool pain) {
    if (pain || s == 0) return AppColors.destructive;
    if (s == 1) return AppColors.destructive;
    if (s == 2) return AppColors.warning;
    return AppColors.success;
  }

  String _scoreLabel(int s, bool pain) {
    if (pain) return 'ألم / خطر';
    switch (s) {
      case 3: return 'ممتاز';
      case 2: return 'متوسط';
      case 1: return 'ضعيف';
      default: return 'ألم / خطر';
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = score.movement;
    final color = _scoreColor(score.finalScore, score.pain);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Icon(m.placeholderIcon, color: color, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${m.nameAr} (${m.nameEn})',
                        style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13.5)),
                    const SizedBox(height: 3),
                    Text(m.description, style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text('${score.finalScore}',
                        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                  const SizedBox(height: 2),
                  Text(_scoreLabel(score.finalScore, score.pain),
                      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
                  if (previousFinalScore != null && previousFinalScore != score.finalScore) ...[
                    const SizedBox(height: 3),
                    Text('$previousFinalScore ← ${score.finalScore}',
                        style: TextStyle(
                          color: score.finalScore > previousFinalScore! ? AppColors.success : AppColors.destructive,
                          fontSize: 9.5, fontWeight: FontWeight.w700,
                        )),
                  ],
                ],
              ),
            ],
          ),
          if (m.isBilateral && (score.leftScore != null || score.rightScore != null)) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _sideChip('يسار', score.leftScore)),
              const SizedBox(width: 8),
              Expanded(child: _sideChip('يمين', score.rightScore)),
            ]),
          ],
          if (score.pain) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.destructive.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.destructive, size: 14),
                SizedBox(width: 6),
                Text('يوجد ألم أثناء الأداء', style: TextStyle(color: AppColors.destructive, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
          if (score.notes != null && score.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('ملاحظات: ${score.notes}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
          ],
          const SizedBox(height: 8),
          Text(
            m.recommendationFor(score.finalScore, score.pain),
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _sideChip(String label, int? value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$label: ', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          Text('${value ?? "—"}', style: const TextStyle(color: AppColors.foreground, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}
