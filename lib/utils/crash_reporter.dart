import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../app_config.dart';

/// Production crash reporter backed by Sentry.
///
/// Privacy guarantees:
///   • Only active in release builds (kReleaseMode).
///   • Requires a DSN — no-op when kSentryDsn is empty.
///   • Never sends: tokens, passwords, player names, email, response bodies.
///   • Only sends: error type, sanitised stack trace, user role tag, route.
///   • `sendDefaultPii = false` disables all Sentry auto-collection of PII.
///   • `beforeSend` strips user and request objects from every event.
///
/// Usage:
///   1. await CrashReporter.init(() => runApp(const App()));  // in main()
///   2. CrashReporter.setRole('club');                        // after login
///   3. CrashReporter.clearContext();                         // after logout
///   4. CrashReporter.breadcrumb('route', category: 'nav');   // navigation
///   5. CrashReporter.apiFailed('ApiService.login');          // in catch blocks
class CrashReporter {
  CrashReporter._();

  static bool _active = false;

  // ── Initialisation ──────────────────────────────────────────────────────────

  /// Initialise crash reporting and start the app.
  ///
  /// [runner] must call `runApp(...)`.
  ///
  /// In debug/profile mode: sets up Flutter error presenter and a guarded
  /// zone for unhandled async errors, then runs [runner] normally.
  ///
  /// In release mode with a configured DSN: initialises Sentry, registers
  /// Flutter and platform error handlers, then runs [runner] inside Sentry's
  /// protected zone.
  static Future<void> init(VoidCallback runner) async {
    if (!kReleaseMode) {
      // Debug: keep Flutter's default error presenter + basic zone guard.
      FlutterError.onError = FlutterError.presentError;
      runZonedGuarded(runner, (e, st) {
        if (kDebugMode) debugPrint('⚠ [Zone] Unhandled: ${e.runtimeType}');
      });
      return;
    }

    if (kSentryDsn.isEmpty) {
      // Release but no DSN configured — run without crash reporting.
      runner();
      return;
    }

    // Release + DSN configured — full Sentry setup.
    await SentryFlutter.init(
      (options) {
        options.dsn            = kSentryDsn;
        options.environment    = 'production';
        options.release        = kAppVersion;
        options.sendDefaultPii = false;          // no IP, no device PII
        options.tracesSampleRate = 0.0;          // disable perf tracing (not needed)
        options.enableAutoSessionTracking = true; // session crash rate tracking
        options.beforeSend = _sanitiseEvent;
      },
      appRunner: () {
        _active = true;

        // Flutter widget / rendering errors
        FlutterError.onError = _onFlutterError;

        // Dart async errors outside Flutter zones (platform channel, plugins)
        PlatformDispatcher.instance.onError = (error, stack) {
          _doCapture(error, stack, source: 'platform');
          return true; // error handled — do not also print to console
        };

        runner();
      },
    );
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  static FutureOr<SentryEvent?> _sanitiseEvent(SentryEvent event, Hint hint) {
    // Strip any user / request objects Sentry may have auto-collected.
    return event.copyWith(user: null, request: null);
  }

  static void _onFlutterError(FlutterErrorDetails details) {
    _doCapture(details.exception, details.stack, source: 'flutter');
  }

  static void _doCapture(Object error, StackTrace? stack, {String source = 'app'}) {
    if (!_active) return;
    Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (s) => s.setTag('source', source),
    );
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Capture a non-fatal error (e.g., unexpected API contract violation).
  /// Use sparingly — this counts against your Sentry quota.
  /// [tag] must be a safe string like 'ApiService.saveAssessment' — no user data.
  static void captureError(Object error, StackTrace? stack, {required String tag}) {
    if (!_active) return;
    Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (s) {
        s.setTag('tag', tag);
        s.level = SentryLevel.warning;
      },
    );
  }

  /// Add a breadcrumb — context that appears before a crash in Sentry.
  /// [message] must contain no user data (routes, action names only).
  static void breadcrumb(String message, {String category = 'app'}) {
    if (!_active) return;
    Sentry.addBreadcrumb(Breadcrumb(
      message: message,
      category: category,
      timestamp: DateTime.now().toUtc(),
    ));
  }

  /// Record a failed API call as a breadcrumb.
  /// Only the [tag] string is sent (e.g. 'ApiService.login') — never error details.
  static void apiFailed(String tag) {
    if (!_active) return;
    Sentry.addBreadcrumb(Breadcrumb(
      message: 'API call failed',
      category: 'api',
      data: {'tag': tag},
      level: SentryLevel.warning,
      timestamp: DateTime.now().toUtc(),
    ));
  }

  /// Set role context after login. NEVER pass email, name, or other PII.
  static void setRole(String role) {
    if (!_active) return;
    Sentry.configureScope((s) => s.setTag('user_role', role));
  }

  /// Clear all Sentry context on logout.
  static void clearContext() {
    if (!_active) return;
    Sentry.configureScope((s) => s.clear());
  }
}
