// Notification Service for Daily Wellness Reminders
// Ready for integration with flutter_local_notifications + timezone packages

class NotificationService {
  static bool _isInitialized = false;

  /// Initialize notification service
  /// Add to main.dart: await NotificationService.init();
  static Future<void> init() async {
    if (_isInitialized) return;
    // When flutter_local_notifications is added to pubspec.yaml, initialize here
    _isInitialized = true;
  }

  /// Schedule pre-training wellness check reminder (9 AM daily)
  /// Requires: flutter_local_notifications, timezone packages
  static Future<void> schedulePreTrainingReminder() async {
    await init();
    print('[NotificationService] Pre-training reminder scheduled for 9 AM');
    // Implementation with flutter_local_notifications:
    // await _notifications.zonedSchedule(
    //   1001,
    //   'Pre-Training Wellness Check',
    //   'Complete your wellness check before training',
    //   _nextInstanceOfTime(9, 0),
    //   ...notificationDetails...
    // );
  }

  /// Schedule post-training RPE reminder (5 PM daily)
  static Future<void> schedulePostTrainingReminder() async {
    await init();
    print('[NotificationService] Post-training reminder scheduled for 5 PM');
    // Implementation with flutter_local_notifications:
    // await _notifications.zonedSchedule(
    //   1002,
    //   'Log Your Training Session',
    //   'Rate your session and log RPE',
    //   _nextInstanceOfTime(17, 0),
    //   ...notificationDetails...
    // );
  }

  /// Show instant notification (e.g., injury risk alert)
  static Future<void> showInstant({
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    print('[NotificationService] ⚡ $title: $body');
  }

  /// Show injury risk alert
  static Future<void> showInjuryRiskAlert(String playerName) async {
    await showInstant(
      title: '⚠️ Injury Risk Alert',
      body: '$playerName showing elevated injury risk markers',
      payload: 'injury_risk',
    );
  }

  /// Show readiness alert
  static Future<void> showReadinessAlert(String playerName, int score) async {
    final title = score >= 70 ? '✅ Ready to go' : score >= 40 ? '⚠️ Monitor' : '🛑 High Risk';
    final body = score >= 70
        ? '$playerName is ready for intense training'
        : score >= 40
            ? '$playerName needs close monitoring'
            : '$playerName is at elevated injury risk';

    await showInstant(title: title, body: body, payload: 'readiness');
  }

  /// Cancel all scheduled notifications
  static Future<void> cancelAll() async {
    print('[NotificationService] All notifications cancelled');
  }

  /// Cancel specific notification by ID
  static Future<void> cancel(int id) async {
    print('[NotificationService] Notification $id cancelled');
  }

  /// Setup daily reminders (call from main.dart or player dashboard on first login)
  static Future<void> setupDailyReminders() async {
    await schedulePreTrainingReminder();
    await schedulePostTrainingReminder();
    print('[NotificationService] Daily reminders configured');
  }
}

// SETUP INSTRUCTIONS:
// 1. Add to pubspec.yaml:
//    flutter_local_notifications: ^17.0.0
//    timezone: ^0.9.0
//
// 2. Add to main.dart initState or main():
//    await NotificationService.init();
//    await NotificationService.setupDailyReminders();
//
// 3. Call from monitoring screens:
//    await NotificationService.showInjuryRiskAlert(playerName);
//    await NotificationService.showReadinessAlert(playerName, score);
//
// 4. Android: Add to android/app/build.gradle:
//    targetSdkVersion 33
//
// 5. iOS: Add to ios/Runner/Info.plist notification permissions
