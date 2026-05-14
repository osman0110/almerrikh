import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import '../models/monitoring_models.dart';

const _baseUrl = 'https://nextkick.me/api';

class PlayerMonitoringService {
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (ApiService.token != null) 'Authorization': 'Bearer ${ApiService.token}',
  };

  static Map<String, dynamic> _decodeResponse(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'error': 'Unexpected response'};
    } catch (_) {
      return {'error': 'Server error'};
    }
  }

  // ─ Body Metrics ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> saveBodyMetrics({
    required double weightKg,
    required double heightCm,
    required double bodyFatPercent,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/player/body-metrics/save.php'),
        headers: _headers,
        body: jsonEncode({
          'weight_kg': weightKg,
          'height_cm': heightCm,
          'body_fat_percent': bodyFatPercent,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (_) {
      return {'error': 'Request failed'};
    }
  }

  static Future<Map<String, dynamic>> getLatestBodyMetrics() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/body-metrics/latest.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (_) {
      return {'metric': null, 'history': []};
    }
  }

  // ─ Hooper Index ──────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> saveHooper({
    required int sleepQuality,
    required int fatigue,
    required int stress,
    required int muscleSoreness,
    double? sleepHours,
    String? notes,
    String? sessionId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/player/hooper/save.php'),
        headers: _headers,
        body: jsonEncode({
          'sleep_quality': sleepQuality,
          'fatigue': fatigue,
          'stress': stress,
          'muscle_soreness': muscleSoreness,
          if (sleepHours != null) 'sleep_hours': sleepHours,
          if (notes != null) 'notes': notes,
          if (sessionId != null) 'training_session_id': sessionId,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (_) {
      return {'error': 'Request failed'};
    }
  }

  static Future<List<HooperEntry>> getHooperHistory({int limit = 14}) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/hooper/history.php?limit=$limit'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      final list = data['history'];
      if (list is List) {
        return list.map((e) => HooperEntry.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ─ RPE ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> saveRpe({
    required int rpeScore,
    required int durationMinutes,
    String? sessionType,
    String? notes,
    String? sessionId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/player/rpe/save.php'),
        headers: _headers,
        body: jsonEncode({
          'rpe_score': rpeScore,
          'duration_minutes': durationMinutes,
          if (sessionType != null) 'session_type': sessionType,
          if (notes != null) 'notes': notes,
          if (sessionId != null) 'training_session_id': sessionId,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (_) {
      return {'error': 'Request failed'};
    }
  }

  static Future<List<RpeEntry>> getRpeHistory({int limit = 14}) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/rpe/history.php?limit=$limit'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      final list = data['history'];
      if (list is List) {
        return list.map((e) => RpeEntry.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ─ Monitoring Dashboard ──────────────────────────────────────────────

  static Future<MonitoringDashboard?> getDashboard() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/monitoring/dashboard.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      if (data.containsKey('readiness_score')) {
        return MonitoringDashboard.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─ Team Wellness (Coach) ──────────────────────────────────────────────

  static Future<TeamWellness?> getTeamWellness() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/team-wellness.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      if (data.containsKey('team_readiness_score')) {
        return TeamWellness.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─ Trend Analysis ───────────────────────────────────────────────────

  static Future<PlayerTrends?> getTrends({int periodDays = 7}) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/trends.php?period=$periodDays'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      if (data.containsKey('period_days')) {
        return PlayerTrends.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
