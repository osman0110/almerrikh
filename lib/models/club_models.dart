import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum TeamCategory { firstTeam, u23, u20, u17, academy }

extension TeamCategoryExt on TeamCategory {
  String get label {
    switch (this) {
      case TeamCategory.firstTeam: return 'First Team';
      case TeamCategory.u23:       return 'U23';
      case TeamCategory.u20:       return 'U20';
      case TeamCategory.u17:       return 'U17';
      case TeamCategory.academy:   return 'Academy';
    }
  }
  String get labelAr {
    switch (this) {
      case TeamCategory.firstTeam: return 'الفريق الأول';
      case TeamCategory.u23:       return 'تحت 23';
      case TeamCategory.u20:       return 'تحت 20';
      case TeamCategory.u17:       return 'تحت 17';
      case TeamCategory.academy:   return 'الأكاديمية';
    }
  }
  static TeamCategory fromString(String v) => TeamCategory.values
      .firstWhere((e) => e.name == v, orElse: () => TeamCategory.firstTeam);
}

enum PlayerStatus { active, injured, recovering, inactive }

extension PlayerStatusExt on PlayerStatus {
  String get label {
    switch (this) {
      case PlayerStatus.active:     return 'Active';
      case PlayerStatus.injured:    return 'Injured';
      case PlayerStatus.recovering: return 'Recovering';
      case PlayerStatus.inactive:   return 'Inactive';
    }
  }
  String get labelAr {
    switch (this) {
      case PlayerStatus.active:     return 'نشط';
      case PlayerStatus.injured:    return 'مصاب';
      case PlayerStatus.recovering: return 'في التعافي';
      case PlayerStatus.inactive:   return 'غير نشط';
    }
  }
  static PlayerStatus fromString(String v) => PlayerStatus.values
      .firstWhere((e) => e.name == v, orElse: () => PlayerStatus.active);
}

enum SessionType { physicalAssessment, strength, mobility, recovery, injuryPrevention, custom }

extension SessionTypeExt on SessionType {
  String get label {
    switch (this) {
      case SessionType.physicalAssessment:  return 'Physical Assessment';
      case SessionType.strength:            return 'Strength Session';
      case SessionType.mobility:            return 'Mobility Session';
      case SessionType.recovery:            return 'Recovery Session';
      case SessionType.injuryPrevention:   return 'Injury Prevention';
      case SessionType.custom:              return 'Custom';
    }
  }
  static SessionType fromString(String v) => SessionType.values
      .firstWhere((e) => e.name == v, orElse: () => SessionType.custom);
}

enum AssessmentType { squat, singleLegBalance, jumpLanding, lunge, custom }

extension AssessmentTypeExt on AssessmentType {
  String get label {
    switch (this) {
      case AssessmentType.squat:            return 'Squat Assessment';
      case AssessmentType.singleLegBalance: return 'Single Leg Balance';
      case AssessmentType.jumpLanding:      return 'Jump Landing';
      case AssessmentType.lunge:            return 'Lunge Assessment';
      case AssessmentType.custom:           return 'Custom Test';
    }
  }
  static AssessmentType fromString(String v) => AssessmentType.values
      .firstWhere((e) => e.name == v, orElse: () => AssessmentType.custom);
}

// ─────────────────────────────────────────────────────────────────────────────
// ClubTeam
// ─────────────────────────────────────────────────────────────────────────────

class ClubTeam {
  ClubTeam({
    required this.id,
    required this.name,
    required this.category,
    required this.coachName,
    required this.physicalCoachName,
    required this.season,
    this.logoUrl,
    this.notes,
    this.playerIds = const [],
    required this.createdAt,
  });

  final String id;
  String name;
  TeamCategory category;
  String coachName;
  String physicalCoachName;
  String season;
  String? logoUrl;
  String? notes;
  List<String> playerIds;
  DateTime createdAt;

  int get playerCount => playerIds.length;

  factory ClubTeam.fromMap(String id, Map<String, dynamic> m) => ClubTeam(
        id: id,
        name: m['name'] as String? ?? '',
        category: TeamCategoryExt.fromString(m['category'] as String? ?? ''),
        coachName: m['coachName'] as String? ?? '',
        physicalCoachName: m['physicalCoachName'] as String? ?? '',
        season: m['season'] as String? ?? '',
        logoUrl: m['logoUrl'] as String?,
        notes: m['notes'] as String?,
        playerIds: List<String>.from(m['playerIds'] as List? ?? []),
        createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category.name,
        'coachName': coachName,
        'physicalCoachName': physicalCoachName,
        'season': season,
        'logoUrl': logoUrl,
        'notes': notes,
        'playerIds': playerIds,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// ClubPlayer
// ─────────────────────────────────────────────────────────────────────────────

class ClubPlayer {
  ClubPlayer({
    required this.id,
    required this.fullName,
    required this.number,
    required this.position,
    this.dateOfBirth,
    this.height,
    this.weight,
    required this.dominantFoot,
    required this.teamId,
    this.teamName,
    this.nationality = '',
    this.profileImageUrl,
    this.faceImageUrls = const [],
    this.injuryNotes,
    this.physicalNotes,
    this.medicalNotes,
    this.status = PlayerStatus.active,
    this.latestScore,
    this.movementScore,
    this.stabilityScore,
    this.symmetryScore,
    this.controlScore,
    required this.createdAt,
  });

  final String id;
  String fullName;
  String number;
  String position;
  DateTime? dateOfBirth;
  double? height;
  double? weight;
  String dominantFoot;
  String teamId;
  String? teamName;
  String nationality;
  String? profileImageUrl;
  List<String> faceImageUrls;
  String? injuryNotes;
  String? physicalNotes;
  String? medicalNotes;
  PlayerStatus status;
  double? latestScore;
  double? movementScore;
  double? stabilityScore;
  double? symmetryScore;
  double? controlScore;
  DateTime createdAt;

  int get age {
    if (dateOfBirth == null) return 0;
    final now = DateTime.now();
    int age = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month ||
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      age--;
    }
    return age;
  }

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  factory ClubPlayer.fromMap(String id, Map<String, dynamic> m) => ClubPlayer(
        id: id,
        fullName: m['fullName'] as String? ?? '',
        number: m['number'] as String? ?? '',
        position: m['position'] as String? ?? '',
        dateOfBirth: (m['dateOfBirth'] as Timestamp?)?.toDate(),
        height: (m['height'] as num?)?.toDouble(),
        weight: (m['weight'] as num?)?.toDouble(),
        dominantFoot: m['dominantFoot'] as String? ?? 'right',
        teamId: m['teamId'] as String? ?? '',
        teamName: m['teamName'] as String?,
        nationality: m['nationality'] as String? ?? '',
        profileImageUrl: m['profileImageUrl'] as String?,
        faceImageUrls: List<String>.from(m['faceImageUrls'] as List? ?? []),
        injuryNotes: m['injuryNotes'] as String?,
        physicalNotes: m['physicalNotes'] as String?,
        medicalNotes: m['medicalNotes'] as String?,
        status: PlayerStatusExt.fromString(m['status'] as String? ?? 'active'),
        latestScore: (m['latestScore'] as num?)?.toDouble(),
        movementScore: (m['movementScore'] as num?)?.toDouble(),
        stabilityScore: (m['stabilityScore'] as num?)?.toDouble(),
        symmetryScore: (m['symmetryScore'] as num?)?.toDouble(),
        controlScore: (m['controlScore'] as num?)?.toDouble(),
        createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'number': number,
        'position': position,
        'dateOfBirth': dateOfBirth != null ? Timestamp.fromDate(dateOfBirth!) : null,
        'height': height,
        'weight': weight,
        'dominantFoot': dominantFoot,
        'teamId': teamId,
        'teamName': teamName,
        'nationality': nationality,
        'profileImageUrl': profileImageUrl,
        'faceImageUrls': faceImageUrls,
        'injuryNotes': injuryNotes,
        'physicalNotes': physicalNotes,
        'medicalNotes': medicalNotes,
        'status': status.name,
        'latestScore': latestScore,
        'movementScore': movementScore,
        'stabilityScore': stabilityScore,
        'symmetryScore': symmetryScore,
        'controlScore': controlScore,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// TrainingSession
// ─────────────────────────────────────────────────────────────────────────────

class TrainingSession {
  TrainingSession({
    required this.id,
    required this.name,
    required this.date,
    required this.teamId,
    this.teamName,
    required this.type,
    this.location,
    required this.coachName,
    this.notes,
    this.playerIds = const [],
    this.completedPlayerIds = const [],
    this.assessmentCount = 0,
    required this.createdAt,
  });

  final String id;
  String name;
  DateTime date;
  String teamId;
  String? teamName;
  SessionType type;
  String? location;
  String coachName;
  String? notes;
  List<String> playerIds;
  List<String> completedPlayerIds;
  int assessmentCount;
  DateTime createdAt;

  bool get isCompleted => completedPlayerIds.length >= playerIds.length && playerIds.isNotEmpty;
  int get pendingCount => playerIds.length - completedPlayerIds.length;

  factory TrainingSession.fromMap(String id, Map<String, dynamic> m) => TrainingSession(
        id: id,
        name: m['name'] as String? ?? '',
        date: (m['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        teamId: m['teamId'] as String? ?? '',
        teamName: m['teamName'] as String?,
        type: SessionTypeExt.fromString(m['type'] as String? ?? ''),
        location: m['location'] as String?,
        coachName: m['coachName'] as String? ?? '',
        notes: m['notes'] as String?,
        playerIds: List<String>.from(m['playerIds'] as List? ?? []),
        completedPlayerIds: List<String>.from(m['completedPlayerIds'] as List? ?? []),
        assessmentCount: m['assessmentCount'] as int? ?? 0,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'date': Timestamp.fromDate(date),
        'teamId': teamId,
        'teamName': teamName,
        'type': type.name,
        'location': location,
        'coachName': coachName,
        'notes': notes,
        'playerIds': playerIds,
        'completedPlayerIds': completedPlayerIds,
        'assessmentCount': assessmentCount,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// PlayerAssessment
// ─────────────────────────────────────────────────────────────────────────────

class PlayerAssessment {
  PlayerAssessment({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.sessionId,
    required this.sessionName,
    required this.type,
    required this.date,
    required this.movementQualityScore,
    required this.stabilityScore,
    required this.symmetryScore,
    required this.controlScore,
    required this.overallScore,
    this.assessmentQuality = 100,
    this.detectedIssues = const [],
    this.recommendations = const [],
    this.coachNotes,
    this.jointAngles,
    this.snapshots = const [],
  });

  final String id;
  String playerId;
  String playerName;
  String sessionId;
  String sessionName;
  AssessmentType type;
  DateTime date;
  double movementQualityScore;
  double stabilityScore;
  double symmetryScore;
  double controlScore;
  double overallScore;
  double assessmentQuality;
  List<String> detectedIssues;
  List<String> recommendations;
  String? coachNotes;
  Map<String, dynamic>? jointAngles;
  List<String> snapshots;

  factory PlayerAssessment.fromMap(String id, Map<String, dynamic> m) => PlayerAssessment(
        id: id,
        playerId: m['playerId'] as String? ?? '',
        playerName: m['playerName'] as String? ?? '',
        sessionId: m['sessionId'] as String? ?? '',
        sessionName: m['sessionName'] as String? ?? '',
        type: AssessmentTypeExt.fromString(m['type'] as String? ?? ''),
        date: (m['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        movementQualityScore: (m['movementQualityScore'] as num?)?.toDouble() ?? 0,
        stabilityScore: (m['stabilityScore'] as num?)?.toDouble() ?? 0,
        symmetryScore: (m['symmetryScore'] as num?)?.toDouble() ?? 0,
        controlScore: (m['controlScore'] as num?)?.toDouble() ?? 0,
        overallScore: (m['overallScore'] as num?)?.toDouble() ?? 0,
        assessmentQuality: (m['assessmentQuality'] as num?)?.toDouble() ?? 100,
        detectedIssues: List<String>.from(m['detectedIssues'] as List? ?? []),
        recommendations: List<String>.from(m['recommendations'] as List? ?? []),
        coachNotes: m['coachNotes'] as String?,
        jointAngles: m['jointAngles'] as Map<String, dynamic>?,
        snapshots: List<String>.from(m['snapshots'] as List? ?? []),
      );

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'playerName': playerName,
        'sessionId': sessionId,
        'sessionName': sessionName,
        'type': type.name,
        'date': Timestamp.fromDate(date),
        'movementQualityScore': movementQualityScore,
        'stabilityScore': stabilityScore,
        'symmetryScore': symmetryScore,
        'controlScore': controlScore,
        'overallScore': overallScore,
        'assessmentQuality': assessmentQuality,
        'detectedIssues': detectedIssues,
        'recommendations': recommendations,
        'coachNotes': coachNotes,
        'jointAngles': jointAngles,
        'snapshots': snapshots,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// CoachNote
// ─────────────────────────────────────────────────────────────────────────────

class CoachNote {
  CoachNote({
    required this.id,
    required this.playerId,
    required this.authorName,
    required this.text,
    required this.date,
  });

  final String id;
  final String playerId;
  final String authorName;
  String text;
  DateTime date;

  factory CoachNote.fromMap(String id, Map<String, dynamic> m) => CoachNote(
        id: id,
        playerId: m['playerId'] as String? ?? '',
        authorName: m['authorName'] as String? ?? '',
        text: m['text'] as String? ?? '',
        date: (m['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'authorName': authorName,
        'text': text,
        'date': Timestamp.fromDate(date),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// DashboardStats (computed, not persisted)
// ─────────────────────────────────────────────────────────────────────────────

class DashboardStats {
  DashboardStats({
    this.totalPlayers = 0,
    this.activePlayers = 0,
    this.injuredPlayers = 0,
    this.totalTeams = 0,
    this.sessionsToday = 0,
    this.assessmentsToday = 0,
    this.playersNeedingReview = 0,
    this.avgMovementScore = 0,
    this.avgStabilityScore = 0,
  });

  int totalPlayers;
  int activePlayers;
  int injuredPlayers;
  int totalTeams;
  int sessionsToday;
  int assessmentsToday;
  int playersNeedingReview;
  double avgMovementScore;
  double avgStabilityScore;
}
