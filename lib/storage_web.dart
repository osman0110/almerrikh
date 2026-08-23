import 'dart:html' as html;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'app_state.dart';

// See storage_stub.dart for why the token specifically uses secure storage
// (IndexedDB + WebCrypto on web) instead of plain localStorage.
const _secureStorage = FlutterSecureStorage();

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
    var token = await _secureStorage.read(key: 'ssot.token');
    if (token == null || token.isEmpty) {
      // One-time migration for sessions started before this app version
      // moved the token out of plaintext localStorage.
      final legacyToken = html.window.localStorage['ssot.token'];
      if (legacyToken != null && legacyToken.isNotEmpty) {
        await _secureStorage.write(key: 'ssot.token', value: legacyToken);
        html.window.localStorage.remove('ssot.token');
        token = legacyToken;
      }
    }
    if (token == null || token.isEmpty) return false;
    ApiService.setToken(token);
    return true;
  }

  Future<void> setSignedIn({required String token, required String userName}) async {
    await _secureStorage.write(key: 'ssot.token', value: token);
    html.window.localStorage['ssot.userName'] = userName;
    ApiService.setToken(token);
  }

  Future<String?> getUserName() async {
    return html.window.localStorage['ssot.userName'];
  }

  Future<void> setUserName(String value) async {
    html.window.localStorage['ssot.userName'] = value;
  }

  Future<String?> getUserAvatarUrl() async {
    return html.window.localStorage['ssot.userAvatarUrl'];
  }

  Future<void> setUserAvatarUrl(String? value) async {
    if (value == null || value.isEmpty) {
      html.window.localStorage.remove('ssot.userAvatarUrl');
    } else {
      html.window.localStorage['ssot.userAvatarUrl'] = value;
    }
  }

  Future<UserRole> getUserRole() async {
    final role = html.window.localStorage['ssot.userRole'] ?? 'club';
    return UserRole.values.firstWhere((r) => r.name == role, orElse: () => UserRole.club);
  }

  Future<void> setUserRole(UserRole role) async {
    html.window.localStorage['ssot.userRole'] = role.name;
  }

  Future<OrgRole> getOrgRole() async {
    // Must go through orgRoleFromString — a raw name-match here misses
    // snake_case server names cached from login (tactical_coach,
    // performance_manager, the legacy massage_specialist alias), silently
    // falling back to OrgRole.staff and landing those accounts on the
    // unrestricted ClubDashboardPage on every app reopen.
    return orgRoleFromString(html.window.localStorage['ssot.orgRole']);
  }

  Future<void> setOrgRole(OrgRole role) async {
    html.window.localStorage['ssot.orgRole'] = role.name;
  }

  Future<String?> getLinkedPlayerId() async {
    return html.window.localStorage['ssot.linkedPlayerId'];
  }

  Future<void> setLinkedPlayerId(String? id) async {
    if (id == null || id.isEmpty) {
      html.window.localStorage.remove('ssot.linkedPlayerId');
    } else {
      html.window.localStorage['ssot.linkedPlayerId'] = id;
    }
  }

  Future<int?> getClubUserId() async {
    final v = html.window.localStorage['ssot.clubUserId'];
    return v == null ? null : int.tryParse(v);
  }

  Future<void> setClubUserId(int? id) async {
    if (id == null) {
      html.window.localStorage.remove('ssot.clubUserId');
    } else {
      html.window.localStorage['ssot.clubUserId'] = id.toString();
    }
  }

  Future<PlayerType?> getPlayerType() async {
    final v = html.window.localStorage['ssot.playerType'];
    if (v == null) return null;
    return v == 'independent' ? PlayerType.independent : PlayerType.club;
  }

  Future<void> setPlayerType(PlayerType? type) async {
    if (type == null) {
      html.window.localStorage.remove('ssot.playerType');
    } else {
      html.window.localStorage['ssot.playerType'] = type.name;
    }
  }

  Future<int?> getUserId() async {
    final v = html.window.localStorage['ssot.userId'];
    return v == null ? null : int.tryParse(v);
  }

  Future<void> setUserId(int? id) async {
    if (id == null) {
      html.window.localStorage.remove('ssot.userId');
    } else {
      html.window.localStorage['ssot.userId'] = id.toString();
    }
  }

  Future<String?> getTrialEndsAt() async {
    return html.window.localStorage['ssot.trialEndsAt'];
  }

  Future<void> setTrialEndsAt(String? value) async {
    if (value == null) {
      html.window.localStorage.remove('ssot.trialEndsAt');
    } else {
      html.window.localStorage['ssot.trialEndsAt'] = value;
    }
  }

  Future<void> clearSignedIn() async {
    await _secureStorage.delete(key: 'ssot.token');
    html.window.localStorage.remove('ssot.userName');
    html.window.localStorage.remove('ssot.userAvatarUrl');
    html.window.localStorage.remove('ssot.userRole');
    html.window.localStorage.remove('ssot.orgRole');
    html.window.localStorage.remove('ssot.playerType');
    html.window.localStorage.remove('ssot.linkedPlayerId');
    html.window.localStorage.remove('ssot.clubUserId');
    html.window.localStorage.remove('ssot.userId');
    html.window.localStorage.remove('ssot.trialEndsAt');
    ApiService.setToken(null);
  }
}
