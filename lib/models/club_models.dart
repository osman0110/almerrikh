import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_localizations.dart';

int _jsonInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum TeamCategory { firstTeam, reserve, u23, u20, u17, academy }

extension TeamCategoryExt on TeamCategory {
  String get label {
    switch (this) {
      case TeamCategory.firstTeam:
        return 'First Team';
      case TeamCategory.reserve:
        return 'Reserve Team';
      case TeamCategory.u23:
        return 'U23';
      case TeamCategory.u20:
        return 'U20';
      case TeamCategory.u17:
        return 'U17';
      case TeamCategory.academy:
        return 'Academy';
    }
  }

  String get labelAr {
    switch (this) {
      case TeamCategory.firstTeam:
        return 'الفريق الأول';
      case TeamCategory.reserve:
        return 'الرديف';
      case TeamCategory.u23:
        return 'تحت 23';
      case TeamCategory.u20:
        return 'تحت 20';
      case TeamCategory.u17:
        return 'تحت 17';
      case TeamCategory.academy:
        return 'الأكاديمية';
    }
  }

  static TeamCategory fromString(String v) => TeamCategory.values.firstWhere(
    (e) => e.name == v,
    orElse: () => TeamCategory.firstTeam,
  );
}

enum PlayerStatus { active, injured, recovering, inactive, suspended }

extension PlayerStatusExt on PlayerStatus {
  String get label {
    switch (this) {
      case PlayerStatus.active:
        return 'Available';
      case PlayerStatus.injured:
        return 'Injured';
      case PlayerStatus.recovering:
        return 'Recovering';
      case PlayerStatus.inactive:
        return 'Unavailable';
      case PlayerStatus.suspended:
        return 'Suspended';
    }
  }

  String get labelAr {
    switch (this) {
      case PlayerStatus.active:
        return 'جاهز';
      case PlayerStatus.injured:
        return 'مصاب';
      case PlayerStatus.recovering:
        return 'في التعافي';
      case PlayerStatus.inactive:
        return 'غير متاح';
      case PlayerStatus.suspended:
        return 'موقوف';
    }
  }

  /// Label localized to the app's current language (en/ar/fr).
  String get localizedLabel => AppLocalizations.get('roster_status_$name');

  static PlayerStatus fromString(String v) => PlayerStatus.values.firstWhere(
    (e) => e.name == v,
    orElse: () => PlayerStatus.active,
  );
}

enum SessionType {
  physicalAssessment,
  strength,
  mobility,
  recovery,
  injuryPrevention,
  custom,
  // Extended types
  teamTraining,
  tactical,
  technical,
  fitness,
  speedAgility,
  goalkeeper,
  positionSpecific,
  individual,
  rehab,
  match,
  preMatch,
  postMatch,
}

extension SessionTypeExt on SessionType {
  String get label {
    const keys = {
      SessionType.physicalAssessment: 'club_session_type_physical_assessment',
      SessionType.strength: 'club_session_type_strength',
      SessionType.mobility: 'club_session_type_mobility',
      SessionType.recovery: 'club_session_type_recovery',
      SessionType.injuryPrevention: 'club_session_type_injury_prevention',
      SessionType.custom: 'club_session_type_custom',
      SessionType.teamTraining: 'club_session_type_team_training',
      SessionType.tactical: 'club_session_type_tactical',
      SessionType.technical: 'club_session_type_technical',
      SessionType.fitness: 'club_session_type_fitness',
      SessionType.speedAgility: 'club_session_type_speed_agility',
      SessionType.goalkeeper: 'club_session_type_goalkeeper',
      SessionType.positionSpecific: 'club_session_type_position_specific',
      SessionType.individual: 'club_session_type_individual',
      SessionType.rehab: 'club_session_type_rehab',
      SessionType.match: 'club_session_type_match',
      SessionType.preMatch: 'club_session_type_pre_match',
      SessionType.postMatch: 'club_session_type_post_match',
    };
    final key = keys[this];
    return key != null ? AppLocalizations.get(key) : name;
  }

  static SessionType fromString(String v) {
    // Handle sessions_models.dart enum names as well
    const aliases = <String, SessionType>{
      'team_training': SessionType.teamTraining,
      'speed_agility': SessionType.speedAgility,
      'position_specific': SessionType.positionSpecific,
      'pre_match_activation': SessionType.preMatch,
      'post_match_recovery': SessionType.postMatch,
      'strength_gym': SessionType.strength,
      'ai_analysis': SessionType.physicalAssessment,
      'performance_test': SessionType.physicalAssessment,
    };
    if (aliases.containsKey(v)) return aliases[v]!;
    return SessionType.values.firstWhere(
      (e) => e.name == v,
      orElse: () => SessionType.custom,
    );
  }
}

enum AssessmentType {
  squat,
  singleLegBalance,
  jumpLanding,
  lunge,
  countermovementJump,
  squatJump,
  dropJump,
  singleLegDropJump,
  custom,
}

extension AssessmentTypeExt on AssessmentType {
  String get label {
    switch (this) {
      case AssessmentType.squat:
        return 'Squat Assessment';
      case AssessmentType.singleLegBalance:
        return 'Single Leg Balance';
      case AssessmentType.jumpLanding:
        return 'Jump Landing';
      case AssessmentType.lunge:
        return 'Lunge Assessment';
      case AssessmentType.countermovementJump:
        return 'Countermovement Jump';
      case AssessmentType.squatJump:
        return 'Squat Jump';
      case AssessmentType.dropJump:
        return 'Drop Jump';
      case AssessmentType.singleLegDropJump:
        return 'Single Leg Drop Jump';
      case AssessmentType.custom:
        return 'Custom Test';
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

  factory ClubTeam.fromJson(Map<String, dynamic> j) => ClubTeam(
    id: j['id']?.toString() ?? j['name'] as String? ?? '',
    name: j['name'] as String? ?? '',
    category: TeamCategoryExt.fromString(
      j['category'] as String? ?? 'firstTeam',
    ),
    coachName: j['coach_name'] as String? ?? '',
    physicalCoachName: j['physical_coach_name'] as String? ?? '',
    season: j['season'] as String? ?? '',
    playerIds: [],
    createdAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category.name,
    'coach_name': coachName,
    'physical_coach_name': physicalCoachName,
    'season': season,
    'notes': notes,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ClubSeason
// ─────────────────────────────────────────────────────────────────────────────

class ClubSeason {
  ClubSeason({
    required this.id,
    this.teamId,
    required this.name,
    required this.startsOn,
    required this.endsOn,
    this.status = 'draft',
  });

  final int id;
  int? teamId;
  String name;
  DateTime startsOn;
  DateTime endsOn;
  String status; // draft | active | archived

  bool get isActive => status == 'active';

  factory ClubSeason.fromJson(Map<String, dynamic> j) => ClubSeason(
    id: int.tryParse(j['id'].toString()) ?? 0,
    teamId: j['team_id'] != null ? int.tryParse(j['team_id'].toString()) : null,
    name: j['name'] as String? ?? '',
    startsOn: DateTime.tryParse(j['starts_on']?.toString() ?? '') ?? DateTime.now(),
    endsOn: DateTime.tryParse(j['ends_on']?.toString() ?? '') ?? DateTime.now(),
    status: j['status'] as String? ?? 'draft',
  );

  Map<String, dynamic> toJson() => {
    if (id != 0) 'id': id,
    'team_id': teamId,
    'name': name,
    'starts_on':
        '${startsOn.year}-${startsOn.month.toString().padLeft(2, '0')}-${startsOn.day.toString().padLeft(2, '0')}',
    'ends_on':
        '${endsOn.year}-${endsOn.month.toString().padLeft(2, '0')}-${endsOn.day.toString().padLeft(2, '0')}',
    'status': status,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ClubCompetition
// ─────────────────────────────────────────────────────────────────────────────

class ClubCompetition {
  ClubCompetition({
    required this.id,
    this.seasonId,
    this.seasonName,
    required this.name,
    this.type = 'league',
    this.notes,
    this.yellowCardThreshold = 3,
    this.suspensionMatches = 1,
    this.resetYellowCycle = true,
    this.carryCardsBetweenStages = true,
    this.carrySuspensionsForward = false,
    this.directRedSuspensionMatches = 2,
    this.twoYellowsSuspensionMatches = 1,
    this.allowAdminOverride = true,
    this.formatType = 'league',
    this.stagesCount = 1,
    this.winPoints = 3,
    this.drawPoints = 1,
    this.lossPoints = 0,
    this.tieBreakRule = 'goal_difference',
    this.competitionStatus = 'upcoming',
  });

  final int id;
  int? seasonId;
  String? seasonName;
  String name;
  String type; // league | cup | friendly
  String? notes;
  int yellowCardThreshold;
  int suspensionMatches;
  bool resetYellowCycle;
  bool carryCardsBetweenStages;
  bool carrySuspensionsForward;
  int directRedSuspensionMatches;
  int twoYellowsSuspensionMatches;
  bool allowAdminOverride;
  String formatType; // league | knockout | groups | friendly
  int stagesCount;
  int winPoints;
  int drawPoints;
  int lossPoints;
  String tieBreakRule; // goal_difference | head_to_head | goals_scored
  String competitionStatus; // upcoming | ongoing | completed

  factory ClubCompetition.fromJson(Map<String, dynamic> j) => ClubCompetition(
    id: int.tryParse(j['id'].toString()) ?? 0,
    seasonId: j['season_id'] != null ? int.tryParse(j['season_id'].toString()) : null,
    seasonName: j['season_name'] as String?,
    name: j['name'] as String? ?? '',
    type: j['type'] as String? ?? 'league',
    notes: j['notes'] as String?,
    yellowCardThreshold: int.tryParse(j['yellow_card_threshold'].toString()) ?? 3,
    suspensionMatches: int.tryParse(j['suspension_matches'].toString()) ?? 1,
    resetYellowCycle: j['reset_yellow_cycle'].toString() != '0',
    carryCardsBetweenStages: j['carry_cards_between_stages'].toString() != '0',
    carrySuspensionsForward: j['carry_suspensions_forward'].toString() == '1',
    directRedSuspensionMatches: int.tryParse(j['direct_red_suspension_matches'].toString()) ?? 2,
    twoYellowsSuspensionMatches: int.tryParse(j['two_yellows_suspension_matches'].toString()) ?? 1,
    allowAdminOverride: j['allow_admin_override'].toString() != '0',
    formatType: j['format_type'] as String? ?? 'league',
    stagesCount: int.tryParse(j['stages_count'].toString()) ?? 1,
    winPoints: int.tryParse(j['win_points'].toString()) ?? 3,
    drawPoints: int.tryParse(j['draw_points'].toString()) ?? 1,
    lossPoints: int.tryParse(j['loss_points'].toString()) ?? 0,
    tieBreakRule: j['tie_break_rule'] as String? ?? 'goal_difference',
    competitionStatus: j['competition_status'] as String? ?? 'upcoming',
  );

  Map<String, dynamic> toJson() => {
    if (id != 0) 'id': id,
    'season_id': seasonId,
    'name': name,
    'type': type,
    'notes': notes,
    'yellow_card_threshold': yellowCardThreshold,
    'suspension_matches': suspensionMatches,
    'reset_yellow_cycle': resetYellowCycle,
    'carry_cards_between_stages': carryCardsBetweenStages,
    'carry_suspensions_forward': carrySuspensionsForward,
    'direct_red_suspension_matches': directRedSuspensionMatches,
    'two_yellows_suspension_matches': twoYellowsSuspensionMatches,
    'allow_admin_override': allowAdminOverride,
    'format_type': formatType,
    'stages_count': stagesCount,
    'win_points': winPoints,
    'draw_points': drawPoints,
    'loss_points': lossPoints,
    'tie_break_rule': tieBreakRule,
    'competition_status': competitionStatus,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// StandingCompetition / StandingRow — league table (api/club/standings.php)
// ─────────────────────────────────────────────────────────────────────────────

/// Lightweight competition reference used by the standings picker — a
/// trimmed-down alternative to [ClubCompetition] that players (blocked from
/// club/competitions.php) can also read via club/standings.php.
class StandingCompetition {
  StandingCompetition({required this.id, required this.name, required this.type});

  final int id;
  final String name;
  final String type;

  factory StandingCompetition.fromJson(Map<String, dynamic> j) => StandingCompetition(
        id: int.tryParse(j['id'].toString()) ?? 0,
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? 'league',
      );
}

class StandingRow {
  StandingRow({
    this.id,
    required this.position,
    required this.teamName,
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.points = 0,
    this.isOwnTeam = false,
  });

  final String? id;
  int position;
  String teamName;
  int played;
  int won;
  int drawn;
  int lost;
  int goalsFor;
  int goalsAgainst;
  int points;
  bool isOwnTeam;

  int get goalDifference => goalsFor - goalsAgainst;

  factory StandingRow.fromJson(Map<String, dynamic> j) => StandingRow(
        id: j['id']?.toString(),
        position: int.tryParse(j['position'].toString()) ?? 0,
        teamName: j['teamName'] as String? ?? '',
        played: int.tryParse(j['played'].toString()) ?? 0,
        won: int.tryParse(j['won'].toString()) ?? 0,
        drawn: int.tryParse(j['drawn'].toString()) ?? 0,
        lost: int.tryParse(j['lost'].toString()) ?? 0,
        goalsFor: int.tryParse(j['goalsFor'].toString()) ?? 0,
        goalsAgainst: int.tryParse(j['goalsAgainst'].toString()) ?? 0,
        points: int.tryParse(j['points'].toString()) ?? 0,
        isOwnTeam: j['isOwnTeam'] == true,
      );

  Map<String, dynamic> toJson() => {
        'position': position,
        'teamName': teamName,
        'played': played,
        'won': won,
        'drawn': drawn,
        'lost': lost,
        'goalsFor': goalsFor,
        'goalsAgainst': goalsAgainst,
        'points': points,
        'isOwnTeam': isOwnTeam,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// MatchCard
// ─────────────────────────────────────────────────────────────────────────────

class MatchCard {
  MatchCard({
    required this.id,
    required this.matchId,
    required this.playerId,
    required this.cardType,
    this.minute,
    this.reason,
  });

  final int id;
  final String matchId;
  final String playerId;
  String cardType; // yellow | red
  int? minute;
  String? reason;

  factory MatchCard.fromJson(Map<String, dynamic> j) => MatchCard(
    id: int.tryParse(j['id'].toString()) ?? 0,
    matchId: j['match_id']?.toString() ?? '',
    playerId: j['player_id']?.toString() ?? '',
    cardType: j['card_type'] as String? ?? 'yellow',
    minute: j['minute'] != null ? int.tryParse(j['minute'].toString()) : null,
    reason: j['reason'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'player_id': playerId,
    'card_type': cardType,
    'minute': minute,
    'reason': reason,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// PlayerManagementReportRow
// ─────────────────────────────────────────────────────────────────────────────

class PlayerManagementReportRow {
  PlayerManagementReportRow({
    required this.playerId,
    required this.name,
    required this.minutes,
    required this.present,
    required this.late,
    required this.absent,
    required this.completedSessions,
    required this.assignedSessions,
    required this.yellowCards,
    required this.redCards,
    this.activeSuspensions = 0,
    this.matchesRemaining = 0,
    this.currentYellowCards = 0,
    this.oneCardToSuspension = false,
  });

  final String playerId;
  final String name;
  final int minutes;
  final int present;
  final int late;
  final int absent;
  final int completedSessions;
  final int assignedSessions;
  final int yellowCards;
  final int redCards;
  final int activeSuspensions;
  final int matchesRemaining;
  final int currentYellowCards;
  final bool oneCardToSuspension;

  factory PlayerManagementReportRow.fromJson(Map<String, dynamic> j) {
    final attendance = j['attendance'] as Map<String, dynamic>? ?? {};
    final sessions = j['sessions'] as Map<String, dynamic>? ?? {};
    final cards = j['cards'] as Map<String, dynamic>? ?? {};
    return PlayerManagementReportRow(
      playerId: j['player_id']?.toString() ?? '',
      name: j['name'] as String? ?? '',
      minutes: int.tryParse(j['minutes'].toString()) ?? 0,
      present: int.tryParse(attendance['present'].toString()) ?? 0,
      late: int.tryParse(attendance['late'].toString()) ?? 0,
      absent: int.tryParse(attendance['absent'].toString()) ?? 0,
      completedSessions:
          int.tryParse(sessions['completed'].toString()) ?? 0,
      assignedSessions: int.tryParse(sessions['assigned'].toString()) ?? 0,
      yellowCards: int.tryParse(cards['yellow'].toString()) ?? 0,
      redCards: int.tryParse(cards['red'].toString()) ?? 0,
      currentYellowCards: int.tryParse(cards['current_yellow'].toString()) ?? 0,
      oneCardToSuspension: cards['one_card_to_suspension'] == true || cards['one_card_to_suspension'].toString() == '1',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ClubPlayer
// ─────────────────────────────────────────────────────────────────────────────

class ClubPlayer {
  ClubPlayer({
    required this.id,
    required this.fullName,
    this.nameArabic = '',
    this.nameEnglish = '',
    this.nickname,
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
    this.expectedReturnDate,
    this.unavailableReason,
    this.lastAssessmentAt,
    this.hasLogin = false,
    this.isArchived = false,
    required this.createdAt,
  });

  final String id;
  String fullName;
  String nameArabic;
  String nameEnglish;
  String? nickname;
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
  DateTime? expectedReturnDate;
  String? unavailableReason;
  DateTime? lastAssessmentAt;
  bool hasLogin;
  bool isArchived;
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
    if (parts.length >= 2)
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  factory ClubPlayer.fromMap(String id, Map<String, dynamic> m) => ClubPlayer(
    id: id,
    fullName: m['fullName'] as String? ?? '',
    nameArabic: m['nameArabic'] as String? ?? '',
    nameEnglish: m['nameEnglish'] as String? ?? '',
    nickname: m['nickname'] as String?,
    number: m['number'] as String? ?? '',
    position: m['position'] as String? ?? '',
    dateOfBirth: (m['dateOfBirth'] as Timestamp?)?.toDate(),
    height: (m['height'] as num?)?.toDouble(),
    weight: (m['weight'] as num?)?.toDouble(),
    dominantFoot: m['dominantFoot'] as String? ?? 'right',
    teamId: m['teamId'] as String? ?? '',
    teamName: m['teamName'] as String?,
    nationality: m['nationality'] as String? ?? '',
    profileImageUrl:
        m['profileImageUrl'] as String? ?? m['photo_url'] as String?,
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
    'nameArabic': nameArabic,
    'nameEnglish': nameEnglish,
    'nickname': nickname,
    'number': number,
    'position': position,
    'dateOfBirth': dateOfBirth != null
        ? Timestamp.fromDate(dateOfBirth!)
        : null,
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

  factory ClubPlayer.fromJson(Map<String, dynamic> j) => ClubPlayer(
    id: j['id']?.toString() ?? '',
    fullName: j['name'] as String? ?? '',
    nameArabic: j['name_ar']?.toString() ?? '',
    nameEnglish: j['name_en']?.toString() ?? '',
    nickname: j['nickname'] as String?,
    number: j['number']?.toString() ?? '',
    position: j['position'] as String? ?? '',
    dateOfBirth: j['date_of_birth'] != null
        ? DateTime.tryParse(j['date_of_birth'].toString())
        : null,
    height: (j['height_cm'] as num?)?.toDouble(),
    weight: (j['weight_kg'] as num?)?.toDouble(),
    dominantFoot: j['dominant_foot'] as String? ?? 'right',
    teamId:
        j['resolved_team_id']?.toString() ??
        j['team_id']?.toString() ??
        j['team_name'] as String? ??
        '',
    teamName: j['team_name'] as String?,
    nationality: j['nationality'] as String? ?? '',
    profileImageUrl: j['photo_url'] as String?,
    injuryNotes: j['injury_notes'] as String?,
    physicalNotes: j['physical_notes'] as String?,
    medicalNotes: j['medical_notes'] as String?,
    status: PlayerStatusExt.fromString(j['status'] as String? ?? 'active'),
    latestScore:
        (j['latest_score'] as num?)?.toDouble() ??
        (j['ai_score'] as num?)?.toDouble(),
    movementScore: (j['movement_score'] as num?)?.toDouble(),
    stabilityScore: (j['stability_score'] as num?)?.toDouble(),
    symmetryScore: (j['symmetry_score'] as num?)?.toDouble(),
    controlScore: (j['control_score'] as num?)?.toDouble(),
    expectedReturnDate: j['expected_return_date'] != null
        ? DateTime.tryParse(j['expected_return_date'].toString())
        : null,
    unavailableReason: j['unavailable_reason'] as String?,
    lastAssessmentAt: j['last_assessment_at'] != null
        ? DateTime.tryParse(j['last_assessment_at'].toString())
        : null,
    hasLogin:
        j['linked_user_id'] != null &&
        j['linked_user_id'].toString().isNotEmpty,
    isArchived: j['is_active'] == false ||
        j['is_active'] == 0 ||
        j['is_active']?.toString() == '0',
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
        : DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': fullName,
    'name_ar': nameArabic,
    'name_en': nameEnglish,
    'nickname': nickname,
    'number': number,
    'position': position,
    'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
    'height_cm': height,
    'weight_kg': weight,
    'dominant_foot': dominantFoot,
    'team_name': teamName ?? teamId,
    'nationality': nationality,
    'photo_url': profileImageUrl,
    'injury_notes': injuryNotes,
    'physical_notes': physicalNotes,
    'medical_notes': medicalNotes,
    'status': status.name,
    'expected_return_date': expectedReturnDate
        ?.toIso8601String()
        .split('T')
        .first,
    'unavailable_reason': unavailableReason,
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
    this.scope = 'team',
    this.status = 'scheduled',
    this.startTime = '08:00',
    this.endTime,
    this.durationMin = 90,
    this.intensity = 'medium',
    this.location,
    required this.coachName,
    this.notes,
    this.playerIds = const [],
    this.completedPlayerIds = const [],
    this.assessmentCount = 0,
    this.attendancePresentCount = 0,
    required this.createdAt,
    this.assessmentType,
    this.assessmentTypes = const [],
    this.wellnessRequired = false,
    this.rpeRequired = false,
    this.attendanceRequired = true,
    this.positionFilter,
    this.wellnessDone = false,
    this.rpeDone = false,
    this.hooperScore,
    this.rpeScore,
    this.rpeEditable = false,
    this.clockRunning = false,
    this.elapsedSeconds = 0,
  });

  final String id;
  String name;
  DateTime date;
  String teamId;
  String? teamName;
  SessionType type;
  String scope; // 'team' | 'group' | 'individual'
  String status; // 'scheduled' | 'active' | 'completed' | 'cancelled'
  String startTime; // 'HH:MM'
  String? endTime;
  int durationMin;
  String intensity; // 'low' | 'medium' | 'high' | 'recovery'
  String? location;
  String coachName;
  String? notes;
  List<String> playerIds;
  List<String> completedPlayerIds;
  int assessmentCount;
  int attendancePresentCount;
  DateTime createdAt;
  String? assessmentType; // legacy single type
  List<String> assessmentTypes; // multiple AI assessment types
  bool wellnessRequired;
  bool rpeRequired;
  bool attendanceRequired;
  String? positionFilter; // 'GK' | 'DEF' | 'MID' | 'FWD' | null
  bool wellnessDone; // this player already submitted Hooper for this session
  bool rpeDone; // this player already submitted RPE for this session
  int? hooperScore; // the submitted Hooper Index value, when wellnessDone
  int? rpeScore; // the submitted post-session RPE value, when rpeDone
  bool rpeEditable; // player may correct it during the 50-minute window
  bool clockRunning;
  int elapsedSeconds;

  bool get isCompleted =>
      completedPlayerIds.length >= playerIds.length && playerIds.isNotEmpty;
  int get pendingCount => playerIds.length - completedPlayerIds.length;

  String get scopeLabel {
    switch (scope) {
      case 'individual':
        return 'فردية';
      case 'group':
        return 'مجموعة';
      default:
        return 'جماعية';
    }
  }

  String get statusLabel {
    switch (status) {
      case 'active':
        return 'نشطة';
      case 'completed':
        return 'مكتملة';
      case 'cancelled':
        return 'ملغاة';
      default:
        return 'مجدولة';
    }
  }

  String get intensityLabel {
    switch (intensity) {
      case 'low':
        return 'خفيفة';
      case 'high':
        return 'عالية';
      case 'recovery':
        return 'استشفاء';
      default:
        return 'متوسطة';
    }
  }

  factory TrainingSession.fromMap(String id, Map<String, dynamic> m) =>
      TrainingSession(
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
        completedPlayerIds: List<String>.from(
          m['completedPlayerIds'] as List? ?? [],
        ),
        assessmentCount: m['assessmentCount'] as int? ?? 0,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        assessmentType: m['assessmentType'] as String?,
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
    'assessmentType': assessmentType,
  };

  factory TrainingSession.fromJson(Map<String, dynamic> j) {
    List<String> _toStringList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String && v.isNotEmpty && v != 'null') {
        try {
          return List<String>.from(jsonDecode(v));
        } catch (_) {}
      }
      return [];
    }

    return TrainingSession(
      id: j['id']?.toString() ?? '',
      name: j['title'] as String? ?? j['name'] as String? ?? '',
      date: j['date'] != null
          ? DateTime.tryParse(j['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      teamId: j['team_id']?.toString() ?? '',
      teamName: j['team_name'] as String?,
      type: SessionTypeExt.fromString(j['type'] as String? ?? ''),
      scope: j['scope'] as String? ?? 'team',
      status: j['status'] as String? ?? 'scheduled',
      startTime: j['start_time'] as String? ?? '08:00',
      endTime: j['end_time'] as String?,
      durationMin: _jsonInt(j['duration_min'], 90),
      intensity: j['intensity'] as String? ?? 'medium',
      location: j['location'] as String?,
      coachName: j['coach_name'] as String? ?? '',
      notes: j['notes'] as String?,
      playerIds: _toStringList(j['player_ids']),
      completedPlayerIds: _toStringList(j['completed_player_ids']),
      assessmentCount: _jsonInt(j['assessment_count']),
      attendancePresentCount:
          int.tryParse(j['attendance_present_count']?.toString() ?? '') ?? 0,
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      assessmentType: j['assessment_type'] as String?,
      assessmentTypes: _toStringList(j['assessment_types']),
      wellnessRequired:
          j['wellness_required'] == true || j['wellness_required'] == 1,
      rpeRequired: j['rpe_required'] == true || j['rpe_required'] == 1,
      attendanceRequired:
          j['attendance_required'] == true || j['attendance_required'] == 1,
      positionFilter: j['position_filter'] as String?,
      wellnessDone: j['wellness_done'] == true || j['wellness_done'] == 1,
      rpeDone: j['rpe_done'] == true || j['rpe_done'] == 1,
      hooperScore: j['hooper_score'] != null
          ? int.tryParse(j['hooper_score'].toString())
          : null,
      rpeScore: j['rpe_score'] != null
          ? int.tryParse(j['rpe_score'].toString())
          : null,
      rpeEditable:
          j['rpe_editable'] == true || j['rpe_editable'] == 1,
      clockRunning:
          j['clock_running'] == true || j['clock_running'] == 1,
      elapsedSeconds: _jsonInt(j['elapsed_seconds']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': name,
    'date':
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'team_name': teamName ?? teamId,
    'team_id': int.tryParse(teamId),
    'type': type.name,
    'scope': scope,
    'status': status,
    'startTime': startTime,
    'endTime': endTime,
    'durationMin': durationMin,
    'intensity': intensity,
    'location': location,
    'coach_name': coachName,
    'notes': notes,
    'player_ids': playerIds,
    'completed_player_ids': completedPlayerIds,
    'assessment_count': assessmentCount,
    'assessment_type': assessmentType,
    'assessment_types': assessmentTypes,
    'wellnessRequired': wellnessRequired,
    'rpeRequired': rpeRequired,
    'attendanceRequired': attendanceRequired,
    'position_filter': positionFilter,
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
    this.overrideScore,
    this.overrideReason,
  });

  /// The score to display/use: a coach's manual override when one has been
  /// applied, otherwise the AI-computed overall score.
  double get effectiveScore => overrideScore?.toDouble() ?? overallScore;

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
  int? overrideScore;
  String? overrideReason;

  factory PlayerAssessment.fromMap(String id, Map<String, dynamic> m) {
    // Safe conversion for any numeric value — avoids cast _TypeError
    double _n(String snakeKey, String camelKey, [double fallback = 0]) {
      final v = m[snakeKey] ?? m[camelKey];
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    // Safe string extraction from either key name
    String? _s(String snakeKey, [String? camelKey]) {
      final v = m[snakeKey];
      if (v != null) return v.toString();
      if (camelKey != null) return m[camelKey]?.toString();
      return null;
    }

    // Safe list extraction — returns empty list on null/wrong type
    List<String> _list(String snakeKey, [String? camelKey]) {
      dynamic raw = m[snakeKey];
      if (raw == null && camelKey != null) raw = m[camelKey];
      if (raw is List) return List<String>.from(raw.map((e) => e.toString()));
      return [];
    }

    DateTime _parseDate() {
      final ts = m['date'];
      if (ts is Timestamp) return ts.toDate();
      final s = _s('created_at', 'createdAt');
      if (s != null) return DateTime.tryParse(s) ?? DateTime.now();
      return DateTime.now();
    }

    return PlayerAssessment(
      id: _s('id') ?? id,
      playerId: _s('player_id', 'playerId') ?? '',
      playerName: _s('player_name', 'playerName') ?? '',
      sessionId: _s('session_id', 'sessionId') ?? '',
      sessionName: _s('sessionName') ?? '',
      type: AssessmentTypeExt.fromString(_s('type') ?? ''),
      date: _parseDate(),
      movementQualityScore: _n(
        'movement_quality_score',
        'movementQualityScore',
      ),
      stabilityScore: _n('stability_score', 'stabilityScore'),
      symmetryScore: _n('symmetry_score', 'symmetryScore'),
      controlScore: _n('control_score', 'controlScore'),
      overallScore: _n('overall_score', 'overallScore'),
      assessmentQuality: _n('quality_score', 'assessmentQuality', 100),
      detectedIssues: _list('issues', 'detectedIssues'),
      recommendations: _list('tips', 'recommendations'),
      coachNotes: _s('notes', 'coachNotes'),
      jointAngles: () {
        final raw = m['metrics'] ?? m['angle_metrics'] ?? m['jointAngles'];
        return raw is Map ? Map<String, dynamic>.from(raw) : null;
      }(),
      snapshots: _list('snapshots'),
      overrideScore: (m['override_score'] as num?)?.toInt(),
      overrideReason: _s('override_reason'),
    );
  }

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
    date: DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'playerId': playerId,
    'authorName': authorName,
    'text': text,
    'date': date.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ClubSessionExercise
// ─────────────────────────────────────────────────────────────────────────────

class ClubSessionExercise {
  ClubSessionExercise({
    this.id = 0,
    required this.exerciseType,
    required this.exerciseName,
    this.category,
    this.sets,
    this.reps,
    this.durationSeconds,
    this.restSeconds,
    this.intensity = 'medium',
    this.assessmentType,
    this.notes,
    this.sortOrder = 0,
  });

  int id;
  String exerciseType; // 'ai' | 'manual'
  String exerciseName;
  String? category;
  int? sets;
  int? reps;
  int? durationSeconds;
  int? restSeconds;
  String intensity;
  String?
  assessmentType; // for AI exercises: squat, cmj, sj, dj, sldj, jumpLanding
  String? notes;
  int sortOrder;

  bool get isAI => exerciseType == 'ai';

  String get volumeLabel {
    if (sets != null && reps != null) return '${sets}×${reps}';
    if (durationSeconds != null) {
      final m = durationSeconds! ~/ 60;
      final s = durationSeconds! % 60;
      return m > 0 ? '${m}د ${s}ث' : '${s}ث';
    }
    return '';
  }

  factory ClubSessionExercise.fromJson(Map<String, dynamic> j) =>
      ClubSessionExercise(
        id: j['id'] as int? ?? 0,
        exerciseType: j['exercise_type'] as String? ?? 'manual',
        exerciseName: j['exercise_name'] as String? ?? '',
        category: j['category'] as String?,
        sets: j['sets'] as int?,
        reps: j['reps'] as int?,
        durationSeconds: j['duration_seconds'] as int?,
        restSeconds: j['rest_seconds'] as int?,
        intensity: j['intensity'] as String? ?? 'medium',
        assessmentType: j['assessment_type'] as String?,
        notes: j['notes'] as String?,
        sortOrder: j['sort_order'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'exercise_type': exerciseType,
    'exercise_name': exerciseName,
    'category': category,
    'sets': sets,
    'reps': reps,
    'duration_seconds': durationSeconds,
    'rest_seconds': restSeconds,
    'intensity': intensity,
    'assessment_type': assessmentType,
    'notes': notes,
    'sort_order': sortOrder,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// MatchModel
// ─────────────────────────────────────────────────────────────────────────────

class MatchModel {
  MatchModel({
    required this.id,
    required this.opponent,
    required this.matchDate,
    this.matchTime = '16:00',
    this.location,
    this.status = 'scheduled',
    this.playerIds = const [],
    this.playerMinutes = const {},
    this.myMinutes,
    this.competitionId,
    this.wellnessRequired = false,
    this.rpeRequired = false,
    this.notes,
    required this.createdAt,
    this.wellnessDone = false,
    this.rpeDone = false,
    this.hooperScore,
    this.rpeScore,
    this.rpeEditable = false,
    this.participations = const [],
    this.competitionName,
    this.myYellowCards = 0,
    this.myRedCards = 0,
    this.clockRunning = false,
    this.elapsedSeconds = 0,
    this.stage,
    this.roundLabel,
    this.groupName,
    this.ourScore,
    this.opponentScore,
  });

  final String id;
  String opponent;
  DateTime matchDate;
  String matchTime;
  String? location;
  String status;
  List<String> playerIds;
  Map<String, int> playerMinutes;
  int? myMinutes;
  int? competitionId;
  bool wellnessRequired;
  bool rpeRequired;
  String? notes;
  DateTime createdAt;
  bool wellnessDone; // this player already submitted Hooper for this match
  bool rpeDone; // this player already submitted RPE for this match
  int? hooperScore; // the submitted Hooper Index value, when wellnessDone
  int? rpeScore; // the submitted post-match RPE value, when rpeDone
  bool rpeEditable; // player may correct it during the 50-minute window
  List<MatchParticipation> participations; // only populated on single-match GET
  String? competitionName;
  int myYellowCards;
  int myRedCards;
  bool clockRunning;
  int elapsedSeconds;
  String? stage; // group | quarterfinal | semifinal | final | round
  String? roundLabel;
  String? groupName;
  int? ourScore;
  int? opponentScore;

  bool get hasResult => ourScore != null && opponentScore != null;

  String get statusLabel {
    switch (status) {
      case 'completed':
        return 'انتهت';
      case 'cancelled':
        return 'ملغاة';
      default:
        return 'مجدولة';
    }
  }

  bool get isUpcoming => matchDate.isAfter(DateTime.now());

  factory MatchModel.fromJson(Map<String, dynamic> j) {
    Map<String, int> _parseMinutes(dynamic v) {
      if (v is Map) {
        return v.map(
          (k, val) => MapEntry(k.toString(), int.tryParse(val.toString()) ?? 0),
        );
      }
      return {};
    }

    List<String> _toStringList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String && v.isNotEmpty && v != 'null') {
        try {
          return List<String>.from(jsonDecode(v));
        } catch (_) {}
      }
      return [];
    }

    return MatchModel(
      id: j['id']?.toString() ?? '',
      opponent: j['opponent'] as String? ?? '',
      matchDate: j['match_date'] != null
          ? DateTime.tryParse(j['match_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      matchTime: j['match_time'] as String? ?? '16:00',
      location: j['location'] as String?,
      status: j['status'] as String? ?? 'scheduled',
      playerIds: _toStringList(j['player_ids']),
      playerMinutes: _parseMinutes(j['player_minutes']),
      myMinutes: j['my_minutes'] != null
          ? int.tryParse(j['my_minutes'].toString())
          : null,
      competitionId: j['competition_id'] != null
          ? int.tryParse(j['competition_id'].toString())
          : null,
      competitionName: j['competition_name'] as String?,
      myYellowCards: int.tryParse(j['my_yellow_cards'].toString()) ?? 0,
      myRedCards: int.tryParse(j['my_red_cards'].toString()) ?? 0,
      wellnessRequired:
          j['wellness_required'] == true || j['wellness_required'] == 1,
      rpeRequired: j['rpe_required'] == true || j['rpe_required'] == 1,
      notes: j['notes'] as String?,
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      wellnessDone: j['wellness_done'] == true || j['wellness_done'] == 1,
      rpeDone: j['rpe_done'] == true || j['rpe_done'] == 1,
      hooperScore: j['hooper_score'] != null
          ? int.tryParse(j['hooper_score'].toString())
          : null,
      rpeScore: j['rpe_score'] != null
          ? int.tryParse(j['rpe_score'].toString())
          : null,
      rpeEditable:
          j['rpe_editable'] == true || j['rpe_editable'] == 1,
      participations: j['participations'] is List
          ? (j['participations'] as List)
              .map((e) => MatchParticipation.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      clockRunning:
          j['clock_running'] == true || j['clock_running'] == 1,
      elapsedSeconds: int.tryParse(j['elapsed_seconds'].toString()) ?? 0,
      stage: j['stage'] as String?,
      roundLabel: j['round_label'] as String?,
      groupName: j['group_name'] as String?,
      ourScore: j['our_score'] != null ? int.tryParse(j['our_score'].toString()) : null,
      opponentScore: j['opponent_score'] != null
          ? int.tryParse(j['opponent_score'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'opponent': opponent,
    'match_date':
        '${matchDate.year}-${matchDate.month.toString().padLeft(2, '0')}-${matchDate.day.toString().padLeft(2, '0')}',
    'match_time': matchTime,
    'location': location,
    'status': status,
    'player_ids': playerIds,
    'player_minutes': playerMinutes,
    'my_minutes': myMinutes,
    'competition_id': competitionId,
    'wellness_required': wellnessRequired,
    'rpe_required': rpeRequired,
    'notes': notes,
    'stage': stage,
    'round_label': roundLabel,
    'group_name': groupName,
    'our_score': ourScore,
    'opponent_score': opponentScore,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// MatchParticipation — starter/sub, minutes, position, goals/assists,
// not-played reason for one player in one match.
// ─────────────────────────────────────────────────────────────────────────────

class MatchParticipation {
  MatchParticipation({
    required this.playerId,
    this.starter = false,
    this.played = true,
    this.minuteIn,
    this.minuteOut,
    this.minutesPlayed = 0,
    this.position,
    this.goals = 0,
    this.assists = 0,
    this.notPlayedReason,
    this.clockRunning = false,
    this.elapsedSeconds = 0,
    this.rating,
    this.injured = false,
  });

  final String playerId;
  bool starter;
  bool played;
  int? minuteIn;
  int? minuteOut;
  int minutesPlayed;
  String? position;
  int goals;
  int assists;
  String? notPlayedReason;
  bool clockRunning;
  int elapsedSeconds;
  double? rating; // post-match performance rating, e.g. 7.5
  bool injured; // injured during this match

  factory MatchParticipation.fromJson(Map<String, dynamic> j) => MatchParticipation(
        playerId: j['player_id']?.toString() ?? '',
        starter: j['starter'] == true || j['starter'] == 1,
        played: j['played'] == true || j['played'] == 1,
        minuteIn: j['minute_in'] != null ? int.tryParse(j['minute_in'].toString()) : null,
        minuteOut: j['minute_out'] != null ? int.tryParse(j['minute_out'].toString()) : null,
        minutesPlayed: int.tryParse(j['minutes_played'].toString()) ?? 0,
        position: j['position'] as String?,
        goals: int.tryParse(j['goals'].toString()) ?? 0,
        assists: int.tryParse(j['assists'].toString()) ?? 0,
        notPlayedReason: j['not_played_reason'] as String?,
        clockRunning:
            j['clock_running'] == true || j['clock_running'] == 1,
        elapsedSeconds: int.tryParse(j['elapsed_seconds'].toString()) ??
            (int.tryParse(j['minutes_played'].toString()) ?? 0) * 60,
        rating: j['rating'] != null ? double.tryParse(j['rating'].toString()) : null,
        injured: j['injured'] == true || j['injured'] == 1,
      );

  Map<String, dynamic> toJson() => {
        'player_id': playerId,
        'starter': starter,
        'played': played,
        'minute_in': minuteIn,
        'minute_out': minuteOut,
        'minutes_played': minutesPlayed,
        'position': position,
        'goals': goals,
        'assists': assists,
        'not_played_reason': notPlayedReason,
        'rating': rating,
        'injured': injured,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// PlayerCompetitionStats — cards/minutes rollup for one player, per competition
// ─────────────────────────────────────────────────────────────────────────────

class PlayerCompetitionStats {
  PlayerCompetitionStats({
    required this.competitionId,
    required this.competitionName,
    required this.appearances,
    required this.starts,
    required this.subAppearances,
    required this.totalMinutes,
    required this.goals,
    required this.assists,
    required this.yellowCards,
    required this.redCards,
    this.activeSuspensions = 0,
    this.matchesRemaining = 0,
  });

  final int competitionId;
  final String competitionName;
  final int appearances;
  final int starts;
  final int subAppearances;
  final int totalMinutes;
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;
  final int activeSuspensions;
  final int matchesRemaining;

  factory PlayerCompetitionStats.fromJson(Map<String, dynamic> j) =>
      PlayerCompetitionStats(
        competitionId: int.tryParse(j['competition_id'].toString()) ?? 0,
        competitionName: j['competition_name']?.toString() ?? 'أخرى',
        appearances: int.tryParse(j['appearances'].toString()) ?? 0,
        starts: int.tryParse(j['starts'].toString()) ?? 0,
        subAppearances: int.tryParse(j['sub_appearances'].toString()) ?? 0,
        totalMinutes: int.tryParse(j['total_minutes'].toString()) ?? 0,
        goals: int.tryParse(j['goals'].toString()) ?? 0,
        assists: int.tryParse(j['assists'].toString()) ?? 0,
        yellowCards: int.tryParse(j['yellow_cards'].toString()) ?? 0,
        redCards: int.tryParse(j['red_cards'].toString()) ?? 0,
        activeSuspensions: int.tryParse(j['active_suspensions'].toString()) ?? 0,
        matchesRemaining: int.tryParse(j['matches_remaining'].toString()) ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CoachEvaluation
// ─────────────────────────────────────────────────────────────────────────────

class CoachEvaluation {
  CoachEvaluation({
    this.id = 0,
    this.sessionId,
    this.matchId,
    required this.playerId,
    this.fitnessLevel,
    this.effort,
    this.speed,
    this.strength,
    this.agility,
    this.endurance,
    this.notes,
  });

  int id;
  String? sessionId;
  String? matchId;
  String playerId;
  int? fitnessLevel;
  int? effort;
  int? speed;
  int? strength;
  int? agility;
  int? endurance;
  String? notes;

  double? get average {
    final vals = [
      fitnessLevel,
      effort,
      speed,
      strength,
      agility,
      endurance,
    ].whereType<int>().toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  factory CoachEvaluation.fromJson(Map<String, dynamic> j) => CoachEvaluation(
    id: j['id'] as int? ?? 0,
    sessionId: j['session_id'] as String?,
    matchId: j['match_id'] as String?,
    playerId: j['player_id']?.toString() ?? '',
    fitnessLevel: j['fitness_level'] as int?,
    effort: j['effort'] as int?,
    speed: j['speed'] as int?,
    strength: j['strength'] as int?,
    agility: j['agility'] as int?,
    endurance: j['endurance'] as int?,
    notes: j['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'match_id': matchId,
    'player_id': playerId,
    'fitness_level': fitnessLevel,
    'effort': effort,
    'speed': speed,
    'strength': strength,
    'agility': agility,
    'endurance': endurance,
    'notes': notes,
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

  factory DashboardStats.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>? ?? j;
    return DashboardStats(
      totalPlayers: s['total_players'] as int? ?? 0,
      activePlayers: s['active_players'] as int? ?? 0,
      injuredPlayers: s['injured_players'] as int? ?? 0,
      sessionsToday: s['sessions_today'] as int? ?? 0,
      assessmentsToday: s['assessments_today'] as int? ?? 0,
      playersNeedingReview: s['players_review'] as int? ?? 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ClubPlayerDetail — aggregated player detail returned by /api/club/player.php
// ─────────────────────────────────────────────────────────────────────────────

class ClubPlayerDetail {
  const ClubPlayerDetail({
    required this.player,
    required this.assessments,
    this.wellness,
    this.discipline,
  });

  final ClubPlayer player;
  final List<PlayerAssessment> assessments;
  final Map<String, dynamic>? wellness;
  final Map<String, dynamic>? discipline;
}

// ─────────────────────────────────────────────────────────────────────────────
// ReportArchiveEntry — one automatically indexed, completed report period
// ─────────────────────────────────────────────────────────────────────────────

class ReportArchiveEntry {
  const ReportArchiveEntry({
    required this.id,
    required this.reportType,
    required this.periodKind,
    required this.periodStart,
    required this.periodEnd,
    required this.dataCount,
    this.playerCount,
    this.dataCompleteness,
    this.lastRefreshedAt,
  });

  final String id;
  final String reportType;
  final String periodKind;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int dataCount;
  final int? playerCount;
  final double? dataCompleteness;
  final DateTime? lastRefreshedAt;

  factory ReportArchiveEntry.fromJson(Map<String, dynamic> json) =>
      ReportArchiveEntry(
        id: json['id']?.toString() ?? '',
        reportType: json['report_type']?.toString() ?? '',
        periodKind: json['period_kind']?.toString() ?? '',
        periodStart: DateTime.parse(json['period_start']?.toString() ?? ''),
        periodEnd: DateTime.parse(json['period_end']?.toString() ?? ''),
        dataCount: int.tryParse(json['data_count']?.toString() ?? '') ?? 0,
        playerCount:
            int.tryParse(json['player_count']?.toString() ?? ''),
        dataCompleteness: double.tryParse(
          json['data_completeness']?.toString() ?? '',
        ),
        lastRefreshedAt:
            DateTime.tryParse(json['last_refreshed_at']?.toString() ?? ''),
      );
}
