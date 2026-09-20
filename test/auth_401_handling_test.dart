import 'package:flutter_test/flutter_test.dart';
import 'package:al_merrikh/api_service.dart';

// A wrong password must not be treated as an expired session: the app used to
// clear the session and jump back to onboarding whenever any request answered
// 401, including the sign-in request itself.
void main() {
  test('sign-in and sign-up 401s are not session expiry', () {
    expect(ApiService.isAuthEntryPoint(Uri.parse('https://x/api/auth.php?action=login')), isTrue);
    expect(ApiService.isAuthEntryPoint(Uri.parse('https://x/api/auth.php?action=register')), isTrue);
  });

  test('every other 401 still means the session expired', () {
    for (final url in [
      'https://x/api/sessions.php',
      'https://x/api/players.php?id=1',
      'https://x/api/auth.php?action=me',
      'https://x/api/auth.php?action=delete_account',
      'https://x/api/club/staff.php',
    ]) {
      expect(ApiService.isAuthEntryPoint(Uri.parse(url)), isFalse, reason: url);
    }
  });
}
