import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_localizations.dart';
import 'readiness_helper.dart';
import 'risk_flags_helper.dart';

class CoachSummary {
  final String statusLabel;
  final String statusReason;
  final String? topFlag;
  final String strength;
  final String mainRecommendation;
  final String nextCheck;
  final Color statusColor;

  const CoachSummary({
    required this.statusLabel,
    required this.statusReason,
    this.topFlag,
    required this.strength,
    required this.mainRecommendation,
    required this.nextCheck,
    required this.statusColor,
  });
}

/// Builds a concise AI-style coach summary from existing local data.
/// No external API. All rules-based.
class CoachSummaryHelper {
  static CoachSummary build({
    required ReadinessResult readiness,
    required List<RiskFlag> flags,
    required List<String> recommendations,
    double? movementScore,
    double? stabilityScore,
    double? symmetryScore,
    String? trend,
    int? hooperScore,
    int? lastRpe,
  }) {
    // Determine the player's main strength
    String strength;
    if (movementScore != null && movementScore >= 75) {
      strength = AppLocalizations.get('coach_summary_strength_good_movement');
    } else if (stabilityScore != null && stabilityScore >= 75) {
      strength = AppLocalizations.get('coach_summary_strength_good_stability');
    } else if (symmetryScore != null && symmetryScore >= 75) {
      strength = AppLocalizations.get('coach_summary_strength_good_balance');
    } else if (trend == 'improving') {
      strength = AppLocalizations.get('trend_improving');
    } else {
      strength = AppLocalizations.get('coach_summary_strength_consistent');
    }

    // Build the reason sentence
    String reason;
    if (hooperScore != null && hooperScore >= 17) {
      reason = '${AppLocalizations.get("hooper_score")}: $hooperScore/28';
    } else if (lastRpe != null && lastRpe >= 8) {
      reason = 'RPE: $lastRpe/10';
    } else if (flags.isNotEmpty && flags.first.priority == RiskPriority.high) {
      reason = flags.first.title;
    } else {
      reason = readiness.recommendation;
    }

    // Top priority flag title (for display)
    final topFlag = flags.isNotEmpty ? flags.first.title : null;

    // Primary recommendation
    final mainRec = recommendations.isNotEmpty
        ? recommendations.first
        : readiness.recommendation;

    // Next check timing
    String nextCheck;
    switch (readiness.status) {
      case 'ready':
        nextCheck = AppLocalizations.get('coach_summary_next_check_week');
        break;
      case 'monitor':
        nextCheck = AppLocalizations.get('coach_summary_next_check_tomorrow');
        break;
      case 'needs_recovery':
        nextCheck = AppLocalizations.get('coach_summary_next_check_today');
        break;
      default: // fatigue_risk
        nextCheck = AppLocalizations.get('coach_summary_next_check_after_session');
    }

    // No data fallback
    Color color = readiness.color;
    if (readiness.score == 0 && flags.isEmpty) {
      color = AppColors.muted;
    }

    return CoachSummary(
      statusLabel: readiness.statusLabel,
      statusReason: reason,
      topFlag: topFlag,
      strength: strength,
      mainRecommendation: mainRec,
      nextCheck: nextCheck,
      statusColor: color,
    );
  }
}
