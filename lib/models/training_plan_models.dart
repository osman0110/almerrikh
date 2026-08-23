class TrainingSessionSummary {
  final String id;
  final String? planId;
  final String title;
  final String? description;
  final String sessionDate;
  final int durationMinutes;
  final String objective;
  final String status;
  final bool wellnessRequired;
  final bool rpeRequired;
  final int exerciseCount;
  final int playerCount;
  final int assignedCount;
  final int preCheckedCount;
  final int startedCount;
  final int completedCount;
  final int missedCount;
  final String createdAt;

  const TrainingSessionSummary({
    required this.id,
    this.planId,
    required this.title,
    this.description,
    required this.sessionDate,
    required this.durationMinutes,
    required this.objective,
    required this.status,
    required this.wellnessRequired,
    required this.rpeRequired,
    required this.exerciseCount,
    required this.playerCount,
    required this.assignedCount,
    required this.preCheckedCount,
    required this.startedCount,
    required this.completedCount,
    required this.missedCount,
    required this.createdAt,
  });

  factory TrainingSessionSummary.fromJson(Map<String, dynamic> j) =>
      TrainingSessionSummary(
        id:               j['id'] as String,
        planId:           j['plan_id'] as String?,
        title:            j['title'] as String,
        description:      j['description'] as String?,
        sessionDate:      j['session_date'] as String,
        durationMinutes:  (j['duration_minutes'] as num).toInt(),
        objective:        j['objective'] as String? ?? 'mixed',
        status:           j['status'] as String? ?? 'assigned',
        wellnessRequired: j['wellness_required'] == true || j['wellness_required'] == 1,
        rpeRequired:      j['rpe_required'] == true || j['rpe_required'] == 1,
        exerciseCount:    (j['exercise_count'] as num?)?.toInt() ?? 0,
        playerCount:      (j['player_count'] as num?)?.toInt() ?? 0,
        assignedCount:    (j['assigned_count'] as num?)?.toInt() ?? 0,
        preCheckedCount:  (j['pre_checked_count'] as num?)?.toInt() ?? 0,
        startedCount:     (j['started_count'] as num?)?.toInt() ?? 0,
        completedCount:   (j['completed_count'] as num?)?.toInt() ?? 0,
        missedCount:      (j['missed_count'] as num?)?.toInt() ?? 0,
        createdAt:        j['created_at'] as String? ?? '',
      );

  double get completionRate =>
      playerCount > 0 ? completedCount / playerCount : 0.0;

  int get activeCount => preCheckedCount + startedCount;

  String get objectiveLabel {
    const map = {
      'fitness': 'Fitness', 'football': 'Football',
      'recovery': 'Recovery', 'assessment': 'Assessment', 'mixed': 'Training',
    };
    return map[objective] ?? 'Training';
  }
}

class SessionReportData {
  final String id;
  final String title;
  final String? description;
  final String sessionDate;
  final int durationMinutes;
  final String objective;
  final String status;
  final bool wellnessRequired;
  final bool rpeRequired;
  final List<ReportExercise> exercises;
  final List<PlayerReportRow> players;
  final int totalPlayers;
  final int completedCount;
  final int painAlerts;

  const SessionReportData({
    required this.id,
    required this.title,
    this.description,
    required this.sessionDate,
    required this.durationMinutes,
    required this.objective,
    required this.status,
    required this.wellnessRequired,
    required this.rpeRequired,
    required this.exercises,
    required this.players,
    required this.totalPlayers,
    required this.completedCount,
    required this.painAlerts,
  });

  factory SessionReportData.fromJson(Map<String, dynamic> j) {
    final s = j['session'] as Map<String, dynamic>;
    return SessionReportData(
      id:               s['id'] as String,
      title:            s['title'] as String,
      description:      s['description'] as String?,
      sessionDate:      s['session_date'] as String,
      durationMinutes:  (s['duration_minutes'] as num).toInt(),
      objective:        s['objective'] as String? ?? 'mixed',
      status:           s['status'] as String? ?? 'assigned',
      wellnessRequired: s['wellness_required'] == true || s['wellness_required'] == 1,
      rpeRequired:      s['rpe_required'] == true || s['rpe_required'] == 1,
      exercises: (j['exercises'] as List?)
              ?.map((e) => ReportExercise.fromJson(e as Map<String, dynamic>))
              .toList() ?? [],
      players: (j['players'] as List?)
              ?.map((p) => PlayerReportRow.fromJson(p as Map<String, dynamic>))
              .toList() ?? [],
      totalPlayers:   (j['total_players'] as num?)?.toInt() ?? 0,
      completedCount: (j['completed_count'] as num?)?.toInt() ?? 0,
      painAlerts:     (j['pain_alerts'] as num?)?.toInt() ?? 0,
    );
  }

  double get completionRate =>
      totalPlayers > 0 ? completedCount / totalPlayers : 0.0;
}

class ReportExercise {
  final int id;
  final String exerciseName;
  final String category;
  final int? sets;
  final int? reps;
  final int? durationSeconds;
  final String intensity;
  final bool requiresPoseDetection;
  final int sortOrder;

  const ReportExercise({
    required this.id,
    required this.exerciseName,
    required this.category,
    this.sets,
    this.reps,
    this.durationSeconds,
    required this.intensity,
    required this.requiresPoseDetection,
    required this.sortOrder,
  });

  factory ReportExercise.fromJson(Map<String, dynamic> j) => ReportExercise(
        id:                    (j['id'] as num).toInt(),
        exerciseName:          j['exercise_name'] as String,
        category:              j['category'] as String? ?? 'fitness',
        sets:                  (j['sets'] as num?)?.toInt(),
        reps:                  (j['reps'] as num?)?.toInt(),
        durationSeconds:       (j['duration_seconds'] as num?)?.toInt(),
        intensity:             j['intensity'] as String? ?? 'medium',
        requiresPoseDetection: j['requires_pose_detection'] == true || j['requires_pose_detection'] == 1,
        sortOrder:             (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  String get volumeLabel {
    if (sets != null && reps != null) return '${sets}×${reps}';
    if (durationSeconds != null) {
      final m = durationSeconds! ~/ 60;
      final s = durationSeconds! % 60;
      return m > 0 ? '${m}m ${s}s' : '${s}s';
    }
    return '';
  }
}

class PlayerReportRow {
  final String? linkedPlayerId;
  final String playerName;
  final String position;
  final String playerStatus;
  final String? preCheckAt;
  final String? completedAt;
  final int? hoooperScore;
  final int? preRpe;
  final int? postRpe;
  final bool painReported;
  final String? difficulty;
  final int? moodAfter;

  const PlayerReportRow({
    this.linkedPlayerId,
    required this.playerName,
    required this.position,
    required this.playerStatus,
    this.preCheckAt,
    this.completedAt,
    this.hoooperScore,
    this.preRpe,
    this.postRpe,
    required this.painReported,
    this.difficulty,
    this.moodAfter,
  });

  factory PlayerReportRow.fromJson(Map<String, dynamic> j) => PlayerReportRow(
        linkedPlayerId: j['linked_player_id'] as String?,
        playerName:     j['player_name'] as String? ?? 'Unknown',
        position:       j['position'] as String? ?? '',
        playerStatus:   j['player_status'] as String? ?? 'assigned',
        preCheckAt:     j['pre_check_completed_at'] as String?,
        completedAt:    j['completed_at'] as String?,
        hoooperScore:   (j['hooper_score'] as num?)?.toInt(),
        preRpe:         (j['pre_rpe'] as num?)?.toInt(),
        postRpe:        (j['post_rpe'] as num?)?.toInt(),
        painReported:   j['pain_reported'] == true || j['pain_reported'] == 1,
        difficulty:     j['difficulty'] as String?,
        moodAfter:      (j['mood_after'] as num?)?.toInt(),
      );

  bool get hasCompleted     => playerStatus == 'completed';
  bool get hasPreChecked    => preCheckAt != null;
}

/// Used locally in ManualPlanBuilderScreen
class PlanExercise {
  String exerciseName;
  String category;
  int? sets;
  int? reps;
  int? durationSeconds;
  int? restSeconds;
  String intensity;
  String instructions;
  bool requiresPoseDetection;
  String? assessmentType;

  PlanExercise({
    this.exerciseName = '',
    this.category = 'fitness',
    this.sets,
    this.reps,
    this.durationSeconds,
    this.restSeconds,
    this.intensity = 'medium',
    this.instructions = '',
    this.requiresPoseDetection = false,
    this.assessmentType,
  });

  Map<String, dynamic> toJson(int sortOrder) => {
    'exercise_name':          exerciseName,
    'category':               category,
    if (sets != null)             'sets':             sets,
    if (reps != null)             'reps':             reps,
    if (durationSeconds != null)  'duration_seconds': durationSeconds,
    if (restSeconds != null)      'rest_seconds':     restSeconds,
    'intensity':              intensity,
    if (instructions.isNotEmpty)  'instructions':     instructions,
    'requires_pose_detection': requiresPoseDetection ? 1 : 0,
    if (assessmentType != null)   'assessment_type':  assessmentType,
    'sort_order':             sortOrder,
  };

  String get volumeLabel {
    if (sets != null && reps != null) return '${sets}×${reps}';
    if (durationSeconds != null) return '${durationSeconds}s';
    return '';
  }
}

/// Used locally in ManualPlanBuilderScreen for player selection
class SelectablePlayer {
  final String id;       // club_players.id
  final String name;
  final String position;
  bool selected;

  SelectablePlayer({
    required this.id,
    required this.name,
    required this.position,
    this.selected = false,
  });
}
