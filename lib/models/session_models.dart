import 'dart:ui' show Color;

class PlayerSessionData {
  final String id;
  final String title;
  final String? description;
  final int durationMinutes;
  final String objective;
  final String sessionStatus;
  final String playerStatus;
  final bool wellnessRequired;
  final bool rpeRequired;
  final int exerciseCount;
  final List<SessionExercise> exercises;

  const PlayerSessionData({
    required this.id,
    required this.title,
    this.description,
    required this.durationMinutes,
    required this.objective,
    required this.sessionStatus,
    required this.playerStatus,
    required this.wellnessRequired,
    required this.rpeRequired,
    required this.exerciseCount,
    required this.exercises,
  });

  factory PlayerSessionData.fromJson(Map<String, dynamic> j) => PlayerSessionData(
        id:               j['id'] as String,
        title:            j['title'] as String,
        description:      j['description'] as String?,
        durationMinutes:  (j['duration_minutes'] as num).toInt(),
        objective:        j['objective'] as String? ?? 'mixed',
        sessionStatus:    j['session_status'] as String? ?? 'assigned',
        playerStatus:     j['player_status'] as String? ?? 'assigned',
        wellnessRequired: j['wellness_required'] == true || j['wellness_required'] == 1,
        rpeRequired:      j['rpe_required'] == true || j['rpe_required'] == 1,
        exerciseCount:    (j['exercise_count'] as num?)?.toInt() ?? 0,
        exercises:        (j['exercises'] as List?)
                              ?.map((e) => SessionExercise.fromJson(e as Map<String, dynamic>))
                              .toList() ?? [],
      );

  bool get needsPreCheck  => wellnessRequired && playerStatus == 'assigned';
  bool get canStart       => playerStatus == 'pre_checked' ||
                             (!wellnessRequired && playerStatus == 'assigned');
  bool get isStarted      => playerStatus == 'started';
  bool get isCompleted    => playerStatus == 'completed';
  bool get isMissed       => playerStatus == 'missed';

  String get statusLabel {
    switch (playerStatus) {
      case 'assigned':    return wellnessRequired ? 'Pre-check required' : 'Ready to start';
      case 'pre_checked': return 'Ready to start';
      case 'started':     return 'In progress';
      case 'completed':   return 'Completed';
      case 'missed':      return 'Missed';
      default:            return 'Assigned';
    }
  }

  String get objectiveLabel {
    const labels = {
      'fitness': 'Fitness', 'football': 'Football',
      'recovery': 'Recovery', 'assessment': 'Assessment', 'mixed': 'Training',
    };
    return labels[objective] ?? 'Training';
  }
}

class SessionExercise {
  final int id;
  final String exerciseName;
  final String category;
  final int? sets;
  final int? reps;
  final int? durationSeconds;
  final int? restSeconds;
  final String intensity;
  final String? instructions;
  final String? videoUrl;
  final bool requiresPoseDetection;
  final String? assessmentType;
  final int sortOrder;

  const SessionExercise({
    required this.id,
    required this.exerciseName,
    required this.category,
    this.sets,
    this.reps,
    this.durationSeconds,
    this.restSeconds,
    required this.intensity,
    this.instructions,
    this.videoUrl,
    required this.requiresPoseDetection,
    this.assessmentType,
    required this.sortOrder,
  });

  factory SessionExercise.fromJson(Map<String, dynamic> j) => SessionExercise(
        id:                    (j['id'] as num).toInt(),
        exerciseName:          j['exercise_name'] as String,
        category:              j['category'] as String? ?? 'fitness',
        sets:                  (j['sets'] as num?)?.toInt(),
        reps:                  (j['reps'] as num?)?.toInt(),
        durationSeconds:       (j['duration_seconds'] as num?)?.toInt(),
        restSeconds:           (j['rest_seconds'] as num?)?.toInt(),
        intensity:             j['intensity'] as String? ?? 'medium',
        instructions:          j['instructions'] as String?,
        videoUrl:              j['video_url'] as String?,
        requiresPoseDetection: j['requires_pose_detection'] == true || j['requires_pose_detection'] == 1,
        assessmentType:        j['assessment_type'] as String?,
        sortOrder:             (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  String get volumeLabel {
    if (sets != null && reps != null) return '${sets}x${reps}';
    if (durationSeconds != null) {
      final m = durationSeconds! ~/ 60;
      final s = durationSeconds! % 60;
      return m > 0 ? '${m}m ${s}s' : '${s}s';
    }
    return '';
  }
}

class SessionCompletionData {
  final String sessionId;
  final String sessionTitle;
  final int? hoooperScore;
  final int? preRpe;
  final int postRpe;
  final String? difficulty;
  final bool painReported;
  final int? moodAfter;
  final int trainingLoad;
  final int durationMinutes;

  const SessionCompletionData({
    required this.sessionId,
    required this.sessionTitle,
    this.hoooperScore,
    this.preRpe,
    required this.postRpe,
    this.difficulty,
    required this.painReported,
    this.moodAfter,
    required this.trainingLoad,
    required this.durationMinutes,
  });

  String get recommendation {
    if (hoooperScore != null && hoooperScore! >= 17) return 'Recovery recommended — high fatigue detected.';
    if (painReported) return 'Pain reported. Your coach will review this.';
    if (postRpe >= 8) return 'High effort recorded. Consider lighter intensity next session.';
    return 'Great work. Session completed successfully.';
  }

  Color get recommendationColor {
    if (hoooperScore != null && hoooperScore! >= 17) return const Color(0xffef4444);
    if (painReported) return const Color(0xffef4444);
    if (postRpe >= 8) return const Color(0xfff59e0b);
    return const Color(0xff22C55E);
  }
}
