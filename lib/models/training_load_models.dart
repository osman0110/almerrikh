import '../app_localizations.dart';

// Models for the Training Load / sRPE / Monotony / Strain report.
// Backed by api/player/training-load/weekly.php — a thin client for
// TrainingLoadCalculator's single source-of-truth math. Do not recompute
// weekly_load/monotony/strain anywhere in Flutter; only display these values.

class TrainingLoadSession {
  final String? sessionId;
  final String? sessionSource;
  final String? sessionType;
  final String? sessionName;
  final double? rpe;
  final int? actualDurationMinutes;
  final double? sessionLoad;
  final String recordStatus;
  final DateTime? lastEditedAt;

  TrainingLoadSession({
    this.sessionId,
    this.sessionSource,
    this.sessionType,
    this.sessionName,
    this.rpe,
    this.actualDurationMinutes,
    this.sessionLoad,
    this.recordStatus = 'original',
    this.lastEditedAt,
  });

  factory TrainingLoadSession.fromJson(Map<String, dynamic> j) =>
      TrainingLoadSession(
        sessionId: j['session_id'] as String?,
        sessionSource: j['session_source'] as String?,
        sessionType: j['session_type'] as String?,
        sessionName: j['session_name'] as String?,
        rpe: (j['rpe'] as num?)?.toDouble(),
        actualDurationMinutes: (j['actual_duration_minutes'] as num?)?.toInt(),
        sessionLoad: (j['session_load'] as num?)?.toDouble(),
        recordStatus: j['record_status'] as String? ?? 'original',
        lastEditedAt: j['last_edited_at'] != null
            ? DateTime.tryParse(j['last_edited_at'].toString())
            : null,
      );
}

class TrainingLoadDay {
  final DateTime date;
  final String dayName;
  final double dailyLoad;
  final String
  participationStatus; // COMPLETE | REST | explicit P0 data-quality status
  final int sessionsCount;
  final List<TrainingLoadSession> sessions;
  final int expectedRecords;
  final int completedRecords;
  final List<String> dataQualityIssues;

  TrainingLoadDay({
    required this.date,
    required this.dayName,
    required this.dailyLoad,
    required this.participationStatus,
    required this.sessionsCount,
    required this.sessions,
    this.expectedRecords = 0,
    this.completedRecords = 0,
    this.dataQualityIssues = const [],
  });

  factory TrainingLoadDay.fromJson(Map<String, dynamic> j) => TrainingLoadDay(
    date: DateTime.parse(j['date'] as String),
    dayName: j['day_name'] as String? ?? '',
    dailyLoad: (j['daily_load'] as num?)?.toDouble() ?? 0.0,
    participationStatus:
        j['participation_status'] as String? ?? 'UNKNOWN_DAY_STATUS',
    sessionsCount: (j['sessions_count'] as num?)?.toInt() ?? 0,
    sessions: (j['sessions'] as List<dynamic>? ?? [])
        .map((s) => TrainingLoadSession.fromJson(s as Map<String, dynamic>))
        .toList(),
    expectedRecords: (j['expected_records'] as num?)?.toInt() ?? 0,
    completedRecords: (j['completed_records'] as num?)?.toInt() ?? 0,
    dataQualityIssues: (j['data_quality_issues'] as List<dynamic>? ?? [])
        .map((value) => value.toString())
        .toList(),
  );
}

class TrainingLoadPreviousWeek {
  final String weekStart;
  final String weekEnd;
  final double weeklyLoad;
  final double? monotony;
  final double? strain;
  final double? changePercent;

  TrainingLoadPreviousWeek({
    required this.weekStart,
    required this.weekEnd,
    required this.weeklyLoad,
    this.monotony,
    this.strain,
    this.changePercent,
  });

  factory TrainingLoadPreviousWeek.fromJson(Map<String, dynamic> j) =>
      TrainingLoadPreviousWeek(
        weekStart: j['week_start'] as String? ?? '',
        weekEnd: j['week_end'] as String? ?? '',
        weeklyLoad: (j['weekly_load'] as num?)?.toDouble() ?? 0.0,
        monotony: (j['monotony'] as num?)?.toDouble(),
        strain: (j['strain'] as num?)?.toDouble(),
        changePercent: (j['change_percent'] as num?)?.toDouble(),
      );
}

class TrainingLoadWeekSummary {
  final String? playerId;
  final String? playerName;
  final String weekStart;
  final String weekEnd;
  final String timezone;
  final String calculationMethodVersion;
  final List<TrainingLoadDay> days;
  final double weeklyLoad;
  final double dailyMean;
  final double standardDeviation;
  final double? monotony;
  final double? strain;
  final dynamic monotonyDisplay; // number, "∞", or null
  final String calculationStatus; // OK | NO_LOAD | CONSTANT_NON_ZERO_LOAD
  final String completenessStatus; // COMPLETE | INCOMPLETE
  final List<dynamic> missingFields;
  final TrainingLoadPreviousWeek? previousWeek;

  TrainingLoadWeekSummary({
    this.playerId,
    this.playerName,
    required this.weekStart,
    required this.weekEnd,
    required this.timezone,
    required this.calculationMethodVersion,
    required this.days,
    required this.weeklyLoad,
    required this.dailyMean,
    required this.standardDeviation,
    this.monotony,
    this.strain,
    this.monotonyDisplay,
    required this.calculationStatus,
    required this.completenessStatus,
    required this.missingFields,
    this.previousWeek,
  });

  bool get isNoLoad => calculationStatus == 'NO_LOAD';
  bool get isConstantLoad => calculationStatus == 'CONSTANT_NON_ZERO_LOAD';
  bool get isIncomplete => completenessStatus == 'INCOMPLETE';

  factory TrainingLoadWeekSummary.fromJson(Map<String, dynamic> j) =>
      TrainingLoadWeekSummary(
        playerId: (j['player'] as Map<String, dynamic>?)?['id'] as String?,
        playerName: (j['player'] as Map<String, dynamic>?)?['name'] as String?,
        weekStart: j['week_start'] as String? ?? '',
        weekEnd: j['week_end'] as String? ?? '',
        timezone: j['timezone'] as String? ?? 'Africa/Kigali',
        calculationMethodVersion:
            j['calculation_method_version'] as String? ?? '',
        days: (j['days'] as List<dynamic>? ?? [])
            .map((d) => TrainingLoadDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        weeklyLoad: (j['weekly_load'] as num?)?.toDouble() ?? 0.0,
        dailyMean: (j['daily_mean'] as num?)?.toDouble() ?? 0.0,
        standardDeviation: (j['standard_deviation'] as num?)?.toDouble() ?? 0.0,
        monotony: (j['monotony'] as num?)?.toDouble(),
        strain: (j['strain'] as num?)?.toDouble(),
        monotonyDisplay: j['monotony_display'],
        calculationStatus: j['calculation_status'] as String? ?? 'NO_LOAD',
        completenessStatus: j['completeness_status'] as String? ?? 'COMPLETE',
        missingFields: j['missing_fields'] as List<dynamic>? ?? [],
        previousWeek: j['previous_week'] != null
            ? TrainingLoadPreviousWeek.fromJson(
                j['previous_week'] as Map<String, dynamic>,
              )
            : null,
      );
}

class PlayerTrainingLoadRow {
  final String playerId;
  final String? playerName;
  final String? position;
  final double weeklyLoad;
  final double dailyMean;
  final double standardDeviation;
  final double? monotony;
  final double? strain;
  final dynamic monotonyDisplay;
  final String calculationStatus;
  final String completenessStatus;
  final List<TrainingLoadDay> days;
  final List<TrainingLoadDay> days28;
  final List<TrainingLoadDay> daysRange;
  final String? teamName;
  final String? playerPhotoUrl;
  final int sessionsCount7d;
  final int totalMinutes7d;
  final double? averageRpe7d;
  final double? load7d;
  final double? load28d;
  final int missingRpeCount;
  final int missingDurationCount;
  final double? dataCompleteness;
  final double? acuteLoad7d;
  final double? chronicLoadWeeklyAverage;
  final double? periodLoadPreliminary;
  final double? periodDataCompleteness;
  final double? acwr;
  final String acwrClassification;

  PlayerTrainingLoadRow({
    required this.playerId,
    this.playerName,
    this.position,
    required this.weeklyLoad,
    required this.dailyMean,
    required this.standardDeviation,
    this.monotony,
    this.strain,
    this.monotonyDisplay,
    required this.calculationStatus,
    required this.completenessStatus,
    this.days = const [],
    this.days28 = const [],
    this.daysRange = const [],
    this.teamName,
    this.playerPhotoUrl,
    this.sessionsCount7d = 0,
    this.totalMinutes7d = 0,
    this.averageRpe7d,
    this.load7d,
    this.load28d,
    this.missingRpeCount = 0,
    this.missingDurationCount = 0,
    this.dataCompleteness,
    this.acuteLoad7d,
    this.chronicLoadWeeklyAverage,
    this.periodLoadPreliminary,
    this.periodDataCompleteness,
    this.acwr,
    this.acwrClassification = 'INSUFFICIENT_DATA',
  });

  factory PlayerTrainingLoadRow.fromJson(Map<String, dynamic> j) =>
      PlayerTrainingLoadRow(
        playerId: j['player_id'] as String? ?? '',
        playerName: j['player_name'] as String?,
        position: j['position'] as String?,
        weeklyLoad: (j['weekly_load'] as num?)?.toDouble() ?? 0.0,
        dailyMean: (j['daily_mean'] as num?)?.toDouble() ?? 0.0,
        standardDeviation: (j['standard_deviation'] as num?)?.toDouble() ?? 0.0,
        monotony: (j['monotony'] as num?)?.toDouble(),
        strain: (j['strain'] as num?)?.toDouble(),
        monotonyDisplay: j['monotony_display'],
        calculationStatus: j['calculation_status'] as String? ?? 'NO_LOAD',
        completenessStatus: j['completeness_status'] as String? ?? 'COMPLETE',
        days: (j['days'] as List<dynamic>? ?? [])
            .map((d) => TrainingLoadDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        days28: (j['days_28'] as List<dynamic>? ?? [])
            .map((d) => TrainingLoadDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        daysRange: (j['days_range'] as List<dynamic>? ?? [])
            .map((d) => TrainingLoadDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        teamName: j['team_name'] as String?,
        playerPhotoUrl: j['player_photo_url'] as String?,
        sessionsCount7d: (j['sessions_count_7d'] as num?)?.toInt() ?? 0,
        totalMinutes7d: (j['total_minutes_7d'] as num?)?.toInt() ?? 0,
        averageRpe7d: (j['average_rpe_7d'] as num?)?.toDouble(),
        load7d: (j['load_7d_preliminary'] as num?)?.toDouble(),
        load28d: (j['load_28d_preliminary'] as num?)?.toDouble(),
        missingRpeCount: (j['missing_rpe_count'] as num?)?.toInt() ?? 0,
        missingDurationCount:
            (j['missing_duration_count'] as num?)?.toInt() ?? 0,
        dataCompleteness: (j['data_completeness'] as num?)?.toDouble(),
        acuteLoad7d: (j['acute_load_7d'] as num?)?.toDouble(),
        chronicLoadWeeklyAverage:
            (j['chronic_load_weekly_average'] as num?)?.toDouble(),
        periodLoadPreliminary:
            (j['period_load_preliminary'] as num?)?.toDouble(),
        periodDataCompleteness:
            (j['period_data_completeness'] as num?)?.toDouble(),
        acwr: (j['acwr'] as num?)?.toDouble(),
        acwrClassification:
            j['acwr_classification'] as String? ?? 'INSUFFICIENT_DATA',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared "selected period" helpers — used by both the on-screen report and
// the exported PDF, so the two always agree on what a chosen period means.
// api/club/team-wellness.php returns the ACWR 7-day/28-day windows plus the
// complete selected daily range, so custom periods are calculated from the
// exact dates the user selected.
// ─────────────────────────────────────────────────────────────────────────────

bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime calendarDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

double? computePeriodLoad(
  PlayerTrainingLoadRow row,
  int periodDays,
  DateTime rangeFrom,
  DateTime rangeTo,
) {
  if (periodDays == 28) return row.load28d;
  if (periodDays == 7) return row.load7d;
  if (periodDays == 1) {
    for (final day in _periodSourceDays(row).reversed) {
      if (isSameCalendarDay(day.date, rangeTo)) return day.dailyLoad;
    }
    return null;
  }
  final from = calendarDateOnly(rangeFrom);
  final to = calendarDateOnly(rangeTo);
  final inRange = _periodSourceDays(row).where((day) {
    final d = calendarDateOnly(day.date);
    return !d.isBefore(from) && !d.isAfter(to);
  });
  if (inRange.isEmpty) return null;
  return inRange.fold<double>(0, (sum, day) => sum + day.dailyLoad);
}

List<TrainingLoadDay> _periodSourceDays(PlayerTrainingLoadRow row) =>
    row.daysRange.isNotEmpty ? row.daysRange : row.days28;

double computePeriodDataCompleteness(
  PlayerTrainingLoadRow row,
  DateTime rangeFrom,
  DateTime rangeTo,
) {
  final from = calendarDateOnly(rangeFrom);
  final to = calendarDateOnly(rangeTo);
  final expectedDays = to.difference(from).inDays + 1;
  if (expectedDays <= 0) return 0;

  final completeDays = trainingLoadDaysInPeriod(
    row,
    rangeFrom,
    rangeTo,
  ).where(isTrainingLoadDayCompleteForPeriod).length;
  return (completeDays / expectedDays).clamp(0.0, 1.0).toDouble();
}

List<TrainingLoadDay> trainingLoadDaysInPeriod(
  PlayerTrainingLoadRow row,
  DateTime rangeFrom,
  DateTime rangeTo,
) {
  final from = calendarDateOnly(rangeFrom);
  final to = calendarDateOnly(rangeTo);
  return _periodSourceDays(row).where((day) {
    final date = calendarDateOnly(day.date);
    return !date.isBefore(from) && !date.isAfter(to);
  }).toList();
}

bool isTrainingLoadDayCompleteForPeriod(TrainingLoadDay day) {
  if (day.dataQualityIssues.isEmpty) return true;
  if (day.expectedRecords != 0) return false;
  const nonTrainingDayStatuses = {
    'HISTORICAL_STATUS_UNKNOWN',
    'UNKNOWN_DAY_STATUS',
  };
  return day.dataQualityIssues.every(nonTrainingDayStatuses.contains);
}

bool isPeriodDataIncomplete(
  PlayerTrainingLoadRow row,
  DateTime rangeFrom,
  DateTime rangeTo,
) =>
    computePeriodDataCompleteness(row, rangeFrom, rangeTo) < 1.0;

String periodLoadLabel(int periodDays) {
  switch (periodDays) {
    case 1:
      return '${AppLocalizations.get('training_load')} — ${AppLocalizations.get('period_today')}';
    case 7:
      return '${AppLocalizations.get('training_load')} — ${AppLocalizations.get('period_7_days')}';
    case 28:
      return '${AppLocalizations.get('training_load')} — ${AppLocalizations.get('period_28_days')}';
    default:
      return '${AppLocalizations.get('training_load')} — ${AppLocalizations.get('period_custom')}';
  }
}
