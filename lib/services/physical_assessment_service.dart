import '../models/assessment_result_model.dart';
import '../services/biomechanics_service.dart';
import '../services/exercise_engine.dart';
import '../services/squat_phase_detector.dart';
import '../services/squat_rules_engine.dart';

class PhysicalAssessmentService {
  static AssessmentResult analyzeSquat(
    AssessmentTestType testType,
    String playerId,
    String playerName,
    List<PoseSnapshot> frames,
  ) {
    // Phase 1: Filter low-confidence frames
    final validFrames = frames
        .where((f) => f.confidence > 0.45 && f.landmarkCount >= 10 && f.bodyFullyVisible)
        .toList();

    if (validFrames.length < 12) {
      // Insufficient quality data
      return AssessmentResult(
        id: '',
        playerId: playerId,
        playerName: playerName,
        testType: testType,
        overallScore: 0,
        movementQualityScore: 0,
        stabilityScore: 0,
        symmetryScore: 0,
        controlScore: 0,
        qualityScore: 20,
        angleMetrics: {},
        issues: ['Assessment quality too low — insufficient valid frames captured. Reposition camera and try again.'],
        correctionTips: ['Ensure athlete is fully visible', 'Improve lighting conditions', 'Keep camera steady at hip height'],
        recommendedDrills: [],
        createdAt: DateTime.now(),
      );
    }

    // Phase 2: Analyze sequence to get extended biomechanics metrics
    final squat = BiomechanicsService.analyzeSquatSequence(validFrames);

    // Phase 3: Detect squat phases (descent/bottom/ascent)
    final leftKneeAngles = validFrames
        .map((f) {
          final m = BiomechanicsService.analyzePose(f);
          return m.leftKneeAngle;
        })
        .toList();
    final rightKneeAngles = validFrames
        .map((f) {
          final m = BiomechanicsService.analyzePose(f);
          return m.rightKneeAngle;
        })
        .toList();

    final repMetrics = SquatPhaseDetector.detectPhases(leftKneeAngles, rightKneeAngles);

    // Phase 4: Evaluate rules and get violations
    final violations = SquatRulesEngine.evaluate(repMetrics, squat);

    // Phase 5: Calculate scores using phase-aware and rule-based logic
    final depthScore = _computeDepthScore(repMetrics.minKneeAngle, repMetrics.repDetected);
    final symmetryScore = _computeSymmetryScore(repMetrics.bottomSymmetryDelta);
    final stabilityScore = _computeStabilityScore(squat, violations);
    final movementQualityScore = _computeMovementQualityScore(depthScore, squat, violations);
    final controlScore = ((movementQualityScore * 0.4) + (stabilityScore * 0.35) + (symmetryScore * 0.25))
        .round()
        .clamp(0, 100);

    final qualityScore = _computeQualityScore(validFrames.length, squat.visibilityScore, repMetrics.repDetected);

    // Quality-based score cap: low-quality data can't produce high scores
    final qualityCap = qualityScore < 40 ? 55 : (qualityScore < 65 ? 80 : 100);

    int cappedOverall = ((movementQualityScore * 0.35) +
            (stabilityScore * 0.25) +
            (symmetryScore * 0.20) +
            (controlScore * 0.20))
        .round()
        .clamp(0, qualityCap);

    // Phase 6: Build issues, tips, drills from rule violations
    final (issues, tips, drills) = _buildFromRuleViolations(violations, qualityScore);

    // Debug data (not persisted)
    final debugData = <String, double>{
      'totalFrames': frames.length.toDouble(),
      'validFrames': validFrames.length.toDouble(),
      'bottomFrameIdx': squat.bottomFrameIndex.toDouble(),
      'minLeftKnee': squat.minLeftKneeAngle,
      'minRightKnee': squat.minRightKneeAngle,
      'bottomKneeAngle': squat.bottomKneeAngle,
      'hipDepthAtBottom': squat.hipDepthAtBottom,
      'avgConf': squat.avgLowerBodyConf,
      'trunkLean': squat.trunkLeanDeg,
      'kneeAlignment': squat.kneeAlignmentScore,
      'repDetected': repMetrics.repDetected ? 1 : 0,
      'qualityCap': qualityCap.toDouble(),
    };

    return AssessmentResult(
      id: '',
      playerId: playerId,
      playerName: playerName,
      testType: testType,
      overallScore: cappedOverall,
      movementQualityScore: movementQualityScore.clamp(0, qualityCap),
      stabilityScore: stabilityScore.clamp(0, qualityCap),
      symmetryScore: symmetryScore.clamp(0, qualityCap),
      controlScore: controlScore.clamp(0, qualityCap),
      qualityScore: qualityScore,
      angleMetrics: {
        'Left knee': squat.minLeftKneeAngle > 0 ? squat.minLeftKneeAngle : squat.leftKneeAngle,
        'Right knee': squat.minRightKneeAngle > 0 ? squat.minRightKneeAngle : squat.rightKneeAngle,
        'Left hip': squat.leftHipAngle,
        'Right hip': squat.rightHipAngle,
        'Trunk lean': squat.trunkLeanDeg,
        'Squat depth': squat.bottomKneeAngle > 0 ? squat.bottomKneeAngle : repMetrics.minKneeAngle,
        'Hip level': squat.hipLevelDifference,
      },
      issues: issues,
      correctionTips: tips,
      recommendedDrills: drills,
      createdAt: DateTime.now(),
      debugData: debugData,
    );
  }

  static int _computeDepthScore(double minKneeAngle, bool repDetected) {
    if (!repDetected) return 0;
    if (minKneeAngle <= 90) return 100;
    if (minKneeAngle <= 110) return 90;
    if (minKneeAngle <= 130) return 70;
    if (minKneeAngle <= 140) return 50;
    return 25;
  }

  static int _computeSymmetryScore(double bottomSymmetryDelta) {
    if (bottomSymmetryDelta < 5) return 100;
    if (bottomSymmetryDelta < 10) return 85;
    if (bottomSymmetryDelta < 20) return 65;
    return 40;
  }

  static int _computeStabilityScore(SquatBiomechanicsMetrics metrics, List<SquatRuleViolation> violations) {
    int base = ((metrics.centerStability * 100).clamp(0, 100)).toInt();
    double penalty = 0;

    for (final v in violations) {
      if (v.rule.id.contains('valgus')) {
        penalty += v.rule.penalty;
      }
    }

    return (base - penalty).toInt().clamp(0, 100);
  }

  static int _computeMovementQualityScore(int depthScore, SquatBiomechanicsMetrics metrics, List<SquatRuleViolation> violations) {
    int base = ((depthScore * 0.6) + 40).toInt(); // Depth + baseline

    double penalty = 0;
    for (final v in violations) {
      if (v.rule.severity == RuleSeverity.critical || v.rule.severity == RuleSeverity.moderate) {
        penalty += v.rule.penalty * 0.5;
      }
    }

    return (base - penalty).toInt().clamp(10, 100);
  }

  static int _computeQualityScore(int validFrameCount, double visibilityScore, bool repDetected) {
    int frameScore = ((validFrameCount / 30 * 100).clamp(0, 100)).toInt();
    int visibleScore = ((visibilityScore * 100).clamp(0, 100)).toInt();
    int repBonus = repDetected ? 20 : 0;

    return ((frameScore * 0.4) + (visibleScore * 0.4) + repBonus).toInt().clamp(0, 100);
  }

  static (List<String>, List<String>, List<String>) _buildFromRuleViolations(
    List<SquatRuleViolation> violations,
    int qualityScore,
  ) {
    final issues = <String>[];
    final tips = <String>[];
    final drills = <String>[];

    // Add quality warning if needed
    if (qualityScore < 50) {
      issues.add('Assessment quality low — camera position or lighting may affect accuracy.');
    }

    // Add top 3 critical/moderate violations
    int ruleCount = 0;
    for (final v in violations) {
      if (ruleCount >= 3) break;
      if (v.rule.severity != RuleSeverity.minor) {
        issues.add(v.rule.explanation);
        tips.add(v.rule.tip);
        drills.add(v.rule.drill);
        ruleCount++;
      }
    }

    // Fallback if no violations
    if (issues.isEmpty) {
      issues.add('Excellent squat form — strong depth and control.');
      tips.add('Maintain this pattern with consistent tempo and body positioning.');
      drills.add('Continue with loaded progressions: barbell squat 5×5, weighted pauses.');
    }

    return (issues, tips, drills);
  }

}
