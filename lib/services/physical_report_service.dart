import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_service.dart';
import '../app_config.dart';
import '../models/physical_report_models.dart';
import '../utils/app_logger.dart';

class PhysicalReportService {
  const PhysicalReportService();

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (ApiService.token != null) 'Authorization': 'Bearer ${ApiService.token}',
  };

  Future<PhysicalReportData?> getReport() async {
    try {
      final response = await http
          .get(
            Uri.parse('$kApiBase/club/physical-report.php'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 &&
          body is Map &&
          body['success'] == true) {
        return PhysicalReportData.fromJson(Map<String, dynamic>.from(body));
      }
      AppLogger.w(
        'PhysicalReportService.getReport',
        'Server rejected report (${response.statusCode})',
      );
    } catch (error) {
      AppLogger.e('PhysicalReportService.getReport', 'Request failed', error);
    }
    return null;
  }

  Future<bool> updateReadiness({
    required String playerId,
    required bool isReady,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$kApiBase/club/physical-report.php'),
            headers: _headers,
            body: jsonEncode({
              'player_id': playerId,
              'status': isReady ? 'ready' : 'not_ready',
            }),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 &&
          body is Map &&
          body['success'] == true) {
        return true;
      }
      AppLogger.w(
        'PhysicalReportService.updateReadiness',
        'Server rejected update (${response.statusCode})',
      );
    } catch (error) {
      AppLogger.e(
        'PhysicalReportService.updateReadiness',
        'Request failed',
        error,
      );
    }
    return false;
  }
}
