import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../api_service.dart';
import '../utils/app_logger.dart';
import 'navigation_service.dart';

/// Registered as [FirebaseMessaging.onBackgroundMessage] in main.dart. Must
/// be a top-level (or static) function per the plugin's requirements.
/// Android/iOS already render the notification tray entry for a
/// data+notification payload while the app is backgrounded/terminated — this
/// only runs for additional background data handling, so it's a no-op today.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Thin wrapper around flutter_local_notifications for the player-facing
/// survey reminders (see SurveyReminderService). Scheduling uses
/// [AndroidScheduleMode.inexactAllowWhileIdle] so it works without the
/// special SCHEDULE_EXACT_ALARM permission — acceptable for reminder-style
/// notifications where a few minutes of slack doesn't matter.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static const _channel = AndroidNotificationChannel(
    'survey_reminders',
    'Survey Reminders',
    description: 'Pre/post training and match wellness survey reminders',
    importance: Importance.high,
  );

  /// Default channel for server-sent push (sessions, matches, physio,
  /// tasks, injuries, readiness alerts). Referenced by name in
  /// AndroidManifest.xml's default_notification_channel_id meta-data.
  static const _pushChannel = AndroidNotificationChannel(
    'push_notifications',
    'Alerts',
    description: 'Session, match, physio and staff alerts',
    importance: Importance.high,
  );

  static bool _pushRegistered = false;

  static Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.local);

      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        ),
        onDidReceiveNotificationResponse: (details) {
          openLinkedRoute(details.payload);
        },
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_pushChannel);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      AppLogger.e('NotificationService.init', 'Failed to initialize', e);
    }
  }

  /// Requests notification permission, registers the FCM token with the
  /// backend, and wires up foreground/tap handling. Call once a user is
  /// signed in (see RootGate._loadState in main.dart); safe to call more
  /// than once — only does work the first time per app run.
  static Future<void> registerPush() async {
    if (_pushRegistered || kIsWeb) return;
    _pushRegistered = true;
    await init();
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null) {
        await ApiService.registerDeviceToken(
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
        );
      }
      messaging.onTokenRefresh.listen((newToken) {
        ApiService.registerDeviceToken(
          token: newToken,
          platform: Platform.isIOS ? 'ios' : 'android',
        );
      });

      // Foreground messages don't show a system tray notification by
      // default — render them through the same local-notifications channel
      // used for survey reminders so foreground/background/terminated all
      // look consistent.
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        _plugin.show(
          message.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _pushChannel.id,
              _pushChannel.name,
              channelDescription: _pushChannel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          payload: message.data['linked_route'] as String?,
        );
      });

      // Tapping the push while the app is backgrounded.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        openLinkedRoute(message.data['linked_route'] as String?);
      });

      // App launched by tapping the push from a fully-terminated state.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        openLinkedRoute(initialMessage.data['linked_route'] as String?);
      }
    } catch (e) {
      AppLogger.e('NotificationService.registerPush', 'Failed to register push', e);
    }
  }

  /// Best-effort token cleanup on logout — never blocks sign-out on failure.
  static Future<void> unregisterPush() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await ApiService.unregisterDeviceToken(token);
    } catch (e) {
      AppLogger.e('NotificationService.unregisterPush', 'Failed to unregister push', e);
    }
  }

  /// Schedules a local notification at [when]. Silently skips if [when] is
  /// already in the past.
  static Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    await init();
    if (when.isBefore(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      AppLogger.e('NotificationService.scheduleAt', 'Failed to schedule $id', e);
    }
  }

  static Future<void> cancel(int id) async {
    await init();
    try {
      await _plugin.cancel(id);
    } catch (e) {
      AppLogger.e('NotificationService.cancel', 'Failed to cancel $id', e);
    }
  }

  static Future<void> cancelAll() async {
    await init();
    try {
      await _plugin.cancelAll();
    } catch (e) {
      AppLogger.e('NotificationService.cancelAll', 'Failed to cancel all', e);
    }
  }
}
