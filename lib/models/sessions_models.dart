import 'package:flutter/material.dart';
import '../app_localizations.dart';

int _jsonInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum SessionType {
  team_training,
  tactical,
  technical,
  fitness,
  strength_gym,
  speed_agility,
  recovery,
  swimming,
  rehab,
  ai_analysis,
  performance_test,
  goalkeeper,
  position_specific,
  individual,
  video_analysis,
  classroom,
  match,
  pre_match_activation,
  post_match_recovery,
  medical_check,
}

enum SessionScope     { team, group, individual }
enum SessionStatus    { scheduled, active, completed, cancelled }
enum SessionIntensity { low, medium, high, recovery }

// ── Label helpers ─────────────────────────────────────────────────────────────

String getSessionTypeLabel(SessionType t) {
  const map = {
    SessionType.team_training:        'session_type_team_training',
    SessionType.tactical:             'session_type_tactical',
    SessionType.technical:            'session_type_technical',
    SessionType.fitness:              'session_type_fitness',
    SessionType.strength_gym:         'session_type_strength_gym',
    SessionType.speed_agility:        'session_type_speed_agility',
    SessionType.recovery:             'session_type_recovery',
    SessionType.swimming:             'session_type_swimming',
    SessionType.rehab:                'session_type_rehab',
    SessionType.ai_analysis:          'session_type_ai_analysis',
    SessionType.performance_test:     'session_type_performance_test',
    SessionType.goalkeeper:           'session_type_goalkeeper',
    SessionType.position_specific:    'session_type_position_specific',
    SessionType.individual:           'session_type_individual',
    SessionType.video_analysis:       'session_type_video_analysis',
    SessionType.classroom:            'session_type_classroom',
    SessionType.match:                'session_type_match',
    SessionType.pre_match_activation: 'session_type_pre_match_activation',
    SessionType.post_match_recovery:  'session_type_post_match_recovery',
    SessionType.medical_check:        'session_type_medical_check',
  };
  final key = map[t];
  return key == null ? t.name : AppLocalizations.get(key);
}

IconData getSessionTypeIcon(SessionType t) {
  switch (t) {
    case SessionType.tactical:             return Icons.psychology_rounded;
    case SessionType.swimming:             return Icons.pool_rounded;
    case SessionType.strength_gym:         return Icons.fitness_center_rounded;
    case SessionType.ai_analysis:          return Icons.auto_awesome_rounded;
    case SessionType.recovery:             return Icons.self_improvement_rounded;
    case SessionType.rehab:                return Icons.medical_services_rounded;
    case SessionType.goalkeeper:           return Icons.sports_rounded;
    case SessionType.match:                return Icons.sports_soccer_rounded;
    case SessionType.team_training:        return Icons.groups_rounded;
    case SessionType.technical:            return Icons.sports_soccer_rounded;
    case SessionType.fitness:              return Icons.directions_run_rounded;
    case SessionType.speed_agility:        return Icons.bolt_rounded;
    case SessionType.performance_test:     return Icons.speed_rounded;
    case SessionType.position_specific:    return Icons.people_rounded;
    case SessionType.individual:           return Icons.person_rounded;
    case SessionType.video_analysis:       return Icons.videocam_rounded;
    case SessionType.classroom:            return Icons.school_rounded;
    case SessionType.pre_match_activation: return Icons.flash_on_rounded;
    case SessionType.post_match_recovery:  return Icons.healing_rounded;
    case SessionType.medical_check:        return Icons.local_hospital_rounded;
  }
}

Color getSessionTypeColor(SessionType t) {
  switch (t) {
    case SessionType.tactical:             return const Color(0xff1A6BEB);
    case SessionType.swimming:             return const Color(0xff0891B2);
    case SessionType.strength_gym:         return const Color(0xffF2B23B);
    case SessionType.ai_analysis:          return const Color(0xff5C7C2E);
    case SessionType.recovery:             return const Color(0xff0891B2);
    case SessionType.rehab:                return const Color(0xffF2B23B);
    case SessionType.goalkeeper:           return const Color(0xff2DBF6C);
    case SessionType.match:                return const Color(0xffF97316);
    case SessionType.team_training:        return const Color(0xff5C7C2E);
    case SessionType.technical:            return const Color(0xff8B5CF6);
    case SessionType.fitness:              return const Color(0xffF2B23B);
    case SessionType.speed_agility:        return const Color(0xffF97316);
    case SessionType.performance_test:     return const Color(0xffF2B23B);
    case SessionType.position_specific:    return const Color(0xff2DBF6C);
    case SessionType.individual:           return const Color(0xff8B5CF6);
    case SessionType.video_analysis:       return const Color(0xff1A6BEB);
    case SessionType.classroom:            return const Color(0xff1A6BEB);
    case SessionType.pre_match_activation: return const Color(0xffF2B23B);
    case SessionType.post_match_recovery:  return const Color(0xff0891B2);
    case SessionType.medical_check:        return const Color(0xffF2B23B);
  }
}

String getSessionScopeLabel(SessionScope s) {
  switch (s) {
    case SessionScope.team:       return AppLocalizations.get('session_scope_team');
    case SessionScope.group:      return AppLocalizations.get('session_scope_group');
    case SessionScope.individual: return AppLocalizations.get('session_scope_individual');
  }
}

String getSessionStatusLabel(SessionStatus s) {
  switch (s) {
    case SessionStatus.scheduled:  return AppLocalizations.get('session_status_scheduled');
    case SessionStatus.active:     return AppLocalizations.get('session_status_active');
    case SessionStatus.completed:  return AppLocalizations.get('session_status_completed');
    case SessionStatus.cancelled:  return AppLocalizations.get('session_status_cancelled');
  }
}

String getSessionIntensityLabel(SessionIntensity i) {
  switch (i) {
    case SessionIntensity.low:      return AppLocalizations.get('session_intensity_low');
    case SessionIntensity.medium:   return AppLocalizations.get('session_intensity_medium');
    case SessionIntensity.high:     return AppLocalizations.get('session_intensity_high');
    case SessionIntensity.recovery: return AppLocalizations.get('session_intensity_recovery');
  }
}

Color getSessionStatusColor(SessionStatus s) {
  switch (s) {
    case SessionStatus.scheduled:  return const Color(0xff6F7368);
    case SessionStatus.active:     return const Color(0xff5C7C2E);
    case SessionStatus.completed:  return const Color(0xff2DBF6C);
    case SessionStatus.cancelled:  return const Color(0xffFF4D2E); // red only for cancelled
  }
}

Color getSessionIntensityColor(SessionIntensity i) {
  switch (i) {
    case SessionIntensity.low:      return const Color(0xff2DBF6C);
    case SessionIntensity.medium:   return const Color(0xffF2B23B);
    case SessionIntensity.high:     return const Color(0xffF97316); // orange, NOT red
    case SessionIntensity.recovery: return const Color(0xff0891B2);
  }
}

// ── SessionModel ──────────────────────────────────────────────────────────────

class SessionModel {
  final String id;
  final String title;
  final SessionType type;
  final SessionScope scope;
  final SessionStatus status;
  final String date;         // 'YYYY-MM-DD'
  final String startTime;    // 'HH:MM'
  final String? endTime;
  final int durationMin;
  final String location;
  final int playerCount;
  final SessionIntensity intensity;
  final bool aiEnabled;
  final bool exerciseLibraryEnabled;
  final bool attendanceRequired;
  final bool rpeRequired;
  final bool wellnessRequired;
  final String? coachName;
  final String? notes;

  const SessionModel({
    required this.id,
    required this.title,
    required this.type,
    required this.scope,
    required this.status,
    required this.date,
    required this.startTime,
    this.endTime,
    required this.durationMin,
    required this.location,
    required this.playerCount,
    required this.intensity,
    required this.aiEnabled,
    required this.exerciseLibraryEnabled,
    required this.attendanceRequired,
    required this.rpeRequired,
    required this.wellnessRequired,
    this.coachName,
    this.notes,
  });

  factory SessionModel.fromJson(Map<String, dynamic> j) => SessionModel(
    id: j['id']?.toString() ?? '',
    title: j['title'] as String? ?? '',
    type: SessionType.values.firstWhere(
        (e) => e.name == j['type'], orElse: () => SessionType.team_training),
    scope: SessionScope.values.firstWhere(
        (e) => e.name == j['scope'], orElse: () => SessionScope.team),
    status: SessionStatus.values.firstWhere(
        (e) => e.name == j['status'], orElse: () => SessionStatus.scheduled),
    date: j['date'] as String? ?? '',
    startTime: j['start_time'] as String? ?? '',
    endTime: j['end_time'] as String?,
    durationMin: _jsonInt(j['duration_min'], 90),
    location: j['location'] as String? ?? '',
    playerCount: _jsonInt(j['player_count']),
    intensity: SessionIntensity.values.firstWhere(
        (e) => e.name == j['intensity'], orElse: () => SessionIntensity.medium),
    aiEnabled: j['ai_enabled'] as bool? ?? false,
    exerciseLibraryEnabled: j['exercise_library_enabled'] as bool? ?? false,
    attendanceRequired: j['attendance_required'] as bool? ?? true,
    rpeRequired: j['rpe_required'] as bool? ?? false,
    wellnessRequired: j['wellness_required'] as bool? ?? false,
    coachName: j['coach']?['name'] as String?,
    notes: j['notes'] as String?,
  );

  bool get isToday {
    final today = DateTime.now();
    final parts = date.split('-');
    if (parts.length != 3) return false;
    return int.tryParse(parts[0]) == today.year &&
        int.tryParse(parts[1]) == today.month &&
        int.tryParse(parts[2]) == today.day;
  }

  SessionModel copyWith({SessionStatus? status}) => SessionModel(
    id: id, title: title, type: type, scope: scope,
    status: status ?? this.status, date: date, startTime: startTime,
    endTime: endTime, durationMin: durationMin, location: location,
    playerCount: playerCount, intensity: intensity, aiEnabled: aiEnabled,
    exerciseLibraryEnabled: exerciseLibraryEnabled,
    attendanceRequired: attendanceRequired, rpeRequired: rpeRequired,
    wellnessRequired: wellnessRequired, coachName: coachName, notes: notes,
  );

  // ── Mock data ──────────────────────────────────────────────────────────────
  static const List<SessionModel> mockList = [
    SessionModel(
      id: 'sess-001',
      title: 'تدريب القوة والسرعة',
      type: SessionType.fitness,
      scope: SessionScope.team,
      status: SessionStatus.active,
      date: '2026-05-15',
      startTime: '10:30',
      endTime: '12:00',
      durationMin: 90,
      location: 'ملعب المريخ الرئيسي',
      playerCount: 18,
      intensity: SessionIntensity.high,
      aiEnabled: false,
      exerciseLibraryEnabled: true,
      attendanceRequired: true,
      rpeRequired: true,
      wellnessRequired: false,
      coachName: 'كوتش',
    ),
    SessionModel(
      id: 'sess-002',
      title: 'تدريب تكتيكي — الضغط العالي',
      type: SessionType.tactical,
      scope: SessionScope.team,
      status: SessionStatus.scheduled,
      date: '2026-05-15',
      startTime: '16:00',
      endTime: '17:30',
      durationMin: 90,
      location: 'ملعب المريخ الرئيسي',
      playerCount: 20,
      intensity: SessionIntensity.medium,
      aiEnabled: false,
      exerciseLibraryEnabled: false,
      attendanceRequired: true,
      rpeRequired: false,
      wellnessRequired: false,
      coachName: 'كوتش',
    ),
    SessionModel(
      id: 'sess-003',
      title: 'تحليل هيكلي — Squat & Jump',
      type: SessionType.ai_analysis,
      scope: SessionScope.group,
      status: SessionStatus.scheduled,
      date: '2026-05-16',
      startTime: '09:00',
      endTime: '10:30',
      durationMin: 90,
      location: 'استوديو التحليل',
      playerCount: 6,
      intensity: SessionIntensity.low,
      aiEnabled: true,
      exerciseLibraryEnabled: false,
      attendanceRequired: true,
      rpeRequired: false,
      wellnessRequired: false,
      coachName: 'كوتش',
    ),
    SessionModel(
      id: 'sess-004',
      title: 'تأهيل — أحمد كمال (إصابة ركبة)',
      type: SessionType.rehab,
      scope: SessionScope.individual,
      status: SessionStatus.scheduled,
      date: '2026-05-15',
      startTime: '14:00',
      endTime: '15:00',
      durationMin: 60,
      location: 'غرفة التأهيل',
      playerCount: 1,
      intensity: SessionIntensity.low,
      aiEnabled: false,
      exerciseLibraryEnabled: true,
      attendanceRequired: false,
      rpeRequired: true,
      wellnessRequired: true,
      coachName: 'كوتش',
    ),
    SessionModel(
      id: 'sess-005',
      title: 'سباحة استشفائية',
      type: SessionType.swimming,
      scope: SessionScope.team,
      status: SessionStatus.completed,
      date: '2026-05-14',
      startTime: '08:00',
      endTime: '09:00',
      durationMin: 60,
      location: 'المسبح',
      playerCount: 15,
      intensity: SessionIntensity.recovery,
      aiEnabled: false,
      exerciseLibraryEnabled: false,
      attendanceRequired: true,
      rpeRequired: true,
      wellnessRequired: false,
      coachName: 'كوتش',
    ),
    SessionModel(
      id: 'sess-006',
      title: 'Sprint 10m / 30m — اختبار السرعة',
      type: SessionType.performance_test,
      scope: SessionScope.team,
      status: SessionStatus.completed,
      date: '2026-05-13',
      startTime: '10:00',
      endTime: '12:00',
      durationMin: 120,
      location: 'ملعب المريخ الرئيسي',
      playerCount: 22,
      intensity: SessionIntensity.high,
      aiEnabled: false,
      exerciseLibraryEnabled: false,
      attendanceRequired: true,
      rpeRequired: true,
      wellnessRequired: false,
      coachName: 'كوتش',
    ),
    SessionModel(
      id: 'sess-007',
      title: 'تدريب سرعة ورشاقة',
      type: SessionType.speed_agility,
      scope: SessionScope.team,
      status: SessionStatus.scheduled,
      date: '2026-05-17',
      startTime: '17:00',
      endTime: '18:00',
      durationMin: 60,
      location: 'ملعب المريخ الرئيسي',
      playerCount: 18,
      intensity: SessionIntensity.high,
      aiEnabled: true,
      exerciseLibraryEnabled: true,
      attendanceRequired: true,
      rpeRequired: true,
      wellnessRequired: false,
      coachName: 'كوتش',
    ),
  ];
}

// ── SessionsSummary ───────────────────────────────────────────────────────────

class SessionsSummary {
  final int today;
  final int active;
  final int individual;
  final int aiEnabled;

  const SessionsSummary({
    required this.today,
    required this.active,
    required this.individual,
    required this.aiEnabled,
  });

  factory SessionsSummary.fromSessions(List<SessionModel> sessions) =>
      SessionsSummary(
        today:      sessions.where((s) => s.isToday).length,
        active:     sessions.where((s) => s.status == SessionStatus.active).length,
        individual: sessions.where((s) => s.scope == SessionScope.individual).length,
        aiEnabled:  sessions.where((s) => s.aiEnabled).length,
      );

  factory SessionsSummary.fromJson(Map<String, dynamic> j) => SessionsSummary(
    today:      j['today'] as int? ?? 0,
    active:     j['active'] as int? ?? 0,
    individual: j['individual'] as int? ?? 0,
    aiEnabled:  j['ai'] as int? ?? 0,
  );
}

// ── SessionParticipant ────────────────────────────────────────────────────────

class SessionParticipant {
  final String id;
  final int number;
  final String name;
  final String position;
  final String attendanceStatus; // 'present' | 'absent' | 'late' | 'pending'
  final String playerStatus;     // 'ready' | 'fatigue' | 'injured' | 'high_risk'
  final int loadScore;

  const SessionParticipant({
    required this.id,
    required this.number,
    required this.name,
    required this.position,
    required this.attendanceStatus,
    required this.playerStatus,
    required this.loadScore,
  });

  factory SessionParticipant.fromJson(Map<String, dynamic> j) => SessionParticipant(
    id: j['id']?.toString() ?? '',
    number: j['number'] as int? ?? 0,
    name: j['name'] as String? ?? '',
    position: j['position'] as String? ?? '',
    attendanceStatus: j['attendance_status'] as String? ?? 'pending',
    playerStatus: j['player_status'] as String? ?? 'ready',
    loadScore: j['hooper_score'] as int? ?? 0,
  );

  SessionParticipant copyWith({String? attendanceStatus}) => SessionParticipant(
    id: id, number: number, name: name, position: position,
    attendanceStatus: attendanceStatus ?? this.attendanceStatus,
    playerStatus: playerStatus, loadScore: loadScore,
  );

  String get attendanceLabel {
    switch (attendanceStatus) {
      case 'present': return 'حاضر';
      case 'absent':  return 'غائب';
      case 'late':    return 'متأخر';
      default:        return 'لم يبدأ';
    }
  }

  Color get attendanceColor {
    switch (attendanceStatus) {
      case 'present': return const Color(0xff2DBF6C);
      case 'absent':  return const Color(0xffFF4D2E);
      case 'late':    return const Color(0xffF2B23B);
      default:        return const Color(0xff6F7368);
    }
  }

  static const List<SessionParticipant> mockList = [
    SessionParticipant(id: 'p1', number: 10, name: 'أحمد كمال',     position: 'ST', attendanceStatus: 'present', playerStatus: 'ready',     loadScore: 72),
    SessionParticipant(id: 'p2', number:  7, name: 'محمد علي',      position: 'CM', attendanceStatus: 'present', playerStatus: 'fatigue',   loadScore: 81),
    SessionParticipant(id: 'p3', number:  4, name: 'إبراهيم حسن',   position: 'CB', attendanceStatus: 'late',    playerStatus: 'ready',     loadScore: 58),
    SessionParticipant(id: 'p4', number:  9, name: 'خالد عمر',      position: 'ST', attendanceStatus: 'pending', playerStatus: 'ready',     loadScore: 45),
    SessionParticipant(id: 'p5', number:  3, name: 'عبدالله محمود', position: 'LB', attendanceStatus: 'pending', playerStatus: 'high_risk', loadScore: 90),
  ];
}

// ── SessionExercise ───────────────────────────────────────────────────────────

class SessionExercise {
  final String id;
  final String name;
  final String category;
  final int sets;
  final int reps;
  final int durationSec;
  final int restSec;
  final String intensity;
  final bool aiTrackable;

  const SessionExercise({
    required this.id,
    required this.name,
    required this.category,
    required this.sets,
    required this.reps,
    required this.durationSec,
    required this.restSec,
    required this.intensity,
    required this.aiTrackable,
  });

  static const List<SessionExercise> mockList = [
    SessionExercise(id: 'ex1', name: 'Back Squat', category: 'قوة',       sets: 4, reps: 8,  durationSec: 0,   restSec: 90,  intensity: 'high',   aiTrackable: true),
    SessionExercise(id: 'ex2', name: 'Sprint 30m',  category: 'سرعة',      sets: 6, reps: 1,  durationSec: 0,   restSec: 120, intensity: 'high',   aiTrackable: false),
    SessionExercise(id: 'ex3', name: 'Plank',        category: 'core',      sets: 3, reps: 0,  durationSec: 60,  restSec: 45,  intensity: 'medium', aiTrackable: false),
    SessionExercise(id: 'ex4', name: 'CMJ',           category: 'قفز',       sets: 3, reps: 5,  durationSec: 0,   restSec: 60,  intensity: 'high',   aiTrackable: true),
  ];
}

// ── SessionAIAnalysis ─────────────────────────────────────────────────────────

class SessionAIAnalysis {
  final String id;
  final String sessionId;
  final String analysisType;
  final String status; // 'pending' | 'in_progress' | 'completed' | 'needs_review'
  final double? score;
  final String? reportUrl;
  final bool reviewedByCoach;

  const SessionAIAnalysis({
    required this.id,
    required this.sessionId,
    required this.analysisType,
    required this.status,
    this.score,
    this.reportUrl,
    required this.reviewedByCoach,
  });

  String get analysisLabel {
    const map = {
      'squat':         'Squat Assessment',
      'jump_landing':  'Jump Landing',
      'cmj':           'Countermovement Jump',
      'drop_jump':     'Drop Jump',
      'sprint':        'Sprint Mechanics',
      'balance':       'Balance Control',
      'mobility':      'Mobility Screening',
      'knee':          'Knee Alignment',
    };
    return map[analysisType] ?? analysisType;
  }

  String get statusLabel {
    switch (status) {
      case 'pending':      return 'لم يبدأ';
      case 'in_progress':  return 'جاري';
      case 'completed':    return 'مكتمل';
      case 'needs_review': return 'يحتاج مراجعة';
      default:             return status;
    }
  }
}
