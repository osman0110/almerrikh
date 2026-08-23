import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_localizations.dart';

class ReadinessResult {
  final int score;
  final String status; // 'ready' | 'monitor' | 'fatigue_risk' | 'needs_recovery'
  final String recommendation;
  final List<String> factors;

  const ReadinessResult({
    required this.score,
    required this.status,
    required this.recommendation,
    required this.factors,
  });

  Color get color {
    switch (status) {
      case 'ready':          return AppColors.success;
      case 'monitor':        return AppColors.warning;
      case 'fatigue_risk':   return const Color(0xFFF97316);
      case 'needs_recovery': return AppColors.destructive;
      default:               return AppColors.muted;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'ready':          return AppLocalizations.get('readiness_ready');
      case 'monitor':        return AppLocalizations.get('readiness_monitor');
      case 'fatigue_risk':   return AppLocalizations.get('readiness_fatigue_risk');
      case 'needs_recovery': return AppLocalizations.get('readiness_needs_recovery');
      default:               return AppLocalizations.get('readiness_no_data');
    }
  }
}

/// Pure local readiness calculation — no server calls.
/// Inputs come from already-loaded wellness snapshot data.
class ReadinessHelper {
  /// [hooperScore] : 4 (perfect) → 28 (worst). Null = no data.
  /// [lastRpe]     : 1–10 post-session effort. Null = no data.
  /// [latestAssessmentScore] : 0–100. Null = no assessment.
  /// [trendDirection] : 'improving' | 'stable' | 'declining' | null.
  static ReadinessResult calculate({
    int? hooperScore,
    int? lastRpe,
    double? latestAssessmentScore,
    String? trendDirection,
  }) {
    double score = 100.0;
    final factors = <String>[];

    // Hooper Index (4=best, 28=worst) → 0-40 penalty
    if (hooperScore != null) {
      final penalty = ((hooperScore - 4).clamp(0, 24) / 24.0) * 40;
      score -= penalty;
      if (hooperScore >= 17) {
        factors.add(AppLocalizations.get('flag_high_fatigue'));
      } else if (hooperScore >= 13) {
        factors.add(AppLocalizations.get('flag_moderate_wellness'));
      }
    } else {
      score -= 5;
    }

    // RPE (1–10) — high values indicate post-session fatigue
    if (lastRpe != null) {
      if (lastRpe >= 8) {
        score -= 20;
        factors.add(AppLocalizations.get('flag_high_rpe'));
      } else if (lastRpe >= 6) {
        score -= 10;
      }
    }

    // Assessment quality bonus/penalty around 65 baseline
    if (latestAssessmentScore != null) {
      final diff = (latestAssessmentScore - 65) * 0.18;
      score += diff;
      if (latestAssessmentScore < 50) {
        factors.add(AppLocalizations.get('flag_low_movement'));
      }
    }

    // Trend modifier
    if (trendDirection == 'declining') {
      score -= 8;
      factors.add(AppLocalizations.get('flag_declining'));
    } else if (trendDirection == 'improving') {
      score = (score + 3).clamp(0, 100);
    }

    final scoreInt = score.clamp(0, 100).round();

    late String status;
    late String recommendation;
    if (scoreInt >= 80) {
      status = 'ready';
      recommendation = AppLocalizations.get('readiness_rec_ready');
    } else if (scoreInt >= 60) {
      status = 'monitor';
      recommendation = AppLocalizations.get('readiness_rec_monitor');
    } else if (scoreInt >= 40) {
      status = 'fatigue_risk';
      recommendation = AppLocalizations.get('readiness_rec_fatigue');
    } else {
      status = 'needs_recovery';
      recommendation = AppLocalizations.get('readiness_rec_recovery');
    }

    return ReadinessResult(
      score: scoreInt,
      status: status,
      recommendation: recommendation,
      factors: factors,
    );
  }
}
