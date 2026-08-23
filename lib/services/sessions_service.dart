import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import '../app_config.dart';
import '../models/sessions_models.dart';
import '../utils/app_logger.dart';

// ── SessionsService ───────────────────────────────────────────────────────────
// Calls nextkick.me/api/sessions.php. Falls back to mock data when offline.

class SessionsService {
  static const _baseUrl = kApiBase;
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (ApiService.token != null) 'Authorization': 'Bearer ${ApiService.token}',
      };

  static Future<List<SessionModel>> getSessions({
    String? date,
    String? status,
    String? type,
    String? scope,
    bool? aiEnabled,
    String? search,
  }) async {
    if (ApiService.token != null) {
      try {
        final params = <String, String>{};
        if (date != null && date.isNotEmpty) params['date'] = date;
        if (status != null && status.isNotEmpty) params['status'] = status;

        final uri = Uri.parse('$_baseUrl/sessions.php').replace(queryParameters: params);
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = body['sessions'] as List<dynamic>? ?? [];
        var result = list.map((e) => SessionModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();

        // Client-side filters for type/scope/aiEnabled/search
        if (type != null && type.isNotEmpty) {
          final t = SessionType.values.firstWhere((e) => e.name == type, orElse: () => SessionType.team_training);
          result = result.where((s) => s.type == t).toList();
        }
        if (scope != null && scope.isNotEmpty) {
          final sc = SessionScope.values.firstWhere((e) => e.name == scope, orElse: () => SessionScope.team);
          result = result.where((s) => s.scope == sc).toList();
        }
        if (aiEnabled != null) result = result.where((s) => s.aiEnabled == aiEnabled).toList();
        if (search != null && search.isNotEmpty) {
          final q = search.toLowerCase();
          result = result.where((s) =>
            s.title.toLowerCase().contains(q) ||
            getSessionTypeLabel(s.type).contains(q) ||
            s.location.contains(q)).toList();
        }
        return result;
      } catch (e) {
        AppLogger.e('SessionsService.getSessions', 'Request failed', e);
      }
    }
    return [];
  }

  static Future<SessionModel?> getSessionDetails(String id) async {
    if (ApiService.token != null) {
      try {
        final uri = Uri.parse('$_baseUrl/sessions.php').replace(queryParameters: {'id': id});
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final session = body['session'];
        if (session is Map) {
          return SessionModel.fromJson(Map<String, dynamic>.from(session));
        }
      } catch (e) {
        AppLogger.e('SessionsService.getSessionDetails', 'Request failed', e);
      }
    }
    return null;
  }

  static Future<SessionsSummary> getSummary() async {
    final sessions = await getSessions();
    return SessionsSummary.fromSessions(sessions);
  }

  static Future<SessionModel> createSession(Map<String, dynamic> payload) async {
    final id = payload['id']?.toString().isNotEmpty == true
        ? payload['id'].toString()
        : 'sess-${DateTime.now().millisecondsSinceEpoch}';
    final withId = {...payload, 'id': id};

    if (ApiService.token != null) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/sessions.php'),
          headers: _headers,
          body: jsonEncode(withId),
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        AppLogger.e('SessionsService.createSession', 'Request failed', e);
      }
    }
    return SessionModel.fromJson(withId);
  }

  static Future<void> updateSession(String id, Map<String, dynamic> payload) async {
    if (ApiService.token != null) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/sessions.php'),
          headers: _headers,
          body: jsonEncode({...payload, 'id': id}),
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        AppLogger.e('SessionsService.updateSession', 'Request failed', e);
      }
    }
  }

  static Future<void> startSession(String id) =>
      updateSession(id, {'status': 'active'});

  static Future<void> completeSession(String id) =>
      updateSession(id, {'status': 'completed'});

  static Future<List<SessionParticipant>> getParticipants(String sessionId) async {
    if (ApiService.token != null) {
      try {
        final uri = Uri.parse('$_baseUrl/sessions.php')
            .replace(queryParameters: {'id': sessionId, 'roster': '1'});
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = body['participants'] as List<dynamic>? ?? [];
        final byId = <String, SessionParticipant>{};
        for (final item in list) {
          final participant = SessionParticipant.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          if (participant.id.isNotEmpty) {
            byId[participant.id] = participant;
          }
        }
        final participants = byId.values.toList()
          ..sort((a, b) {
            final aHasNumber = a.number > 0;
            final bHasNumber = b.number > 0;
            if (aHasNumber != bHasNumber) return aHasNumber ? -1 : 1;
            final byNumber = a.number.compareTo(b.number);
            return byNumber != 0 ? byNumber : a.name.compareTo(b.name);
          });
        return participants;
      } catch (e) {
        AppLogger.e('SessionsService.getParticipants', 'Request failed', e);
      }
    }
    return [];
  }

  static Future<List<SessionExercise>> getExercises(String sessionId) async {
    return [];
  }

  /// Saves attendance for a session.
  /// [attendance] maps player_id → 'present' | 'absent' | 'late'
  static Future<bool> saveAttendance(String id, Map<String, String> attendance) async {
    if (ApiService.token == null) return false;
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/sessions.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'attendance',
          'session_id': id,
          'attendance': attendance,
        }),
      ).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return res.statusCode >= 200 &&
          res.statusCode < 300 &&
          body['success'] == true;
    } catch (e) {
      AppLogger.e('SessionsService.saveAttendance', 'Request failed', e);
      return false;
    }
  }

  /// Adds an exercise to a session.
  /// [payload] must include 'exercise_name' at minimum.
  static Future<void> addExercise(String id, Map<String, dynamic> payload) async {
    if (ApiService.token == null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/sessions.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'add_exercise',
          'session_id': id,
          ...payload,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.e('SessionsService.addExercise', 'Request failed', e);
    }
  }

  /// AI session analysis — not yet available.
  /// Callers should show their own "coming soon" message.
  static Future<void> startAiAnalysis(String id, String analysisType) async {
    AppLogger.i('SessionsService.startAiAnalysis', 'Feature not yet available');
  }
}
