import 'dart:convert';
import 'package:http/http.dart' as http;

// Base URL of the PHP API on your WAMP server.
// When running Flutter in dev mode (different port) this points to Apache.
// After building to WAMP www, both are on the same origin.
const _baseUrl = 'http://localhost/smart-sport-scribe-main/api';

class ApiService {
  static String? _token;

  static void setToken(String? token) => _token = token;
  static String? get token => _token;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Map<String, dynamic> _decodeResponse(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'error': 'Unexpected server response.'};
    } catch (_) {
      return {
        'error': res.statusCode >= 500
            ? 'Server/database error. Check WAMP MySQL and the PHP API.'
            : 'Unexpected server response.',
      };
    }
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth.php?action=register'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
      }),
    );
    return _decodeResponse(res);
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth.php?action=login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _decodeResponse(res);
  }

  static Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/auth.php?action=logout'),
        headers: _headers,
      );
    } catch (_) {
      // Best-effort: clear local state regardless.
    }
    _token = null;
  }

  static Future<Map<String, dynamic>> saveProfile({
    required String playerName,
    required int age,
    required String position,
    required String foot,
    required List<String> weaknesses,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/profile.php'),
      headers: _headers,
      body: jsonEncode({
        'player_name': playerName,
        'age': age,
        'position': position,
        'foot': foot,
        'weaknesses': weaknesses,
      }),
    );
    return _decodeResponse(res);
  }

  static Future<Map<String, dynamic>> getProfile() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/profile.php'),
      headers: _headers,
    );
    return _decodeResponse(res);
  }
}
