class AIPlanSummary {
  final String id;
  final String planType;
  final String title;
  final String goal;
  final String status;
  final int? numWeeks;
  final int sessionCount;
  final int completedCount;
  final String? startDate;
  final String? endDate;
  final String? recoveryNotes;
  final String? progressionRules;
  final String createdAt;

  const AIPlanSummary({
    required this.id,
    required this.planType,
    required this.title,
    required this.goal,
    required this.status,
    this.numWeeks,
    required this.sessionCount,
    required this.completedCount,
    this.startDate,
    this.endDate,
    this.recoveryNotes,
    this.progressionRules,
    required this.createdAt,
  });

  factory AIPlanSummary.fromJson(Map<String, dynamic> j) => AIPlanSummary(
        id:               j['id'] as String,
        planType:         j['plan_type'] as String? ?? 'ai',
        title:            j['title'] as String,
        goal:             j['goal'] as String? ?? '',
        status:           j['status'] as String? ?? 'published',
        numWeeks:         (j['num_weeks'] as num?)?.toInt(),
        sessionCount:     (j['session_count'] as num?)?.toInt() ?? 0,
        completedCount:   (j['completed_count'] as num?)?.toInt() ?? 0,
        startDate:        j['start_date'] as String?,
        endDate:          j['end_date'] as String?,
        recoveryNotes:    j['recovery_notes'] as String?,
        progressionRules: j['progression_rules'] as String?,
        createdAt:        j['created_at'] as String? ?? '',
      );

  double get completionRate =>
      sessionCount > 0 ? completedCount / sessionCount : 0.0;
}

class AIPlanDetail {
  final AIPlanSummary plan;
  final List<AIPlanWeek> weeks;
  final int totalSessions;

  const AIPlanDetail({
    required this.plan,
    required this.weeks,
    required this.totalSessions,
  });

  factory AIPlanDetail.fromJson(Map<String, dynamic> j) {
    final planMap = j['plan'] as Map<String, dynamic>;
    return AIPlanDetail(
      plan: AIPlanSummary.fromJson({
        ...planMap,
        'session_count':   j['total_sessions'] ?? 0,
        'completed_count': 0,
      }),
      weeks: (j['weeks'] as List?)
              ?.map((w) => AIPlanWeek.fromJson(w as Map<String, dynamic>))
              .toList() ?? [],
      totalSessions: (j['total_sessions'] as num?)?.toInt() ?? 0,
    );
  }

  // Next session to start (first non-completed assigned/started)
  AIPlanSession? get nextSession {
    for (final week in weeks) {
      for (final s in week.sessions) {
        if (s.playerStatus != 'completed' && s.playerStatus != 'missed') return s;
      }
    }
    return null;
  }
}

class AIPlanWeek {
  final int week;
  final List<AIPlanSession> sessions;

  const AIPlanWeek({required this.week, required this.sessions});

  factory AIPlanWeek.fromJson(Map<String, dynamic> j) => AIPlanWeek(
        week:     (j['week'] as num).toInt(),
        sessions: (j['sessions'] as List?)
                      ?.map((s) => AIPlanSession.fromJson(s as Map<String, dynamic>))
                      .toList() ?? [],
      );

  int get completedCount =>
      sessions.where((s) => s.playerStatus == 'completed').length;
  bool get isComplete => completedCount == sessions.length;
}

class AIPlanSession {
  final String id;
  final String title;
  final String sessionDate;
  final int durationMinutes;
  final String objective;
  final String sessionStatus;
  final String playerStatus;
  final int weekNumber;
  final String intensity;
  final int exerciseCount;

  const AIPlanSession({
    required this.id,
    required this.title,
    required this.sessionDate,
    required this.durationMinutes,
    required this.objective,
    required this.sessionStatus,
    required this.playerStatus,
    required this.weekNumber,
    required this.intensity,
    required this.exerciseCount,
  });

  factory AIPlanSession.fromJson(Map<String, dynamic> j) => AIPlanSession(
        id:             j['id'] as String,
        title:          j['title'] as String,
        sessionDate:    j['session_date'] as String,
        durationMinutes:(j['duration_minutes'] as num).toInt(),
        objective:      j['objective'] as String? ?? 'mixed',
        sessionStatus:  j['session_status'] as String? ?? 'assigned',
        playerStatus:   j['player_status'] as String? ?? 'assigned',
        weekNumber:     (j['week_number'] as num?)?.toInt() ?? 1,
        intensity:      j['intensity'] as String? ?? 'medium',
        exerciseCount:  (j['exercise_count'] as num?)?.toInt() ?? 0,
      );

  bool get isCompleted  => playerStatus == 'completed';
  bool get isStarted    => playerStatus == 'started';
  bool get canStart     => playerStatus == 'pre_checked' || playerStatus == 'assigned';
  bool get isMissed     => playerStatus == 'missed';

  String get objectiveLabel {
    const m = {'fitness':'Fitness','football':'Football',
                'recovery':'Recovery','assessment':'Assessment','mixed':'Training'};
    return m[objective] ?? 'Training';
  }
}

/// Used in IndependentAIPlanScreen form
class AIPlanGenerateRequest {
  final String goal;
  final int availableDays;
  final int preferredDuration;
  final int numWeeks;
  final List<String> equipment;
  final String difficultyPreference;
  final String? injuryLimitations;

  const AIPlanGenerateRequest({
    required this.goal,
    required this.availableDays,
    required this.preferredDuration,
    required this.numWeeks,
    required this.equipment,
    required this.difficultyPreference,
    this.injuryLimitations,
  });

  Map<String, dynamic> toJson() => {
    'goal':                  goal,
    'available_days':        availableDays,
    'preferred_duration':    preferredDuration,
    'num_weeks':             numWeeks,
    'equipment':             equipment,
    'difficulty_preference': difficultyPreference,
    if (injuryLimitations?.isNotEmpty == true)
      'injury_limitations':  injuryLimitations,
  };
}
