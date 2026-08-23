import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import '../app_config.dart';
import '../models/coach_monitoring_models.dart';
import '../utils/app_logger.dart';

const _baseUrl = kApiBase;

Map<String, dynamic> _safeJsonDecode(http.Response res, String tag) {
  try {
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    AppLogger.w(tag, 'Non-map — status=${res.statusCode} url=${res.request?.url}');
    return {};
  } catch (e) {
    final ct      = res.headers['content-type'] ?? 'unknown';
    final preview = res.body.length > 500 ? res.body.substring(0, 500) : res.body;
    AppLogger.e(tag,
        '[JSON PARSE FAIL]\n  url: ${res.request?.url}\n  status: ${res.statusCode}\n'
        '  content-type: $ct\n  body[0:500]: $preview', e);
    return {};
  }
}

class CoachMonitoringService {
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (ApiService.token != null)
          'Authorization': 'Bearer ${ApiService.token}',
      };

  static Future<TodaySession?> getTodaySession() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/session/today.php'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      final body = _safeJsonDecode(res, 'CoachMonitoringService.getTodaySession');
      if (body['success'] == true) {
        final data = body['data'];
        if (data is Map<String, dynamic>) return TodaySession.fromJson(data);
      }
    } catch (e) {
      AppLogger.e('CoachMonitoringService.getTodaySession', 'Request failed', e);
    }
    return null;
  }

  static Future<TeamReadiness?> getTeamReadiness() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/team/readiness.php'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      final body = _safeJsonDecode(res, 'CoachMonitoringService.getTeamReadiness');
      if (body['success'] == true && body['data'] is Map<String, dynamic>) {
        return TeamReadiness.fromJson(body['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      AppLogger.e('CoachMonitoringService.getTeamReadiness', 'Request failed', e);
    }
    return null;
  }

  static Future<List<CoachAlertV2>> getCoachAlerts() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/alerts/coach.php'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        return decoded
            .map((e) => CoachAlertV2.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      AppLogger.w('CoachMonitoringService.getCoachAlerts',
          'Expected list — status=${res.statusCode} url=${res.request?.url}');
    } catch (e) {
      AppLogger.e('CoachMonitoringService.getCoachAlerts', 'Request failed', e);
    }
    return [];
  }

  static Future<List<PlayerStatusV2>> getPlayersStatus() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/players/status.php'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        return (decoded
            .map((e) => PlayerStatusV2.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.loadPct.compareTo(a.loadPct)));
      }
      AppLogger.w('CoachMonitoringService.getPlayersStatus',
          'Expected list — status=${res.statusCode} url=${res.request?.url}');
    } catch (e) {
      AppLogger.e('CoachMonitoringService.getPlayersStatus', 'Request failed', e);
    }
    return [];
  }

  static Future<CoachDashboardData> getDashboard() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/coach/monitoring/dashboard.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _safeJsonDecode(res, 'CoachMonitoringService.getDashboard');
      if (body['success'] == true) return CoachDashboardData.fromJson(body);
      AppLogger.w('CoachMonitoringService.getDashboard', 'success!=true — returning empty');
    } catch (e) {
      AppLogger.e('CoachMonitoringService.getDashboard', 'Request failed', e);
    }
    return CoachDashboardData.empty;
  }
}
