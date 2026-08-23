class CoachPlanSummary {
  final String id;
  final String planType;
  final String title;
  final String goal;
  final String status;
  final String? targetType;
  final int numWeeks;
  final String? summary;
  final int sessionCount;
  final String createdAt;

  const CoachPlanSummary({
    required this.id,
    required this.planType,
    required this.title,
    required this.goal,
    required this.status,
    this.targetType,
    required this.numWeeks,
    this.summary,
    required this.sessionCount,
    required this.createdAt,
  });

  factory CoachPlanSummary.fromJson(Map<String, dynamic> j) => CoachPlanSummary(
        id:           j['id']?.toString() ?? '',
        planType:     j['plan_type'] as String? ?? 'manual',
        title:        j['title']    as String? ?? '',
        goal:         j['goal']     as String? ?? '',
        status:       j['status']   as String? ?? 'draft',
        targetType:   j['target_type'] as String?,
        numWeeks:     (j['num_weeks']    as num?)?.toInt() ?? 1,
        summary:      j['summary']  as String?,
        sessionCount: (j['session_count'] as num?)?.toInt() ?? 0,
        createdAt:    j['created_at'] as String? ?? '',
      );
}

class CoachPlanDetail {
  final String id;
  final String planType;
  final String title;
  final String goal;
  final String status;
  final String? targetType;
  final int numWeeks;
  final String? summary;
  final String? recoveryNotes;
  final String? progressionRules;
  final String createdAt;
  final List<CoachPlanPlayer> players;
  final List<CoachPlanWeek> weeks;

  const CoachPlanDetail({
    required this.id,
    required this.planType,
    required this.title,
    required this.goal,
    required this.status,
    this.targetType,
    required this.numWeeks,
    this.summary,
    this.recoveryNotes,
    this.progressionRules,
    required this.createdAt,
    required this.players,
    required this.weeks,
  });

  factory CoachPlanDetail.fromJson(Map<String, dynamic> j) {
    final plan = j['plan'] as Map<String, dynamic>? ?? j;
    return CoachPlanDetail(
      id:               plan['id']?.toString() ?? '',
      planType:         plan['plan_type']   as String? ?? 'manual',
      title:            plan['title']       as String? ?? '',
      goal:             plan['goal']        as String? ?? '',
      status:           plan['status']      as String? ?? 'draft',
      targetType:       plan['target_type'] as String?,
      numWeeks:         (plan['num_weeks']  as num?)?.toInt() ?? 1,
      summary:          plan['summary']     as String?,
      recoveryNotes:    plan['recovery_notes']    as String?,
      progressionRules: plan['progression_rules'] as String?,
      createdAt:        plan['created_at']  as String? ?? '',
      players: (plan['players'] as List?)
              ?.map((e) => CoachPlanPlayer.fromJson(e as Map<String, dynamic>))
              .toList() ?? [],
      weeks: (plan['weeks'] as List?)
              ?.map((e) => CoachPlanWeek.fromJson(e as Map<String, dynamic>))
              .toList() ?? [],
    );
  }
}

class CoachPlanPlayer {
  final String clubPlayerId;
  final String name;
  final String? position;
  const CoachPlanPlayer({required this.clubPlayerId, required this.name, this.position});
  factory CoachPlanPlayer.fromJson(Map<String, dynamic> j) => CoachPlanPlayer(
        clubPlayerId: j['club_player_id']?.toString() ?? '',
        name:         j['name']     as String? ?? '',
        position:     j['position'] as String?,
      );
}

class CoachPlanWeek {
  final int week;
  final List<CoachPlanSession> sessions;
  const CoachPlanWeek({required this.week, required this.sessions});
  factory CoachPlanWeek.fromJson(Map<String, dynamic> j) => CoachPlanWeek(
        week: (j['week'] as num?)?.toInt() ?? 1,
        sessions: (j['sessions'] as List?)
                ?.map((e) => CoachPlanSession.fromJson(e as Map<String, dynamic>))
                .toList() ?? [],
      );
}

class CoachPlanSession {
  final String id;
  final String title;
  final String objective;
  final int durationMinutes;
  final String intensity;
  final String status;
  final String? sessionDate;
  final int exerciseCount;
  final List<CoachPlanExercise> exercises;

  const CoachPlanSession({
    required this.id,
    required this.title,
    required this.objective,
    required this.durationMinutes,
    required this.intensity,
    required this.status,
    this.sessionDate,
    required this.exerciseCount,
    required this.exercises,
  });

  factory CoachPlanSession.fromJson(Map<String, dynamic> j) => CoachPlanSession(
        id:              j['id']?.toString() ?? j['session_id']?.toString() ?? '',
        title:           j['title']           as String? ?? '',
        objective:       j['objective']       as String? ?? 'mixed',
        durationMinutes: (j['duration_minutes'] as num?)?.toInt() ?? 60,
        intensity:       j['intensity']       as String? ?? 'medium',
        status:          j['status']          as String? ?? 'draft',
        sessionDate:     j['session_date']    as String?,
        exerciseCount:   (j['exercise_count'] as num?)?.toInt() ?? 0,
        exercises: (j['exercises'] as List?)
                ?.map((e) => CoachPlanExercise.fromJson(e as Map<String, dynamic>))
                .toList() ?? [],
      );
}

class CoachPlanExercise {
  final String id;
  final String exerciseName;
  final String category;
  final int? sets;
  final int? reps;
  final int? durationSeconds;
  final int? restSeconds;
  final String? instructions;
  final bool requiresPoseDetection;
  final String? assessmentType;

  const CoachPlanExercise({
    required this.id,
    required this.exerciseName,
    required this.category,
    this.sets,
    this.reps,
    this.durationSeconds,
    this.restSeconds,
    this.instructions,
    required this.requiresPoseDetection,
    this.assessmentType,
  });

  factory CoachPlanExercise.fromJson(Map<String, dynamic> j) => CoachPlanExercise(
        id:                     j['id']?.toString() ?? '',
        exerciseName:           j['exercise_name'] as String? ?? '',
        category:               j['category']      as String? ?? 'fitness',
        sets:                   (j['sets']             as num?)?.toInt(),
        reps:                   (j['reps']             as num?)?.toInt(),
        durationSeconds:        (j['duration_seconds'] as num?)?.toInt(),
        restSeconds:            (j['rest_seconds']     as num?)?.toInt(),
        instructions:           j['instructions']  as String?,
        requiresPoseDetection:  j['requires_pose_detection'] == true || j['requires_pose_detection'] == 1,
        assessmentType:         j['assessment_type'] as String?,
      );

  CoachPlanExercise copyWith({
    String? exerciseName,
    int? sets,
    int? reps,
    int? durationSeconds,
    int? restSeconds,
    String? instructions,
  }) => CoachPlanExercise(
        id: id,
        exerciseName:          exerciseName          ?? this.exerciseName,
        category:              category,
        sets:                  sets                  ?? this.sets,
        reps:                  reps                  ?? this.reps,
        durationSeconds:       durationSeconds       ?? this.durationSeconds,
        restSeconds:           restSeconds           ?? this.restSeconds,
        instructions:          instructions          ?? this.instructions,
        requiresPoseDetection: requiresPoseDetection,
        assessmentType:        assessmentType,
      );
}

/// Lightweight model for building the AI plan generation request.
class CoachAIPlanRequest {
  final String targetType;
  final List<String> playerIds;
  final String? teamName;
  final String goal;
  final int durationMinutes;
  final int daysPerWeek;
  final int weeks;
  final String intensityPreference;
  final List<String> equipment;
  final String coachNotes;

  const CoachAIPlanRequest({
    required this.targetType,
    required this.playerIds,
    this.teamName,
    required this.goal,
    required this.durationMinutes,
    required this.daysPerWeek,
    required this.weeks,
    required this.intensityPreference,
    required this.equipment,
    required this.coachNotes,
  });

  Map<String, dynamic> toJson() => {
        'target_type':          targetType,
        'player_ids':           playerIds,
        if (teamName != null)   'team_name': teamName,
        'goal':                 goal,
        'duration_minutes':     durationMinutes,
        'days_per_week':        daysPerWeek,
        'weeks':                weeks,
        'intensity_preference': intensityPreference,
        'equipment':            equipment,
        'coach_notes':          coachNotes,
      };
}
