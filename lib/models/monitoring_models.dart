class BodyMetric {
  int? id;
  double weightKg, heightCm, bodyFatPercent;
  double? bmi;
  DateTime? measuredAt;

  BodyMetric({
    this.id,
    required this.weightKg,
    required this.heightCm,
    required this.bodyFatPercent,
    this.bmi,
    this.measuredAt,
  });

  factory BodyMetric.fromJson(Map<String, dynamic> j) => BodyMetric(
    id: j['id'] as int?,
    weightKg: (j['weight_kg'] as num?)?.toDouble() ?? 0,
    heightCm: (j['height_cm'] as num?)?.toDouble() ?? 0,
    bodyFatPercent: (j['body_fat_percent'] as num?)?.toDouble() ?? 0,
    bmi: (j['bmi'] as num?)?.toDouble(),
    measuredAt: j['measured_at'] != null ? DateTime.tryParse(j['measured_at']) : null,
  );
}

class HooperEntry {
  int? id;
  int sleepQuality, fatigue, stress, muscleSoreness, hooperScore;
  double? sleepHours;
  String? notes;
  DateTime? submittedAt;

  HooperEntry({
    this.id,
    required this.sleepQuality,
    required this.fatigue,
    required this.stress,
    required this.muscleSoreness,
    required this.hooperScore,
    this.sleepHours,
    this.notes,
    this.submittedAt,
  });

  factory HooperEntry.fromJson(Map<String, dynamic> j) => HooperEntry(
    id: j['id'] as int?,
    sleepQuality: j['sleep_quality'] as int? ?? 1,
    fatigue: j['fatigue'] as int? ?? 1,
    stress: j['stress'] as int? ?? 1,
    muscleSoreness: j['muscle_soreness'] as int? ?? 1,
    hooperScore: j['hooper_score'] as int? ?? 0,
    sleepHours: (j['sleep_hours'] as num?)?.toDouble(),
    notes: j['notes'] as String?,
    submittedAt: j['submitted_at'] != null ? DateTime.tryParse(j['submitted_at']) : null,
  );

  String get status {
    if (hooperScore <= 10) return 'normal';
    if (hooperScore <= 16) return 'moderate';
    return 'high_risk';
  }
}

class RpeEntry {
  int? id;
  int rpeScore, durationMinutes, trainingLoad;
  String? sessionType;
  String? notes;
  DateTime? submittedAt;

  RpeEntry({
    this.id,
    required this.rpeScore,
    required this.durationMinutes,
    required this.trainingLoad,
    this.sessionType,
    this.notes,
    this.submittedAt,
  });

  factory RpeEntry.fromJson(Map<String, dynamic> j) => RpeEntry(
    id: j['id'] as int?,
    rpeScore: j['rpe_score'] as int? ?? 1,
    durationMinutes: j['duration_minutes'] as int? ?? 0,
    trainingLoad: j['training_load'] as int? ?? 0,
    sessionType: j['session_type'] as String?,
    notes: j['notes'] as String?,
    submittedAt: j['submitted_at'] != null ? DateTime.tryParse(j['submitted_at']) : null,
  );
}

class MonitoringDashboard {
  BodyMetric? bodyMetric;
  HooperEntry? todayHooper;
  RpeEntry? lastRpe;
  List<int> weeklyLoads;
  int readinessScore;
  double acwr;
  double acuteLoad;
  double chronicLoad;
  String wellnessStatus; // 'good', 'moderate', 'high_risk'
  int injuryRiskCount;
  List<String> alerts;
  List<String> insights;
  List<String> recommendations;

  MonitoringDashboard({
    this.bodyMetric,
    this.todayHooper,
    this.lastRpe,
    required this.weeklyLoads,
    required this.readinessScore,
    required this.acwr,
    required this.acuteLoad,
    required this.chronicLoad,
    required this.wellnessStatus,
    required this.injuryRiskCount,
    required this.alerts,
    required this.insights,
    required this.recommendations,
  });

  factory MonitoringDashboard.fromJson(Map<String, dynamic> j) => MonitoringDashboard(
    bodyMetric: j['body_metric'] != null ? BodyMetric.fromJson(j['body_metric']) : null,
    todayHooper: j['today_hooper'] != null ? HooperEntry.fromJson(j['today_hooper']) : null,
    lastRpe: j['last_rpe'] != null ? RpeEntry.fromJson(j['last_rpe']) : null,
    weeklyLoads: (j['weekly_loads'] as List?)?.cast<int>() ?? [],
    readinessScore: j['readiness_score'] as int? ?? 100,
    acwr: (j['acwr'] as num?)?.toDouble() ?? 0,
    acuteLoad: (j['acute_load'] as num?)?.toDouble() ?? 0,
    chronicLoad: (j['chronic_load'] as num?)?.toDouble() ?? 0,
    wellnessStatus: j['wellness_status'] as String? ?? 'good',
    injuryRiskCount: j['injury_risk_count'] as int? ?? 0,
    alerts: (j['alerts'] as List?)?.cast<String>() ?? [],
    insights: (j['insights'] as List?)?.cast<String>() ?? [],
    recommendations: (j['recommendations'] as List?)?.cast<String>() ?? [],
  );

  String get readinessColor {
    if (readinessScore >= 70) return 'success';
    if (readinessScore >= 40) return 'warning';
    return 'destructive';
  }
}

class TeamWellness {
  int teamReadinessScore;
  int injuryRiskCount;
  double averageRpe;
  int weeklyLoad;
  int recoveryScore;
  int playersNeedingAttention;
  int totalCheckedIn;

  TeamWellness({
    required this.teamReadinessScore,
    required this.injuryRiskCount,
    required this.averageRpe,
    required this.weeklyLoad,
    required this.recoveryScore,
    required this.playersNeedingAttention,
    required this.totalCheckedIn,
  });

  factory TeamWellness.fromJson(Map<String, dynamic> j) => TeamWellness(
    teamReadinessScore: j['team_readiness_score'] as int? ?? 0,
    injuryRiskCount: j['injury_risk_count'] as int? ?? 0,
    averageRpe: (j['average_rpe'] as num?)?.toDouble() ?? 0,
    weeklyLoad: j['weekly_load'] as int? ?? 0,
    recoveryScore: j['recovery_score'] as int? ?? 0,
    playersNeedingAttention: j['players_needing_attention'] as int? ?? 0,
    totalCheckedIn: j['total_checked_in'] as int? ?? 0,
  );
}

class TrendDataPoint {
  String date;
  double value;
  TrendDataPoint({required this.date, required this.value});
  factory TrendDataPoint.fromJson(Map<String, dynamic> j) => TrendDataPoint(
    date: j['date'] as String? ?? '',
    value: (j['value'] as num?)?.toDouble() ?? 0,
  );
}

class SleepTrendPoint {
  String date;
  double quality, hours;
  SleepTrendPoint({required this.date, required this.quality, required this.hours});
  factory SleepTrendPoint.fromJson(Map<String, dynamic> j) => SleepTrendPoint(
    date: j['date'] as String? ?? '',
    quality: (j['quality'] as num?)?.toDouble() ?? 0,
    hours: (j['hours'] as num?)?.toDouble() ?? 0,
  );
}

class PlayerTrends {
  int periodDays;
  List<TrendDataPoint> fatigueTrend, recoveryTrend, loadTrend;
  List<SleepTrendPoint> sleepTrend;
  Map<String, double> averages;

  PlayerTrends({
    required this.periodDays,
    required this.fatigueTrend,
    required this.recoveryTrend,
    required this.loadTrend,
    required this.sleepTrend,
    required this.averages,
  });

  factory PlayerTrends.fromJson(Map<String, dynamic> j) => PlayerTrends(
    periodDays: j['period_days'] as int? ?? 7,
    fatigueTrend: (j['fatigue_trend'] as List?)?.map((e) => TrendDataPoint.fromJson(e)).toList() ?? [],
    recoveryTrend: (j['recovery_trend'] as List?)?.map((e) => TrendDataPoint.fromJson(e)).toList() ?? [],
    loadTrend: (j['load_trend'] as List?)?.map((e) => TrendDataPoint.fromJson(e)).toList() ?? [],
    sleepTrend: (j['sleep_trend'] as List?)?.map((e) => SleepTrendPoint.fromJson(e)).toList() ?? [],
    averages: Map<String, double>.from(j['averages'] as Map? ?? {}),
  );
}
