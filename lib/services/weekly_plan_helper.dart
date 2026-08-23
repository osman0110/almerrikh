import '../app_localizations.dart';

/// Generates a 5-point weekly training suggestion based on player readiness status.
/// Completely local — no external API needed.
class WeeklyPlanHelper {
  static List<String> suggest(String readinessStatus) {
    switch (readinessStatus) {
      case 'ready':
        return [
          AppLocalizations.get('weekly_plan_normal_1'),
          AppLocalizations.get('weekly_plan_normal_2'),
          AppLocalizations.get('weekly_plan_normal_3'),
          AppLocalizations.get('weekly_plan_normal_4'),
          AppLocalizations.get('weekly_plan_normal_5'),
        ];
      case 'monitor':
        return [
          AppLocalizations.get('weekly_plan_monitor_1'),
          AppLocalizations.get('weekly_plan_monitor_2'),
          AppLocalizations.get('weekly_plan_monitor_3'),
          AppLocalizations.get('weekly_plan_monitor_4'),
          AppLocalizations.get('weekly_plan_monitor_5'),
        ];
      case 'fatigue_risk':
        return [
          AppLocalizations.get('weekly_plan_fatigue_1'),
          AppLocalizations.get('weekly_plan_fatigue_2'),
          AppLocalizations.get('weekly_plan_fatigue_3'),
          AppLocalizations.get('weekly_plan_fatigue_4'),
          AppLocalizations.get('weekly_plan_fatigue_5'),
        ];
      case 'needs_recovery':
        return [
          AppLocalizations.get('weekly_plan_recovery_1'),
          AppLocalizations.get('weekly_plan_recovery_2'),
          AppLocalizations.get('weekly_plan_recovery_3'),
          AppLocalizations.get('weekly_plan_recovery_4'),
          AppLocalizations.get('weekly_plan_recovery_5'),
        ];
      default:
        return [AppLocalizations.get('no_data')];
    }
  }
}
