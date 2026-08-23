enum AssessmentTestType {
  squat,
  singleLegBalance,
  jumpLanding,
  countermovementJump,
  squatJump,
  dropJump,
  singleLegDropJump,
}

/// Pipeline maturity of each test type.
enum AssessmentTestStatus {
  complete,        // full dedicated analysis pipeline
  partial,         // jump pipeline works but no type-specific tuning
  demoOnly,        // UI works, analysis returns placeholder (not squat data)
  notImplemented,  // reserved for future types
}

extension AssessmentTestTypeExt on AssessmentTestType {
  String get id => name;

  String get displayName {
    switch (this) {
      case AssessmentTestType.squat:              return 'Squat Assessment';
      case AssessmentTestType.singleLegBalance:   return 'Single Leg Balance';
      case AssessmentTestType.jumpLanding:        return 'Jump Landing';
      case AssessmentTestType.countermovementJump: return 'Countermovement Jump';
      case AssessmentTestType.squatJump:          return 'Squat Jump';
      case AssessmentTestType.dropJump:           return 'Drop Jump';
      case AssessmentTestType.singleLegDropJump:  return 'Single Leg Drop Jump';
    }
  }

  /// Analysis pipeline maturity — used for UI badges and routing guards.
  AssessmentTestStatus get testStatus {
    switch (this) {
      case AssessmentTestType.squat:              return AssessmentTestStatus.complete;
      case AssessmentTestType.countermovementJump: return AssessmentTestStatus.complete;
      case AssessmentTestType.dropJump:           return AssessmentTestStatus.complete;
      case AssessmentTestType.singleLegDropJump:  return AssessmentTestStatus.complete;
      case AssessmentTestType.squatJump:          return AssessmentTestStatus.partial;
      case AssessmentTestType.singleLegBalance:   return AssessmentTestStatus.partial;
      case AssessmentTestType.jumpLanding:        return AssessmentTestStatus.partial;
    }
  }

  // Kept for backward compatibility — jump routing now uses explicit switch.
  bool get isJumpTest => this == AssessmentTestType.countermovementJump ||
      this == AssessmentTestType.squatJump ||
      this == AssessmentTestType.dropJump ||
      this == AssessmentTestType.singleLegDropJump;
}

class AssessmentResult {
  AssessmentResult({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.testType,
    required this.overallScore,
    required this.movementQualityScore,
    required this.stabilityScore,
    required this.symmetryScore,
    required this.controlScore,
    required this.qualityScore,
    required this.angleMetrics,
    required this.issues,
    required this.correctionTips,
    required this.recommendedDrills,
    required this.createdAt,
    this.sessionId,
    this.coachNotes,
    this.debugData = const {},
    this.preHooperIndex,
    this.preRpe,
    this.postRpe,
    this.painReported = false,
    this.difficulty,
    this.moodAfter,
    this.invalidReason,
    this.attemptGroupId,
    this.attemptNumber = 1,
    this.overrideScore,
    this.overrideReason,
    this.status = 'pending_review',
    this.approvedByUserId,
    this.approvedAt,
  });

  AssessmentResult copyWithSession(String? sid) => sid == null ? this : AssessmentResult(
    id: id, playerId: playerId, playerName: playerName, testType: testType,
    overallScore: overallScore, movementQualityScore: movementQualityScore,
    stabilityScore: stabilityScore, symmetryScore: symmetryScore,
    controlScore: controlScore, qualityScore: qualityScore,
    angleMetrics: angleMetrics, issues: issues, correctionTips: correctionTips,
    recommendedDrills: recommendedDrills, createdAt: createdAt,
    sessionId: sid, coachNotes: coachNotes, debugData: debugData,
    preHooperIndex: preHooperIndex, preRpe: preRpe, postRpe: postRpe,
    painReported: painReported, difficulty: difficulty, moodAfter: moodAfter,
    invalidReason: invalidReason, attemptGroupId: attemptGroupId,
    attemptNumber: attemptNumber, overrideScore: overrideScore, overrideReason: overrideReason,
    status: status, approvedByUserId: approvedByUserId, approvedAt: approvedAt,
  );

  /// Attaches this capture to an attempt group — multiple captures of the
  /// same test/player/session share [attemptGroupId] so a best/average can
  /// be computed across them; [attemptNumber] records the capture order.
  AssessmentResult copyWithAttempt({
    required String attemptGroupId,
    required int attemptNumber,
  }) => AssessmentResult(
    id: id, playerId: playerId, playerName: playerName, testType: testType,
    overallScore: overallScore, movementQualityScore: movementQualityScore,
    stabilityScore: stabilityScore, symmetryScore: symmetryScore,
    controlScore: controlScore, qualityScore: qualityScore,
    angleMetrics: angleMetrics, issues: issues, correctionTips: correctionTips,
    recommendedDrills: recommendedDrills, createdAt: createdAt,
    sessionId: sessionId, coachNotes: coachNotes, debugData: debugData,
    preHooperIndex: preHooperIndex, preRpe: preRpe, postRpe: postRpe,
    painReported: painReported, difficulty: difficulty, moodAfter: moodAfter,
    invalidReason: invalidReason, attemptGroupId: attemptGroupId,
    attemptNumber: attemptNumber, overrideScore: overrideScore, overrideReason: overrideReason,
    status: status, approvedByUserId: approvedByUserId, approvedAt: approvedAt,
  );

  /// The score a coach/UI should treat as authoritative: the manual override
  /// when one has been applied, otherwise the AI-computed overall score.
  int get effectiveScore => overrideScore ?? overallScore;

  /// True when the analyzer flagged this capture as unusable (insufficient
  /// frames, low visibility, no detected movement, etc.) — should be
  /// excluded from best/average attempt calculations.
  bool get isValidAttempt => invalidReason == null;

  /// True once a coach has reviewed and certified this result. Only then may
  /// the on-device capture video be deleted.
  bool get isApproved => status == 'approved';

  AssessmentResult copyWithApproval({
    required String status,
    int? approvedByUserId,
    DateTime? approvedAt,
  }) => AssessmentResult(
    id: id, playerId: playerId, playerName: playerName, testType: testType,
    overallScore: overallScore, movementQualityScore: movementQualityScore,
    stabilityScore: stabilityScore, symmetryScore: symmetryScore,
    controlScore: controlScore, qualityScore: qualityScore,
    angleMetrics: angleMetrics, issues: issues, correctionTips: correctionTips,
    recommendedDrills: recommendedDrills, createdAt: createdAt,
    sessionId: sessionId, coachNotes: coachNotes, debugData: debugData,
    preHooperIndex: preHooperIndex, preRpe: preRpe, postRpe: postRpe,
    painReported: painReported, difficulty: difficulty, moodAfter: moodAfter,
    invalidReason: invalidReason, attemptGroupId: attemptGroupId,
    attemptNumber: attemptNumber, overrideScore: overrideScore, overrideReason: overrideReason,
    status: status, approvedByUserId: approvedByUserId ?? this.approvedByUserId,
    approvedAt: approvedAt ?? this.approvedAt,
  );

  final String id;
  final String playerId;
  final String playerName;
  final AssessmentTestType testType;
  final int overallScore;
  final int movementQualityScore;
  final int stabilityScore;
  final int symmetryScore;
  final int controlScore;
  final int qualityScore;
  final Map<String, double> angleMetrics;
  final List<String> issues;
  final List<String> correctionTips;
  final List<String> recommendedDrills;
  final DateTime createdAt;
  final String? sessionId;
  final String? coachNotes;
  final Map<String, double> debugData; // not persisted — for debug panel only
  // Legacy API read compatibility only. Assessments do not write or display
  // wellness, RPE or training-load context.
  final int? preHooperIndex;
  final int? preRpe;
  final int? postRpe;
  final bool painReported;
  final String? difficulty;
  final int? moodAfter;
  // ── Attempts + structured invalid reason ──────────────────────────────────
  final String? invalidReason; // e.g. 'insufficient_frames', 'low_visibility', 'movement_not_detected'
  final String? attemptGroupId;
  final int attemptNumber;
  // ── Coach manual override ─────────────────────────────────────────────────
  final int? overrideScore;
  final String? overrideReason;
  // ── Coach review/certification ────────────────────────────────────────────
  final String status; // 'pending_review' | 'approved'
  final int? approvedByUserId;
  final DateTime? approvedAt;

  factory AssessmentResult.fromMap(String id, Map<String, dynamic> data) {
    return AssessmentResult(
      id: id,
      playerId: data['playerId'] as String? ?? '',
      playerName: data['playerName'] as String? ?? 'Player',
      testType: _testTypeFromId(data['testType'] as String? ?? 'squat'),
      overallScore: (data['overallScore'] as num?)?.toInt() ?? 0,
      movementQualityScore: (data['movementQualityScore'] as num?)?.toInt() ?? 0,
      stabilityScore: (data['stabilityScore'] as num?)?.toInt() ?? 0,
      symmetryScore: (data['symmetryScore'] as num?)?.toInt() ?? 0,
      controlScore: (data['controlScore'] as num?)?.toInt() ?? 0,
      qualityScore: (data['qualityScore'] as num?)?.toInt() ?? 0,
      angleMetrics: Map<String, double>.from(
        (data['angleMetrics'] as Map<String, dynamic>?)?.map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        ) ?? {},
      ),
      issues: List<String>.from(data['issues'] as List<dynamic>? ?? []),
      correctionTips:
          List<String>.from(data['correctionTips'] as List<dynamic>? ?? []),
      recommendedDrills:
          List<String>.from(data['recommendedDrills'] as List<dynamic>? ?? []),
      createdAt: data['createdAt'] is String
          ? DateTime.tryParse(data['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      sessionId:  data['session_id'] as String?,
      coachNotes: data['coachNotes'] as String?,
      preHooperIndex: data['pre_hooper_index'] as int?,
      preRpe:         data['pre_rpe']          as int?,
      postRpe:        data['post_rpe']         as int?,
      painReported:   (data['pain_reported'] as bool?) ?? false,
      difficulty:     data['difficulty']       as String?,
      moodAfter:      data['mood_after']       as int?,
      invalidReason:  data['invalid_reason']   as String?,
      attemptGroupId: data['attempt_group_id'] as String?,
      attemptNumber:  (data['attempt_number']  as num?)?.toInt() ?? 1,
      overrideScore:  (data['override_score']  as num?)?.toInt(),
      overrideReason: data['override_reason']  as String?,
      status: data['status'] as String? ?? 'pending_review',
      approvedByUserId: (data['approved_by_user_id'] as num?)?.toInt(),
      approvedAt: data['approved_at'] is String
          ? DateTime.tryParse(data['approved_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'playerId': playerId,
      'playerName': playerName,
      'testType': testType.id,
      'overallScore': overallScore,
      'movementQualityScore': movementQualityScore,
      'stabilityScore': stabilityScore,
      'symmetryScore': symmetryScore,
      'controlScore': controlScore,
      'qualityScore': qualityScore,
      'angleMetrics': angleMetrics.map((key, value) => MapEntry(key, value)),
      'issues': issues,
      'correctionTips': correctionTips,
      'recommendedDrills': recommendedDrills,
      'createdAt': createdAt.toIso8601String(),
      if (sessionId != null)       'session_id':        sessionId,
      if (coachNotes != null)      'coachNotes':        coachNotes,
      if (preHooperIndex != null)  'pre_hooper_index':  preHooperIndex,
      if (preRpe != null)          'pre_rpe':           preRpe,
      if (postRpe != null)         'post_rpe':          postRpe,
      if (painReported)            'pain_reported':     painReported,
      if (difficulty != null)      'difficulty':        difficulty,
      if (moodAfter != null)       'mood_after':        moodAfter,
      if (invalidReason != null)   'invalid_reason':    invalidReason,
      if (attemptGroupId != null)  'attempt_group_id':  attemptGroupId,
      'attempt_number': attemptNumber,
      if (overrideScore != null)  'override_score':  overrideScore,
      if (overrideReason != null) 'override_reason': overrideReason,
    };
  }
}

AssessmentTestType _testTypeFromId(String id) {
  return AssessmentTestType.values.firstWhere(
    (type) => type.id == id,
    orElse: () => AssessmentTestType.squat,
  );
}
