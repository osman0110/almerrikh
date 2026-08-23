import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import '../app_config.dart';
import '../models/body_composition_models.dart';
import '../utils/app_logger.dart';

const _baseUrl = kApiBase;

class BodyCompositionService {
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (ApiService.token != null) 'Authorization': 'Bearer ${ApiService.token}',
  };

  static Map<String, dynamic> _decodeResponse(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      AppLogger.w(
        'BodyCompositionService',
        'Non-map response — status ${res.statusCode} url=${res.request?.url}',
      );
      return {'error': 'Unexpected response'};
    } catch (e) {
      final url = res.request?.url.toString() ?? '?';
      final preview = res.body.length > 500
          ? res.body.substring(0, 500)
          : res.body;
      AppLogger.e(
        'BodyCompositionService',
        '[JSON PARSE FAIL] url=$url status=${res.statusCode} body[0:500]=$preview',
        e,
      );
      return {'error': 'Server error'};
    }
  }

  static Future<Map<String, dynamic>> saveAssessment({
    required double weightKg,
    double? heightCm,
    String? assessmentDate,
    String? assessmentTime,
    String assessmentType = 'periodic',
    Map<String, double?>? bicepsAttempts,
    Map<String, double?>? tricepsAttempts,
    Map<String, double?>? subscapularAttempts,
    Map<String, double?>? suprailiacAttempts,
    String? notes,
    String? assessedBy,
    String? playerId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'weight_kg': weightKg,
        if (heightCm != null) 'height_cm': heightCm,
        if (assessmentDate != null) 'assessment_date': assessmentDate,
        if (assessmentTime != null) 'assessment_time': assessmentTime,
        'assessment_type': assessmentType,
        if (notes != null) 'notes': notes,
        if (assessedBy != null) 'assessed_by': assessedBy,
        if (playerId != null) 'player_id': playerId,
      };
      void addAttempts(String site, Map<String, double?>? attempts) {
        if (attempts == null) return;
        attempts.forEach((k, v) {
          if (v != null) payload['${site}_$k'] = v;
        });
      }

      addAttempts('biceps', bicepsAttempts);
      addAttempts('triceps', tricepsAttempts);
      addAttempts('subscapular', subscapularAttempts);
      addAttempts('suprailiac', suprailiacAttempts);

      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/body-composition/save.php'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('BodyCompositionService.saveAssessment', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<List<BodyCompositionEntry>> getHistory({
    String? playerId,
    int limit = 30,
    bool approvedOnly = false,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/player/body-composition/history.php')
          .replace(
            queryParameters: {
              if (playerId != null) 'player_id': playerId,
              'limit': '$limit',
              if (approvedOnly) 'approved_only': '1',
            },
          );
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      final list = data['history'];
      if (list is List) {
        return list
            .map(
              (e) => BodyCompositionEntry.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      }
      return [];
    } catch (e) {
      AppLogger.e('BodyCompositionService.getHistory', 'Request failed', e);
      return [];
    }
  }

  static Future<BodyCompositionEntry?> getDetail(String id) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/player/body-composition/detail.php',
      ).replace(queryParameters: {'id': id});
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      if (data['assessment'] is! Map<String, dynamic>) return null;
      final merged = Map<String, dynamic>.from(
        data['assessment'] as Map<String, dynamic>,
      );
      if (data['delta'] != null) merged['delta'] = data['delta'];
      if (data['goal_status'] != null)
        merged['goal_status'] = data['goal_status'];
      return BodyCompositionEntry.fromJson(merged);
    } catch (e) {
      AppLogger.e('BodyCompositionService.getDetail', 'Request failed', e);
      return null;
    }
  }

  static Future<Map<String, dynamic>> updateAssessment(
    String id,
    Map<String, dynamic> fields,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/body-composition/update.php'),
            headers: _headers,
            body: jsonEncode({'id': id, ...fields}),
          )
          .timeout(const Duration(seconds: 12));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e(
        'BodyCompositionService.updateAssessment',
        'Request failed',
        e,
      );
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> deleteAssessment(String id) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/body-composition/delete.php'),
            headers: _headers,
            body: jsonEncode({'id': id}),
          )
          .timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e(
        'BodyCompositionService.deleteAssessment',
        'Request failed',
        e,
      );
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> approveAssessment(
    String id, {
    bool approved = true,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/body-composition/approve.php'),
            headers: _headers,
            body: jsonEncode({
              'id': id,
              'action': approved ? 'approve' : 'unapprove',
            }),
          )
          .timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e(
        'BodyCompositionService.approveAssessment',
        'Request failed',
        e,
      );
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>?> getActiveSeason() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/club/active-season.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      return data['season'] is Map<String, dynamic>
          ? data['season'] as Map<String, dynamic>
          : null;
    } catch (e) {
      AppLogger.e(
        'BodyCompositionService.getActiveSeason',
        'Request failed',
        e,
      );
      return null;
    }
  }

  static Future<Map<String, dynamic>> getList({
    String? playerId,
    String? team,
    String? position,
    String? assessmentType,
    String? dateFrom,
    String? dateTo,
    double? bodyFatMin,
    double? bodyFatMax,
    String? goalStatus,
    bool allHistory = false,
    int page = 1,
    int perPage = 25,
    bool throwOnError = false,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/player/body-composition/list.php')
          .replace(
            queryParameters: {
              if (playerId != null) 'player_id': playerId,
              if (team != null) 'team': team,
              if (position != null) 'position': position,
              if (assessmentType != null) 'assessment_type': assessmentType,
              if (dateFrom != null) 'date_from': dateFrom,
              if (dateTo != null) 'date_to': dateTo,
              if (bodyFatMin != null) 'body_fat_min': '$bodyFatMin',
              if (bodyFatMax != null) 'body_fat_max': '$bodyFatMax',
              if (goalStatus != null) 'goal_status': goalStatus,
              if (allHistory) 'all_history': '1',
              'page': '$page',
              'per_page': '$perPage',
            },
          );
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      final data = _decodeResponse(res);
      if (throwOnError && data['assessments'] is! List) {
        throw StateError('Body composition list is unavailable');
      }
      return data;
    } catch (e) {
      AppLogger.e('BodyCompositionService.getList', 'Request failed', e);
      if (throwOnError) rethrow;
      return {'assessments': [], 'total': 0};
    }
  }

  static Future<Map<String, dynamic>> compare(
    String fromId,
    String toId,
  ) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/player/body-composition/compare.php',
      ).replace(queryParameters: {'from_id': fromId, 'to_id': toId});
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('BodyCompositionService.compare', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> saveGoal({
    required String playerId,
    double? targetWeightKg,
    double? targetBodyFatPercentage,
    double? targetFatMassKg,
    double? minAcceptableBodyFat,
    double? maxAcceptableBodyFat,
    String? targetDate,
    String? notes,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/body-composition/goals/save.php'),
            headers: _headers,
            body: jsonEncode({
              'player_id': playerId,
              if (targetWeightKg != null) 'target_weight_kg': targetWeightKg,
              if (targetBodyFatPercentage != null)
                'target_body_fat_percentage': targetBodyFatPercentage,
              if (targetFatMassKg != null)
                'target_fat_mass_kg': targetFatMassKg,
              if (minAcceptableBodyFat != null)
                'min_acceptable_body_fat': minAcceptableBodyFat,
              if (maxAcceptableBodyFat != null)
                'max_acceptable_body_fat': maxAcceptableBodyFat,
              if (targetDate != null) 'target_date': targetDate,
              if (notes != null) 'notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('BodyCompositionService.saveGoal', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<Map<String, dynamic>> getGoal({String? playerId}) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/player/body-composition/goals/get.php',
      ).replace(queryParameters: {if (playerId != null) 'player_id': playerId});
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('BodyCompositionService.getGoal', 'Request failed', e);
      return {'goal': null};
    }
  }

  static Future<Map<String, dynamic>> bulkSave(
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/player/body-composition/bulk-save.php'),
            headers: _headers,
            body: jsonEncode({'rows': rows}),
          )
          .timeout(const Duration(seconds: 30));
      return _decodeResponse(res);
    } catch (e) {
      AppLogger.e('BodyCompositionService.bulkSave', 'Request failed', e);
      return {'error': AppLogger.userMessage(e)};
    }
  }

  static Future<TeamBodyCompositionSummary?> getTeamSummary({
    bool throwOnError = false,
  }) async {
    try {
      final res = await http
          .get(
            Uri.parse('$_baseUrl/club/body-composition/team-summary.php'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _decodeResponse(res);
      if (data.containsKey('roster_size'))
        return TeamBodyCompositionSummary.fromJson(data);
      if (throwOnError) {
        throw StateError('Body composition summary is unavailable');
      }
      return null;
    } catch (e) {
      AppLogger.e('BodyCompositionService.getTeamSummary', 'Request failed', e);
      if (throwOnError) rethrow;
      return null;
    }
  }
}
