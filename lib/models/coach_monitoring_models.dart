class CoachDashboardSummary {
  final int totalPlayers;
  final int submittedToday;
  final double averageHooper;
  final double averageRpe;
  final int weeklyTrainingLoad;
  final int highRiskCount;

  const CoachDashboardSummary({
    required this.totalPlayers,
    required this.submittedToday,
    required this.averageHooper,
    required this.averageRpe,
    required this.weeklyTrainingLoad,
    required this.highRiskCount,
  });

  factory CoachDashboardSummary.fromJson(Map<String, dynamic> j) =>
      CoachDashboardSummary(
        totalPlayers: j['total_players'] as int? ?? 0,
        submittedToday: j['submitted_today'] as int? ?? 0,
        averageHooper: (j['average_hooper'] as num?)?.toDouble() ?? 0,
        averageRpe: (j['average_rpe'] as num?)?.toDouble() ?? 0,
        weeklyTrainingLoad: j['weekly_training_load'] as int? ?? 0,
        highRiskCount: j['high_risk_count'] as int? ?? 0,
      );

  static CoachDashboardSummary get empty => const CoachDashboardSummary(
    totalPlayers: 0,
    submittedToday: 0,
    averageHooper: 0,
    averageRpe: 0,
    weeklyTrainingLoad: 0,
    highRiskCount: 0,
  );
}

class CoachPlayerStatus {
  final String id;
  final String name;
  final String status; // 'normal' | 'moderate' | 'high_risk'
  final double? hooperScore;
  final double? rpe;
  final double? trainingLoad;
  final double? bodyFat;
  final int? fmsScore;
  final DateTime? lastUpdated;

  const CoachPlayerStatus({
    required this.id,
    required this.name,
    required this.status,
    required this.hooperScore,
    required this.rpe,
    required this.trainingLoad,
    required this.bodyFat,
    required this.fmsScore,
    this.lastUpdated,
  });

  factory CoachPlayerStatus.fromJson(
    Map<String, dynamic> j,
  ) => CoachPlayerStatus(
    id: j['id']?.toString() ?? '',
    name: j['name'] as String? ?? '',
    // wellness_status (normal/moderate/high_risk) takes precedence; fall back to status
    status: (j['wellness_status'] ?? j['status']) as String? ?? 'normal',
    hooperScore: (j['hooper_score'] as num?)?.toDouble(),
    // post_rpe (PHP field name) or rpe
    rpe: ((j['post_rpe'] ?? j['rpe']) as num?)?.toDouble(),
    trainingLoad: (j['training_load'] as num?)?.toDouble(),
    bodyFat: (j['body_fat'] as num?)?.toDouble(),
    fmsScore: (j['fms_score'] as num?)?.toInt(),
    lastUpdated: j['last_updated'] != null
        ? DateTime.tryParse(j['last_updated'])
        : null,
  );

  /// True only if at least one real wellness metric was actually recorded.
  /// The `status` field defaults to 'normal' server-side even when nothing
  /// was ever submitted for this player — use this to tell a genuinely
  /// "ready" player apart from one with no data at all.
  bool get hasAnyMetric =>
      hooperScore != null ||
      rpe != null ||
      trainingLoad != null ||
      bodyFat != null ||
      fmsScore != null;
}

class CoachAlert {
  final String
  type; // 'missing_check', 'high_fatigue', 'muscle_soreness', 'high_load', 'injury_risk'
  final String playerName;
  final String message;
  final String severity; // 'warning' | 'danger'

  const CoachAlert({
    required this.type,
    required this.playerName,
    required this.message,
    required this.severity,
  });

  factory CoachAlert.fromJson(Map<String, dynamic> j) => CoachAlert(
    type: j['type'] as String? ?? '',
    playerName: j['player_name'] as String? ?? '',
    message: j['message'] as String? ?? '',
    severity: j['severity'] as String? ?? 'warning',
  );
}

class CoachDashboardData {
  final CoachDashboardSummary summary;
  final List<CoachPlayerStatus> players;
  final List<CoachAlert> alerts;

  const CoachDashboardData({
    required this.summary,
    required this.players,
    required this.alerts,
  });

  factory CoachDashboardData.fromJson(Map<String, dynamic> j) =>
      CoachDashboardData(
        summary: j['summary'] != null
            ? CoachDashboardSummary.fromJson(j['summary'])
            : CoachDashboardSummary.empty,
        players:
            (j['players'] as List?)
                ?.map(
                  (e) => CoachPlayerStatus.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
        alerts:
            (j['alerts'] as List?)
                ?.map((e) => CoachAlert.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  static CoachDashboardData get empty => CoachDashboardData(
    summary: CoachDashboardSummary.empty,
    players: [],
    alerts: [],
  );
}

// ── V2 models for the NextKick design-system dashboard ────────────────────────

class TodaySession {
  final String id;
  final String name;
  final String time;
  final String location;
  final int durationMin;
  final int playerCount;

  const TodaySession({
    required this.id,
    required this.name,
    required this.time,
    required this.location,
    required this.durationMin,
    required this.playerCount,
  });

  factory TodaySession.fromJson(Map<String, dynamic> j) => TodaySession(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    time: j['time'] as String? ?? '',
    location: j['location'] as String? ?? '',
    durationMin: j['duration_min'] as int? ?? 90,
    playerCount: j['player_count'] as int? ?? 0,
  );
}

class TeamReadiness {
  final int squadTotal;
  final int readyPct;
  final int ready;
  final int fatigue;
  final int injured;
  final int highRisk;

  const TeamReadiness({
    required this.squadTotal,
    required this.readyPct,
    required this.ready,
    required this.fatigue,
    required this.injured,
    required this.highRisk,
  });

  factory TeamReadiness.fromJson(Map<String, dynamic> j) => TeamReadiness(
    squadTotal: j['squad_total'] as int? ?? 0,
    readyPct: j['ready_pct'] as int? ?? 0,
    ready: j['ready'] as int? ?? 0,
    fatigue: j['fatigue'] as int? ?? 0,
    injured: j['injured'] as int? ?? 0,
    highRisk: j['high_risk'] as int? ?? 0,
  );
}

class CoachAlertV2 {
  final String id;
  final int priority; // 1 = P1 injury, 2 = P2 load, 3 = P3 info
  final String type;
  final String title;
  final String description;
  final int minutesAgo;

  const CoachAlertV2({
    required this.id,
    required this.priority,
    required this.type,
    required this.title,
    required this.description,
    required this.minutesAgo,
  });

  factory CoachAlertV2.fromJson(Map<String, dynamic> j) => CoachAlertV2(
    id: j['id']?.toString() ?? '',
    priority: j['priority'] as int? ?? 3,
    type: j['type'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String? ?? '',
    minutesAgo: j['minutes_ago'] as int? ?? 0,
  );

  String get priorityLabel => 'P$priority';
}

class PlayerStatusV2 {
  final int number;
  final String name;
  final String position;
  final int loadPct;
  final String status; // ready | fatigue | injured | high_risk

  const PlayerStatusV2({
    required this.number,
    required this.name,
    required this.position,
    required this.loadPct,
    required this.status,
  });

  factory PlayerStatusV2.fromJson(Map<String, dynamic> j) => PlayerStatusV2(
    number: j['number'] as int? ?? 0,
    name: j['name'] as String? ?? '',
    position: j['position'] as String? ?? '',
    loadPct: j['load_pct'] as int? ?? 0,
    status: j['status'] as String? ?? 'ready',
  );
}
