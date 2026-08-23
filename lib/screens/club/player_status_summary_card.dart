import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/coach_summary_helper.dart';
import '../../services/readiness_helper.dart';
import '../../services/risk_flags_helper.dart';
import '../../shared/club_status_color.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Plain-language readiness/status summary for club management. Built purely
// from data ClubPlayerDetailPage already loads (no network calls) — reuses
// the same ReadinessHelper/RiskFlagsHelper/CoachSummaryHelper as the
// physical-coach-facing report, just renders a single short sentence instead
// of the full risk-flag breakdown. Club-admin player profile only.
// ─────────────────────────────────────────────────────────────────────────────

class PlayerStatusSummaryCard extends StatelessWidget {
  const PlayerStatusSummaryCard({
    super.key,
    required this.wellness,
    required this.assessments,
    required this.player,
    required this.showMedicalNotes,
  });

  final Map<String, dynamic>? wellness;
  final List<PlayerAssessment> assessments;
  final ClubPlayer player;
  final bool showMedicalNotes;

  @override
  Widget build(BuildContext context) {
    final latest = assessments.isNotEmpty ? assessments.first : null;

    String? trend;
    if (assessments.length >= 3) {
      final diff = assessments[0].overallScore - assessments[2].overallScore;
      if (diff > 5) {
        trend = 'improving';
      } else if (diff < -5) {
        trend = 'declining';
      } else {
        trend = 'stable';
      }
    }

    final hooper = wellness?['hooper_score'] as int?;
    final rpe = (wellness?['last_rpe'] as num?)?.round();

    final readiness = ReadinessHelper.calculate(
      hooperScore: hooper,
      lastRpe: rpe,
      latestAssessmentScore: latest?.overallScore,
      trendDirection: trend,
    );

    final flags = RiskFlagsHelper.evaluate(
      hooperScore: hooper,
      lastRpe: rpe,
      latestAssessmentScore: latest?.overallScore,
      latestAssessmentType: latest?.type,
      stabilityScore: latest?.stabilityScore,
      movementScore: latest?.movementQualityScore,
      trend: trend,
      lastAssessmentDate: latest?.date,
    );

    final summary = CoachSummaryHelper.build(
      readiness: readiness,
      flags: flags,
      recommendations: [readiness.recommendation],
      movementScore: latest?.movementQualityScore,
      stabilityScore: latest?.stabilityScore,
      symmetryScore: latest?.symmetryScore,
      trend: trend,
      hooperScore: hooper,
      lastRpe: rpe,
    );

    final showAvailability = player.status != PlayerStatus.active;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: readiness.color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: readiness.color.withOpacity(0.10),
                  border: Border.all(color: readiness.color.withOpacity(0.40), width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${readiness.score}',
                  style: TextStyle(
                    color: readiness.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppLocalizations.get('readiness_card_title'),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: readiness.color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: readiness.color.withOpacity(0.25)),
                          ),
                          child: Text(
                            readiness.statusLabel,
                            style: TextStyle(
                              color: readiness.color,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      summary.mainRecommendation,
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showAvailability) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            _availabilityBlock(),
          ],
        ],
      ),
    );
  }

  Widget _availabilityBlock() {
    final color = clubStatusColor(player.status);
    final lines = <String>[];
    if (player.expectedReturnDate != null) {
      final d = player.expectedReturnDate!;
      lines.add(
        '${AppLocalizations.get('expected_return_label')}: '
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }
    if (player.unavailableReason != null && player.unavailableReason!.trim().isNotEmpty) {
      lines.add(player.unavailableReason!.trim());
    }
    if (showMedicalNotes &&
        player.injuryNotes != null &&
        player.injuryNotes!.trim().isNotEmpty) {
      lines.add(player.injuryNotes!.trim());
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.status.localizedLabel,
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
              ),
              if (lines.isNotEmpty) ...[
                const SizedBox(height: 4),
                ...lines.map(
                  (l) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
