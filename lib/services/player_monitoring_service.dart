import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import '../app_config.dart';
import '../models/monitoring_models.dart';
import '../utils/app_logger.dart';
import 'survey_reminder_service.dart';

const _baseUrl = kApiBase;

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
      AppLogger.w('PlayerMonitoringService',
          'Non-map response — status ${res.statusCode} url=${res.request?.url}');
      return {'error': 'Unexpected response'};
    } catch (e) {
      final url     = res.request?.url.toString() ?? '?';
      final ct      = res.headers['content-type'] ?? 'unknown';
      final preview = res.body.length > 500 ? res.body.substring(0, 500) : res.body;
      AppLogger.e('PlayerMonitoringService',
          '[JSON PARSE FAIL]\n  url: $url\n  status: ${res.statusCode}\n'
          '  content-type: $ct\n  body[0:500]: $preview', e);
      return {'error': 'Server error'};
    }
  }

  // ─ Body Metrics ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> saveBodyMetrics({
    required double weightKg,
    required double heightCm,
    required double bodyFatPercent,
    double? waistCm,
    String? measurementMethod,
    String? deviceName,
    String? measuredBy,
    String? specialistNotes,
    String? playerId, // coach recording on behalf of a roster player
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/player/body-metrics/save.php'),
        headers: _headers,
        body: jsonEncode({
          'weight_kg': weightKg,
          'height_cm': heightCm,
          'body_fat_percent': bodyFatPercent,
          if (waistCm != null) 'waist_cm': waistCm,
          if (measurementMethod != null) 'measurement_method': measurementMethod,
          if (deviceName != null) 'device_name': deviceName,
          if (measuredBy != null) 'measured_by': measuredBy,
          if (specialistNotes != null) 'specialist_notes': specialistNotes,
          if (playerId != null) 'player_id': playerId,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.saveBodyMetrics', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> getLatestBodyMetrics() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/body-metrics/latest.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.getLatestBodyMetrics', 'Request failed', e);
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
    int? mood,
    bool painToday = false,
    String? painLocation,
    String? notes,
    String? sessionId,
    String? playerId, // coach recording on behalf of a roster player
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
          if (mood != null) 'mood': mood,
          'pain_today': painToday,
          if (painToday && painLocation != null) 'pain_location': painLocation,
          if (notes != null) 'notes': notes,
          if (sessionId != null) 'training_session_id': sessionId,
          if (playerId != null) 'player_id': playerId,
        }),
      ).timeout(const Duration(seconds: 10));
      final result = _decodeResponse(res);
      if (result['error'] == null) {
        if (sessionId != null) {
          await SurveyReminderService.cancelPreForSession(sessionId);
        } else {
          await SurveyReminderService.cancelTodayMatchReminders(pre: true);
        }
      }
      return result;
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.saveHooper', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
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
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.getHooperHistory', 'Request failed', e);
      return [];
    }
  }

  // ─ RPE ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> saveRpe({
    required num rpeScore,
    int? durationMinutes,
    String? sessionId,
    int? actualDurationMinutes,
    String? playerId, // coach recording on behalf of a roster player
    String? reason,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/player/rpe/save.php'),
        headers: _headers,
        body: jsonEncode({
          'rpe_score': rpeScore,
          if (durationMinutes != null) 'duration_minutes': durationMinutes,
          if (sessionId != null) 'training_session_id': sessionId,
          if (actualDurationMinutes != null)
            'actual_duration_minutes': actualDurationMinutes,
          if (playerId != null) 'player_id': playerId,
          if (reason != null) 'reason': reason,
        }),
      ).timeout(const Duration(seconds: 10));
      final result = _decodeResponse(res);
      if (result['error'] == null) {
        if (sessionId != null) {
          await SurveyReminderService.cancelPostForSession(sessionId);
        } else {
          await SurveyReminderService.cancelTodayMatchReminders(pre: false);
        }
      }
      return result;
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.saveRpe', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
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
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.getRpeHistory', 'Request failed', e);
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
      AppLogger.w('PlayerMonitoringService.getDashboard', 'Missing readiness_score in response');
      return null;
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.getDashboard', 'Request failed', e);
      return null;
    }
  }

  // ─ Team Wellness (Coach) ──────────────────────────────────────────────

  static Future<TeamWellness?> getTeamWellness({
    DateTime? from,
    DateTime? to,
    bool throwOnError = false,
  }) async {
    try {
      final qp = <String, String>{};
      if (from != null) qp['from'] = from.toIso8601String().split('T').first;
      if (to != null) qp['to'] = to.toIso8601String().split('T').first;
      final uri = Uri.parse('$_baseUrl/club/team-wellness.php').replace(
        queryParameters: qp.isEmpty ? null : qp,
      );
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      if (data.containsKey('team_readiness_score')) {
        return TeamWellness.fromJson(data);
      }
      AppLogger.w('PlayerMonitoringService.getTeamWellness', 'Missing team_readiness_score in response');
      if (throwOnError) {
        throw StateError('Team wellness response is unavailable');
      }
      return null;
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.getTeamWellness', 'Request failed', e);
      if (throwOnError) rethrow;
      return null;
    }
  }

  // ─ Club: per-player wellness list (coach view) ──────────────────────

  static Future<List<PlayerWellnessEntry>> getPlayerWellnessList({
    bool throwOnError = false,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/wellness_summary.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      final list = data['players'];
      if (list is List) {
        return list
            .map((e) => PlayerWellnessEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (throwOnError) {
        throw StateError('Player wellness response is unavailable');
      }
      return [];
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.getPlayerWellnessList', 'Request failed', e);
      if (throwOnError) rethrow;
      return [];
    }
  }

  // ─ Club: per-player wellness snapshot (coach view) ──────────────────

  static Future<Map<String, dynamic>?> getPlayerWellnessSnapshot(
      String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/wellness_summary.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      final list = data['players'];
      if (list is List) {
        final match = list.cast<Map<String, dynamic>>()
            .where((p) => p['id']?.toString() == playerId)
            .toList();
        if (match.isNotEmpty) return match.first;
      }
      return null;
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.getPlayerWellnessSnapshot', 'Request failed', e);
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
      AppLogger.w('PlayerMonitoringService.getTrends', 'Missing period_days in response');
      return null;
    } catch (e) {
      AppLogger.e('PlayerMonitoringService.getTrends', 'Request failed', e);
      return null;
    }
  }
}
