import 'dart:html' as html;
import 'api_service.dart';

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

  Future<void> clearSignedIn() async {
    html.window.localStorage.remove('ssot.token');
    html.window.localStorage.remove('ssot.userName');
    ApiService.setToken(null);
  }
}
