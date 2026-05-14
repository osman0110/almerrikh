import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'app_state.dart';

class OnboardingStore {
  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('ssot.onboarded') ?? false;
  }

  Future<void> setSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ssot.onboarded', true);
  }

  Future<String?> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ssot.language');
  }

  Future<void> setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssot.language', lang);
  }

  Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('ssot.token');
    if (token == null || token.isEmpty) return false;
    ApiService.setToken(token);
    return true;
  }

  Future<void> setSignedIn({required String token, required String userName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssot.token', token);
    await prefs.setString('ssot.userName', userName);
    ApiService.setToken(token);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ssot.userName');
  }

  Future<UserRole> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('ssot.userRole') ?? 'club';
    return UserRole.values.firstWhere((r) => r.name == role, orElse: () => UserRole.club);
  }

  Future<void> setUserRole(UserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssot.userRole', role.name);
  }

  Future<void> clearSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ssot.token');
    await prefs.remove('ssot.userName');
    await prefs.remove('ssot.userRole');
    ApiService.setToken(null);
  }
}
