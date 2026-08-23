import 'package:flutter/foundation.dart';
import 'crash_reporter.dart';

/// Lightweight structured logger.
///
/// Rules:
///   • Never log tokens, passwords, or player PII.
///   • Logs exception *type* only (runtimeType), not toString().
///   • In debug: all output goes to console via debugPrint (tree-shaken in release).
///   • In release: .e() adds an API breadcrumb to Sentry; no console output.
class AppLogger {
  AppLogger._();

  /// Informational — normal flow milestones.
  static void i(String tag, String message) {
    if (kDebugMode) debugPrint('  [$tag] $message');
  }

  /// Warning — recoverable failure (timeout, empty response, 4xx).
  static void w(String tag, String message) {
    if (kDebugMode) debugPrint('⚠ [$tag] $message');
  }

  /// Error — unexpected exception.
  ///
  /// In debug: prints `tag`, `message`, and `err.runtimeType` to console.
  /// In release: adds a Sentry breadcrumb with the tag only (no error details).
  static void e(String tag, String message, Object err) {
    if (kDebugMode) {
      debugPrint('✖ [$tag] $message (${err.runtimeType})');
    } else {
      // Release: record as breadcrumb — context for future crashes.
      // Only the tag string is sent; never the error message or type.
      CrashReporter.apiFailed(tag);
    }
  }

  /// Classifies a caught exception into a user-safe message string.
  static String userMessage(Object err) {
    final type = err.runtimeType.toString();
    if (type.contains('Timeout') || type.contains('timeout')) {
      return 'Request timed out. Check your connection and try again.';
    }
    if (type.contains('Socket') || type.contains('Connection')) {
      return 'No connection. Check your network and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
