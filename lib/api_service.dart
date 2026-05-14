import 'dart:convert';
import 'package:http/http.dart' as http;

// nextkick.me PHP/MySQL API — shared between website and app.
// Accounts created on the website work in the app and vice versa.
const _baseUrl = 'https://nextkick.me/api';

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

  // ── Assessment sync ───────────────────────────────────────────────────────

  /// Sends one assessment result to nextkick.me.
  /// Fire-and-forget: caller should not await if result is non-critical.
  static Future<Map<String, dynamic>> saveAssessment({
    required String id,
    required String playerId,
    required String playerName,
    required String type,
    required int overallScore,
    required int movementQualityScore,
    required int stabilityScore,
    required int symmetryScore,
    required int controlScore,
    required int qualityScore,
    required List<String> issues,
    required List<String> correctionTips,
    required List<String> recommendedDrills,
    required Map<String, double> angleMetrics,
    String? coachNotes,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/assessments.php'),
            headers: _headers,
            body: jsonEncode({
              'id': id,
              'player_id': playerId,
              'player_name': playerName,
              'type': type,
              'overall_score': overallScore,
              'movement_quality_score': movementQualityScore,
              'stability_score': stabilityScore,
              'symmetry_score': symmetryScore,
              'control_score': controlScore,
              'quality_score': qualityScore,
              'issues': issues,
              'correction_tips': correctionTips,
              'recommended_drills': recommendedDrills,
              'angle_metrics': angleMetrics,
              if (coachNotes != null) 'coach_notes': coachNotes,
            }),
          )
          .timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (_) {
      return {'error': 'sync_failed'};
    }
  }

  /// Returns all assessments for the current user, optionally filtered by player.
  static Future<List<Map<String, dynamic>>> getAssessments({
    String? playerId,
    int limit = 50,
  }) async {
    try {
      final params = {
        'limit': '$limit',
        if (playerId != null) 'player_id': playerId,
      };
      final uri = Uri.parse('$_baseUrl/assessments.php')
          .replace(queryParameters: params);
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      final decoded = _decodeResponse(res);
      final list = decoded['assessments'];
      if (list is List) {
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
