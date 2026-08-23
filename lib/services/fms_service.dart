import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import '../app_config.dart';
import '../models/fms_model.dart';
import '../utils/app_logger.dart';

/// FMS input for one movement — either {score, pain, notes} for a
/// unilateral movement, or {left, right, pain, notes} for a bilateral one.
class FmsMovementInput {
  const FmsMovementInput({this.score, this.left, this.right, this.pain = false, this.notes});
  final int? score;
  final int? left;
  final int? right;
  final bool pain;
  final String? notes;

  Map<String, dynamic> toJson() => {
        if (score != null) 'score': score,
        if (left != null) 'left': left,
        if (right != null) 'right': right,
        'pain': pain,
        if (notes != null) 'notes': notes,
      };
}

class FmsService {
  static const _baseUrl = kApiBase;
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (ApiService.token != null) 'Authorization': 'Bearer ${ApiService.token}',
      };

  static Future<Map<String, dynamic>> saveFmsAssessment({
    required String playerId,
    required Map<FmsMovement, FmsMovementInput> movements,
    String? sessionId,
    String? notes,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/fms/save.php'),
            headers: _headers,
            body: jsonEncode({
              'player_id': playerId,
              if (sessionId != null) 'session_id': sessionId,
              if (notes != null) 'notes': notes,
              'movements': movements.map((k, v) => MapEntry(k.id, v.toJson())),
            }),
          )
          .timeout(const Duration(seconds: 12));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.e('FmsService.saveFmsAssessment', 'Request failed', e);
      return {'error': 'sync_failed'};
    }
  }

  static Future<List<FmsAssessment>> getFmsHistory(String playerId, {int limit = 10}) async {
    try {
      final uri = Uri.parse('$_baseUrl/fms/history.php')
          .replace(queryParameters: {'player_id': playerId, 'limit': '$limit'});
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = body['history'] as List<dynamic>? ?? [];
      return list
          .map((e) => FmsAssessment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      AppLogger.e('FmsService.getFmsHistory', 'Request failed', e);
      return [];
    }
  }
}
