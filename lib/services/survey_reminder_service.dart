import '../app_localizations.dart';
import '../models/club_models.dart' show TrainingSession, MatchModel;
import 'notification_service.dart';

/// Schedules local reminders so a player fills the readiness (Hooper) survey
/// from the day before a session/match, and the RPE survey 30 minutes after it
/// ends — if not already done.
///
/// Notification ids are deterministic (derived from the session/match id) so
/// they can be cancelled precisely the moment the player actually submits —
/// see the cancellation hooks in PlayerMonitoringService.saveHooper/saveRpe.
///
/// Limitation: without a backend push/cron this is a best-effort, client-only
/// scheduler. It resyncs every time the player opens the app (see
/// _PlayerDashboardPageState._loadData), which is an acceptable MVP
/// trade-off given there's no background task runner in this project.
class SurveyReminderService {
  static const _preWindow = Duration(minutes: 15);
  static const _postWindow = Duration(minutes: 30);
  static const _defaultMatchDurationMin = 105;

  static int _preId(String id) => ('pre_$id').hashCode & 0x7fffffff;
  static int _postId(String id) => ('post_$id').hashCode & 0x7fffffff;

  /// Ids of matches happening today, refreshed on every [sync] call — used
  /// by [cancelTodayMatchReminders] since Hooper/RPE submissions aren't
  /// tied to a match id on the backend.
  static List<String> _todayMatchIds = [];

  static Future<void> sync({
    required List<TrainingSession> sessions,
    required List<MatchModel> matches,
  }) async {
    final now = DateTime.now();
    final horizon = now.add(const Duration(hours: 48));
    final lookback = now.subtract(const Duration(hours: 2));

    for (final s in sessions) {
      final start = _combineDate(s.date, s.startTime);
      if (start.isBefore(lookback) || start.isAfter(horizon)) continue;
      final end = start.add(Duration(minutes: s.durationMin));

      if (s.wellnessRequired && start.isAfter(now)) {
        final preAt = _preReminderAt(start);
        final isDayBefore = _isCalendarDay(preAt, start.subtract(const Duration(days: 1)));
        await NotificationService.scheduleAt(
          id: _preId(s.id),
          title: isDayBefore
              ? AppLocalizations.get('survey_reminder_pre_available_title')
              : AppLocalizations.format('survey_reminder_pre_title', {'minutes': _preWindow.inMinutes}),
          body: isDayBefore
              ? AppLocalizations.format('survey_reminder_pre_available_body', {
                  'event': AppLocalizations.get('survey_event_session'),
                })
              : AppLocalizations.format('survey_reminder_pre_body', {
                  'event': AppLocalizations.get('survey_event_session'),
                  'minutes': _preWindow.inMinutes,
                }),
          when: preAt,
          payload: 'session_pre:${s.id}',
        );
      }
      if (s.rpeRequired) {
        final postAt = end.add(_postWindow);
        await NotificationService.scheduleAt(
          id: _postId(s.id),
          title: AppLocalizations.get('survey_reminder_post_title'),
          body: AppLocalizations.format('survey_reminder_post_body',
              {'event': AppLocalizations.get('survey_event_session')}),
          when: postAt,
          payload: 'session_post:${s.id}',
        );
      }
    }

    final today = DateTime.now();
    _todayMatchIds = matches
        .where((m) => m.matchDate.year == today.year &&
            m.matchDate.month == today.month &&
            m.matchDate.day == today.day)
        .map((m) => m.id)
        .toList();

    for (final m in matches) {
      final start = _combineDate(m.matchDate, m.matchTime);
      if (start.isBefore(lookback) || start.isAfter(horizon)) continue;
      final end = start.add(const Duration(minutes: _defaultMatchDurationMin));

      if (m.wellnessRequired && start.isAfter(now)) {
        final preAt = _preReminderAt(start);
        final isDayBefore = _isCalendarDay(preAt, start.subtract(const Duration(days: 1)));
        await NotificationService.scheduleAt(
          id: _preId(m.id),
          title: isDayBefore
              ? AppLocalizations.get('survey_reminder_pre_available_title')
              : AppLocalizations.format('survey_reminder_pre_title', {'minutes': _preWindow.inMinutes}),
          body: isDayBefore
              ? AppLocalizations.format('survey_reminder_pre_available_body', {
                  'event': AppLocalizations.get('survey_event_match'),
                })
              : AppLocalizations.format('survey_reminder_pre_body', {
                  'event': AppLocalizations.get('survey_event_match'),
                  'minutes': _preWindow.inMinutes,
                }),
          when: preAt,
          payload: 'match_pre:${m.id}',
        );
      }
      if (m.rpeRequired) {
        await NotificationService.scheduleAt(
          id: _postId(m.id),
          title: AppLocalizations.get('survey_reminder_post_title'),
          body: AppLocalizations.format('survey_reminder_post_body',
              {'event': AppLocalizations.get('survey_event_match')}),
          when: end.add(_postWindow),
          payload: 'match_post:${m.id}',
        );
      }
    }
  }

  /// Cancels the pre-survey reminder for a specific session, called right
  /// after the player successfully submits their Hooper check-in.
  static Future<void> cancelPreForSession(String sessionId) =>
      NotificationService.cancel(_preId(sessionId));

  /// Cancels the post-survey reminder for a specific session, called right
  /// after the player successfully submits their RPE.
  static Future<void> cancelPostForSession(String sessionId) =>
      NotificationService.cancel(_postId(sessionId));

  /// Matches have no id linkage back from the save API (Hooper/RPE are only
  /// tied to a training_session_id), so a match-day submission cancels any
  /// match reminder scheduled for today — matching the backend's own
  /// "one entry per day when no session_id given" dedup rule.
  static Future<void> cancelTodayMatchReminders({required bool pre}) async {
    for (final id in _todayMatchIds) {
      await NotificationService.cancel(pre ? _preId(id) : _postId(id));
    }
  }

  static DateTime _combineDate(DateTime date, String time) {
    final tp = time.split(':');
    final h = tp.isNotEmpty ? int.tryParse(tp[0]) ?? 16 : 16;
    final mi = tp.length > 1 ? int.tryParse(tp[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, h, mi);
  }

  static DateTime _preReminderAt(DateTime start) {
    final now = DateTime.now();
    final calendarDayBefore = DateTime(start.year, start.month, start.day - 1);
    if (_isCalendarDay(now, calendarDayBefore)) {
      return now.add(const Duration(minutes: 1));
    }
    final dayBeforeAt = DateTime(start.year, start.month, start.day - 1, 9);
    if (dayBeforeAt.isAfter(now)) return dayBeforeAt;
    final beforeStart = start.subtract(_preWindow);
    if (beforeStart.isAfter(now)) return beforeStart;
    return now.add(const Duration(minutes: 1));
  }

  static bool _isCalendarDay(DateTime value, DateTime reference) =>
      value.year == reference.year &&
      value.month == reference.month &&
      value.day == reference.day;
}
