import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_sport_scribe_main/models/body_composition_models.dart';
import 'package:smart_sport_scribe_main/models/monitoring_models.dart';
import 'package:smart_sport_scribe_main/models/training_load_models.dart';
import 'package:smart_sport_scribe_main/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseUrl = Platform.environment['FITNESS_AUDIT_BASE_URL'];
  final token = Platform.environment['FITNESS_AUDIT_TOKEN'];
  final enabled = baseUrl != null && token != null && token.isNotEmpty;

  test(
    'validates and generates the fitness PDFs from actual API data',
    () async {
      HttpOverrides.global = null;

      Future<Map<String, dynamic>> getJson(String path) async {
        final response = await http.get(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
        expect(response.statusCode, 200, reason: path);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      final bodyList = await getJson(
        '/api/player/body-composition/list.php'
        '?all_history=0&per_page=100&date_from=2026-01-01&date_to=2026-12-31',
      );
      final teamWellness = await getJson(
        '/api/club/team-wellness.php?from=2026-07-20&to=2026-07-26',
      );

      final teamEntries = (bodyList['assessments'] as List<dynamic>)
          .map(
            (entry) =>
                BodyCompositionEntry.fromJson(entry as Map<String, dynamic>),
          )
          .toList();
      expect(teamEntries, isNotEmpty);

      final playerId = teamEntries.first.linkedPlayerId;
      expect(playerId, isNotNull);
      final historyJson = await getJson(
        '/api/player/body-composition/history.php'
        '?player_id=$playerId&limit=100&approved_only=1',
      );
      final clubPlayer = await getJson('/api/club/player.php?id=$playerId');
      final weeklyJson = await getJson(
        '/api/player/training-load/weekly.php'
        '?player_id=$playerId&date=2026-07-26',
      );
      final history = (historyJson['history'] as List<dynamic>)
          .map(
            (entry) =>
                BodyCompositionEntry.fromJson(entry as Map<String, dynamic>),
          )
          .toList();
      final wellness = TeamWellness.fromJson(teamWellness);
      final playerWeekly = TrainingLoadWeekSummary.fromJson(weeklyJson);
      expect(wellness.playersTrainingLoad, isNotEmpty);

      final latest = history.first;
      final playerName = teamEntries
          .firstWhere((entry) => entry.linkedPlayerId == playerId)
          .playerName;
      expect(latest.approvalStatus, 'approved');
      expect(latest.skinfoldSumMm, isNotNull);
      final excelBodyFat =
          27.775 * (math.log(latest.skinfoldSumMm!) / math.ln10) - 27.203;
      expect(latest.bodyFatPercentage, closeTo(excelBodyFat, 0.005));
      expect(
        latest.fatMassKg,
        closeTo(latest.weightKg * excelBodyFat / 100, 0.01),
      );
      expect(
        latest.fatFreeMassKg,
        closeTo(latest.weightKg - latest.fatMassKg!, 0.01),
      );
      final playerWellness = clubPlayer['wellness'] as Map<String, dynamic>;
      expect(
        (playerWellness['body_fat'] as num?)?.toDouble(),
        closeTo(latest.bodyFatPercentage!, 0.0001),
      );
      expect(
        playerWellness['body_fat_measured_at'].toString().substring(0, 10),
        latest.assessmentDate.substring(0, 10),
      );

      final loadRow = wellness.playersTrainingLoad.firstWhere(
        (row) => row.playerId == playerId,
      );
      expect(playerWeekly.playerId, playerId);
      expect(
        playerWeekly.weekStart,
        loadRow.days.first.date.toIso8601String().substring(0, 10),
      );
      expect(playerWeekly.weeklyLoad, closeTo(loadRow.weeklyLoad, 0.0001));
      expect(playerWeekly.dailyMean, closeTo(loadRow.dailyMean, 0.0001));
      expect(
        playerWeekly.standardDeviation,
        closeTo(loadRow.standardDeviation, 0.0001),
      );
      expect(playerWeekly.monotony, loadRow.monotony);
      expect(playerWeekly.strain, loadRow.strain);
      expect(playerWeekly.completenessStatus, loadRow.completenessStatus);
      final dailyLoads = loadRow.days.map((day) => day.dailyLoad).toList();
      expect(dailyLoads, hasLength(7));
      final weeklyLoad = dailyLoads.fold<double>(
        0,
        (sum, value) => sum + value,
      );
      final dailyMean = weeklyLoad / 7;
      final squaredDiffs = dailyLoads.fold<double>(
        0,
        (sum, value) => sum + math.pow(value - dailyMean, 2).toDouble(),
      );
      final sampleStandardDeviation = math.sqrt(squaredDiffs / 6);
      expect(loadRow.weeklyLoad, closeTo(weeklyLoad, 0.0001));
      expect(loadRow.dailyMean, closeTo(dailyMean, 0.0001));
      expect(
        loadRow.standardDeviation,
        closeTo(sampleStandardDeviation, 0.0001),
      );
      for (final day in loadRow.days) {
        final playerDay = playerWeekly.days.firstWhere(
          (candidate) => candidate.date == day.date,
        );
        expect(playerDay.dailyLoad, closeTo(day.dailyLoad, 0.0001));
        expect(playerDay.participationStatus, day.participationStatus);
        final calculatedDailyLoad = day.sessions.fold<double>(
          0,
          (sum, session) =>
              sum +
              ((session.rpe == null || session.actualDurationMinutes == null)
                  ? 0
                  : session.rpe! * session.actualDurationMinutes!),
        );
        expect(day.dailyLoad, closeTo(calculatedDailyLoad, 0.0001));
      }
      if (loadRow.completenessStatus == 'INCOMPLETE') {
        expect(loadRow.monotony, isNull);
        expect(loadRow.strain, isNull);
      }

      final output = Directory('output/pdf/actual-data')
        ..createSync(recursive: true);
      final metadata = ReportMetadata(
        team: latest.teamName ?? loadRow.teamName ?? 'غير متوفر',
        season: 'غير متوفر',
        period:
            '${loadRow.days.first.date.toIso8601String().split('T').first}'
            ' — ${loadRow.days.last.date.toIso8601String().split('T').first}',
        issuedBy: latest.assessedBy ?? 'مستخدم النظام',
        notes: 'تقرير تحقق من بيانات قاعدة الاختبار الفعلية.',
      );

      Future<void> save(String name, Future<List<int>> bytes) async {
        await File('${output.path}/$name').writeAsBytes(await bytes);
      }

      await save(
        'actual_team_body_composition.pdf',
        ReportService.instance.generateTeamBodyCompositionReportPdf(
          entries: teamEntries,
          excludedPlayersCount:
              (bodyList['players_without_data'] as List<dynamic>).length,
          metadata: metadata,
        ),
      );
      await save(
        'actual_player_body_composition.pdf',
        ReportService.instance.generateBodyCompositionReportPdf(
          playerName: playerName ?? 'اللاعب',
          history: history,
          metadata: metadata,
        ),
      );
      await save(
        'actual_team_training_load.pdf',
        ReportService.instance.generateTrainingLoadReportPdf(
          wellness.playersTrainingLoad,
          metadata: metadata,
        ),
      );
      await save(
        'actual_team_training_load_compact.pdf',
        ReportService.instance.generateCompactTrainingLoadReportPdf(
          wellness.playersTrainingLoad,
          metadata: metadata,
        ),
      );
      await save(
        'actual_player_training_load.pdf',
        ReportService.instance.generatePlayerTrainingLoadReportPdf(
          row: loadRow,
          metadata: metadata,
        ),
      );

      for (final name in [
        'actual_team_body_composition.pdf',
        'actual_player_body_composition.pdf',
        'actual_team_training_load.pdf',
        'actual_team_training_load_compact.pdf',
        'actual_player_training_load.pdf',
      ]) {
        expect(File('${output.path}/$name').lengthSync(), greaterThan(1000));
      }
    },
    skip: enabled ? false : 'Requires local read-only fitness audit API.',
  );
}
