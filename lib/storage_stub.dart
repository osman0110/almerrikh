import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'app_state.dart';

// The auth token is the one piece of state here that grants account access
// (30-day server-side lifetime, see api/auth.php) — it lives in the OS
// keystore/keychain via flutter_secure_storage, not plain SharedPreferences,
// so it isn't readable via `adb backup`/root file access. Everything else
// in this store (language, cached display name, role) is non-sensitive and
// stays in SharedPreferences.
const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

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
    var token = await _secureStorage.read(key: 'ssot.token');
    if (token == null || token.isEmpty) {
      // One-time migration for installs that signed in before this app
      // version moved the token out of plaintext SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      final legacyToken = prefs.getString('ssot.token');
      if (legacyToken != null && legacyToken.isNotEmpty) {
        await _secureStorage.write(key: 'ssot.token', value: legacyToken);
        await prefs.remove('ssot.token');
        token = legacyToken;
      }
    }
    if (token == null || token.isEmpty) return false;
    ApiService.setToken(token);
    return true;
  }

  Future<void> setSignedIn({required String token, required String userName}) async {
    await _secureStorage.write(key: 'ssot.token', value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssot.userName', userName);
    ApiService.setToken(token);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ssot.userName');
  }

  Future<void> setUserName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssot.userName', value);
  }

  Future<String?> getUserAvatarUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ssot.userAvatarUrl');
  }

  Future<void> setUserAvatarUrl(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove('ssot.userAvatarUrl');
    } else {
      await prefs.setString('ssot.userAvatarUrl', value);
    }
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

  Future<OrgRole> getOrgRole() async {
    final prefs = await SharedPreferences.getInstance();
    // Must go through orgRoleFromString — a raw name-match here misses
    // snake_case server names cached from login (tactical_coach,
    // performance_manager, the legacy massage_specialist alias), silently
    // falling back to OrgRole.staff and landing those accounts on the
    // unrestricted ClubDashboardPage on every app reopen.
    return orgRoleFromString(prefs.getString('ssot.orgRole'));
  }

  Future<void> setOrgRole(OrgRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssot.orgRole', role.name);
  }

  Future<String?> getLinkedPlayerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ssot.linkedPlayerId');
  }

  Future<void> setLinkedPlayerId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.isEmpty) {
      await prefs.remove('ssot.linkedPlayerId');
    } else {
      await prefs.setString('ssot.linkedPlayerId', id);
    }
  }

  Future<int?> getClubUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('ssot.clubUserId');
  }

  Future<void> setClubUserId(int? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove('ssot.clubUserId');
    } else {
      await prefs.setInt('ssot.clubUserId', id);
    }
  }

  Future<PlayerType?> getPlayerType() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('ssot.playerType');
    if (v == null) return null;
    return v == 'independent' ? PlayerType.independent : PlayerType.club;
  }

  Future<void> setPlayerType(PlayerType? type) async {
    final prefs = await SharedPreferences.getInstance();
    if (type == null) {
      await prefs.remove('ssot.playerType');
    } else {
      await prefs.setString('ssot.playerType', type.name);
    }
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('ssot.userId');
  }

  Future<void> setUserId(int? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove('ssot.userId');
    } else {
      await prefs.setInt('ssot.userId', id);
    }
  }

  Future<String?> getTrialEndsAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ssot.trialEndsAt');
  }

  Future<void> setTrialEndsAt(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('ssot.trialEndsAt');
    } else {
      await prefs.setString('ssot.trialEndsAt', value);
    }
  }

  Future<void> clearSignedIn() async {
    await _secureStorage.delete(key: 'ssot.token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ssot.userName');
    await prefs.remove('ssot.userAvatarUrl');
    await prefs.remove('ssot.userRole');
    await prefs.remove('ssot.orgRole');
    await prefs.remove('ssot.playerType');
    await prefs.remove('ssot.linkedPlayerId');
    await prefs.remove('ssot.clubUserId');
    await prefs.remove('ssot.userId');
    await prefs.remove('ssot.trialEndsAt');
    ApiService.setToken(null);
  }
}
