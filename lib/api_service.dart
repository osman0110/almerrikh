import 'dart:convert';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'models/club_models.dart';
import 'models/session_models.dart';
import 'models/training_plan_models.dart';
import 'models/ai_plan_models.dart';
import 'models/coach_ai_plan_models.dart';
import 'models/report_models.dart';
import 'models/training_load_models.dart';
import 'utils/app_logger.dart';

const _baseUrl = kApiBase;

class ApiService {
  static String? _token;

  static void setToken(String? token) => _token = token;
  static String? get token => _token;

  /// Set once at app startup (see main.dart). Invoked the first time any
  /// request comes back 401 — clears the stored session and routes to
  /// login, so a revoked/expired token forces re-authentication instead of
  /// every screen failing (or silently swallowing the error) independently.
  static void Function()? onUnauthorized;
  static bool _handlingUnauthorized = false;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static void _handleUnauthorized() {
    if (_handlingUnauthorized) return; // one trigger per burst of 401s
    _handlingUnauthorized = true;
    _token = null;
    onUnauthorized?.call();
    Future.delayed(const Duration(seconds: 2), () => _handlingUnauthorized = false);
  }

  static Map<String, dynamic> _decodeResponse(http.Response res) {
    if (res.statusCode == 401) _handleUnauthorized();
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      AppLogger.w('ApiService',
          'Non-map response — status ${res.statusCode} '
          'url=${res.request?.url}');
      return {'error': 'Unexpected server response.'};
    } catch (e) {
      final url = res.request?.url.toString() ?? '?';
      final ct  = res.headers['content-type'] ?? 'unknown';
      final preview = res.body.length > 500
          ? res.body.substring(0, 500)
          : res.body;
      AppLogger.e(
        'ApiService',
        '[JSON PARSE FAIL]\n'
        '  url         : $url\n'
        '  status      : ${res.statusCode}\n'
        '  content-type: $ct\n'
        '  body[0:500] : $preview',
        e,
      );
      return {
        'error': res.statusCode >= 500
            ? 'Server error. Please try again later.'
            : 'Unexpected server response.',
      };
    }
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String role = 'club',
    String? playerType,    // 'independent' | 'club'
    String? inviteCode,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth.php?action=register'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
        if (playerType != null)  'player_type':  playerType,
        if (inviteCode != null)  'invite_code':  inviteCode,
      }),
    );
    return _decodeResponse(res);
  }

  static Future<Map<String, dynamic>> joinClub({
    required String inviteCode,
    bool shareHistory = true,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/player/join-club.php'),
        headers: _headers,
        body: jsonEncode({
          'invite_code':    inviteCode,
          'share_history':  shareHistory,
        }),
      ).timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.joinClub', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> getMyPlayerProfile() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/my-profile.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getMyPlayerProfile', 'Request failed', e);
      return {};
    }
  }

  /// Unified access codes remain reusable until they are deactivated or deleted.
  static Future<List<Map<String, dynamic>>?> getClubAccessCodes() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/staff.php?codes=1'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (body['codes'] is! List) return null;
      return (body['codes'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.e('ApiService.getClubAccessCodes', 'Request failed', e);
      return null;
    }
  }

  static Future<Map<String, dynamic>> createAccessCode({
    required String accountType,
    String? note,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/staff.php'),
        headers: _headers,
        body: jsonEncode({
          'account_type': accountType,
          if (note != null) 'note': note,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.createAccessCode', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> toggleAccessCode({
    required String code,
    required bool isActive,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/staff.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'toggle_code',
          'code': code,
          'is_active': isActive,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.toggleAccessCode', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> deleteAccessCode(String code) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/club/staff.php?code=$code'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.deleteAccessCode', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<Map<String, dynamic>>?> getClubStaff() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/staff.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (body['staff'] is! List) return null;
      return (body['staff'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.e('ApiService.getClubStaff', 'Request failed', e);
      return null;
    }
  }

  static Future<Map<String, dynamic>> removeStaffMember(String id) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/club/staff.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.removeStaffMember', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> assignStaffTeam({
    required String staffId,
    required String teamId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/staff.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'assign_team',
          'staff_id': staffId,
          'team_id': teamId,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.assignStaffTeam', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<Map<String, dynamic>>> getInjuryCases(String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/injuries.php?player_id=$playerId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['cases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getInjuryCases', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> getInjuryCaseDetail(String id) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/injuries.php?id=$id&updates=1'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getInjuryCaseDetail', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> createInjuryCase({
    required String playerId,
    required String injuryDate,
    String? bodyLocation,
    String? injuryType,
    String severity = 'moderate',
    String? diagnosis,
    String? examNotes,
    String? expectedReturnDate,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/injuries.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'create',
          'player_id': playerId,
          'injury_date': injuryDate,
          if (bodyLocation != null) 'body_location': bodyLocation,
          if (injuryType != null) 'injury_type': injuryType,
          'severity': severity,
          if (diagnosis != null) 'diagnosis': diagnosis,
          if (examNotes != null) 'exam_notes': examNotes,
          if (expectedReturnDate != null) 'expected_return_date': expectedReturnDate,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.createInjuryCase', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> addInjuryUpdate({
    required String id,
    String? note,
    String? rtpStage,
    String? caseStatus,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/injuries.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'update',
          'id': id,
          if (note != null) 'note': note,
          if (rtpStage != null) 'rtp_stage': rtpStage,
          if (caseStatus != null) 'case_status': caseStatus,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.addInjuryUpdate', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<Map<String, dynamic>>> getPlayerStatusHistory(String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/players.php?id=$playerId&status_history=1'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getPlayerStatusHistory', 'Request failed', e);
      return [];
    }
  }

  // ── Cross-department tasks ────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getTasks({
    String filter = 'mine',
    String? playerId,
  }) async {
    try {
      final qp = <String, String>{'filter': filter, if (playerId != null) 'player_id': playerId};
      final uri = Uri.parse('$_baseUrl/club/tasks.php').replace(queryParameters: qp);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['tasks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getTasks', 'Request failed', e);
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getTaskAssigneeDirectory() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/tasks.php?directory=1'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['staff'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getTaskAssigneeDirectory', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> getTaskDetail(String id) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/tasks.php?id=$id&comments=1'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getTaskDetail', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> createTask({
    required String title,
    String? description,
    int? assignedToUserId,
    String? linkedPlayerId,
    String? linkedEntityType,
    String? linkedEntityId,
    String priority = 'normal',
    String? dueDate,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/tasks.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'create',
          'title': title,
          if (description != null) 'description': description,
          if (assignedToUserId != null) 'assigned_to_user_id': assignedToUserId,
          if (linkedPlayerId != null) 'linked_player_id': linkedPlayerId,
          if (linkedEntityType != null) 'linked_entity_type': linkedEntityType,
          if (linkedEntityId != null) 'linked_entity_id': linkedEntityId,
          'priority': priority,
          if (dueDate != null) 'due_date': dueDate,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.createTask', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> updateTaskStatus({
    required String id,
    required String status,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/tasks.php'),
        headers: _headers,
        body: jsonEncode({'action': 'update_status', 'id': id, 'status': status}),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.updateTaskStatus', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> addTaskComment({
    required String id,
    required String comment,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/tasks.php'),
        headers: _headers,
        body: jsonEncode({'action': 'comment', 'id': id, 'comment': comment}),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.addTaskComment', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/notifications.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['notifications'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getNotifications', 'Request failed', e);
      return [];
    }
  }

  static Future<int> getUnreadNotificationCount() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/notifications.php?count=1'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['unread_count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      AppLogger.e('ApiService.getUnreadNotificationCount', 'Request failed', e);
      return 0;
    }
  }

  static Future<void> markNotificationRead(String id) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/notifications.php'),
        headers: _headers,
        body: jsonEncode({'action': 'mark_read', 'id': id}),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.e('ApiService.markNotificationRead', 'Request failed', e);
    }
  }

  static Future<void> markAllNotificationsRead() async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/notifications.php'),
        headers: _headers,
        body: jsonEncode({'action': 'mark_all_read'}),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.e('ApiService.markAllNotificationsRead', 'Request failed', e);
    }
  }

  // ── League Standings ─────────────────────────────────────────────────────

  static Future<List<StandingCompetition>> getStandingsCompetitions() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/standings.php?section=competitions'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      final list = body['competitions'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => StandingCompetition.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      AppLogger.e('ApiService.getStandingsCompetitions', 'Request failed', e);
      return [];
    }
  }

  static Future<List<StandingRow>> getStandingsTable(int competitionId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/standings.php?section=table&competition_id=$competitionId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      final list = body['standings'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => StandingRow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      AppLogger.e('ApiService.getStandingsTable', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> saveStandingsTable({
    required int competitionId,
    required List<StandingRow> rows,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/standings.php'),
        headers: _headers,
        body: jsonEncode({
          'competition_id': competitionId,
          'rows': rows.map((r) => r.toJson()).toList(),
        }),
      ).timeout(const Duration(seconds: 15));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.saveStandingsTable', 'Request failed', e);
      return {'success': false, 'message': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> sendAlert({
    required String title,
    required String message,
    required String target, // 'individual' | 'club'
    List<String> playerIds = const [],
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/alerts/send.php'),
        headers: _headers,
        body: jsonEncode({
          'title': title,
          'message': message,
          'target': target,
          if (target == 'individual') 'player_ids': playerIds,
        }),
      ).timeout(const Duration(seconds: 15));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.sendAlert', 'Request failed', e);
      return {'success': false, 'message': AppLogger.userMessage(e)};
    }
  }

  static Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/device-tokens.php'),
        headers: _headers,
        body: jsonEncode({'action': 'register', 'token': token, 'platform': platform}),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.e('ApiService.registerDeviceToken', 'Request failed', e);
    }
  }

  static Future<void> unregisterDeviceToken(String token) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/device-tokens.php'),
        headers: _headers,
        body: jsonEncode({'action': 'unregister', 'token': token}),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.e('ApiService.unregisterDeviceToken', 'Request failed', e);
    }
  }

  // ── Hydration ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getMyHydrationLogs({int days = 14}) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/hydration.php?days=$days'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['logs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getMyHydrationLogs', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> logMyHydration({required int amountMl, String? logDate}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/player/hydration.php'),
        headers: _headers,
        body: jsonEncode({
          'amount_ml': amountMl,
          if (logDate != null) 'log_date': logDate,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.logMyHydration', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<Map<String, dynamic>>> getPlayerHydrationLogs(String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/nutrition.php?player_id=$playerId&section=hydration'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['logs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getPlayerHydrationLogs', 'Request failed', e);
      rethrow;
    }
  }

  // ── Individual program weekly reviews ─────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getPlayerIndividualPlans(String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/individual_program_reviews.php?player_id=$playerId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      AppLogger.i(
        'ApiService.getPlayerIndividualPlans',
        'HTTP ${res.statusCode}; playerId=$playerId; plans=${(body['plans'] as List?)?.length ?? 0}; '
        'error=${body['error'] ?? body['message'] ?? '-'}',
      );
      return (body['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getPlayerIndividualPlans', 'Request failed', e);
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getProgramReviews(String planId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/individual_program_reviews.php?plan_id=$planId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['reviews'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getProgramReviews', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> createProgramReview({
    required String planId,
    required int weekNumber,
    required int completionPercent,
    String? coachNotes,
    String? playerFeedback,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/individual_program_reviews.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'create_review',
          'plan_id': planId,
          'week_number': weekNumber,
          'completion_percent': completionPercent,
          if (coachNotes != null) 'coach_notes': coachNotes,
          if (playerFeedback != null) 'player_feedback': playerFeedback,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.createProgramReview', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  // ── Return-to-Play phases ─────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getRehabPhases(String injuryCaseId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/rehab_phases.php?injury_case_id=$injuryCaseId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['phases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getRehabPhases', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> upsertRehabPhase({
    required String injuryCaseId,
    required int phaseNumber,
    String? goals,
    String? exercises,
    int completionPercent = 0,
    int? painScore,
    String? playerNotes,
    String? specialistNotes,
    String? expectedEndDate,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/rehab_phases.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'upsert',
          'injury_case_id': injuryCaseId,
          'phase_number': phaseNumber,
          if (goals != null) 'goals': goals,
          if (exercises != null) 'exercises': exercises,
          'completion_percent': completionPercent,
          if (painScore != null) 'pain_score': painScore,
          if (playerNotes != null) 'player_notes': playerNotes,
          if (specialistNotes != null) 'specialist_notes': specialistNotes,
          if (expectedEndDate != null) 'expected_end_date': expectedEndDate,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.upsertRehabPhase', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> advanceRehabPhase({
    required String injuryCaseId,
    required String id,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/rehab_phases.php'),
        headers: _headers,
        body: jsonEncode({'action': 'advance', 'injury_case_id': injuryCaseId, 'id': id}),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.advanceRehabPhase', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> completeRehabPhase({
    required String injuryCaseId,
    required String id,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/rehab_phases.php'),
        headers: _headers,
        body: jsonEncode({'action': 'complete', 'injury_case_id': injuryCaseId, 'id': id}),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.completeRehabPhase', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  // ── Medical attachments ───────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getMedicalAttachments(String injuryCaseId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/medical_attachments.php?injury_case_id=$injuryCaseId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['attachments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getMedicalAttachments', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> addMedicalAttachment({
    required String injuryCaseId,
    required String fileUrl,
    String fileType = 'other',
    String? description,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/medical_attachments.php'),
        headers: _headers,
        body: jsonEncode({
          'injury_case_id': injuryCaseId,
          'file_url': fileUrl,
          'file_type': fileType,
          if (description != null) 'description': description,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.addMedicalAttachment', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<void> deleteMedicalAttachment(String id) async {
    try {
      await http.delete(
        Uri.parse('$_baseUrl/club/medical_attachments.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.e('ApiService.deleteMedicalAttachment', 'Request failed', e);
    }
  }

  // ── Physiotherapy & Massage Scheduling ────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getPhysioSessions(String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/physio_sessions.php?player_id=$playerId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getPhysioSessions', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> getPhysioSessionDetail(String id) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/physio_sessions.php?id=$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getPhysioSessionDetail', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<Map<String, dynamic>>> getPhysioScheduleForDate(String date) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/physio_sessions.php?date=$date'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getPhysioScheduleForDate', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> createPhysioSession({
    required String playerId,
    required String scheduledAt,
    int durationMinutes = 30,
    int? therapistUserId,
    String? room,
    String? bodyArea,
    String sessionReason = 'recovery',
    String? treatmentType,
    String intensity = 'moderate',
    String? contraindications,
    String? sessionName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/physio_sessions.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'create',
          'player_id': playerId,
          'scheduled_at': scheduledAt,
          'duration_minutes': durationMinutes,
          if (therapistUserId != null) 'therapist_user_id': therapistUserId,
          if (room != null) 'room': room,
          if (bodyArea != null) 'body_area': bodyArea,
          'session_reason': sessionReason,
          if (treatmentType != null) 'treatment_type': treatmentType,
          'intensity': intensity,
          if (contraindications != null) 'contraindications': contraindications,
          if (sessionName != null) 'session_name': sessionName,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.createPhysioSession', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> createPhysioSessionsBulk({
    required String audience,
    required String scheduledAt,
    required int durationMinutes,
    int? therapistUserId,
    String? playerId,
    List<String> excludedPlayerIds = const [],
    String? room,
    String? bodyArea,
    String sessionReason = 'recovery',
    String? treatmentType,
    String intensity = 'moderate',
    String? contraindications,
    String? sessionName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/physio_sessions.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'create_bulk',
          'audience': audience,
          'scheduled_at': scheduledAt,
          'duration_minutes': durationMinutes,
          if (therapistUserId != null) 'therapist_user_id': therapistUserId,
          if (playerId != null) 'player_id': playerId,
          'excluded_player_ids': excludedPlayerIds,
          if (room != null) 'room': room,
          if (bodyArea != null) 'body_area': bodyArea,
          'session_reason': sessionReason,
          if (treatmentType != null) 'treatment_type': treatmentType,
          'intensity': intensity,
          if (contraindications != null) 'contraindications': contraindications,
          if (sessionName != null) 'session_name': sessionName,
        }),
      ).timeout(const Duration(seconds: 15));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.createPhysioSessionsBulk', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  /// Recent club-wide physio sessions (no date filter) — used to merge
  /// physio group sessions into the shared club Sessions list for the
  /// physical coach / admin, alongside training sessions.
  static Future<List<Map<String, dynamic>>> getAllPhysioSessions({int limit = 100}) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/physio_sessions.php?limit=$limit'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getAllPhysioSessions', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> updatePhysioSession({
    required String id,
    String? status,
    String? recommendation,
    String? specialistNotes,
    String? playerResponse,
    String? scheduledAt,
    int? durationMinutes,
    String? room,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/physio_sessions.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'update',
          'id': id,
          if (status != null) 'status': status,
          if (recommendation != null) 'recommendation': recommendation,
          if (specialistNotes != null) 'specialist_notes': specialistNotes,
          if (playerResponse != null) 'player_response': playerResponse,
          if (scheduledAt != null) 'scheduled_at': scheduledAt,
          if (durationMinutes != null) 'duration_minutes': durationMinutes,
          if (room != null) 'room': room,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.updatePhysioSession', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  // ── Nutrition, Hydration & Supplements ─────────────────────────────────────

  // These 4 rethrow (unlike most ApiService methods, which swallow and
  // return a safe empty default) so nutrition_screen.dart's tabs can show a
  // real error+retry state instead of it looking identical to "no data yet".
  // Only 2 other call sites exist project-wide (both audited): the plans one
  // is used inside a Future.wait batch in club_player_profile_page.dart,
  // which catches it locally to keep that unrelated batch load unaffected.
  static Future<Map<String, dynamic>?> getNutritionProfile(String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/nutrition.php?player_id=$playerId&section=profile'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return body['profile'] as Map<String, dynamic>?;
    } catch (e) {
      AppLogger.e('ApiService.getNutritionProfile', 'Request failed', e);
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getNutritionPlans(String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/nutrition.php?player_id=$playerId&section=plans'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getNutritionPlans', 'Request failed', e);
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getSupplements(String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/nutrition.php?player_id=$playerId&section=supplements'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['supplements'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getSupplements', 'Request failed', e);
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getNutritionCompliance(String playerId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/nutrition.php?player_id=$playerId&section=compliance'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['logs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getNutritionCompliance', 'Request failed', e);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> saveNutritionProfile({
    required String playerId,
    String? allergies,
    String? dietaryRestrictions,
    int? calorieTarget,
    int? proteinTargetG,
    int? carbTargetG,
    int? fluidTargetMl,
    String? notes,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/nutrition.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'save_profile',
          'player_id': playerId,
          if (allergies != null) 'allergies': allergies,
          if (dietaryRestrictions != null) 'dietary_restrictions': dietaryRestrictions,
          if (calorieTarget != null) 'calorie_target': calorieTarget,
          if (proteinTargetG != null) 'protein_target_g': proteinTargetG,
          if (carbTargetG != null) 'carb_target_g': carbTargetG,
          if (fluidTargetMl != null) 'fluid_target_ml': fluidTargetMl,
          if (notes != null) 'notes': notes,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.saveNutritionProfile', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> saveNutritionDayPlan({
    required String playerId,
    required String planType,
    int? calorieTarget,
    int? proteinTargetG,
    int? carbTargetG,
    int? fluidTargetMl,
    String? hydrationBefore,
    String? hydrationDuring,
    String? hydrationAfter,
    String? notes,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/nutrition.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'save_plan',
          'player_id': playerId,
          'plan_type': planType,
          if (calorieTarget != null) 'calorie_target': calorieTarget,
          if (proteinTargetG != null) 'protein_target_g': proteinTargetG,
          if (carbTargetG != null) 'carb_target_g': carbTargetG,
          if (fluidTargetMl != null) 'fluid_target_ml': fluidTargetMl,
          if (hydrationBefore != null) 'hydration_before': hydrationBefore,
          if (hydrationDuring != null) 'hydration_during': hydrationDuring,
          if (hydrationAfter != null) 'hydration_after': hydrationAfter,
          if (notes != null) 'notes': notes,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.saveNutritionDayPlan', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> addSupplement({
    required String playerId,
    required String supplementName,
    String? dosage,
    String? reason,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/nutrition.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'add_supplement',
          'player_id': playerId,
          'supplement_name': supplementName,
          if (dosage != null) 'dosage': dosage,
          if (reason != null) 'reason': reason,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.addSupplement', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> signoffSupplement({
    required String id,
    String? asRole,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/nutrition.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'signoff_supplement',
          'id': id,
          if (asRole != null) 'as_role': asRole,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.signoffSupplement', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> logNutritionCompliance({
    required String playerId,
    required String logDate,
    String status = 'compliant',
    String? notes,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/nutrition.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'log_compliance',
          'player_id': playerId,
          'log_date': logDate,
          'status': status,
          if (notes != null) 'notes': notes,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.logNutritionCompliance', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  // ── Unified Daily Readiness & Intervention Dashboard ───────────────────────

  static Future<Map<String, dynamic>> getDailyReadiness(String date) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/club/daily_readiness.php?date=$date'),
        headers: _headers,
      ).timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getDailyReadiness', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> sendReadinessReminder(String date) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/daily_readiness.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'send_reminder',
          'date': date,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.sendReadinessReminder', 'Request failed', e);
      return {'success': false, 'message': AppLogger.userMessage(e)};
    }
  }

  // ── Player self-service views (read-only) ───────────────────────────────────

  static Future<Map<String, dynamic>> getDoctorDashboard({String? date}) async {
    try {
      final query = date == null ? '' : '?date=$date';
      final res = await http.get(
        Uri.parse('$_baseUrl/club/doctor_dashboard.php$query'),
        headers: _headers,
      ).timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getDoctorDashboard', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<Map<String, dynamic>>> getMyPhysioSessions() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/my-physio-sessions.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getMyPhysioSessions', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getMyNutritionProfile() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/my-nutrition.php?section=profile'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return body['profile'] as Map<String, dynamic>?;
    } catch (e) {
      AppLogger.e('ApiService.getMyNutritionProfile', 'Request failed', e);
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getMyNutritionPlans() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/my-nutrition.php?section=plans'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getMyNutritionPlans', 'Request failed', e);
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getMySupplements() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/my-nutrition.php?section=supplements'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['supplements'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getMySupplements', 'Request failed', e);
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getMyCoachNotes() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/player/my-notes.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      return (body['notes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      AppLogger.e('ApiService.getMyCoachNotes', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> getMyDailyStatus({String? date}) async {
    try {
      final q = date != null ? '?date=$date' : '';
      final res = await http.get(
        Uri.parse('$_baseUrl/player/my-daily-status.php$q'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getMyDailyStatus', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> setDailyDecision({
    required String playerId,
    required String decisionDate,
    required String participationStatus,
    int? allowedDurationMinutes,
    String? restrictions,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/club/daily_readiness.php'),
        headers: _headers,
        body: jsonEncode({
          'action': 'set_decision',
          'player_id': playerId,
          'decision_date': decisionDate,
          'participation_status': participationStatus,
          if (allowedDurationMinutes != null) 'allowed_duration_minutes': allowedDurationMinutes,
          if (restrictions != null) 'restrictions': restrictions,
        }),
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.setDailyDecision', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
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

  static Future<Map<String, dynamic>> getMe() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth.php?action=me'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getMe', 'Request failed', e);
      return {};
    }
  }

  static Future<Map<String, dynamic>> updateAccountProfile({
    required String name,
    required String phone,
    String? avatarUrl,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth.php?action=update_profile'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              'phone': phone,
              'avatar_url': avatarUrl,
            }),
          )
          .timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.updateAccountProfile', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  /// Syncs the app's selected language to the server so server-generated
  /// notifications/push text can be translated per-recipient. Best-effort —
  /// failures are swallowed since this is a background preference sync, not
  /// a user-facing action.
  static Future<void> updateAccountLanguage(String language) async {
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/auth.php?action=update_language'),
            headers: _headers,
            body: jsonEncode({'language': language}),
          )
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      AppLogger.e('ApiService.updateAccountLanguage', 'Request failed', e);
    }
  }

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth.php?action=change_password'),
            headers: _headers,
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.changePassword', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<void> logout() async {
    final headers = _headers;
    _token = null;
    try {
      await http.post(
        Uri.parse('$_baseUrl/auth.php?action=logout'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      // Best-effort — local token is cleared regardless.
      AppLogger.w('ApiService.logout', 'Server logout skipped (${e.runtimeType})');
    }
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
    String? sessionId,
    String? coachNotes,
    int? preHooperIndex,
    int? preRpe,
    int? postRpe,
    bool painReported = false,
    String? difficulty,
    int? moodAfter,
    String? attemptGroupId,
    int attemptNumber = 1,
    String? invalidReason,
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
              if (sessionId != null)      'session_id':        sessionId,
              if (coachNotes != null)     'coach_notes':       coachNotes,
              if (preHooperIndex != null) 'pre_hooper_index':  preHooperIndex,
              if (preRpe != null)         'pre_rpe':           preRpe,
              if (postRpe != null)        'post_rpe':          postRpe,
              if (painReported)           'pain_reported':     painReported,
              if (difficulty != null)     'difficulty':        difficulty,
              if (moodAfter != null)      'mood_after':        moodAfter,
              if (attemptGroupId != null) 'attempt_group_id':  attemptGroupId,
              'attempt_number': attemptNumber,
              if (invalidReason != null)  'invalid_reason':    invalidReason,
            }),
          )
          .timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.saveAssessment', 'Sync failed', e);
      return {'error': 'sync_failed'};
    }
  }

  /// Fetches every attempt in the same attempt-taking group, plus the
  /// server-computed best/average score across the VALID attempts.
  static Future<Map<String, dynamic>> getAssessmentAttemptGroup(String attemptGroupId) async {
    try {
      final uri = Uri.parse('$_baseUrl/assessments.php')
          .replace(queryParameters: {'attempt_group_id': attemptGroupId});
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getAssessmentAttemptGroup', 'Request failed', e);
      return {'attempts': [], 'attempt_count': 0};
    }
  }

  static Future<Map<String, dynamic>> getAssessmentSummary() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/club/assessment_summary.php'), headers: _headers)
          .timeout(const Duration(seconds: 14));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getAssessmentSummary', 'Request failed', e);
      return {};
    }
  }

  /// Coach endpoint — returns assessments for current user (all or filtered by player).
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
      if (list is List) return list.cast<Map<String, dynamic>>();
      return [];
    } catch (e) {
      AppLogger.e('ApiService.getAssessments', 'Request failed', e);
      return [];
    }
  }

  /// Player endpoint — scoped by server-side linked_player_id (never from request).
  /// Only call this for the authenticated player's own assessment history.
  static Future<List<Map<String, dynamic>>> getPlayerAssessments({
    required String linkedPlayerId,
    int limit = 50,
  }) async {
    if (linkedPlayerId.isEmpty) return [];
    try {
      final uri = Uri.parse('$_baseUrl/player/assessments.php')
          .replace(queryParameters: {'limit': '$limit'});
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      final decoded = _decodeResponse(res);
      if (decoded.containsKey('error')) {
        AppLogger.w('ApiService.getPlayerAssessments', 'Server returned error');
        return [];
      }
      final list = decoded['assessments'];
      if (list is List) return list.cast<Map<String, dynamic>>();
      return [];
    } catch (e) {
      AppLogger.e('ApiService.getPlayerAssessments', 'Request failed', e);
      return [];
    }
  }

  // ── Training Session Flow ─────────────────────────────────────────────────

  static Future<PlayerSessionData?> getTodaySession() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/player/today-session.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (body.containsKey('error')) {
        AppLogger.w('ApiService.getTodaySession', 'Server returned error');
        return null;
      }
      final session = body['session'];
      if (session == null) return null;
      return PlayerSessionData.fromJson(session as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('ApiService.getTodaySession', 'Request failed', e);
      return null;
    }
  }

  static Future<PlayerSessionData?> getSessionDetail(String sessionId) async {
    try {
      final uri = Uri.parse('$_baseUrl/player/session-detail.php')
          .replace(queryParameters: {'id': sessionId});
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (res.statusCode == 403) return null;
      if (res.statusCode == 404) return null;
      if (body.containsKey('error')) return null;
      final session = body['session'];
      if (session == null) return null;
      return PlayerSessionData.fromJson(session as Map<String, dynamic>);
    } catch (e) {
      AppLogger.e('ApiService.getSessionDetail', 'Request failed', e);
      return null;
    }
  }

  /// Read-only list of the club training sessions the player is assigned to.
  static Future<List<TrainingSession>> getMyClubSessions() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/player/sessions.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      final list = body['sessions'];
      if (list is! List) return [];
      return list
          .map((e) => TrainingSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.e('ApiService.getMyClubSessions', 'Request failed', e);
      rethrow;
    }
  }

  /// Read-only list of the club matches the player is part of.
  static Future<List<MatchModel>> getMyMatches() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/player/matches.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      final list = body['matches'];
      if (list is! List) return [];
      return list
          .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.e('ApiService.getMyMatches', 'Request failed', e);
      rethrow;
    }
  }

  /// Save pre-training wellness check (hooper + pre_rpe) linked to a session.
  static Future<Map<String, dynamic>> saveSessionPreCheck({
    required String sessionId,
    required int sleepQuality,
    required int fatigue,
    required int stress,
    required int muscleSoreness,
    required int preRpe,
    required bool painToday,
    double? sleepHours,
    String? notes,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/hooper/save.php'),
            headers: _headers,
            body: jsonEncode({
              'session_id':      sessionId,
              'sleep_quality':   sleepQuality,
              'fatigue':         fatigue,
              'stress':          stress,
              'muscle_soreness': muscleSoreness,
              'pre_rpe':         preRpe,
              'pain_today':      painToday ? 1 : 0,
              if (sleepHours != null) 'sleep_hours': sleepHours,
              if (notes != null)      'notes':       notes,
            }),
          )
          .timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.saveSessionPreCheck', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> startSession(String sessionId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/session/start.php'),
            headers: _headers,
            body: jsonEncode({'session_id': sessionId}),
          )
          .timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.startSession', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  // ── Profile (full onboarding payload) ────────────────────────────────────────

  static Future<Map<String, dynamic>> saveFullProfile(
      Map<String, dynamic> payload) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/profile.php'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.saveFullProfile', 'Request failed', e);
      return {'error': 'Request failed'};
    }
  }

  // ── Coach Players Data ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getCoachPlayersData() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/coach/players.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.getCoachPlayersData', 'Request failed', e);
      return {'players': []};
    }
  }

  // ── Coach Training Plan Methods ──────────────────────────────────────────────

  static Future<List<SelectablePlayer>> getCoachPlayersForSelection() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/coach/players.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      final list = body['players'];
      if (list is! List) return [];
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return SelectablePlayer(
          id:       m['id']?.toString() ?? '',
          name:     m['name'] as String? ?? '',
          position: m['position'] as String? ?? '',
        );
      }).where((p) => p.id.isNotEmpty).toList();
    } catch (e) {
      AppLogger.e('ApiService.getCoachPlayersForSelection', 'Request failed', e);
      return [];
    }
  }

  static Future<Map<String, dynamic>> createManualPlan({
    required String title,
    String? description,
    required String sessionDate,
    required int durationMinutes,
    required String objective,
    required bool wellnessRequired,
    required bool rpeRequired,
    String? notes,
    required List<Map<String, dynamic>> exercises,
    required List<String> playerIds,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/coach/plans/create-manual.php'),
            headers: _headers,
            body: jsonEncode({
              'title':              title,
              if (description != null) 'description': description,
              'session_date':       sessionDate,
              'duration_minutes':   durationMinutes,
              'objective':          objective,
              'wellness_required':  wellnessRequired ? 1 : 0,
              'rpe_required':       rpeRequired ? 1 : 0,
              if (notes != null)    'notes': notes,
              'exercises':          exercises,
              'player_ids':         playerIds,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.createManualPlan', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<TrainingSessionSummary>> getCoachTrainingSessions() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/coach/training-sessions.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (body.containsKey('error')) return [];
      final list = body['sessions'];
      if (list is! List) return [];
      return list
          .map((e) => TrainingSessionSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.e('ApiService.getCoachTrainingSessions', 'Request failed', e);
      return [];
    }
  }

  static Future<SessionReportData?> getSessionReport(String sessionId) async {
    try {
      final uri = Uri.parse('$_baseUrl/coach/session-report.php')
          .replace(queryParameters: {'id': sessionId});
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (res.statusCode == 404 || body.containsKey('error')) return null;
      return SessionReportData.fromJson(body);
    } catch (e) {
      AppLogger.e('ApiService.getSessionReport', 'Request failed', e);
      return null;
    }
  }

  // ── AI Plan — Player ─────────────────────────────────────────────────────────

  /// Generate an AI training plan. May take 15–45 s — uses 60s timeout.
  static Future<Map<String, dynamic>> generateAIPlan(
      AIPlanGenerateRequest request) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/ai-plan/generate.php'),
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 60));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.generateAIPlan', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<AIPlanSummary>> getPlayerPlans() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/player/plans.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (body.containsKey('error')) return [];
      final list = body['plans'];
      if (list is! List) return [];
      return list
          .map((e) => AIPlanSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.e('ApiService.getPlayerPlans', 'Request failed', e);
      return [];
    }
  }

  static Future<AIPlanDetail?> getPlayerPlanDetail(String planId) async {
    try {
      final uri = Uri.parse('$_baseUrl/player/plan-detail.php')
          .replace(queryParameters: {'id': planId});
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (res.statusCode == 404 || body.containsKey('error')) return null;
      return AIPlanDetail.fromJson(body);
    } catch (e) {
      AppLogger.e('ApiService.getPlayerPlanDetail', 'Request failed', e);
      return null;
    }
  }

  // ── Coach AI Plan ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> generateCoachAIPlan(CoachAIPlanRequest req) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/coach/plans/generate-ai.php'),
            headers: _headers,
            body: jsonEncode(req.toJson()),
          )
          .timeout(const Duration(seconds: 100));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.generateCoachAIPlan', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<CoachPlanSummary>> getCoachPlans({String? status, String? type}) async {
    try {
      final params = <String, String>{};
      if (status != null) params['status'] = status;
      if (type   != null) params['type']   = type;
      final uri = Uri.parse('$_baseUrl/coach/plans/list.php').replace(queryParameters: params.isEmpty ? null : params);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (body.containsKey('error')) return [];
      final list = body['plans'];
      if (list is! List) return [];
      return list.map((e) => CoachPlanSummary.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      AppLogger.e('ApiService.getCoachPlans', 'Request failed', e);
      return [];
    }
  }

  static Future<CoachPlanDetail?> getCoachPlanDetail(String planId) async {
    try {
      final uri = Uri.parse('$_baseUrl/coach/plans/detail.php').replace(queryParameters: {'id': planId});
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      final body = _decodeResponse(res);
      if (res.statusCode == 404 || body.containsKey('error')) return null;
      return CoachPlanDetail.fromJson(body);
    } catch (e) {
      AppLogger.e('ApiService.getCoachPlanDetail', 'Request failed', e);
      return null;
    }
  }

  static Future<Map<String, dynamic>> updateCoachDraft({
    required String planId,
    String? title,
    List<Map<String, dynamic>>? sessionUpdates,
    List<Map<String, dynamic>>? exerciseUpdates,
    List<String>? exerciseRemovals,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/coach/plans/update-draft.php'),
            headers: _headers,
            body: jsonEncode({
              'plan_id': planId,
              if (title              != null) 'title':              title,
              if (sessionUpdates     != null) 'session_updates':    sessionUpdates,
              if (exerciseUpdates    != null) 'exercise_updates':   exerciseUpdates,
              if (exerciseRemovals   != null) 'exercise_removals':  exerciseRemovals,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.updateCoachDraft', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> publishCoachPlan(String planId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/coach/plans/publish.php'),
            headers: _headers,
            body: jsonEncode({'plan_id': planId}),
          )
          .timeout(const Duration(seconds: 15));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.publishCoachPlan', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  // ── Phase 6 Reports ──────────────────────────────────────────────────────────

  static Future<CoachPlayerReport?> getCoachPlayerReport(String playerId) async {
    try {
      final uri = Uri.parse('$_baseUrl/coach/reports/player.php')
          .replace(queryParameters: {'player_id': playerId});
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 403 || res.statusCode == 404) return null;
      final body = _decodeResponse(res);
      if (body.containsKey('error')) return null;
      return CoachPlayerReport.fromJson(body);
    } catch (e) {
      AppLogger.e('ApiService.getCoachPlayerReport', 'Request failed', e);
      return null;
    }
  }

  // ── Training Load (sRPE / Monotony / Strain) ─────────────────────────────────

  /// Fetches the calendar-week (Mon-Sun) training-load report for one player.
  /// [playerId] is club_players.id — omit for a player fetching their own report.
  /// [date] (YYYY-MM-DD) selects the week containing that date; defaults to today.
  static Future<TrainingLoadWeekSummary?> getPlayerTrainingLoadWeekly({
    String? playerId,
    String? date,
  }) async {
    try {
      final params = <String, String>{
        if (playerId != null && playerId.isNotEmpty) 'player_id': playerId,
        if (date != null && date.isNotEmpty) 'date': date,
      };
      final uri = Uri.parse('$_baseUrl/player/training-load/weekly.php')
          .replace(queryParameters: params.isEmpty ? null : params);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 403 || res.statusCode == 404) return null;
      final body = _decodeResponse(res);
      if (body.containsKey('error')) return null;
      return TrainingLoadWeekSummary.fromJson(body);
    } catch (e) {
      AppLogger.e('ApiService.getPlayerTrainingLoadWeekly', 'Request failed', e);
      return null;
    }
  }

  static Future<CoachTeamReport?> getCoachTeamReport({
    String? teamName,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final params = <String, String>{};
      if (teamName != null && teamName.isNotEmpty) params['team_name'] = teamName;
      if (from != null) params['from'] = from.toIso8601String().split('T').first;
      if (to != null) params['to'] = to.toIso8601String().split('T').first;
      final uri = Uri.parse('$_baseUrl/coach/reports/team.php')
          .replace(queryParameters: params.isEmpty ? null : params);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      if (res.statusCode == 403) return null;
      final body = _decodeResponse(res);
      if (body.containsKey('error')) return null;
      return CoachTeamReport.fromJson(body);
    } catch (e) {
      AppLogger.e('ApiService.getCoachTeamReport', 'Request failed', e);
      return null;
    }
  }

  static Future<CoachAssessmentReport?> getCoachAssessmentReport(String playerId) async {
    try {
      final uri = Uri.parse('$_baseUrl/coach/reports/assessments.php')
          .replace(queryParameters: {'player_id': playerId});
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 403 || res.statusCode == 404) return null;
      final body = _decodeResponse(res);
      if (body.containsKey('error')) return null;
      return CoachAssessmentReport.fromJson(body);
    } catch (e) {
      AppLogger.e('ApiService.getCoachAssessmentReport', 'Request failed', e);
      return null;
    }
  }

  static Future<MyProgressReport?> getMyProgressReport() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/player/reports/my-progress.php'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 403) return null;
      final body = _decodeResponse(res);
      if (body.containsKey('error')) return null;
      return MyProgressReport.fromJson(body);
    } catch (e) {
      AppLogger.e('ApiService.getMyProgressReport', 'Request failed', e);
      return null;
    }
  }

  static Future<Map<String, dynamic>> savePostTrainingFeedback({
    required String sessionId,
    required int postRpe,
    int? durationMinutes,
    bool painReported = false,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/session/post-feedback.php'),
            headers: _headers,
            body: jsonEncode({
              'session_id':   sessionId,
              'post_rpe':     postRpe,
              if (durationMinutes != null)
                'duration_minutes': durationMinutes,
              'pain_reported': painReported,
            }),
          )
          .timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('ApiService.savePostTrainingFeedback', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }
}
