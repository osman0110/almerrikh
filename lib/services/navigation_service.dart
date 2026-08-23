import 'package:flutter/material.dart';
import '../app_state.dart';
import '../screens/club/notifications_page.dart';

/// Attached to MaterialApp in main.dart so pushes can navigate without a
/// widget BuildContext (background/terminated FCM taps, local-notification
/// taps).
final navigatorKey = GlobalKey<NavigatorState>();

/// Mirrors NotificationsPage._onTapNotification's route handling
/// (lib/screens/club/notifications_page.dart) so an in-app tap and a
/// push/local-notification tap land on the same screen.
void openLinkedRoute(String? route) {
  if (route == null || route.isEmpty) return;
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  if (route.startsWith('/club/players/')) {
    nav.pushNamed(route);
  } else if (route.startsWith('/session/') ||
      route.startsWith('/match/') ||
      route.startsWith('/physio-session/')) {
    nav.pushNamed(
        currentUserRole == UserRole.player ? '/player/sessions' : '/club/sessions');
  } else if (route == '/club/notifications') {
    nav.push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
  }
}
