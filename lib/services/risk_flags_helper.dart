import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_localizations.dart';
import '../models/club_models.dart';

enum RiskPriority { high, medium, low }

class RiskFlag {
  final String id;
  final RiskPriority priority;
  final IconData icon;
  final String title;
  final String reason;
  final String recommendation;

  const RiskFlag({
    required this.id,
    required this.priority,
    required this.icon,
    required this.title,
    required this.reason,
    required this.recommendation,
  });

  Color get color {
    switch (priority) {
      case RiskPriority.high:   return AppColors.destructive;
      case RiskPriority.medium: return AppColors.warning;
      case RiskPriority.low:    return const Color(0xFFF97316);
    }
  }

  String get priorityLabel {
    switch (priority) {
      case RiskPriority.high:   return 'P1';
      case RiskPriority.medium: return 'P2';
      case RiskPriority.low:    return 'P3';
    }
  }
}

/// Pure local flag evaluation — no server call needed.
class RiskFlagsHelper {
  static List<RiskFlag> evaluate({
    int? hooperScore,
    int? lastRpe,
    double? latestAssessmentScore,
    AssessmentType? latestAssessmentType,
    double? stabilityScore,
    double? movementScore,
    String? trend,
    DateTime? lastAssessmentDate,
  }) {
    final flags = <RiskFlag>[];
    final now = DateTime.now();

    // 1. Hooper fatigue
    if (hooperScore != null && hooperScore >= 17) {
      flags.add(RiskFlag(
        id: 'high_fatigue',
        priority: RiskPriority.high,
        icon: Icons.battery_0_bar_rounded,
        title: AppLocalizations.get('flag_high_fatigue'),
        reason: '${AppLocalizations.get('hooper_score')}: $hooperScore/28',
        recommendation: AppLocalizations.get('flag_rec_high_fatigue'),
      ));
    } else if (hooperScore != null && hooperScore >= 13) {
      flags.add(RiskFlag(
        id: 'moderate_fatigue',
        priority: RiskPriority.medium,
        icon: Icons.battery_2_bar_rounded,
        title: AppLocalizations.get('flag_moderate_fatigue'),
        reason: '${AppLocalizations.get('hooper_score')}: $hooperScore/28',
        recommendation: AppLocalizations.get('flag_rec_moderate_fatigue'),
      ));
    }

    // 2. High RPE
    if (lastRpe != null && lastRpe >= 8) {
      flags.add(RiskFlag(
        id: 'high_rpe',
        priority: RiskPriority.medium,
        icon: Icons.speed_rounded,
        title: AppLocalizations.get('flag_high_rpe'),
        reason: 'RPE: $lastRpe/10',
        recommendation: AppLocalizations.get('flag_rec_high_rpe'),
      ));
    }

    // 3. Low assessment score (only if no more specific flag will cover it)
    // Skip if it's a squat/jump type since those get their own specific flag (low_movement / poor_landing)
    final hasSpecificFlag = (latestAssessmentType == AssessmentType.squat && movementScore != null && movementScore < 55) ||
        (latestAssessmentType == AssessmentType.jumpLanding && stabilityScore != null && stabilityScore < 55);
    if (latestAssessmentScore != null && latestAssessmentScore < 50 && !hasSpecificFlag) {
      flags.add(RiskFlag(
        id: 'low_readiness',
        priority: RiskPriority.high,
        icon: Icons.warning_rounded,
        title: AppLocalizations.get('flag_low_readiness'),
        reason: '${AppLocalizations.get('score_overall')}: ${latestAssessmentScore.round()}/100',
        recommendation: AppLocalizations.get('flag_rec_low_readiness'),
      ));
    }

    // 4. Poor landing control (jump tests)
    if ((latestAssessmentType == AssessmentType.jumpLanding) &&
        stabilityScore != null && stabilityScore < 55) {
      flags.add(RiskFlag(
        id: 'poor_landing',
        priority: RiskPriority.high,
        icon: Icons.arrow_downward_rounded,
        title: AppLocalizations.get('flag_poor_landing'),
        reason: '${AppLocalizations.get('score_stability')}: ${stabilityScore.round()}/100',
        recommendation: AppLocalizations.get('flag_rec_poor_landing'),
      ));
    }

    // 5. Low movement quality (squat)
    if (latestAssessmentType == AssessmentType.squat &&
        movementScore != null && movementScore < 55) {
      flags.add(RiskFlag(
        id: 'low_movement',
        priority: RiskPriority.medium,
        icon: Icons.accessibility_new_rounded,
        title: AppLocalizations.get('flag_low_movement'),
        reason: '${AppLocalizations.get('score_movement')}: ${movementScore.round()}/100',
        recommendation: AppLocalizations.get('flag_rec_low_movement'),
      ));
    }

    // 6. Declining performance trend
    if (trend == 'declining') {
      flags.add(RiskFlag(
        id: 'declining',
        priority: RiskPriority.medium,
        icon: Icons.trending_down_rounded,
        title: AppLocalizations.get('flag_declining'),
        reason: AppLocalizations.get('flag_declining_reason'),
        recommendation: AppLocalizations.get('flag_rec_declining'),
      ));
    }

    // 7. Missing recent assessments
    if (lastAssessmentDate != null) {
      final daysSince = now.difference(lastAssessmentDate).inDays;
      if (daysSince > 14) {
        flags.add(RiskFlag(
          id: 'missing_assessment',
          priority: RiskPriority.low,
          icon: Icons.event_busy_rounded,
          title: AppLocalizations.get('flag_missing_assessment'),
          reason: AppLocalizations.format('flag_days_since', {'days': daysSince}),
          recommendation: AppLocalizations.get('flag_rec_missing_assessment'),
        ));
      }
    } else {
      flags.add(RiskFlag(
        id: 'no_assessment',
        priority: RiskPriority.low,
        icon: Icons.event_busy_rounded,
        title: AppLocalizations.get('flag_no_assessment'),
        reason: AppLocalizations.get('flag_no_assessment_reason'),
        recommendation: AppLocalizations.get('flag_rec_missing_assessment'),
      ));
    }

    flags.sort((a, b) => a.priority.index.compareTo(b.priority.index));
    return flags;
  }
}
