import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/assessment_result_model.dart';
import '../services/exercise_engine.dart';

/// Single-Leg Balance Assessment.
///
/// Unlike the jump tests, this is a static hold — there is no takeoff/landing
/// phase to detect. The athlete stands on one leg for the capture duration
/// and the score is built from postural control over that whole window:
/// centre-of-mass sway, pelvic (hip) level control, stance-knee angle
/// stability, and trunk lean consistency. All metrics are computed directly
/// from pose landmarks, not randomised or hardcoded.
class BalanceAnalysisService {
  static String _generateId(String playerId, String testTypeName) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix =
        playerId.length > 8 ? playerId.substring(playerId.length - 8) : playerId;
    return '${suffix}_${testTypeName}_$ts';
  }

  static AssessmentResult analyze(
    String playerId,
    String playerName,
    List<PoseSnapshot> frames,
  ) {
    final validFrames = frames
        .where((f) =>
            f.confidence > 0.40 &&
            f.landmarkCount >= 8 &&
            f.landmarks.containsKey('leftHip') &&
            f.landmarks.containsKey('rightHip'))
        .toList();

    if (validFrames.length < 15) {
      return _insufficientResult(playerId, playerName);
    }

    // Stance leg = the ankle whose vertical position stays closer to the
    // ground across the capture (the lifted leg's ankle rises and varies more).
    final stanceSide = _detectStanceSide(validFrames);

    final swayScore = _computeSwayScore(validFrames);
    final hipLevelScore = _computeHipLevelScore(validFrames);
    final kneeStabilityScore = _computeKneeStabilityScore(validFrames, stanceSide);
    final trunkControlScore = _computeTrunkControlScore(validFrames);

    final quality = _computeQuality(validFrames);
    final qualityCap = quality < 40 ? 55 : (quality < 65 ? 80 : 100);

    // movementQuality = stance-knee control, stability = COM sway,
    // symmetry = pelvic level (hip drop / Trendelenburg), control = trunk lean.
    final overall = ((kneeStabilityScore * 0.30) +
            (swayScore * 0.30) +
            (hipLevelScore * 0.20) +
            (trunkControlScore * 0.20))
        .round()
        .clamp(0, qualityCap);

    final (issues, tips, drills) = _buildFeedback(
        swayScore, hipLevelScore, kneeStabilityScore, trunkControlScore, quality, stanceSide);

    return AssessmentResult(
      id: _generateId(playerId, AssessmentTestType.singleLegBalance.name),
      playerId: playerId,
      playerName: playerName,
      testType: AssessmentTestType.singleLegBalance,
      overallScore: overall,
      movementQualityScore: kneeStabilityScore.clamp(0, qualityCap),
      stabilityScore: swayScore.clamp(0, qualityCap),
      symmetryScore: hipLevelScore.clamp(0, qualityCap),
      controlScore: trunkControlScore.clamp(0, qualityCap),
      qualityScore: quality,
      angleMetrics: {
        'Postural sway score': swayScore.toDouble(),
        'Hip level control score': hipLevelScore.toDouble(),
        'Stance knee stability score': kneeStabilityScore.toDouble(),
        'Trunk control score': trunkControlScore.toDouble(),
      },
      issues: issues,
      correctionTips: tips,
      recommendedDrills: drills,
      createdAt: DateTime.now(),
      debugData: {
        'validFrames': validFrames.length.toDouble(),
        'stanceSideIsLeft': stanceSide == 'left' ? 1.0 : 0.0,
        'qualityCap': qualityCap.toDouble(),
      },
    );
  }

  /// The stance leg's ankle Y varies less (foot planted) than the lifted
  /// leg's ankle Y (which sits higher/moves more while held off the ground).
  static String _detectStanceSide(List<PoseSnapshot> frames) {
    final leftAnkleYs = <double>[];
    final rightAnkleYs = <double>[];
    for (final f in frames) {
      final la = f.landmarks['leftAnkle'];
      final ra = f.landmarks['rightAnkle'];
      if (la != null) leftAnkleYs.add(la.dy);
      if (ra != null) rightAnkleYs.add(ra.dy);
    }
    if (leftAnkleYs.isEmpty) return 'right';
    if (rightAnkleYs.isEmpty) return 'left';
    // Lower average Y (closer to top of frame = lifted) → that's the raised leg.
    final leftAvg = leftAnkleYs.reduce((a, b) => a + b) / leftAnkleYs.length;
    final rightAvg = rightAnkleYs.reduce((a, b) => a + b) / rightAnkleYs.length;
    // Whichever ankle sits lower on screen (larger Y = closer to ground) is planted.
    return leftAvg > rightAvg ? 'left' : 'right';
  }

  /// Centre-of-mass sway: variance of the hip midpoint (x and y) across the
  /// hold. Lower variance = better postural control. 0–100 score.
  static int _computeSwayScore(List<PoseSnapshot> frames) {
    final xs = <double>[];
    final ys = <double>[];
    for (final f in frames) {
      final lh = f.landmarks['leftHip'];
      final rh = f.landmarks['rightHip'];
      if (lh != null && rh != null) {
        xs.add((lh.dx + rh.dx) / 2);
        ys.add((lh.dy + rh.dy) / 2);
      }
    }
    if (xs.length < 5) return 60;
    final swayX = _standardDeviation(xs);
    final swayY = _standardDeviation(ys);
    final totalSway = swayX + swayY;
    // Threshold calibrated in normalised frame units (0–1 range).
    return (100 - (totalSway / 0.05 * 100)).round().clamp(0, 100);
  }

  /// Pelvic (hip) level control — how level the hips stay throughout the
  /// hold. A larger average left/right hip height gap indicates a pelvic
  /// drop (Trendelenburg-type compensation) on the stance side.
  static int _computeHipLevelScore(List<PoseSnapshot> frames) {
    final diffs = <double>[];
    for (final f in frames) {
      final lh = f.landmarks['leftHip'];
      final rh = f.landmarks['rightHip'];
      if (lh != null && rh != null) diffs.add((lh.dy - rh.dy).abs());
    }
    if (diffs.isEmpty) return 60;
    final avgDiff = diffs.reduce((a, b) => a + b) / diffs.length;
    // Normalised frame units — 0.02 negligible, 0.08+ significant drop.
    return (100 - (avgDiff / 0.08 * 100)).round().clamp(0, 100);
  }

  /// Stability of the stance-leg knee angle — a leg that keeps buckling and
  /// re-straightening under balance load shows high angle variance.
  static int _computeKneeStabilityScore(List<PoseSnapshot> frames, String stanceSide) {
    final angles = <double>[];
    for (final f in frames) {
      final lm = f.landmarks;
      final h = lm['${stanceSide}Hip'];
      final k = lm['${stanceSide}Knee'];
      final a = lm['${stanceSide}Ankle'];
      if (h != null && k != null && a != null) {
        angles.add(_angle(h, k, a));
      }
    }
    if (angles.length < 5) return 60;
    final variance = _standardDeviation(angles);
    // Low variance (locked-in, controlled knee) = high score.
    return (100 - (variance / 12.0 * 100)).round().clamp(0, 100);
  }

  /// Trunk lean consistency — average deviation from vertical plus how much
  /// it wobbles over the hold (both penalised).
  static int _computeTrunkControlScore(List<PoseSnapshot> frames) {
    final leans = <double>[];
    for (final f in frames) {
      final lm = f.landmarks;
      final ls = lm['leftShoulder'], rs = lm['rightShoulder'];
      final lh = lm['leftHip'], rh = lm['rightHip'];
      if (ls != null && rs != null && lh != null && rh != null) {
        final midShoulder = Offset((ls.dx + rs.dx) / 2, (ls.dy + rs.dy) / 2);
        final midHip = Offset((lh.dx + rh.dx) / 2, (lh.dy + rh.dy) / 2);
        final dy = midShoulder.dy - midHip.dy;
        final dx = midShoulder.dx - midHip.dx;
        if (dy.abs() > 0.001) {
          leans.add(math.atan(dx.abs() / dy.abs()) * 180 / math.pi);
        }
      }
    }
    if (leans.length < 5) return 60;
    final avgLean = leans.reduce((a, b) => a + b) / leans.length;
    final wobble = _standardDeviation(leans);
    final avgPenalty = avgLean > 20 ? 25 : (avgLean > 12 ? 12 : 0);
    final wobblePenalty = wobble > 8 ? 20 : (wobble > 4 ? 8 : 0);
    return (100 - avgPenalty - wobblePenalty).clamp(0, 100);
  }

  static int _computeQuality(List<PoseSnapshot> frames) {
    final avgConf = frames.map((f) => f.confidence).reduce((a, b) => a + b) / frames.length;
    final avgVis =
        frames.map((f) => f.bodyFullyVisible ? 1.0 : 0.5).reduce((a, b) => a + b) / frames.length;
    return ((avgConf * 50) + (avgVis * 50)).round().clamp(0, 100);
  }

  static double _standardDeviation(List<double> values) {
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.fold<double>(0, (sum, v) => sum + (v - mean) * (v - mean)) / values.length;
    return math.sqrt(variance);
  }

  static double _angle(Offset a, Offset joint, Offset b) {
    final v1 = a - joint;
    final v2 = b - joint;
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final mag = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy) *
        math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy);
    if (mag < 0.0001) return 170.0;
    return math.acos((dot / mag).clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  static (List<String>, List<String>, List<String>) _buildFeedback(
    int swayScore,
    int hipLevelScore,
    int kneeStabilityScore,
    int trunkControlScore,
    int quality,
    String stanceSide,
  ) {
    final issues = <String>[];
    final tips = <String>[];
    final drills = <String>[];

    if (quality < 50) {
      issues.add('Assessment quality low — camera position or lighting may affect accuracy.');
      tips.add('Ensure full body is visible and well lit throughout the hold.');
    }

    if (swayScore < 55) {
      issues.add('High postural sway detected — balance control needs development.');
      tips.add('Focus on a fixed visual point and engage the core throughout the hold.');
      drills.add('Single-leg stance 3×30s, single-leg stance eyes closed 3×15s, wobble board 3×30s.');
    } else if (swayScore < 75) {
      issues.add('Moderate postural sway — room to improve steady-state balance.');
      tips.add('Progress hold duration gradually while keeping trunk still.');
      drills.add('Single-leg stance 3×45s, single-leg reach drills 3×8.');
    }

    if (hipLevelScore < 55) {
      issues.add('Significant pelvic drop on the stance side — possible hip abductor weakness.');
      tips.add('Strengthen glute medius to control pelvic level during single-leg stance.');
      drills.add('Side-lying hip abduction 3×15, single-leg glute bridge 3×12, clamshells 3×15.');
    } else if (hipLevelScore < 75) {
      issues.add('Mild pelvic drop under single-leg load.');
      tips.add('Cue "level hips" during the hold — check in a mirror if available.');
      drills.add('Band walks 3×15, single-leg deadlift 3×8.');
    }

    if (kneeStabilityScore < 55) {
      issues.add('Stance knee shows significant instability (buckling/re-straightening).');
      tips.add('Build isometric strength around the knee before progressing hold time.');
      drills.add('Wall sit 3×30s, single-leg squat to box 3×8, terminal knee extension 3×15.');
    }

    if (trunkControlScore < 55) {
      issues.add('Trunk lean/wobble during the hold — core control needs attention.');
      tips.add('Keep chest tall and ribs stacked over hips throughout the hold.');
      drills.add('Dead bug 3×10, Pallof press 3×12, plank variations 3×30s.');
    }

    if (issues.isEmpty || (issues.length == 1 && quality < 50)) {
      final side = stanceSide == 'left' ? 'left' : 'right';
      issues.add('Solid single-leg balance on the $side leg — good postural control.');
      tips.add('Progress to dynamic/perturbation balance work under fatigue.');
      drills.add('Single-leg stance with ball toss 3×30s, single-leg hop and hold 3×6.');
    }

    return (issues, tips, drills);
  }

  static AssessmentResult _insufficientResult(String playerId, String playerName) {
    return AssessmentResult(
      id: _generateId(playerId, AssessmentTestType.singleLegBalance.name),
      playerId: playerId,
      playerName: playerName,
      testType: AssessmentTestType.singleLegBalance,
      overallScore: 0,
      movementQualityScore: 0,
      stabilityScore: 0,
      symmetryScore: 0,
      controlScore: 0,
      qualityScore: 15,
      angleMetrics: {},
      issues: ['Insufficient frames captured — reposition camera and retry.'],
      correctionTips: [
        'Ensure full body is visible throughout the hold.',
        'Camera should be 2–3m away at hip height.',
        'Hold a clear single-leg stance in the centre of the frame for at least 5 seconds.',
      ],
      recommendedDrills: [],
      createdAt: DateTime.now(),
      invalidReason: 'insufficient_frames',
    );
  }
}
