import 'training_load_models.dart';

class BodyMetric {
  String? id;
  double? weightKg, heightCm, bodyFatPercent;
  double? bmi;
  double? fatMassKg;
  double? leanMassKg;
  double? waistCm;
  String? bmiForAgeCategory;
  String? measurementMethod;
  String? deviceName;
  String? measuredBy;
  String? specialistNotes;
  DateTime? measuredAt;

  BodyMetric({
    this.id,
    this.weightKg,
    this.heightCm,
    this.bodyFatPercent,
    this.bmi,
    this.fatMassKg,
    this.leanMassKg,
    this.waistCm,
    this.bmiForAgeCategory,
    this.measurementMethod,
    this.deviceName,
    this.measuredBy,
    this.specialistNotes,
    this.measuredAt,
  });

  factory BodyMetric.fromJson(Map<String, dynamic> j) => BodyMetric(
    id: j['id']?.toString(),
    weightKg: (j['weight_kg'] as num?)?.toDouble(),
    heightCm: (j['height_cm'] as num?)?.toDouble(),
    bodyFatPercent: (j['body_fat_percent'] as num?)?.toDouble(),
    bmi: (j['bmi'] as num?)?.toDouble(),
    fatMassKg: (j['fat_mass_kg'] as num?)?.toDouble(),
    leanMassKg: (j['lean_mass_kg'] as num?)?.toDouble(),
    waistCm: (j['waist_cm'] as num?)?.toDouble(),
    bmiForAgeCategory: j['bmi_for_age_category'] as String?,
    measurementMethod: j['measurement_method'] as String?,
    deviceName: j['device_name'] as String?,
    measuredBy: j['measured_by'] as String?,
    specialistNotes: j['specialist_notes'] as String?,
    measuredAt: j['measured_at'] != null
        ? DateTime.tryParse(j['measured_at'])
        : null,
  );
}

class HooperEntry {
  int? id;
  int sleepQuality, fatigue, stress, muscleSoreness, hooperScore;
  double? sleepHours;
  int? mood;
  bool painToday;
  String? painLocation;
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
    this.mood,
    this.painToday = false,
    this.painLocation,
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
    mood: j['mood'] as int?,
    painToday:
        (j['pain_today'] as num?)?.toInt() == 1 || j['pain_today'] == true,
    painLocation: j['pain_location'] as String?,
    notes: j['notes'] as String?,
    submittedAt: j['submitted_at'] != null
        ? DateTime.tryParse(j['submitted_at'])
        : null,
  );

  String get status {
    if (hooperScore <= 10) return 'normal';
    if (hooperScore <= 16) return 'moderate';
    return 'high_risk';
  }
}

class RpeEntry {
  int? id;
  // rpeScore/trainingLoad are decimal (RPE accepts values like 5.5 per the
  // RPE APR Rwanda reference sheet) — see TrainingLoadCalculator.
  double? rpeScore, trainingLoad;
  int? durationMinutes;
  String? sessionType;
  String? notes;
  DateTime? submittedAt;
  bool completedFullSession;
  int? actualDurationMinutes;
  String? incompleteReason;
  String recordStatus;
  DateTime? lastEditedAt;

  RpeEntry({
    this.id,
    required this.rpeScore,
    required this.durationMinutes,
    required this.trainingLoad,
    this.sessionType,
    this.notes,
    this.submittedAt,
    this.completedFullSession = true,
    this.actualDurationMinutes,
    this.incompleteReason,
    this.recordStatus = 'original',
    this.lastEditedAt,
  });

  factory RpeEntry.fromJson(Map<String, dynamic> j) => RpeEntry(
    id: j['id'] as int?,
    rpeScore: (j['rpe_score'] as num?)?.toDouble(),
    durationMinutes: (j['duration_minutes'] as num?)?.toInt(),
    trainingLoad: (j['training_load'] as num?)?.toDouble(),
    sessionType: j['session_type'] as String?,
    notes: j['notes'] as String?,
    submittedAt: j['submitted_at'] != null
        ? DateTime.tryParse(j['submitted_at'])
        : null,
    completedFullSession: (j['completed_full_session'] as num?)?.toInt() != 0,
    actualDurationMinutes: (j['actual_duration_minutes'] as num?)?.toInt(),
    incompleteReason: j['incomplete_reason'] as String?,
    recordStatus: j['record_status'] as String? ?? 'original',
    lastEditedAt: j['last_edited_at'] != null
        ? DateTime.tryParse(j['last_edited_at'].toString())
        : null,
  );
}

class MonitoringDashboard {
  BodyMetric? bodyMetric;
  HooperEntry? todayHooper;
  RpeEntry? lastRpe;
  List<int?> weeklyLoads;
  int readinessScore;
  double acwr;
  double acuteLoad;
  double chronicLoad;
  bool hasAcwrData;
  String acwrClassification;
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
    required this.hasAcwrData,
    required this.acwrClassification,
    required this.wellnessStatus,
    required this.injuryRiskCount,
    required this.alerts,
    required this.insights,
    required this.recommendations,
  });

  factory MonitoringDashboard.fromJson(Map<String, dynamic> j) =>
      MonitoringDashboard(
        bodyMetric: j['body_metric'] != null
            ? BodyMetric.fromJson(j['body_metric'])
            : null,
        todayHooper: j['today_hooper'] != null
            ? HooperEntry.fromJson(j['today_hooper'])
            : null,
        lastRpe: j['last_rpe'] != null
            ? RpeEntry.fromJson(j['last_rpe'])
            : null,
        weeklyLoads:
            (j['weekly_loads'] as List?)
                ?.map((value) => (value as num?)?.round())
                .toList() ??
            [],
        readinessScore: j['readiness_score'] as int? ?? 100,
        acwr: (j['acwr'] as num?)?.toDouble() ?? 0,
        acuteLoad: (j['acute_load'] as num?)?.toDouble() ?? 0,
        chronicLoad: (j['chronic_load'] as num?)?.toDouble() ?? 0,
        hasAcwrData: j['acwr'] != null,
        acwrClassification:
            (j['acwr_details'] as Map<String, dynamic>?)?['classification']
                as String? ??
            'INSUFFICIENT_DATA',
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
  bool hasReadinessData;
  bool hasAverageRpeData;
  bool hasWeeklyLoadData;
  double? periodLoad;
  double? periodLoadPreliminary;
  DateTime? rangeFrom;
  DateTime? rangeTo;
  bool hasPeriodLoadData;
  bool hasRecoveryData;
  // Per-player calendar-week Monotony/Strain rows from TrainingLoadCalculator.
  List<PlayerTrainingLoadRow> playersTrainingLoad;
  Map<String, dynamic>? activeSeason;

  TeamWellness({
    required this.teamReadinessScore,
    required this.injuryRiskCount,
    required this.averageRpe,
    required this.weeklyLoad,
    required this.recoveryScore,
    required this.playersNeedingAttention,
    required this.totalCheckedIn,
    this.hasReadinessData = true,
    this.hasAverageRpeData = true,
    this.hasWeeklyLoadData = true,
    this.periodLoad,
    this.periodLoadPreliminary,
    this.rangeFrom,
    this.rangeTo,
    this.hasPeriodLoadData = true,
    this.hasRecoveryData = true,
    this.playersTrainingLoad = const [],
    this.activeSeason,
  });

  factory TeamWellness.fromJson(Map<String, dynamic> j) => TeamWellness(
    teamReadinessScore: (j['team_readiness_score'] as num?)?.round() ?? 0,
    injuryRiskCount: (j['injury_risk_count'] as num?)?.round() ?? 0,
    averageRpe: (j['average_rpe'] as num?)?.toDouble() ?? 0,
    weeklyLoad: (j['weekly_load'] as num?)?.round() ?? 0,
    periodLoad: (j['period_load'] as num?)?.toDouble(),
    periodLoadPreliminary:
        (j['period_load_preliminary'] as num?)?.toDouble(),
    rangeFrom: DateTime.tryParse(
      (j['range'] as Map<String, dynamic>?)?['from']?.toString() ?? '',
    ),
    rangeTo: DateTime.tryParse(
      (j['range'] as Map<String, dynamic>?)?['to']?.toString() ?? '',
    ),
    recoveryScore: (j['recovery_score'] as num?)?.round() ?? 0,
    playersNeedingAttention:
        (j['players_needing_attention'] as num?)?.round() ?? 0,
    totalCheckedIn: (j['total_checked_in'] as num?)?.round() ?? 0,
    hasReadinessData: j['team_readiness_score'] != null,
    hasAverageRpeData: j['average_rpe'] != null,
    hasWeeklyLoadData: j['weekly_load'] != null,
    hasPeriodLoadData: j['period_load'] != null,
    hasRecoveryData: j['recovery_score'] != null,
    playersTrainingLoad: (j['players_training_load'] as List<dynamic>? ?? [])
        .map((r) => PlayerTrainingLoadRow.fromJson(r as Map<String, dynamic>))
        .toList(),
    activeSeason: j['active_season'] as Map<String, dynamic>?,
  );
}

class PlayerWellnessEntry {
  final String id;
  final String name;
  final String playerStatus;
  final int? hooperScore;
  final int? fatigue;
  final double? sleepQuality;
  final double? stress;
  final double? muscleSoreness;
  final double? lastRpe;
  final double? lastLoad;
  final DateTime? submittedAt;
  final String
  wellnessStatus; // 'normal' | 'moderate' | 'high_risk' | 'no_data'
  // Trend direction from backend when available: 'improving' | 'declining' | 'stable' | null.
  // The team-wellness endpoint does not yet return this field; null means no indicator shown.
  final String? trend;

  const PlayerWellnessEntry({
    required this.id,
    required this.name,
    required this.playerStatus,
    this.hooperScore,
    this.fatigue,
    this.lastRpe,
    this.sleepQuality,
    this.stress,
    this.muscleSoreness,
    this.lastLoad,
    this.submittedAt,
    required this.wellnessStatus,
    this.trend,
  });

  factory PlayerWellnessEntry.fromJson(Map<String, dynamic> j) =>
      PlayerWellnessEntry(
        id: j['id']?.toString() ?? '',
        name: j['name'] as String? ?? '',
        playerStatus: j['player_status'] as String? ?? 'active',
        hooperScore: j['hooper_score'] as int?,
        fatigue: j['fatigue'] as int?,
        sleepQuality: (j['sleep_quality'] as num?)?.toDouble(),
        stress: (j['stress'] as num?)?.toDouble(),
        muscleSoreness: (j['muscle_soreness'] as num?)?.toDouble(),
        lastRpe: (j['last_rpe'] as num?)?.toDouble(),
        lastLoad: (j['last_load'] as num?)?.toDouble(),
        submittedAt: j['hooper_at'] != null
            ? DateTime.tryParse(j['hooper_at'].toString())
            : null,
        wellnessStatus: j['wellness_status'] as String? ?? 'no_data',
        trend: j['trend'] as String?, // null when backend omits field
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
  SleepTrendPoint({
    required this.date,
    required this.quality,
    required this.hours,
  });
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
    fatigueTrend:
        (j['fatigue_trend'] as List?)
            ?.map((e) => TrendDataPoint.fromJson(e))
            .toList() ??
        [],
    recoveryTrend:
        (j['recovery_trend'] as List?)
            ?.map((e) => TrendDataPoint.fromJson(e))
            .toList() ??
        [],
    loadTrend:
        (j['load_trend'] as List?)
            ?.map((e) => TrendDataPoint.fromJson(e))
            .toList() ??
        [],
    sleepTrend:
        (j['sleep_trend'] as List?)
            ?.map((e) => SleepTrendPoint.fromJson(e))
            .toList() ??
        [],
    averages: Map<String, double>.from(j['averages'] as Map? ?? {}),
  );
}
