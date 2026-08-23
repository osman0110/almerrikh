import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/assessment_result_model.dart';
import '../services/exercise_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model returned from jump phase analysis
// ─────────────────────────────────────────────────────────────────────────────

class JumpBiomechanics {
  const JumpBiomechanics({
    required this.jumpDetected,
    required this.jumpHeightNorm,
    required this.jumpHeightEstCm,
    required this.flightTimeEstMs,
    required this.takeoffFrameIdx,
    required this.peakFrameIdx,
    required this.landingFrameIdx,
    required this.landingKneeValgusScore,
    required this.landingSymmetryDelta,
    required this.trunkLeanAtLanding,
    required this.landingStabilityScore,
    required this.countermovementDetected,
    required this.countermovementDepthNorm,
    required this.validStartingPosture,
    required this.startingKneeAngle,
    required this.avgConfidence,
    required this.visibilityScore,
    required this.validFrameCount,
    required this.baselineHipY,
    required this.peakHipY,
    required this.bodyBoxHeightNorm,
  });

  final bool jumpDetected;

  // Jump height (camera-based estimate — not medical-grade)
  final double jumpHeightNorm;   // hip displacement in normalised frame units
  final double jumpHeightEstCm;  // converted estimate in centimetres
  final double flightTimeEstMs;  // estimated flight time in ms (30fps assumed)

  // Phase frame indices (into validFrames list)
  final int? takeoffFrameIdx;
  final int? peakFrameIdx;
  final int? landingFrameIdx;

  // Landing mechanics
  final double landingKneeValgusScore;  // 0–1, higher = better alignment
  final double landingSymmetryDelta;    // L/R knee angle difference (°)
  final double trunkLeanAtLanding;      // forward trunk lean (°)
  final double landingStabilityScore;   // 0–1, higher = more stable

  // CMJ-specific
  final bool   countermovementDetected;
  final double countermovementDepthNorm; // how deep the dip was (normalised)

  // SJ-specific
  final bool   validStartingPosture;
  final double startingKneeAngle; // average knee angle in first 15 frames

  // Quality
  final double avgConfidence;
  final double visibilityScore;
  final int    validFrameCount;

  // Baseline reference (used for debug/display)
  final double baselineHipY;
  final double peakHipY;
  final double bodyBoxHeightNorm;
}

// ─────────────────────────────────────────────────────────────────────────────
// Jump Analysis Service
// ─────────────────────────────────────────────────────────────────────────────

class JumpAnalysisService {
  static const double _assumedHeightCm = 175.0;
  // Fallback duration used only when frame timestamps are unavailable (web).
  static const double _fallbackFrameDurationMs = 1000.0 / 30.0;

  static String _generateId(String playerId, String testTypeName) {
    final ts     = DateTime.now().millisecondsSinceEpoch;
    final suffix = playerId.length > 8
        ? playerId.substring(playerId.length - 8)
        : playerId;
    return '${suffix}_${testTypeName}_$ts';
  }

  // Entry point — routes to type-specific analysis
  static AssessmentResult analyze(
    AssessmentTestType testType,
    String playerId,
    String playerName,
    List<PoseSnapshot> frames, {
    double? playerHeightCm,
  }) {
    final validFrames = frames
        .where((f) =>
            f.confidence > 0.40 &&
            f.landmarkCount >= 8 &&
            (f.landmarks.containsKey('leftHip') || f.landmarks.containsKey('rightHip')))
        .toList();

    if (validFrames.length < 10) {
      return _insufficientResult(testType, playerId, playerName);
    }

    final heightCm = playerHeightCm ?? _assumedHeightCm;

    switch (testType) {
      case AssessmentTestType.dropJump:
        return _analyzeDropJump(testType, playerId, playerName, validFrames, heightCm);
      case AssessmentTestType.singleLegDropJump:
        return _analyzeSingleLegDropJump(testType, playerId, playerName, validFrames);
      case AssessmentTestType.countermovementJump:
      case AssessmentTestType.squatJump:
        final bio = _detectJumpPhases(validFrames, testType, heightCm);
        return _buildResult(testType, playerId, playerName, bio, validFrames);
      case AssessmentTestType.jumpLanding:
        return _analyzeJumpLanding(testType, playerId, playerName, validFrames, heightCm);
      default:
        return _insufficientResult(testType, playerId, playerName);
    }
  }

  // ── Jump Landing Assessment ────────────────────────────────────────────────
  // Scores landing mechanics only (valgus, symmetry, trunk lean, stability,
  // soft-landing knee flexion) — jump height/power is not part of the score,
  // unlike CMJ/SJ, since this test evaluates landing quality specifically.

  static AssessmentResult _analyzeJumpLanding(
    AssessmentTestType testType,
    String playerId,
    String playerName,
    List<PoseSnapshot> frames,
    double playerHeightCm,
  ) {
    final hipYs = _extractHipYs(frames);
    final bodyBoxH = _avgBodyBoxHeight(frames.take(15).toList());
    final baselineHipY = _computeBaseline(hipYs, math.min(10, frames.length));

    final (peakIdx, _) = _findPeak(hipYs);
    final landingIdx = _findLanding(hipYs, peakIdx, baselineHipY, bodyBoxH) ??
        math.min(peakIdx + 4, frames.length - 1);

    final lStart = math.max(0, landingIdx - 2);
    final lEnd = math.min(landingIdx + 10, frames.length);
    final landingFrames = frames.sublist(lStart, lEnd);

    if (landingFrames.length < 3) {
      return _insufficientResult(testType, playerId, playerName);
    }

    final valgus = _computeLandingValgus(landingFrames);
    final symDelta = _computeLandingSymmetryDelta(landingFrames);
    final trunkLean = _computeTrunkLean(landingFrames);
    final stability = _computeLandingStability(landingFrames);
    final kneeFlexion = _computeAvgKneeAngle(landingFrames);

    final quality = _computeQualityBasic(frames);
    final qualityCap = quality < 40 ? 55 : (quality < 65 ? 80 : 100);

    final softLandingScore = _softLandingScore(kneeFlexion);
    final stabilityScore = (stability * 100).round().clamp(0, 100);
    final symmetryScore = _symmetryScore(symDelta);
    final valgusScore = (valgus * 100).round().clamp(0, 100);
    final controlScore = _landingControlScore(trunkLean, stability);

    final movementScore = ((valgusScore * 0.5) + (softLandingScore * 0.5))
        .round()
        .clamp(0, 100);

    final overall = ((movementScore * 0.35) +
            (stabilityScore * 0.25) +
            (symmetryScore * 0.20) +
            (controlScore * 0.20))
        .round()
        .clamp(0, qualityCap);

    final (issues, tips, drills) = _buildJumpLandingFeedback(
        valgus, symDelta, trunkLean, stability, kneeFlexion, quality);

    return AssessmentResult(
      id: _generateId(playerId, testType.name),
      playerId: playerId,
      playerName: playerName,
      testType: testType,
      overallScore: overall,
      movementQualityScore: movementScore.clamp(0, qualityCap),
      stabilityScore: stabilityScore.clamp(0, qualityCap),
      symmetryScore: symmetryScore.clamp(0, qualityCap),
      controlScore: controlScore.clamp(0, qualityCap),
      qualityScore: quality,
      angleMetrics: {
        'Landing valgus score': valgus * 100,
        'Landing symmetry Δ': symDelta,
        'Trunk lean at landing (°)': trunkLean,
        'Landing stability': stability * 100,
        'Landing knee flexion (°)': kneeFlexion,
      },
      issues: issues,
      correctionTips: tips,
      recommendedDrills: drills,
      createdAt: DateTime.now(),
      debugData: {
        'landingIdx': landingIdx.toDouble(),
        'valgus': valgus,
        'symDelta': symDelta,
        'trunkLean': trunkLean,
        'stability': stability,
        'kneeFlexion': kneeFlexion,
        'qualityCap': qualityCap.toDouble(),
      },
    );
  }

  // Average knee angle (both legs) across the landing window — a proxy for
  // how much the knee bends to absorb impact. ~170° = stiff/straight leg,
  // ~110-150° = active flexion (good shock absorption).
  static double _computeAvgKneeAngle(List<PoseSnapshot> frames) {
    final angles = <double>[];
    for (final f in frames) {
      final lm = f.landmarks;
      for (final side in [
        ['leftHip', 'leftKnee', 'leftAnkle'],
        ['rightHip', 'rightKnee', 'rightAnkle'],
      ]) {
        final h = lm[side[0]], k = lm[side[1]], a = lm[side[2]];
        if (h != null && k != null && a != null) {
          angles.add(_angle(h, k, a));
        }
      }
    }
    if (angles.isEmpty) return 170.0;
    return angles.reduce((a, b) => a + b) / angles.length;
  }

  static int _softLandingScore(double kneeFlexionDeg) {
    if (kneeFlexionDeg >= 100 && kneeFlexionDeg <= 150) return 100;
    if (kneeFlexionDeg > 150 && kneeFlexionDeg <= 160) return 80;
    if (kneeFlexionDeg > 160) return 55; // near-straight leg landing — stiff
    if (kneeFlexionDeg >= 85 && kneeFlexionDeg < 100) return 75; // deep but controlled
    return 50; // very deep flexion — possible instability
  }

  static int _landingControlScore(double trunkLean, double stability) {
    int score = 80;
    if (trunkLean > 30) score -= 25;
    else if (trunkLean > 20) score -= 12;
    if (stability < 0.4) score -= 20;
    else if (stability < 0.6) score -= 8;
    return score.clamp(0, 100);
  }

  static (List<String>, List<String>, List<String>) _buildJumpLandingFeedback(
    double valgus,
    double symDelta,
    double trunkLean,
    double stability,
    double kneeFlexion,
    int quality,
  ) {
    final issues = <String>[];
    final tips = <String>[];
    final drills = <String>[];

    if (quality < 50) {
      issues.add('Assessment quality low — camera position or lighting may affect accuracy.');
    }

    if (valgus < 0.55) {
      issues.add('Significant knee collapse (valgus) detected on landing — injury risk.');
      tips.add('Cue "push knees out" on landing. Strengthen glutes and hip abductors.');
      drills.add('Resistance band squats 3×12, lateral band walks 3×15, single-leg press 3×10.');
    } else if (valgus < 0.72) {
      issues.add('Mild knee valgus on landing — monitor under fatigue.');
      tips.add('Ensure knees track over toes throughout landing deceleration.');
      drills.add('Single-leg squats 3×8, glute bridges 3×15.');
    }

    if (kneeFlexion > 160) {
      issues.add('Stiff, near-straight-leg landing (${kneeFlexion.round()}°) — poor shock absorption.');
      tips.add('Land softly: absorb through ankles → knees → hips with active knee bend.');
      drills.add('Soft landing drills 3×8, pause squats 3×10, step-off landings 3×6.');
    } else if (kneeFlexion < 85) {
      issues.add('Very deep knee flexion on landing (${kneeFlexion.round()}°) — check control at depth.');
      tips.add('Land with a controlled, moderate squat depth rather than collapsing down.');
      drills.add('Box step-down with hold 3×8, tempo squats 3×8.');
    }

    if (symDelta > 15) {
      issues.add('Asymmetric landing detected — L/R knee angle difference ${symDelta.round()}°.');
      tips.add('Work on bilateral landing drills to balance L/R absorption.');
      drills.add('Single-leg box step-down 3×8 each leg, split squat 3×10.');
    }

    if (stability < 0.5) {
      issues.add('Landing stability low — excessive sway or balance loss after landing.');
      tips.add('Stick the landing and hold position for 2 seconds before moving.');
      drills.add('Pause landings 3×6, balance board training 3×60s.');
    }

    if (trunkLean > 25) {
      issues.add('Excessive forward trunk lean on landing (${trunkLean.round()}°).');
      tips.add('Keep chest up on landing — think "tall landing position".');
      drills.add('Overhead squat 3×8, landing drills with wall reference 3×6.');
    }

    if (issues.isEmpty || (issues.length == 1 && quality < 50)) {
      issues.add('Solid landing mechanics — good shock absorption and alignment.');
      tips.add('Maintain this landing pattern under fatigue and progress to reactive tasks.');
      drills.add('Depth drops 3×5, reactive landing-to-sprint 3×4.');
    }

    return (issues, tips, drills);
  }

  // ── Drop Jump Analysis ─────────────────────────────────────────────────────

  static AssessmentResult _analyzeDropJump(
    AssessmentTestType testType,
    String playerId,
    String playerName,
    List<PoseSnapshot> frames,
    double playerHeightCm,
  ) {
    final hipYs    = _extractHipYs(frames);
    final bodyBoxH = _avgBodyBoxHeight(frames.take(15).toList());
    final baseline = _computeBaseline(hipYs, 10);

    // First valley = maximum hip Y → first landing after drop
    final valleyIdx = _findValley(hipYs, 5, frames.length - 1);

    // Second peak = minimum hip Y after valley → reactive jump peak
    final (peakIdx, peakHipY) = _findPeakAfter(hipYs, valleyIdx);

    // Takeoff after landing (where hip starts rising from valley)
    final takeoffAfterLanding =
        _findTakeoffAfterValley(hipYs, valleyIdx, peakIdx, bodyBoxH);
    final takeoffAfterLandingIdx =
        (takeoffAfterLanding ?? valleyIdx + 2).clamp(0, frames.length - 1);
    final gcFrames = (takeoffAfterLandingIdx - valleyIdx).abs();
    final gcTimeMs = _durationMs(frames, valleyIdx, takeoffAfterLandingIdx, gcFrames);

    // Reactive jump height
    final reactiveDisp = (baseline - peakHipY).clamp(0.0, 1.0);
    final heightRatio   = bodyBoxH > 0 ? reactiveDisp / bodyBoxH : 0.0;
    final reactiveCm    = heightRatio * playerHeightCm;

    // RSI = jump height (m) / ground contact time (s)
    final gcSec = gcTimeMs / 1000.0;
    final rsi   = (gcSec > 0.05 && reactiveCm > 5)
        ? (reactiveCm / 100.0) / gcSec
        : 0.0;

    // Landing stiffness (0–1, moderate = good)
    final stiffness = _computeLandingStiffness(hipYs, valleyIdx, bodyBoxH);

    // Landing mechanics around first landing
    final lStart = math.max(0, valleyIdx - 3);
    final lEnd   = math.min(valleyIdx + 8, frames.length);
    final lFrames = frames.sublist(lStart, lEnd);

    final valgus    = _computeLandingValgus(lFrames);
    final symDelta  = _computeLandingSymmetryDelta(lFrames);
    final trunkLean = _computeTrunkLean(lFrames);
    final stability = _computeLandingStability(lFrames);

    // Quality
    final quality    = _computeQualityBasic(frames);
    final qualityCap = quality < 40 ? 55 : (quality < 65 ? 80 : 100);

    // Scores
    final rsiScore       = _rsiScore(rsi);
    final landingScore   = _landingQualityScore(valgus, stability, trunkLean);
    final symmetryScore  = _symmetryScore(symDelta);
    final controlScore   = _djControlScore(stiffness, trunkLean);
    final movementScore  = ((rsiScore * 0.6) + (landingScore * 0.4)).round().clamp(0, 100);

    final overall = ((movementScore * 0.35) +
            (landingScore * 0.25) +
            (symmetryScore * 0.20) +
            (controlScore * 0.20))
        .round()
        .clamp(0, qualityCap);

    final (issues, tips, drills) = _buildDJFeedback(
        reactiveCm, gcTimeMs, rsi, valgus, symDelta, trunkLean, stiffness, quality);

    return AssessmentResult(
      id:                   _generateId(playerId, testType.name),
      playerId:             playerId,
      playerName:           playerName,
      testType:             testType,
      overallScore:         overall,
      movementQualityScore: movementScore.clamp(0, qualityCap),
      stabilityScore:       landingScore.clamp(0, qualityCap),
      symmetryScore:        symmetryScore.clamp(0, qualityCap),
      controlScore:         controlScore.clamp(0, qualityCap),
      qualityScore:         quality,
      angleMetrics: {
        'Reactive height (est cm)':    reactiveCm,
        'Ground contact (est ms)':     gcTimeMs,
        'RSI estimate':                rsi,
        'Landing stiffness':           stiffness * 100,
        'Landing valgus score':        valgus * 100,
        'Landing symmetry Δ':          symDelta,
        'Trunk lean at landing (°)':   trunkLean,
      },
      issues:            issues,
      correctionTips:    tips,
      recommendedDrills: drills,
      createdAt:         DateTime.now(),
      debugData: {
        'valleyIdx':       valleyIdx.toDouble(),
        'gcFrames':        gcFrames.toDouble(),
        'gcTimeMs':        gcTimeMs,
        'reactiveCm':      reactiveCm,
        'rsi':             rsi,
        'stiffness':       stiffness,
        'qualityCap':      qualityCap.toDouble(),
      },
    );
  }

  // ── Single Leg Drop Jump Analysis ─────────────────────────────────────────

  static AssessmentResult _analyzeSingleLegDropJump(
    AssessmentTestType testType,
    String playerId,
    String playerName,
    List<PoseSnapshot> frames,
  ) {
    final hipYs    = _extractHipYs(frames);

    // Landing frame = valley in hip trajectory (maximum hip Y)
    final valleyIdx = _findValley(hipYs, 5, frames.length - 1);

    final lStart  = math.max(0, valleyIdx - 3);
    final lEnd    = math.min(valleyIdx + 18, frames.length);
    final lFrames = frames.sublist(lStart, lEnd);

    // Per-leg metrics at landing
    final valgusL    = _computeSingleLegValgus(lFrames, 'left');
    final valgusR    = _computeSingleLegValgus(lFrames, 'right');
    final ankleCtlL  = _computeAnkleControl(lFrames, 'left');
    final ankleCtlR  = _computeAnkleControl(lFrames, 'right');
    final stabilityL = _computeSingleLegStability(lFrames, 'left');
    final stabilityR = _computeSingleLegStability(lFrames, 'right');
    final trunkLean  = _computeTrunkLean(lFrames);

    // Asymmetry
    final valgusAsym    = (valgusL - valgusR).abs();
    final stabilityAsym = (stabilityL - stabilityR).abs();
    final asymmetryPct  = ((valgusAsym + stabilityAsym) / 2 * 100).clamp(0.0, 100.0);
    final asymmetryScore = (100.0 - asymmetryPct).clamp(0.0, 100.0);

    // Risk flag
    final riskFlag = valgusL < 0.50 || valgusR < 0.50 ||
        stabilityL < 0.40  || stabilityR < 0.40 ||
        asymmetryScore < 60;

    // Scores
    final quality    = _computeQualityBasic(frames);
    final qualityCap = quality < 40 ? 55 : (quality < 65 ? 80 : 100);

    final avgValgus   = (valgusL + valgusR) / 2;
    final avgStability = (stabilityL + stabilityR) / 2;
    final avgAnkle    = (ankleCtlL + ankleCtlR) / 2;
    final trunkCtrl   = (1.0 - trunkLean / 45.0).clamp(0.0, 1.0);

    final movementScore  = (avgValgus * 100).round().clamp(0, 100);
    final stabilityScore = (avgStability * 100).round().clamp(0, 100);
    final symScore       = asymmetryScore.round();
    final controlScore   = ((avgAnkle * 0.5 + trunkCtrl * 0.5) * 100).round().clamp(0, 100);

    final overall = ((movementScore * 0.35) +
            (stabilityScore * 0.25) +
            (symScore * 0.20) +
            (controlScore * 0.20))
        .round()
        .clamp(0, qualityCap);

    final (issues, tips, drills) = _buildSLDJFeedback(
        valgusL, valgusR, stabilityL, stabilityR,
        ankleCtlL, ankleCtlR, asymmetryScore, riskFlag, trunkLean, quality);

    return AssessmentResult(
      id:                   _generateId(playerId, testType.name),
      playerId:             playerId,
      playerName:           playerName,
      testType:             testType,
      overallScore:         overall,
      movementQualityScore: movementScore.clamp(0, qualityCap),
      stabilityScore:       stabilityScore.clamp(0, qualityCap),
      symmetryScore:        symScore.clamp(0, qualityCap),
      controlScore:         controlScore.clamp(0, qualityCap),
      qualityScore:         quality,
      angleMetrics: {
        'Left knee valgus':     valgusL * 100,
        'Right knee valgus':    valgusR * 100,
        'Left ankle control':   ankleCtlL * 100,
        'Right ankle control':  ankleCtlR * 100,
        'Left stability':       stabilityL * 100,
        'Right stability':      stabilityR * 100,
        'L/R asymmetry score':  asymmetryScore,
        'Trunk lean (°)':       trunkLean,
      },
      issues:            issues,
      correctionTips:    tips,
      recommendedDrills: drills,
      createdAt:         DateTime.now(),
      debugData: {
        'valleyIdx':        valleyIdx.toDouble(),
        'valgusL':          valgusL,
        'valgusR':          valgusR,
        'stabilityL':       stabilityL,
        'stabilityR':       stabilityR,
        'asymmetryScore':   asymmetryScore,
        'riskFlag':         riskFlag ? 1.0 : 0.0,
        'qualityCap':       qualityCap.toDouble(),
      },
    );
  }

  // ── Phase detection (CMJ / SJ) ─────────────────────────────────────────────

  static JumpBiomechanics _detectJumpPhases(
    List<PoseSnapshot> frames,
    AssessmentTestType type,
    double playerHeightCm,
  ) {
    // Extract hip Y per frame (image Y increases downward; lower Y = higher up)
    final hipYs = _extractHipYs(frames);
    final ankleYs = _extractAnkleYs(frames);

    // Baseline: median hip Y over the longest initial low-motion window
    // (hip velocity < 0.01/frame, minimum 8 frames) — frozen, not a running
    // average, so it can't drift as the athlete starts moving.
    final baselineWindowLen = _stableBaselineWindowLength(hipYs);
    final baselineHipY = _medianOf(hipYs.take(baselineWindowLen).toList());

    // Average body box height from the baseline window (proxy for body scale;
    // fallback when leg length can't be measured).
    final bodyBoxH = _avgBodyBoxHeight(frames.take(baselineWindowLen).toList());

    // Leg length from the same frozen baseline window — preferred
    // normalisation reference over body box height.
    final baselineAnkleY = _medianOf(ankleYs.take(baselineWindowLen).toList());
    final legLength = (baselineAnkleY - baselineHipY).abs();

    // Peak frame: minimum hip Y = player at highest point
    final (peakIdx, peakHipY) = _findPeak(hipYs);

    // Jump height in normalised units
    final hipDisplacement = (baselineHipY - peakHipY).clamp(0.0, 1.0);

    // Minimum displacement threshold: 5% of body box height
    final jumpThreshold = bodyBoxH > 0 ? bodyBoxH * 0.05 : 0.025;
    final jumpDetected   = hipDisplacement > jumpThreshold;

    // Estimate jump height in cm — normalise by leg length when available,
    // fall back to body box height.
    final normRef = legLength > 0.02 ? legLength : bodyBoxH;
    final heightRatio   = normRef > 0 ? hipDisplacement / normRef : 0.0;
    final jumpHeightCm  = heightRatio * playerHeightCm;

    // Takeoff: last frame before peak where hip Y was near baseline
    int? takeoffIdx = _findTakeoff(hipYs, peakIdx, baselineHipY, bodyBoxH);

    // Landing: first frame after peak where hip Y returns near baseline
    int? landingIdx = _findLanding(hipYs, peakIdx, baselineHipY, bodyBoxH);

    // Flight time estimate — prefer real frame timestamps, fall back to an
    // assumed 30fps duration when timestamps are unavailable (e.g. web).
    final flightFrames = (landingIdx != null && takeoffIdx != null)
        ? (landingIdx - takeoffIdx).clamp(0, frames.length).toDouble()
        : 0.0;
    final flightTimeMs = (landingIdx != null && takeoffIdx != null)
        ? _durationMs(frames, takeoffIdx, landingIdx, flightFrames.round())
        : 0.0;

    // CMJ: countermovement = was there a hip dip before propulsion?
    bool cmDetected = false;
    double cmDepth  = 0.0;
    if (type == AssessmentTestType.countermovementJump && peakIdx > 0) {
      final prePeakHipYs = hipYs.take(peakIdx).toList();
      if (prePeakHipYs.isNotEmpty) {
        final maxY = prePeakHipYs.reduce(math.max);
        cmDepth    = maxY - baselineHipY;
        cmDetected = bodyBoxH > 0
            ? cmDepth > bodyBoxH * 0.02
            : cmDepth > 0.01;
      }
    }

    // SJ: starting posture — knee angle during first 15 frames
    double startKneeAngle = 170.0;
    bool   validStart     = false;
    if (type == AssessmentTestType.squatJump) {
      startKneeAngle = _avgStartingKneeAngle(frames.take(20).toList());
      validStart     = startKneeAngle >= 70 && startKneeAngle <= 120;
    }

    // Landing mechanics — analyse frames right after landing
    final landingStart = landingIdx ?? math.max(0, frames.length - 15);
    final landingEnd   = math.min(landingStart + 12, frames.length);
    final landingFrames = frames.sublist(landingStart, landingEnd);

    final landingValgus    = _computeLandingValgus(landingFrames);
    final landingSymmetry  = _computeLandingSymmetryDelta(landingFrames);
    final trunkLean        = _computeTrunkLean(landingFrames);
    final landingStability = _computeLandingStability(landingFrames);

    // Overall confidence + visibility
    final avgConf = frames.map((f) => f.confidence).reduce((a, b) => a + b) / frames.length;
    final avgVis  = frames.map((f) => f.bodyFullyVisible ? 1.0 : 0.5)
        .reduce((a, b) => a + b) / frames.length;

    return JumpBiomechanics(
      jumpDetected:            jumpDetected,
      jumpHeightNorm:          hipDisplacement,
      jumpHeightEstCm:         jumpHeightCm,
      flightTimeEstMs:         flightTimeMs,
      takeoffFrameIdx:         takeoffIdx,
      peakFrameIdx:            peakIdx,
      landingFrameIdx:         landingIdx,
      landingKneeValgusScore:  landingValgus,
      landingSymmetryDelta:    landingSymmetry,
      trunkLeanAtLanding:      trunkLean,
      landingStabilityScore:   landingStability,
      countermovementDetected: cmDetected,
      countermovementDepthNorm: cmDepth,
      validStartingPosture:    validStart,
      startingKneeAngle:       startKneeAngle,
      avgConfidence:           avgConf,
      visibilityScore:         avgVis,
      validFrameCount:         frames.length,
      baselineHipY:            baselineHipY,
      peakHipY:                peakHipY,
      bodyBoxHeightNorm:       bodyBoxH,
    );
  }

  // ── Score builder ──────────────────────────────────────────────────────────

  static AssessmentResult _buildResult(
    AssessmentTestType testType,
    String playerId,
    String playerName,
    JumpBiomechanics bio,
    List<PoseSnapshot> frames,
  ) {
    // Quality score
    final qualityScore = _computeQuality(bio);
    final qualityCap   = qualityScore < 40 ? 55 : (qualityScore < 65 ? 80 : 100);

    // Component scores
    final powerScore     = bio.jumpDetected ? _jumpHeightScore(bio.jumpHeightEstCm) : 20;
    final stabilityScore = (bio.landingStabilityScore * 100).round().clamp(0, 100);
    final symmetryScore  = _symmetryScore(bio.landingSymmetryDelta);
    final controlScore   = _controlScore(bio, testType);
    final movementScore  = _movementScore(bio, testType, powerScore);

    final overall = ((movementScore * 0.35) +
            (stabilityScore * 0.25) +
            (symmetryScore * 0.20) +
            (controlScore * 0.20))
        .round()
        .clamp(0, qualityCap);

    final (issues, tips, drills) = _buildFeedback(bio, testType, qualityScore);

    return AssessmentResult(
      id:                   _generateId(playerId, testType.name),
      playerId:             playerId,
      playerName:           playerName,
      testType:             testType,
      overallScore:         overall,
      movementQualityScore: movementScore.clamp(0, qualityCap),
      stabilityScore:       stabilityScore.clamp(0, qualityCap),
      symmetryScore:        symmetryScore.clamp(0, qualityCap),
      controlScore:         controlScore.clamp(0, qualityCap),
      qualityScore:         qualityScore,
      angleMetrics:         _buildMetrics(bio),
      issues:               issues,
      correctionTips:       tips,
      recommendedDrills:    drills,
      createdAt:            DateTime.now(),
      invalidReason:        bio.jumpDetected ? null : 'movement_not_detected',
      debugData: {
        'validFrames':        bio.validFrameCount.toDouble(),
        'baselineHipY':       bio.baselineHipY,
        'peakHipY':           bio.peakHipY,
        'jumpHeightNorm':     bio.jumpHeightNorm,
        'jumpHeightEstCm':    bio.jumpHeightEstCm,
        'flightTimeEstMs':    bio.flightTimeEstMs,
        'landingValgus':      bio.landingKneeValgusScore,
        'landingSymmetry':    bio.landingSymmetryDelta,
        'landingStability':   bio.landingStabilityScore,
        'trunkLean':          bio.trunkLeanAtLanding,
        'cmDetected':         bio.countermovementDetected ? 1.0 : 0.0,
        'qualityCap':         qualityCap.toDouble(),
      },
    );
  }

  // ── Metric extraction helpers ──────────────────────────────────────────────

  static List<double> _extractHipYs(List<PoseSnapshot> frames) {
    return frames.map((f) {
      final lh = f.landmarks['leftHip'];
      final rh = f.landmarks['rightHip'];
      if (lh != null && rh != null) return (lh.dy + rh.dy) / 2;
      if (lh != null) return lh.dy;
      if (rh != null) return rh.dy;
      return double.nan;
    }).toList();
  }

  /// Duration between frames[idxA] and frames[idxB] using real capture
  /// timestamps when both are present; falls back to an assumed 30fps
  /// duration (web / missing timestamps) using [fallbackFrameCount].
  static double _durationMs(
      List<PoseSnapshot> frames, int idxA, int idxB, int fallbackFrameCount) {
    if (idxA < 0 || idxB < 0 || idxA >= frames.length || idxB >= frames.length) {
      return fallbackFrameCount * _fallbackFrameDurationMs;
    }
    final tsA = frames[idxA].timestampMs;
    final tsB = frames[idxB].timestampMs;
    if (tsA > 0 && tsB > 0) return (tsB - tsA).abs().toDouble();
    return fallbackFrameCount * _fallbackFrameDurationMs;
  }

  static double _computeBaseline(List<double> hipYs, int windowSize) {
    final valid = hipYs.take(windowSize).where((y) => !y.isNaN).toList();
    if (valid.isEmpty) return 0.55;
    return valid.reduce((a, b) => a + b) / valid.length;
  }

  static List<double> _extractAnkleYs(List<PoseSnapshot> frames) {
    return frames.map((f) {
      final la = f.landmarks['leftAnkle'];
      final ra = f.landmarks['rightAnkle'];
      if (la != null && ra != null) return (la.dy + ra.dy) / 2;
      if (la != null) return la.dy;
      if (ra != null) return ra.dy;
      return double.nan;
    }).toList();
  }

  static double _medianOf(List<double> values) {
    final valid = values.where((v) => !v.isNaN).toList()..sort();
    if (valid.isEmpty) return 0.55;
    final mid = valid.length ~/ 2;
    return valid.length.isOdd ? valid[mid] : (valid[mid - 1] + valid[mid]) / 2;
  }

  /// Length of the longest initial run of frames where hip Y barely moves
  /// (velocity < 0.01/frame) — the athlete standing still before the jump.
  /// Falls back to a fixed 15-frame window (the old behaviour) when fewer
  /// than 8 low-motion frames are found, e.g. a very short/noisy capture.
  static int _stableBaselineWindowLength(List<double> hipYs) {
    if (hipYs.isEmpty) return 0;
    int len = 1;
    for (int i = 1; i < hipYs.length; i++) {
      if (hipYs[i].isNaN || hipYs[i - 1].isNaN) break;
      if ((hipYs[i] - hipYs[i - 1]).abs() < 0.01) {
        len = i + 1;
      } else {
        break;
      }
    }
    if (len < 8) len = math.min(15, hipYs.length);
    return len;
  }

  static double _avgBodyBoxHeight(List<PoseSnapshot> frames) {
    final heights = frames
        .where((f) => f.bodyBox != null)
        .map((f) => f.bodyBox!.height)
        .toList();
    if (heights.isEmpty) return 0.35;
    return heights.reduce((a, b) => a + b) / heights.length;
  }

  static (int, double) _findPeak(List<double> hipYs) {
    int idx = 0;
    double minY = hipYs.firstWhere((y) => !y.isNaN, orElse: () => 0.5);
    for (int i = 0; i < hipYs.length; i++) {
      if (!hipYs[i].isNaN && hipYs[i] < minY) {
        minY = hipYs[i];
        idx  = i;
      }
    }
    return (idx, minY);
  }

  static int? _findTakeoff(
      List<double> hipYs, int peakIdx, double baselineY, double bodyH) {
    // Search backwards from peak for the last PAIR of consecutive frames
    // near baseline — a single noisy frame can no longer trigger takeoff.
    final nearBaselineThreshold = bodyH > 0 ? bodyH * 0.04 : 0.02;
    for (int i = peakIdx - 1; i >= 1; i--) {
      if (!hipYs[i].isNaN && !hipYs[i - 1].isNaN &&
          (hipYs[i] - baselineY).abs() < nearBaselineThreshold &&
          (hipYs[i - 1] - baselineY).abs() < nearBaselineThreshold) {
        return i;
      }
    }
    return null;
  }

  static int? _findLanding(
      List<double> hipYs, int peakIdx, double baselineY, double bodyH) {
    // Search forward from peak for the first PAIR of consecutive frames
    // returning near baseline — a single noisy frame can no longer trigger landing.
    final returnThreshold = bodyH > 0 ? bodyH * 0.10 : 0.05;
    for (int i = peakIdx + 1; i < hipYs.length - 1; i++) {
      if (!hipYs[i].isNaN && !hipYs[i + 1].isNaN &&
          (hipYs[i] - baselineY).abs() < returnThreshold &&
          (hipYs[i + 1] - baselineY).abs() < returnThreshold) {
        return i;
      }
    }
    return null;
  }

  static double _avgStartingKneeAngle(List<PoseSnapshot> frames) {
    final angles = <double>[];
    for (final f in frames) {
      final lm = f.landmarks;
      for (final side in [
        ['leftHip', 'leftKnee', 'leftAnkle'],
        ['rightHip', 'rightKnee', 'rightAnkle'],
      ]) {
        final h = lm[side[0]], k = lm[side[1]], a = lm[side[2]];
        if (h != null && k != null && a != null) {
          angles.add(_angle(h, k, a));
        }
      }
    }
    if (angles.isEmpty) return 170.0;
    return angles.reduce((a, b) => a + b) / angles.length;
  }

  // Landing: knee valgus score (0–1, 1 = perfect alignment)
  static double _computeLandingValgus(List<PoseSnapshot> frames) {
    if (frames.isEmpty) return 0.7;
    final scores = <double>[];
    for (final f in frames) {
      final lm = f.landmarks;
      final lh = lm['leftHip'],  lk = lm['leftKnee'],  la = lm['leftAnkle'];
      final rh = lm['rightHip'], rk = lm['rightKnee'], ra = lm['rightAnkle'];
      if (lh != null && lk != null && la != null &&
          rh != null && rk != null && ra != null) {
        // Valgus: knee X should be between hip X and ankle X
        // Left side (image coords may be mirrored, use relative position)
        final lKneeInward = (lk.dx - lh.dx) / ((la.dx - lh.dx).abs() + 0.001);
        final rKneeInward = (rk.dx - rh.dx) / ((ra.dx - rh.dx).abs() + 0.001);
        // Score: 1 if knees track over ankles, 0 if collapsed inward
        final lScore = (1.0 - (lKneeInward - 1.0).abs()).clamp(0.0, 1.0);
        final rScore = (1.0 - (rKneeInward + 1.0).abs()).clamp(0.0, 1.0);
        scores.add((lScore + rScore) / 2);
      }
    }
    if (scores.isEmpty) return 0.7;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  // Landing: L/R knee angle symmetry delta
  static double _computeLandingSymmetryDelta(List<PoseSnapshot> frames) {
    if (frames.isEmpty) return 10.0;
    final deltas = <double>[];
    for (final f in frames) {
      final lm = f.landmarks;
      final lh = lm['leftHip'],  lk = lm['leftKnee'],  la = lm['leftAnkle'];
      final rh = lm['rightHip'], rk = lm['rightKnee'], ra = lm['rightAnkle'];
      if (lh != null && lk != null && la != null &&
          rh != null && rk != null && ra != null) {
        final lAngle = _angle(lh, lk, la);
        final rAngle = _angle(rh, rk, ra);
        deltas.add((lAngle - rAngle).abs());
      }
    }
    if (deltas.isEmpty) return 10.0;
    return deltas.reduce((a, b) => a + b) / deltas.length;
  }

  // Trunk lean at landing (degrees from vertical)
  static double _computeTrunkLean(List<PoseSnapshot> frames) {
    if (frames.isEmpty) return 15.0;
    final leans = <double>[];
    for (final f in frames) {
      final lm = f.landmarks;
      final ls = lm['leftShoulder'], rs = lm['rightShoulder'];
      final lh = lm['leftHip'],     rh = lm['rightHip'];
      if (ls != null && rs != null && lh != null && rh != null) {
        final midShoulder = Offset((ls.dx + rs.dx) / 2, (ls.dy + rs.dy) / 2);
        final midHip      = Offset((lh.dx + rh.dx) / 2, (lh.dy + rh.dy) / 2);
        final dy = midShoulder.dy - midHip.dy;
        final dx = midShoulder.dx - midHip.dx;
        if (dy.abs() > 0.001) {
          final deg = math.atan(dx.abs() / dy.abs()) * 180 / math.pi;
          leans.add(deg);
        }
      }
    }
    if (leans.isEmpty) return 15.0;
    return leans.reduce((a, b) => a + b) / leans.length;
  }

  // Landing stability: 0–1, based on hip position variance after landing
  static double _computeLandingStability(List<PoseSnapshot> frames) {
    if (frames.length < 3) return 0.6;
    final hipYs = _extractHipYs(frames).where((y) => !y.isNaN).toList();
    if (hipYs.length < 3) return 0.6;
    final mean = hipYs.reduce((a, b) => a + b) / hipYs.length;
    final variance = hipYs.map((y) => math.pow(y - mean, 2)).reduce((a, b) => a + b) / hipYs.length;
    final stdDev = math.sqrt(variance);
    // Low stdDev = stable. Threshold: 0.02 normalised = very stable
    return (1.0 - (stdDev / 0.04)).clamp(0.0, 1.0);
  }

  // ── Scoring ────────────────────────────────────────────────────────────────

  static int _jumpHeightScore(double heightCm) {
    if (heightCm >= 50) return 100;
    if (heightCm >= 42) return 90;
    if (heightCm >= 35) return 78;
    if (heightCm >= 28) return 65;
    if (heightCm >= 20) return 50;
    if (heightCm >= 12) return 35;
    return 20;
  }

  static int _symmetryScore(double delta) {
    if (delta < 5)  return 100;
    if (delta < 10) return 85;
    if (delta < 20) return 65;
    return 40;
  }

  static int _controlScore(JumpBiomechanics bio, AssessmentTestType type) {
    int score = 75;
    // Trunk lean penalty
    if (bio.trunkLeanAtLanding > 30) score -= 20;
    else if (bio.trunkLeanAtLanding > 20) score -= 10;
    // SJ starting posture bonus/penalty
    if (type == AssessmentTestType.squatJump) {
      if (!bio.validStartingPosture) score -= 15;
    }
    // CMJ countermovement bonus
    if (type == AssessmentTestType.countermovementJump && bio.countermovementDetected) {
      score += 10;
    }
    return score.clamp(0, 100);
  }

  static int _movementScore(
      JumpBiomechanics bio, AssessmentTestType type, int powerScore) {
    int base = powerScore;
    // Landing valgus penalty
    if (bio.landingKneeValgusScore < 0.5) base -= 20;
    else if (bio.landingKneeValgusScore < 0.7) base -= 10;
    return base.clamp(0, 100);
  }

  static int _computeQuality(JumpBiomechanics bio) {
    int score = 0;
    score += (bio.avgConfidence * 40).round().clamp(0, 40);
    score += (bio.visibilityScore * 40).round().clamp(0, 40);
    if (bio.jumpDetected) score += 20;
    return score.clamp(0, 100);
  }

  // ── Feedback builder ───────────────────────────────────────────────────────

  static (List<String>, List<String>, List<String>) _buildFeedback(
    JumpBiomechanics bio,
    AssessmentTestType type,
    int qualityScore,
  ) {
    final issues = <String>[];
    final tips   = <String>[];
    final drills = <String>[];

    if (!bio.jumpDetected) {
      issues.add('Jump not detected — ensure athlete performs a clear vertical jump within the camera frame.');
      tips.add('Position camera 2–3m away at hip height. Make sure full body is visible.');
      drills.add('Practice jumping in place with arms overhead to create clear hip trajectory.');
      return (issues, tips, drills);
    }

    if (qualityScore < 50) {
      issues.add('Assessment quality low — camera position or lighting may affect accuracy.');
      tips.add('Improve lighting and ensure full body is visible throughout the jump.');
    }

    // Jump height feedback
    final h = bio.jumpHeightEstCm;
    if (h < 20) {
      issues.add('Jump height estimate low (${h.round()} cm*) — power output needs improvement.');
      tips.add('Focus on triple extension: ankle, knee, hip fully extended at takeoff.');
      drills.add('Box jumps 3×8, broad jumps 3×6, loaded squats 4×6 @ 70% 1RM.');
    } else if (h < 32) {
      issues.add('Moderate jump height (${h.round()} cm*). Room to develop explosive power.');
      tips.add('Add plyometric training and strengthen hip extensors.');
      drills.add('Depth drops 3×5, trap bar deadlifts 4×4, reactive hops 3×10.');
    }

    // Landing valgus
    if (bio.landingKneeValgusScore < 0.55) {
      issues.add('Significant knee collapse (valgus) detected on landing — injury risk.');
      tips.add('Cue "push knees out" on landing. Strengthen glutes and hip abductors.');
      drills.add('Resistance band squats 3×12, lateral band walks 3×15, single-leg press 3×10.');
    } else if (bio.landingKneeValgusScore < 0.72) {
      issues.add('Mild knee valgus on landing — monitor under fatigue.');
      tips.add('Ensure knees track over toes throughout landing deceleration.');
      drills.add('Single-leg squats 3×8, glute bridges 3×15.');
    }

    // Landing symmetry
    if (bio.landingSymmetryDelta > 15) {
      issues.add('Asymmetric landing detected — L/R knee angle difference ${bio.landingSymmetryDelta.round()}°.');
      tips.add('Work on single-leg landing drills to balance bilateral strength.');
      drills.add('Single-leg box step-down 3×8 each leg, split squat 3×10.');
    }

    // Landing stability
    if (bio.landingStabilityScore < 0.5) {
      issues.add('Landing stability low — excessive sway or balance loss after jump.');
      tips.add('Stick the landing: absorb through ankles → knees → hips in sequence.');
      drills.add('Pause landings 3×6, balance board training 3×60s.');
    }

    // SJ starting posture
    if (type == AssessmentTestType.squatJump && !bio.validStartingPosture) {
      issues.add('Starting squat position not ideal (${bio.startingKneeAngle.round()}° knee angle). Target: 80–110°.');
      tips.add('Hold static squat at 90° for 2 seconds before jumping.');
      drills.add('Isometric squat holds 5×30s, goblet squats 3×10 with 3s hold at bottom.');
    }

    // CMJ countermovement
    if (type == AssessmentTestType.countermovementJump && !bio.countermovementDetected) {
      issues.add('Countermovement not clearly detected — pre-stretch reflex may not be utilised.');
      tips.add('Start with a rapid dip (countermovement) before jumping to use elastic energy.');
      drills.add('CMJ with arm swing 3×5, pogo hops 3×15, depth drops 3×5.');
    }

    // Trunk lean
    if (bio.trunkLeanAtLanding > 25) {
      issues.add('Excessive forward trunk lean on landing (${bio.trunkLeanAtLanding.round()}°).');
      tips.add('Keep chest up on landing — think "tall landing position".');
      drills.add('Overhead squat 3×8, landing drills with wall reference 3×6.');
    }

    // Positive feedback
    if (issues.isEmpty || (issues.length == 1 && qualityScore < 50)) {
      final label = type == AssessmentTestType.countermovementJump ? 'CMJ' : 'Squat Jump';
      issues.add('$label execution looks solid — continue to develop explosive power.');
      tips.add('Maintain current landing mechanics under fatigue. Add progressive overload.');
      drills.add('Loaded CMJs 3×5 @ 20% BW, reactive drops 3×4, sprint starts 3×3.');
    }

    // Add camera estimate note to first issue
    if (issues.isNotEmpty && bio.jumpDetected) {
      issues[0] = '${issues[0]} (* camera-based estimate)';
    }

    return (issues, tips, drills);
  }

  static Map<String, double> _buildMetrics(JumpBiomechanics bio) {
    return {
      'Jump height (est cm)': bio.jumpHeightEstCm,
      'Flight time (est ms)': bio.flightTimeEstMs,
      'Landing valgus score': bio.landingKneeValgusScore * 100,
      'Landing symmetry Δ':  bio.landingSymmetryDelta,
      'Trunk lean (°)':      bio.trunkLeanAtLanding,
      'Landing stability':   bio.landingStabilityScore * 100,
      if (bio.validStartingPosture || bio.startingKneeAngle < 160)
        'Starting knee angle': bio.startingKneeAngle,
    };
  }

  // ── Drop Jump helpers ──────────────────────────────────────────────────────

  // Find valley = maximum hip Y (first landing after drop)
  static int _findValley(List<double> hipYs, int startFrom, int endAt) {
    int idx = startFrom.clamp(0, hipYs.length - 1);
    double maxY = hipYs[idx].isNaN ? 0 : hipYs[idx];
    for (int i = startFrom + 1; i <= endAt && i < hipYs.length; i++) {
      if (!hipYs[i].isNaN && hipYs[i] > maxY) {
        maxY = hipYs[i];
        idx  = i;
      }
    }
    return idx;
  }

  // Find peak after a valley index = minimum hip Y after valley (reactive jump)
  static (int, double) _findPeakAfter(List<double> hipYs, int afterIdx) {
    final start = (afterIdx + 1).clamp(0, hipYs.length - 1);
    int    idx  = start;
    double minY = hipYs[start].isNaN ? 0.5 : hipYs[start];
    for (int i = start + 1; i < hipYs.length; i++) {
      if (!hipYs[i].isNaN && hipYs[i] < minY) {
        minY = hipYs[i];
        idx  = i;
      }
    }
    return (idx, minY);
  }

  // Find where hip starts rising from valley → takeoff point for reactive jump
  static int? _findTakeoffAfterValley(
      List<double> hipYs, int valleyIdx, int peakIdx, double bodyH) {
    final threshold = (bodyH * 0.015).clamp(0.005, 0.04);
    for (int i = valleyIdx + 1; i < peakIdx - 1; i++) {
      if (!hipYs[i].isNaN && !hipYs[i + 1].isNaN &&
          hipYs[i] - hipYs[i + 1] > threshold) {
        return i;
      }
    }
    return null;
  }

  // Landing stiffness: rate of velocity change around the valley (0=soft, 1=stiff)
  static double _computeLandingStiffness(
      List<double> hipYs, int valleyIdx, double bodyH) {
    if (valleyIdx < 3 || valleyIdx >= hipYs.length - 3) return 0.5;
    final pre  = hipYs[valleyIdx] - hipYs[valleyIdx - 3];
    final post = hipYs[math.min(valleyIdx + 3, hipYs.length - 1)] - hipYs[valleyIdx];
    final ref  = bodyH > 0 ? bodyH : 0.35;
    return ((pre + post.abs()) / (ref * 3.0)).clamp(0.0, 1.0);
  }

  // DJ: RSI score
  static int _rsiScore(double rsi) {
    if (rsi >= 2.5) return 100;
    if (rsi >= 2.0) return 88;
    if (rsi >= 1.5) return 75;
    if (rsi >= 1.0) return 60;
    if (rsi >= 0.5) return 45;
    return 25;
  }

  // DJ: landing quality composite
  static int _landingQualityScore(double valgus, double stability, double trunk) {
    int score = (valgus * 60).round() + (stability * 40).round();
    if (trunk > 30) score -= 15;
    else if (trunk > 20) score -= 8;
    return score.clamp(0, 100);
  }

  // DJ: control score from stiffness + trunk
  static int _djControlScore(double stiffness, double trunk) {
    // Moderate stiffness (0.4–0.7) is ideal; too soft or too stiff = penalty
    final stiffPenalty = (stiffness < 0.3 || stiffness > 0.85)
        ? 20
        : (stiffness < 0.4 || stiffness > 0.75)
            ? 10
            : 0;
    final trunkPenalty = trunk > 30 ? 15 : trunk > 20 ? 8 : 0;
    return (80 - stiffPenalty - trunkPenalty).clamp(0, 100);
  }

  // ── Single Leg Drop Jump helpers ───────────────────────────────────────────

  // Single-leg knee valgus (0–1, 1 = perfect alignment)
  static double _computeSingleLegValgus(List<PoseSnapshot> frames, String side) {
    final scores = <double>[];
    for (final f in frames) {
      final lm = f.landmarks;
      final h  = lm['${side}Hip'];
      final k  = lm['${side}Knee'];
      final a  = lm['${side}Ankle'];
      if (h == null || k == null || a == null) continue;
      final dxHA = (a.dx - h.dx).abs() + 0.001;
      final kneeRatio = (k.dx - h.dx) / dxHA;
      // For left side: ratio ≈ +1 means knee tracks over ankle (good)
      // For right side: ratio ≈ -1 means knee tracks over ankle
      final expected = side == 'left' ? 1.0 : -1.0;
      final score = (1.0 - (kneeRatio - expected).abs() * 0.5).clamp(0.0, 1.0);
      scores.add(score);
    }
    if (scores.isEmpty) return 0.7;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  // Ankle lateral control — variance of ankle X relative to hip X
  static double _computeAnkleControl(List<PoseSnapshot> frames, String side) {
    final offsets = <double>[];
    for (final f in frames) {
      final a = f.landmarks['${side}Ankle'];
      final h = f.landmarks['${side}Hip'];
      if (a != null && h != null) offsets.add((a.dx - h.dx).abs());
    }
    if (offsets.length < 3) return 0.7;
    final mean     = offsets.reduce((a, b) => a + b) / offsets.length;
    final variance = offsets.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) / offsets.length;
    final stdDev   = math.sqrt(variance);
    return (1.0 - (stdDev / 0.030)).clamp(0.0, 1.0);
  }

  // Single-leg stability (hip Y variance for one side)
  static double _computeSingleLegStability(List<PoseSnapshot> frames, String side) {
    final hipYs = <double>[];
    for (final f in frames) {
      final h = f.landmarks['${side}Hip'];
      if (h != null) hipYs.add(h.dy);
    }
    if (hipYs.length < 3) return 0.65;
    final mean     = hipYs.reduce((a, b) => a + b) / hipYs.length;
    final variance = hipYs.map((y) => math.pow(y - mean, 2)).reduce((a, b) => a + b) / hipYs.length;
    return (1.0 - (math.sqrt(variance) / 0.040)).clamp(0.0, 1.0);
  }

  // Quality score without jump detection requirement
  static int _computeQualityBasic(List<PoseSnapshot> frames) {
    final avgConf = frames.isEmpty
        ? 0.0
        : frames.map((f) => f.confidence).reduce((a, b) => a + b) / frames.length;
    final avgVis = frames.isEmpty
        ? 0.0
        : frames.map((f) => f.bodyFullyVisible ? 1.0 : 0.5)
              .reduce((a, b) => a + b) / frames.length;
    return ((avgConf * 50) + (avgVis * 50)).round().clamp(0, 100);
  }

  // ── Drop Jump feedback ─────────────────────────────────────────────────────

  static (List<String>, List<String>, List<String>) _buildDJFeedback(
    double heightCm,
    double gcTimeMs,
    double rsi,
    double valgus,
    double symDelta,
    double trunk,
    double stiffness,
    int quality,
  ) {
    final issues = <String>[];
    final tips   = <String>[];
    final drills = <String>[];

    if (quality < 50) {
      issues.add('Assessment quality low — camera position or visibility may reduce accuracy.');
    }

    // RSI feedback
    if (rsi <= 0) {
      issues.add('Reactive jump not clearly detected — ensure box drop + immediate rebound is performed.');
      tips.add('Step off box and immediately jump upward without pausing on contact.');
      drills.add('Pogo hops 3×15, ankle stiffness drills 3×20, mini hurdle hops 3×8.');
    } else if (rsi < 1.0) {
      issues.add('RSI estimate low (${rsi.toStringAsFixed(2)}*) — reactive power needs development.');
      tips.add('Minimise ground contact time by using stiff ankles and rapid hip extension.');
      drills.add('Hurdle hops 3×6, depth jumps from low box 3×5, calf raises with loaded rapid push-off 3×12.');
    } else if (rsi < 1.5) {
      issues.add('RSI estimate moderate (${rsi.toStringAsFixed(2)}*) — room to improve reactive strength.');
      tips.add('Focus on quick ground contact: "hot coals" cue during landing-to-jump transition.');
      drills.add('Depth drops from 30cm box 3×6, ankle bouncing 3×20, reactive box jumps 3×5.');
    }

    // Ground contact
    if (gcTimeMs > 280) {
      issues.add('Ground contact time high (${gcTimeMs.round()} ms*) — target < 250 ms for effective drop jump.');
      tips.add('Land with pre-tensed calves and minimal knee flexion — do not squat deeply on contact.');
      drills.add('Ankle stiffness hops 3×20, single-leg hops 3×10, timed rebound jumps 3×6.');
    }

    // Landing valgus
    if (valgus < 0.55) {
      issues.add('Knee valgus (collapse) on landing — significant injury risk in reactive tasks.');
      tips.add('Cue "push floor apart" on landing. Strengthen glutes and lateral hip rotators.');
      drills.add('Single-leg glute bridge 3×12, lateral band walks 3×15, box step-down 3×10.');
    } else if (valgus < 0.72) {
      issues.add('Mild knee valgus on drop landing — monitor under fatigue and loading.');
      tips.add('Focus on knee-over-toe alignment at moment of contact.');
      drills.add('Squat to landing drill 3×8, hip abductor strengthening 3×15.');
    }

    // Symmetry
    if (symDelta > 15) {
      issues.add('Asymmetric landing — ${symDelta.round()}° L/R knee difference at contact.');
      tips.add('Check for limb dominance — strengthen weaker side with unilateral work.');
      drills.add('Single-leg drops 3×6 per leg, Bulgarian split squat 3×8, unilateral calf press 3×12.');
    }

    // Stiffness
    if (stiffness < 0.25) {
      issues.add('Landing appears too soft — insufficient spring stiffness for effective reactive jump.');
      tips.add('Increase pre-activation of calf and quad before contact. Stay rigid on touchdown.');
      drills.add('Ankle stiffness hops on flat surface 3×20, pogo jumps 3×15.');
    }

    if (issues.isEmpty) {
      issues.add('Strong drop jump mechanics — explosive reactive power with clean landing (* camera estimate).');
      tips.add('Progress to higher boxes and add training load.');
      drills.add('Loaded depth jumps 3×5, sprint starts 3×4, band-resisted CMJ 3×6.');
    } else if (!issues.any((i) => i.contains('*'))) {
      // Add estimate note
      issues[issues.length - 1] += ' (* camera-based estimate)';
    }

    return (issues, tips, drills);
  }

  // ── SLDJ feedback ──────────────────────────────────────────────────────────

  static (List<String>, List<String>, List<String>) _buildSLDJFeedback(
    double valgusL,
    double valgusR,
    double stabilityL,
    double stabilityR,
    double ankleL,
    double ankleR,
    double asymmetry,
    bool riskFlag,
    double trunk,
    int quality,
  ) {
    final issues = <String>[];
    final tips   = <String>[];
    final drills = <String>[];

    if (quality < 50) {
      issues.add('Assessment quality low — ensure full body is visible on landing.');
    }

    // Risk flag
    if (riskFlag) {
      issues.add('RISK FLAG: Significant landing asymmetry or valgus detected — potential injury risk.');
      tips.add('Prioritise unilateral strength and landing mechanics before sport-specific loading.');
      drills.add('Single-leg squat 3×10, hip abductor work 3×15, landing mechanics drills 3×8.');
    }

    // Per-leg valgus
    final weaker = valgusL < valgusR ? 'left' : 'right';
    final weakScore = math.min(valgusL, valgusR);
    if (weakScore < 0.55) {
      issues.add('Severe knee valgus on $weaker leg landing — injury risk flag.');
      tips.add('Correct $weaker leg landing pattern before progressive loading.');
      drills.add('Single-leg box step-down 3×10 ($weaker), hip abductor band walks 3×15, glute activation 3×12.');
    } else if (weakScore < 0.70) {
      issues.add('Mild knee valgus on $weaker leg — monitor under fatigue.');
      tips.add('Strengthen $weaker side hip abductors. Cue knee-out on single-leg landing.');
      drills.add('Single-leg squat 3×8 ($weaker), lateral band walk 3×15, clamshells 3×15.');
    }

    // Asymmetry
    if (asymmetry < 60) {
      issues.add('L/R asymmetry high (${(100 - asymmetry).round()}%) — significant side-to-side difference.');
      tips.add('Train weaker leg independently before bilateral work.');
      drills.add('Unilateral drills 3× per leg: step-down, split squat, single-leg press.');
    } else if (asymmetry < 80) {
      issues.add('Moderate asymmetry (${(100 - asymmetry).round()}%) — extra attention to weaker side needed.');
      tips.add('Include unilateral training 2× per week to address imbalance.');
      drills.add('Bulgarian split squat 3×10, single-leg RDL 3×8, unilateral hop and hold 3×6.');
    }

    // Ankle control
    final weakAnkle = ankleL < ankleR ? 'left' : 'right';
    if (math.min(ankleL, ankleR) < 0.55) {
      issues.add('Ankle instability on $weakAnkle side — ankle lateral control compromised.');
      tips.add('Ankle strengthening and proprioception training for $weakAnkle side.');
      drills.add('Single-leg balance on wobble board 3×30s, calf raises 3×15, ankle banded inversion 3×12.');
    }

    // Trunk lean
    if (trunk > 25) {
      issues.add('Excessive trunk lean at landing (${trunk.round()}°) — increases ACL loading.');
      tips.add('Maintain upright trunk on single-leg landing. Strengthen core stabilisers.');
      drills.add('Overhead single-leg squat 3×8, Pallof press 3×12, dead bug 3×10.');
    }

    if (issues.isEmpty) {
      issues.add('Solid single-leg landing mechanics — good symmetry and knee alignment.');
      tips.add('Maintain consistent landing quality under fatigue. Progress to reactive tasks.');
      drills.add('Single-leg hurdle hops 3×6, reactive drop to sprint 3×4.');
    }

    return (issues, tips, drills);
  }

  static AssessmentResult _insufficientResult(
      AssessmentTestType type, String playerId, String playerName) {
    return AssessmentResult(
      id: _generateId(playerId, type.name),
      playerId: playerId,
      playerName: playerName,
      testType: type,
      overallScore: 0,
      movementQualityScore: 0,
      stabilityScore: 0,
      symmetryScore: 0,
      controlScore: 0,
      qualityScore: 15,
      angleMetrics: {},
      issues: ['Insufficient frames captured — reposition camera and retry.'],
      correctionTips: [
        'Ensure full body is visible throughout the jump.',
        'Camera should be 2–3m away at hip height.',
        'Perform one clear vertical jump in the centre of the frame.',
      ],
      recommendedDrills: [],
      createdAt: DateTime.now(),
      invalidReason: 'insufficient_frames',
    );
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  static double _angle(Offset a, Offset joint, Offset b) {
    final v1 = a - joint;
    final v2 = b - joint;
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final mag = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy) *
        math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy);
    if (mag < 0.0001) return 170.0;
    return math.acos((dot / mag).clamp(-1.0, 1.0)) * 180 / math.pi;
  }
}
