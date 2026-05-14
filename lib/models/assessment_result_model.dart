import 'package:cloud_firestore/cloud_firestore.dart';

enum AssessmentTestType {
  squat,
  singleLegBalance,
  jumpLanding,
  lunge,
}

extension AssessmentTestTypeExt on AssessmentTestType {
  String get id {
    return name;
  }

  String get displayName {
    switch (this) {
      case AssessmentTestType.squat:
        return 'Squat Assessment';
      case AssessmentTestType.singleLegBalance:
        return 'Single Leg Balance';
      case AssessmentTestType.jumpLanding:
        return 'Jump Landing Assessment';
      case AssessmentTestType.lunge:
        return 'Lunge Assessment';
    }
  }
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
    this.coachNotes,
    this.debugData = const {},
  });

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
  final String? coachNotes;
  final Map<String, double> debugData; // not persisted — for debug panel only

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
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      coachNotes: data['coachNotes'] as String?,
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
      'createdAt': FieldValue.serverTimestamp(),
      if (coachNotes != null) 'coachNotes': coachNotes,
    };
  }
}

AssessmentTestType _testTypeFromId(String id) {
  return AssessmentTestType.values.firstWhere(
    (type) => type.id == id,
    orElse: () => AssessmentTestType.squat,
  );
}
