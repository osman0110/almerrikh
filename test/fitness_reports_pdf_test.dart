import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:al_merrikh/models/body_composition_models.dart';
import 'package:al_merrikh/models/monitoring_models.dart';
import 'package:al_merrikh/models/training_load_models.dart';
import 'package:al_merrikh/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates the six fitness PDF samples', () async {
    final output = Directory('output/pdf')..createSync(recursive: true);
    const metadata = ReportMetadata(
      team: 'الفريق الأول',
      season: '2026/2027',
      period: '2026-07-01 — 2026-07-26',
      issuedBy: 'مستخدم الاختبار',
      notes: 'عينة تحقق آلية — لا تستخدم كبيانات تشغيلية.',
    );
    final bodyHistory = List.generate(
      4,
      (index) => BodyCompositionEntry(
        id: 'body-$index',
        linkedPlayerId: 'player-1',
        playerName: 'أحمد محمد',
        teamName: 'الفريق الأول',
        position: 'وسط',
        assessmentDate: '2026-07-${(5 + index * 7).toString().padLeft(2, '0')}',
        assessmentType: 'periodic',
        heightCm: 180,
        weightKg: 78 - index * .6,
        bicepsMm: 6.4 - index * .1,
        tricepsMm: 10.8 - index * .2,
        subscapularMm: 13.2 - index * .2,
        suprailiacMm: 8.6 - index * .1,
        bodyFatPercentage: 17.4 - index * .5,
        fatMassKg: 13.6 - index * .5,
        fatFreeMassKg: 64.4 - index * .1,
        skinfoldSumMm: 42 - index * 1.5,
        bmi: 24.1 - index * .2,
        approvalStatus: index == 3 ? 'draft' : 'approved',
        delta: BodyCompositionDelta(
          weightKg: -.6,
          bodyFatPercentage: -.5,
          fatMassKg: -.5,
          fatFreeMassKg: -.1,
          skinfoldSumMm: -1.5,
          previousDate:
              '2026-07-${(index * 7).clamp(1, 31).toString().padLeft(2, '0')}',
        ),
        goalStatus: BodyCompositionGoalStatus(
          targetBodyFatPercentage: 15.5,
          status: index == 0 ? 'needs_follow_up' : 'on_track',
        ),
      ),
    ).reversed.toList();
    final days = List.generate(28, (index) {
      final date = DateTime(2026, 6, 29).add(Duration(days: index));
      final missingRpe = index == 25;
      final missingDuration = index == 26;
      final load = index.isEven && !missingRpe && !missingDuration
          ? 360.0 + index * 4
          : 0.0;
      return TrainingLoadDay(
        date: date,
        dayName: '',
        dailyLoad: load,
        participationStatus: missingRpe
            ? 'MISSING_RPE'
            : missingDuration
            ? 'MISSING_DURATION'
            : 'COMPLETE',
        sessionsCount: index.isEven ? 1 : 0,
        expectedRecords: index.isEven ? 1 : 0,
        completedRecords: index.isEven && !missingRpe && !missingDuration
            ? 1
            : 0,
        dataQualityIssues: [
          if (missingRpe) 'MISSING_RPE',
          if (missingDuration) 'MISSING_DURATION',
        ],
        sessions: index.isEven
            ? [
                TrainingLoadSession(
                  sessionType: 'تدريب فني',
                  sessionName: 'الحصة الصباحية',
                  rpe: missingRpe ? null : 6.0,
                  actualDurationMinutes: missingDuration ? null : 60,
                  sessionLoad: load == 0 ? null : load,
                ),
              ]
            : const [],
      );
    });
    final loadRows = [
      PlayerTrainingLoadRow(
        playerId: 'player-1',
        playerName: 'أحمد محمد',
        position: 'وسط',
        teamName: 'الفريق الأول',
        weeklyLoad: 1280,
        dailyMean: 182.9,
        standardDeviation: 75,
        monotony: 2.44,
        strain: 3123,
        monotonyDisplay: 2.44,
        calculationStatus: 'OK',
        completenessStatus: 'INCOMPLETE',
        days: days.sublist(21),
        days28: days,
        sessionsCount7d: 4,
        totalMinutes7d: 240,
        averageRpe7d: 6,
        load7d: 1280,
        load28d: 4920,
        missingRpeCount: 1,
        missingDurationCount: 1,
        dataCompleteness: .88,
        acwr: null,
        acwrClassification: 'INSUFFICIENT_DATA',
      ),
      PlayerTrainingLoadRow(
        playerId: 'player-2',
        playerName: 'محمد علي',
        position: 'دفاع',
        weeklyLoad: 1520,
        dailyMean: 217.1,
        standardDeviation: 81,
        monotony: 1.87,
        strain: 2842,
        calculationStatus: 'OK',
        completenessStatus: 'COMPLETE',
        days: days.sublist(21),
        days28: days,
        sessionsCount7d: 5,
        totalMinutes7d: 315,
        averageRpe7d: 6.4,
        load7d: 1520,
        load28d: 5480,
        dataCompleteness: 1,
        acwr: 1.11,
        acwrClassification: 'IN_TARGET',
      ),
    ];
    const compactPlayerNames = [
      'أحمد محمد',
      'محمد علي',
      'مصعب عمر',
      'عثمان جعفر',
      'معتصم حسن',
    ];
    final compactLoadRows = List.generate(5, (index) {
      final source = loadRows[index % loadRows.length];
      return PlayerTrainingLoadRow(
        playerId: 'compact-player-$index',
        playerName: compactPlayerNames[index],
        position: source.position,
        weeklyLoad: source.weeklyLoad + index * 75,
        dailyMean: source.dailyMean + index * 10,
        standardDeviation: source.standardDeviation + index * 4,
        monotony: source.monotony,
        strain: source.strain,
        monotonyDisplay: source.monotonyDisplay,
        calculationStatus: source.calculationStatus,
        completenessStatus: source.completenessStatus,
        days: source.days,
        days28: source.days28,
        teamName: source.teamName,
        sessionsCount7d: source.sessionsCount7d,
        totalMinutes7d: source.totalMinutes7d,
        averageRpe7d: source.averageRpe7d,
        load7d: source.load7d,
        load28d: source.load28d,
        missingRpeCount: source.missingRpeCount,
        missingDurationCount: source.missingDurationCount,
        dataCompleteness: source.dataCompleteness,
        acwr: source.acwr,
        acwrClassification: source.acwrClassification,
      );
    });
    final players = [
      PlayerWellnessEntry(
        id: 'player-1',
        name: 'أحمد محمد',
        playerStatus: 'active',
        hooperScore: 12,
        fatigue: 3,
        sleepQuality: 4,
        stress: 2,
        muscleSoreness: 3,
        lastRpe: 6,
        lastLoad: 360,
        submittedAt: DateTime(2026, 7, 26, 8, 30),
        wellnessStatus: 'normal',
      ),
      const PlayerWellnessEntry(
        id: 'player-2',
        name: 'محمد علي',
        playerStatus: 'active',
        wellnessStatus: 'no_data',
      ),
    ];
    final wellness = TeamWellness(
      teamReadinessScore: 74,
      injuryRiskCount: 0,
      averageRpe: 6,
      weeklyLoad: 2800,
      recoveryScore: 70,
      playersNeedingAttention: 1,
      totalCheckedIn: 1,
    );

    Future<void> save(String name, Future<List<int>> bytes) async {
      await File('${output.path}/$name').writeAsBytes(await bytes);
    }

    await save(
      'team_body_composition.pdf',
      ReportService.instance.generateTeamBodyCompositionReportPdf(
        entries: bodyHistory,
        metadata: metadata,
      ),
    );
    await save(
      'player_body_composition.pdf',
      ReportService.instance.generateBodyCompositionReportPdf(
        playerName: 'أحمد محمد',
        history: bodyHistory,
        metadata: metadata,
      ),
    );
    await save(
      'team_training_load.pdf',
      ReportService.instance.generateTrainingLoadReportPdf(
        loadRows,
        metadata: metadata,
      ),
    );
    await save(
      'team_training_load_compact.pdf',
      ReportService.instance.generateCompactTrainingLoadReportPdf(
        compactLoadRows,
        metadata: metadata,
      ),
    );
    await save(
      'player_training_load.pdf',
      ReportService.instance.generatePlayerTrainingLoadReportPdf(
        row: loadRows.first,
        metadata: metadata,
      ),
    );
    await save(
      'team_hooper_rpe.pdf',
      ReportService.instance.generateTeamWellnessReportPdf(
        wellness: wellness,
        players: players,
        metadata: metadata,
      ),
    );

    for (final name in [
      'team_body_composition.pdf',
      'player_body_composition.pdf',
      'team_training_load.pdf',
      'team_training_load_compact.pdf',
      'player_training_load.pdf',
      'team_hooper_rpe.pdf',
    ]) {
      expect(File('${output.path}/$name').lengthSync(), greaterThan(1000));
    }
  });
}
