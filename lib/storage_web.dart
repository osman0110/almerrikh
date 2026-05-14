import 'dart:html' as html;
import 'api_service.dart';
import 'app_state.dart';

class OnboardingStore {
  Future<bool> hasSeenOnboarding() async {
    return html.window.localStorage['ssot.onboarded'] == '1';
  }

  Future<void> setSeenOnboarding() async {
    html.window.localStorage['ssot.onboarded'] = '1';
  }

  Future<String?> getLanguage() async {
    return html.window.localStorage['ssot.language'];
  }

  Future<void> setLanguage(String lang) async {
    html.window.localStorage['ssot.language'] = lang;
  }

  Future<bool> isSignedIn() async {
    final token = html.window.localStorage['ssot.token'];
    if (token == null || token.isEmpty) return false;
    ApiService.setToken(token);
    return true;
  }

  Future<void> setSignedIn({required String token, required String userName}) async {
    html.window.localStorage['ssot.token'] = token;
    html.window.localStorage['ssot.userName'] = userName;
    ApiService.setToken(token);
  }

  Future<String?> getUserName() async {
    return html.window.localStorage['ssot.userName'];
  }

  Future<UserRole> getUserRole() async {
    final role = html.window.localStorage['ssot.userRole'] ?? 'club';
    return UserRole.values.firstWhere((r) => r.name == role, orElse: () => UserRole.club);
  }

  Future<void> setUserRole(UserRole role) async {
    html.window.localStorage['ssot.userRole'] = role.name;
  }

  Future<void> clearSignedIn() async {
    html.window.localStorage.remove('ssot.token');
    html.window.localStorage.remove('ssot.userName');
    html.window.localStorage.remove('ssot.userRole');
    ApiService.setToken(null);
  }
}
