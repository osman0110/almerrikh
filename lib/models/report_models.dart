// Phase 6 report models — backed by /api/coach/reports/* and /api/player/reports/*

class TrendPoint {
  final String date;
  final double score;
  const TrendPoint({required this.date, required this.score});
  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        date: j['date']?.toString() ?? '',
        score: (j['score'] as num?)?.toDouble() ?? 0,
      );
}

class RpeTrendPoint {
  final String date;
  final int? preRpe;
  final int? postRpe;
  const RpeTrendPoint({required this.date, this.preRpe, this.postRpe});
  factory RpeTrendPoint.fromJson(Map<String, dynamic> j) => RpeTrendPoint(
        date: j['date']?.toString() ?? '',
        preRpe: j['pre_rpe'] as int?,
        postRpe: j['post_rpe'] as int?,
      );
}

class AssessmentHistoryItem {
  final String date;
  final String assessmentType;
  final int overallScore;
  final int stabilityScore;
  final int symmetryScore;
  final int controlScore;
  const AssessmentHistoryItem({
    required this.date,
    required this.assessmentType,
    required this.overallScore,
    required this.stabilityScore,
    required this.symmetryScore,
    required this.controlScore,
  });
  factory AssessmentHistoryItem.fromJson(Map<String, dynamic> j) =>
      AssessmentHistoryItem(
        date: j['date']?.toString() ?? '',
        assessmentType: j['assessment_type']?.toString() ?? '',
        overallScore: (j['overall_score'] as num?)?.toInt() ?? 0,
        stabilityScore: (j['stability_score'] as num?)?.toInt() ?? 0,
        symmetryScore: (j['symmetry_score'] as num?)?.toInt() ?? 0,
        controlScore: (j['control_score'] as num?)?.toInt() ?? 0,
      );
}

class FullAssessmentItem {
  final String date;
  final String assessmentType;
  final int overallScore;
  final int movementScore;
  final int stabilityScore;
  final int symmetryScore;
  final int controlScore;
  final int qualityScore;
  const FullAssessmentItem({
    required this.date,
    required this.assessmentType,
    required this.overallScore,
    required this.movementScore,
    required this.stabilityScore,
    required this.symmetryScore,
    required this.controlScore,
    required this.qualityScore,
  });
  factory FullAssessmentItem.fromJson(Map<String, dynamic> j) =>
      FullAssessmentItem(
        date: j['date']?.toString() ?? '',
        assessmentType: j['assessment_type']?.toString() ?? '',
        overallScore: (j['overall_score'] as num?)?.toInt() ?? 0,
        movementScore: (j['movement_score'] as num?)?.toInt() ?? 0,
        stabilityScore: (j['stability_score'] as num?)?.toInt() ?? 0,
        symmetryScore: (j['symmetry_score'] as num?)?.toInt() ?? 0,
        controlScore: (j['control_score'] as num?)?.toInt() ?? 0,
        qualityScore: (j['quality_score'] as num?)?.toInt() ?? 0,
      );
}

class SessionHistoryItem {
  final String date;
  final String title;
  final String status;
  final int durationMinutes;
  const SessionHistoryItem({
    required this.date,
    required this.title,
    required this.status,
    required this.durationMinutes,
  });
  factory SessionHistoryItem.fromJson(Map<String, dynamic> j) =>
      SessionHistoryItem(
        date: j['date']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        durationMinutes: (j['duration_minutes'] as num?)?.toInt() ?? 0,
      );
}

class BodyMetricPoint {
  final String date;
  final double? weightKg;
  final double? heightCm;
  final double? bodyFatPercent;
  final double? bmi;
  final double? leanBodyMass;
  const BodyMetricPoint({
    required this.date,
    this.weightKg,
    this.heightCm,
    this.bodyFatPercent,
    this.bmi,
    this.leanBodyMass,
  });
  factory BodyMetricPoint.fromJson(Map<String, dynamic> j) => BodyMetricPoint(
        date: j['date']?.toString() ?? '',
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        heightCm: (j['height_cm'] as num?)?.toDouble(),
        bodyFatPercent: (j['body_fat_percent'] as num?)?.toDouble(),
        bmi: (j['bmi'] as num?)?.toDouble(),
        leanBodyMass: (j['lean_body_mass'] as num?)?.toDouble(),
      );
}

class WeeklyLoadPoint {
  final String week;
  final int totalLoad;
  const WeeklyLoadPoint({required this.week, required this.totalLoad});
  factory WeeklyLoadPoint.fromJson(Map<String, dynamic> j) => WeeklyLoadPoint(
        week: j['week']?.toString() ?? '',
        totalLoad: (j['total_load'] as num?)?.toInt() ?? 0,
      );
}

class PlayerInfo {
  final String id;
  final String name;
  final String? position;
  final String? teamName;
  final String? playerType;
  const PlayerInfo({
    required this.id,
    required this.name,
    this.position,
    this.teamName,
    this.playerType,
  });
  factory PlayerInfo.fromJson(Map<String, dynamic> j) => PlayerInfo(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        position: j['position'] as String?,
        teamName: j['team_name'] as String?,
        playerType: j['player_type'] as String?,
      );
}

class ReportBodyMetrics {
  final double? latestWeight;
  final double? latestHeight;
  final double? latestFatPercentage;
  final double? latestBmi;
  final double? latestLeanBodyMass;
  const ReportBodyMetrics({
    this.latestWeight,
    this.latestHeight,
    this.latestFatPercentage,
    this.latestBmi,
    this.latestLeanBodyMass,
  });
  factory ReportBodyMetrics.fromJson(Map<String, dynamic> j) =>
      ReportBodyMetrics(
        latestWeight: (j['latest_weight'] as num?)?.toDouble(),
        latestHeight: (j['latest_height'] as num?)?.toDouble(),
        latestFatPercentage: (j['latest_fat_percentage'] as num?)?.toDouble(),
        latestBmi: (j['latest_bmi'] as num?)?.toDouble(),
        latestLeanBodyMass: (j['latest_lean_body_mass'] as num?)?.toDouble(),
      );
}

class Phase6Summary {
  final int completionRate30d;
  final double? averageHooper30d;
  final double? averagePostRpe30d;
  final int trainingLoad7d;
  final int painReports30d;
  final int? bestAssessmentScore;
  const Phase6Summary({
    required this.completionRate30d,
    this.averageHooper30d,
    this.averagePostRpe30d,
    required this.trainingLoad7d,
    required this.painReports30d,
    this.bestAssessmentScore,
  });
  factory Phase6Summary.fromJson(Map<String, dynamic> j) => Phase6Summary(
        completionRate30d: (j['completion_rate_30d'] as num?)?.toInt() ?? 0,
        averageHooper30d: (j['average_hooper_30d'] as num?)?.toDouble(),
        averagePostRpe30d: (j['average_post_rpe_30d'] as num?)?.toDouble(),
        trainingLoad7d: (j['training_load_7d'] as num?)?.toInt() ?? 0,
        painReports30d: (j['pain_reports_30d'] as num?)?.toInt() ?? 0,
        bestAssessmentScore: (j['best_assessment_score'] as num?)?.toInt(),
      );
}

class CoachPlayerReport {
  final PlayerInfo player;
  final ReportBodyMetrics bodyMetrics;
  final List<TrendPoint> hooperTrend;
  final List<RpeTrendPoint> rpeTrend;
  final List<AssessmentHistoryItem> assessmentHistory;
  final List<SessionHistoryItem> sessionHistory;
  final Phase6Summary summary;
  const CoachPlayerReport({
    required this.player,
    required this.bodyMetrics,
    required this.hooperTrend,
    required this.rpeTrend,
    required this.assessmentHistory,
    required this.sessionHistory,
    required this.summary,
  });
  factory CoachPlayerReport.fromJson(Map<String, dynamic> j) =>
      CoachPlayerReport(
        player: PlayerInfo.fromJson(j['player'] as Map<String, dynamic>? ?? {}),
        bodyMetrics: ReportBodyMetrics.fromJson(
            j['body_metrics'] as Map<String, dynamic>? ?? {}),
        hooperTrend: _parseList(j['hooper_trend'], TrendPoint.fromJson),
        rpeTrend: _parseList(j['rpe_trend'], RpeTrendPoint.fromJson),
        assessmentHistory: _parseList(
            j['assessment_history'], AssessmentHistoryItem.fromJson),
        sessionHistory:
            _parseList(j['session_history'], SessionHistoryItem.fromJson),
        summary: Phase6Summary.fromJson(
            j['summary'] as Map<String, dynamic>? ?? {}),
      );
}

class TeamPlayerRow {
  final String playerId;
  final String name;
  final String? position;
  final double? avgHooper;
  final double? avgPostRpe;
  final int completionRate;
  final int? lastAssessmentScore;
  final int trainingLoad7d;
  final int trainingLoadPeriod;
  final int trainingLoadPeriodDays;
  final String status;
  const TeamPlayerRow({
    required this.playerId,
    required this.name,
    this.position,
    this.avgHooper,
    this.avgPostRpe,
    required this.completionRate,
    this.lastAssessmentScore,
    required this.trainingLoad7d,
    this.trainingLoadPeriod = 0,
    this.trainingLoadPeriodDays = 7,
    required this.status,
  });
  factory TeamPlayerRow.fromJson(Map<String, dynamic> j) => TeamPlayerRow(
        playerId: j['player_id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        position: j['position'] as String?,
        avgHooper: (j['avg_hooper'] as num?)?.toDouble(),
        avgPostRpe: (j['avg_post_rpe'] as num?)?.toDouble(),
        completionRate: (j['completion_rate'] as num?)?.toInt() ?? 0,
        lastAssessmentScore: (j['last_assessment_score'] as num?)?.toInt(),
        trainingLoad7d: (j['training_load_7d'] as num?)?.toInt() ?? 0,
        trainingLoadPeriod:
            (j['training_load_period'] as num?)?.toInt() ??
            (j['training_load_7d'] as num?)?.toInt() ??
            0,
        trainingLoadPeriodDays:
            (j['training_load_period_days'] as num?)?.toInt() ?? 7,
        status: j['status']?.toString() ?? 'ready',
      );
}

class TeamAverages {
  final double? avgHooper;
  final double? avgPostRpe;
  final int completionRate;
  final int trainingLoad7d;
  final int trainingLoadPeriod;
  final int trainingLoadPeriodDays;
  final int squadSize;
  const TeamAverages({
    this.avgHooper,
    this.avgPostRpe,
    required this.completionRate,
    required this.trainingLoad7d,
    this.trainingLoadPeriod = 0,
    this.trainingLoadPeriodDays = 7,
    required this.squadSize,
  });
  factory TeamAverages.fromJson(Map<String, dynamic> j) => TeamAverages(
        avgHooper: (j['avg_hooper'] as num?)?.toDouble(),
        avgPostRpe: (j['avg_post_rpe'] as num?)?.toDouble(),
        completionRate: (j['completion_rate'] as num?)?.toInt() ?? 0,
        trainingLoad7d: (j['training_load_7d'] as num?)?.toInt() ?? 0,
        trainingLoadPeriod:
            (j['training_load_period'] as num?)?.toInt() ??
            (j['training_load_7d'] as num?)?.toInt() ??
            0,
        trainingLoadPeriodDays:
            (j['training_load_period_days'] as num?)?.toInt() ?? 7,
        squadSize: (j['squad_size'] as num?)?.toInt() ?? 0,
      );
}

class CoachTeamReport {
  final String? teamName;
  final List<TeamPlayerRow> players;
  final TeamAverages teamAverages;
  final List<TeamPlayerRow> topPerformers;
  final List<TeamPlayerRow> atRiskPlayers;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  const CoachTeamReport({
    this.teamName,
    required this.players,
    required this.teamAverages,
    required this.topPerformers,
    required this.atRiskPlayers,
    this.rangeFrom,
    this.rangeTo,
  });
  factory CoachTeamReport.fromJson(Map<String, dynamic> j) => CoachTeamReport(
        teamName: j['team_name'] as String?,
        players: _parseList(j['players'], TeamPlayerRow.fromJson),
        teamAverages: TeamAverages.fromJson(
            j['team_averages'] as Map<String, dynamic>? ?? {}),
        topPerformers: _parseList(j['top_performers'], TeamPlayerRow.fromJson),
        atRiskPlayers: _parseList(j['at_risk_players'], TeamPlayerRow.fromJson),
        rangeFrom: DateTime.tryParse(
          (j['range'] as Map<String, dynamic>?)?['from']?.toString() ?? '',
        ),
        rangeTo: DateTime.tryParse(
          (j['range'] as Map<String, dynamic>?)?['to']?.toString() ?? '',
        ),
      );

  int get rangeDays => rangeFrom != null && rangeTo != null
      ? rangeTo!.difference(rangeFrom!).inDays + 1
      : 7;
}

class AssessmentReportSummary {
  final int? bestScore;
  final int? worstScore;
  final double? averageScore;
  final String trend;
  const AssessmentReportSummary({
    this.bestScore,
    this.worstScore,
    this.averageScore,
    required this.trend,
  });
  factory AssessmentReportSummary.fromJson(Map<String, dynamic> j) =>
      AssessmentReportSummary(
        bestScore: (j['best_score'] as num?)?.toInt(),
        worstScore: (j['worst_score'] as num?)?.toInt(),
        averageScore: (j['average_score'] as num?)?.toDouble(),
        trend: j['trend']?.toString() ?? 'insufficient_data',
      );
}

class CoachAssessmentReport {
  final PlayerInfo player;
  final List<FullAssessmentItem> assessments;
  final AssessmentReportSummary summary;
  const CoachAssessmentReport({
    required this.player,
    required this.assessments,
    required this.summary,
  });
  factory CoachAssessmentReport.fromJson(Map<String, dynamic> j) =>
      CoachAssessmentReport(
        player: PlayerInfo.fromJson(j['player'] as Map<String, dynamic>? ?? {}),
        assessments: _parseList(j['assessments'], FullAssessmentItem.fromJson),
        summary: AssessmentReportSummary.fromJson(
            j['summary'] as Map<String, dynamic>? ?? {}),
      );
}

class SessionCompletion30d {
  final int completed;
  final int assigned;
  final int completionRate;
  const SessionCompletion30d({
    required this.completed,
    required this.assigned,
    required this.completionRate,
  });
  factory SessionCompletion30d.fromJson(Map<String, dynamic> j) =>
      SessionCompletion30d(
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        assigned: (j['assigned'] as num?)?.toInt() ?? 0,
        completionRate: (j['completion_rate'] as num?)?.toInt() ?? 0,
      );
}

class MyProgressReport {
  final List<TrendPoint> hooperTrend;
  final List<RpeTrendPoint> rpeTrend;
  final SessionCompletion30d sessionCompletion30d;
  final List<AssessmentHistoryItem> assessmentHistory;
  final List<BodyMetricPoint> bodyMetricsHistory;
  final List<WeeklyLoadPoint> weeklyLoad;
  const MyProgressReport({
    required this.hooperTrend,
    required this.rpeTrend,
    required this.sessionCompletion30d,
    required this.assessmentHistory,
    required this.bodyMetricsHistory,
    required this.weeklyLoad,
  });
  factory MyProgressReport.fromJson(Map<String, dynamic> j) => MyProgressReport(
        hooperTrend: _parseList(j['hooper_trend'], TrendPoint.fromJson),
        rpeTrend: _parseList(j['rpe_trend'], RpeTrendPoint.fromJson),
        sessionCompletion30d: SessionCompletion30d.fromJson(
            j['session_completion_30d'] as Map<String, dynamic>? ?? {}),
        assessmentHistory: _parseList(
            j['assessment_history'], AssessmentHistoryItem.fromJson),
        bodyMetricsHistory:
            _parseList(j['body_metrics_history'], BodyMetricPoint.fromJson),
        weeklyLoad: _parseList(j['weekly_load'], WeeklyLoadPoint.fromJson),
      );
}

List<T> _parseList<T>(
    dynamic raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw is! List) return [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(fromJson)
      .toList();
}
