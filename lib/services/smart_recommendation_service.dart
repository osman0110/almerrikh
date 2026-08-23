import '../app_localizations.dart';
import 'readiness_helper.dart';
import 'risk_flags_helper.dart';

/// Rules-based training recommendation engine.
/// No external AI — all logic is local and safe for demo.
class SmartRecommendationService {
  /// Generate up to 5 training recommendations for a player.
  static List<String> generate({
    required ReadinessResult readiness,
    required List<RiskFlag> flags,
    int? hooperScore,
    int? lastRpe,
    double? latestAssessmentScore,
    String? latestAssessmentType, // 'squat' | 'jumpLanding' | 'singleLegBalance'
    String? trend,
  }) {
    final recs = <String>[];

    // 1. Primary recommendation based on readiness status
    switch (readiness.status) {
      case 'ready':
        recs.add(AppLocalizations.get('rec_player_ready_normal'));
        if (latestAssessmentScore != null && latestAssessmentScore >= 75) {
          recs.add(AppLocalizations.get('rec_strength_football'));
        }
        break;
      case 'monitor':
        recs.add(AppLocalizations.get('rec_monitor_fatigue_next'));
        recs.add(AppLocalizations.get('rec_technique_focus'));
        break;
      case 'fatigue_risk':
        recs.add(AppLocalizations.get('rec_reduce_load_today'));
        recs.add(AppLocalizations.get('rec_add_recovery_session'));
        break;
      case 'needs_recovery':
        recs.add(AppLocalizations.get('rec_add_recovery_session'));
        recs.add(AppLocalizations.get('rec_check_sleep_stress'));
        break;
    }

    // 2. Flag-driven recommendations (top 3 flags only)
    for (final flag in flags.take(3)) {
      switch (flag.id) {
        case 'poor_landing':
          recs.add(AppLocalizations.get('rec_focus_landing_control'));
          recs.add(AppLocalizations.get('rec_avoid_high_jump_load'));
          break;
        case 'low_movement':
          recs.add(AppLocalizations.get('rec_add_mobility_work'));
          break;
        case 'no_assessment':
        case 'missing_assessment':
          recs.add(AppLocalizations.get('rec_schedule_assessment'));
          break;
        case 'declining':
          recs.add(AppLocalizations.get('rec_technique_focus'));
          break;
        case 'high_fatigue':
        case 'high_rpe':
          if (!recs.contains(AppLocalizations.get('rec_check_sleep_stress'))) {
            recs.add(AppLocalizations.get('rec_check_sleep_stress'));
          }
          break;
      }
    }

    // 3. Assessment-type specific follow-ups
    if (latestAssessmentType == 'squat' &&
        latestAssessmentScore != null &&
        latestAssessmentScore < 65) {
      recs.add(AppLocalizations.get('rec_repeat_squat_next_week'));
    }
    if (latestAssessmentType == 'singleLegBalance') {
      recs.add(AppLocalizations.get('rec_bilateral_balance'));
    }

    // 4. Always suggest re-assessment after session (last slot)
    if (recs.length < 5) {
      recs.add(AppLocalizations.get('rec_repeat_assessment'));
    }

    // Deduplicate and cap at 5
    final seen = <String>{};
    return recs.where(seen.add).take(5).toList();
  }

  /// Generate a single-sentence smart session recommendation for a coach
  /// based on the average state of the squad in a session.
  static String sessionSummaryRecommendation({
    required int totalPlayers,
    required int readyCount,
    required int monitorCount,
    required int fatigueRiskCount,
    required bool hasJumpDrills,
    required bool hasCompleted,
  }) {
    if (totalPlayers == 0) return AppLocalizations.get('rec_full_training_suitable');

    final atRiskRatio = (fatigueRiskCount / totalPlayers);
    final monitorRatio = (monitorCount / totalPlayers);

    if (atRiskRatio >= 0.3) {
      if (hasJumpDrills) return AppLocalizations.get('session_rec_avoid_jump');
      return AppLocalizations.get('session_rec_add_recovery');
    }
    if (monitorRatio >= 0.3) {
      return AppLocalizations.get('session_rec_reduce_intensity');
    }
    if (hasCompleted) {
      return AppLocalizations.get('session_rec_repeat_after');
    }
    return AppLocalizations.get('rec_full_training_suitable');
  }
}
