import 'dart:async';

import '../api_service.dart';
import '../storage.dart';
import '../utils/crash_reporter.dart';
import 'firebase_service.dart';
import 'notification_service.dart';

/// The one sign-out path for every logout button: drops this device's push
/// token, revokes the session on the server, then clears the local token.
/// Remote steps are bounded so a hanging call (e.g. FCM getToken on iOS)
/// can never leave the user signed in.
Future<void> signOutUser() async {
  try {
    await NotificationService.unregisterPush()
        .timeout(const Duration(seconds: 5));
  } catch (_) {}
  // logout() captures the auth header before clearing it, so it can run
  // in the background once started.
  unawaited(ApiService.logout());
  unawaited(FirebaseService().signOut());
  await OnboardingStore().clearSignedIn();
  CrashReporter.clearContext();
}
