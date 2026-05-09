import '../models/assessment_result_model.dart';
import '../services/biomechanics_service.dart';
import '../services/exercise_engine.dart';

class PhysicalAssessmentService {
  static AssessmentResult analyzeSquat(
    AssessmentTestType testType,
    String playerId,
    String playerName,
    List<PoseSnapshot> frames,
  ) {
    final validMetrics = frames
        .map(BiomechanicsService.analyzePose)
        .where((metric) => metric.visibilityScore > 0.3)
        .toList();

    final average = _averageMetrics(validMetrics);

    final movementQuality = _movementQualityScore(average);
    final symmetry = _symmetryScore(average);
    final stability = _stabilityScore(average);
    final control = _controlScore(movementQuality, stability, symmetry);
    final overall = ((movementQuality * 0.35) +
            (stability * 0.25) +
            (symmetry * 0.20) +
            (control * 0.20))
        .round();
    final qualityScore = _qualityScore(validMetrics.length, average.visibilityScore);
    final issues = _buildIssues(average, movementQuality, symmetry, stability);
    final tips = _buildTips(average, issues);
    final drills = _buildDrillRecommendations(issues);

    return AssessmentResult(
      id: '',
      playerId: playerId,
      playerName: playerName,
      testType: testType,
      overallScore: overall.clamp(0, 100),
      movementQualityScore: movementQuality,
      stabilityScore: stability,
      symmetryScore: symmetry,
      controlScore: control,
      qualityScore: qualityScore,
      angleMetrics: {
        'Left knee': average.leftKneeAngle,
        'Right knee': average.rightKneeAngle,
        'Left hip': average.leftHipAngle,
        'Right hip': average.rightHipAngle,
        'Trunk tilt': average.trunkAngle,
        'Shoulder level': average.shoulderLevelDifference,
        'Hip level': average.hipLevelDifference,
      },
      issues: issues,
      correctionTips: tips,
      recommendedDrills: drills,
      createdAt: DateTime.now(),
    );
  }

  static BiomechanicsMetrics _averageMetrics(List<BiomechanicsMetrics> metrics) {
    if (metrics.isEmpty) {
      return BiomechanicsMetrics(
        leftKneeAngle: 0,
        rightKneeAngle: 0,
        leftHipAngle: 0,
        rightHipAngle: 0,
        trunkAngle: 0,
        shoulderLevelDifference: 0,
        hipLevelDifference: 0,
        centerStability: 0,
        visibilityScore: 0,
      );
    }
    final count = metrics.length.toDouble();
    return BiomechanicsMetrics(
      leftKneeAngle: metrics.map((m) => m.leftKneeAngle).reduce((a, b) => a + b) / count,
      rightKneeAngle: metrics.map((m) => m.rightKneeAngle).reduce((a, b) => a + b) / count,
      leftHipAngle: metrics.map((m) => m.leftHipAngle).reduce((a, b) => a + b) / count,
      rightHipAngle: metrics.map((m) => m.rightHipAngle).reduce((a, b) => a + b) / count,
      trunkAngle: metrics.map((m) => m.trunkAngle).reduce((a, b) => a + b) / count,
      shoulderLevelDifference: metrics.map((m) => m.shoulderLevelDifference).reduce((a, b) => a + b) / count,
      hipLevelDifference: metrics.map((m) => m.hipLevelDifference).reduce((a, b) => a + b) / count,
      centerStability: metrics.map((m) => m.centerStability).reduce((a, b) => a + b) / count,
      visibilityScore: metrics.map((m) => m.visibilityScore).reduce((a, b) => a + b) / count,
    );
  }

  static int _movementQualityScore(BiomechanicsMetrics metrics) {
    final kneePenalty = ((metrics.averageKneeAngle - 90).abs() / 1.2).clamp(0, 40);
    final hipPenalty = ((metrics.averageHipAngle - 90).abs() / 1.4).clamp(0, 30);
    final trunkPenalty = (metrics.trunkAngle / 2).clamp(0, 15);
    final visibilityBonus = (metrics.visibilityScore * 10).clamp(0, 10);
    return (100 - kneePenalty - hipPenalty - trunkPenalty + visibilityBonus).round().clamp(0, 100);
  }

  static int _symmetryScore(BiomechanicsMetrics metrics) {
    final delta = metrics.symmetryDelta;
    return (100 - (delta * 1.3)).round().clamp(0, 100);
  }

  static int _stabilityScore(BiomechanicsMetrics metrics) {
    final center = (metrics.centerStability * 100).clamp(0, 100);
    final levelPenalty = ((metrics.shoulderLevelDifference + metrics.hipLevelDifference) / 2 * 80).clamp(0, 40);
    return (center - levelPenalty).round().clamp(0, 100);
  }

  static int _controlScore(int movementQuality, int stability, int symmetry) {
    return ((movementQuality * 0.4) + (stability * 0.35) + (symmetry * 0.25)).round().clamp(0, 100);
  }

  static int _qualityScore(int validFrames, double visibility) {
    final frameScore = (validFrames / 20 * 100).clamp(0, 100);
    final visibleScore = (visibility * 100).clamp(0, 100);
    return ((frameScore * 0.6) + (visibleScore * 0.4)).round().clamp(0, 100);
  }

  static List<String> _buildIssues(
    BiomechanicsMetrics metrics,
    int movementQuality,
    int symmetry,
    int stability,
  ) {
    final issues = <String>[];
    if (movementQuality < 80) {
      issues.add('Movement quality indicator is below ideal.');
    }
    if (symmetry < 85) {
      issues.add('Asymmetry indicator detected between left and right.');
    }
    if (stability < 75) {
      issues.add('Potential risk signal: trunk alignment or balance drift.');
    }
    if (metrics.trunkAngle > 15) {
      issues.add('Forward lean is pronounced, suggesting unstable core posture.');
    }
    if (metrics.visibilityScore < 0.35) {
      issues.add('Body visibility is low; capture more of the legs and torso.');
    }
    return issues;
  }

  static List<String> _buildTips(
    BiomechanicsMetrics metrics,
    List<String> issues,
  ) {
    final tips = <String>[];
    if (metrics.averageKneeAngle > 100) {
      tips.add('Focus on reaching a deeper squat while keeping the knees stable.');
    }
    if (metrics.symmetryDelta > 12) {
      tips.add('Drive through both legs evenly to reduce asymmetry.');
    }
    if (metrics.trunkAngle > 15) {
      tips.add('Keep the chest upright and avoid leaning forward too much.');
    }
    if (issues.isEmpty) {
      tips.add('Great form! Keep this movement controlled and steady.');
    }
    return tips;
  }

  static List<String> _buildDrillRecommendations(List<String> issues) {
    final drills = <String>[];
    if (issues.any((issue) => issue.contains('deeper squat'))) {
      drills.add('Hip hinge control drills');
    }
    if (issues.any((issue) => issue.contains('Asymmetry'))) {
      drills.add('Single-leg stability drills');
    }
    if (issues.any((issue) => issue.contains('core posture'))) {
      drills.add('Core stability and posture drills');
    }
    if (drills.isEmpty) {
      drills.add('Continue with structured squat progressions');
    }
    return drills;
  }
}
