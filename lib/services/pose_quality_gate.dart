import 'dart:ui';

import 'exercise_engine.dart';
import 'pose_assessment_config.dart';

/// Prioritized guidance shown to the athlete while the gate is not READY.
enum PoseGateGuidance {
  none,
  noBody,
  stepBack,
  stepCloser,
  showFeet,
  improveLighting,
  holdPhoneSteady,
  holdStill,
}

/// Single source of truth for "how good is this frame" — every debug
/// surface (skeleton overlay, setup HUD, PoseDebugOverlay) reads from the
/// same [PoseGateResult] instead of recomputing their own answer from raw
/// [PoseSnapshot] fields, which is how "bodyFull: true" and "feet outside
/// frame" ended up on screen at the same time.
class PoseGateResult {
  const PoseGateResult({
    required this.frameValid,
    required this.readyStreak,
    required this.rejectedRatio,
    required this.isReady,
    required this.guidance,
    required this.failReason,
    required this.qualityScore,
    required this.upperBodyQuality,
    required this.lowerBodyQuality,
    required this.bodyFull,
    required this.feetVisible,
    required this.headVisible,
    required this.poseStable,
    required this.bodyScalePercent,
  });

  final bool frameValid;
  final int readyStreak;
  final double rejectedRatio;
  final bool isReady;
  final PoseGateGuidance guidance;
  final String failReason;

  /// Weighted 0-100 score — see [PoseQualityGate] for the breakdown. This is
  /// the ONE number that decides [frameValid]; nothing else in the app
  /// should independently judge whether a frame is "good".
  final double qualityScore;
  final double upperBodyQuality; // 0-100, head visibility
  final double lowerBodyQuality; // 0-100, hips+knees+feet weighted
  final bool bodyFull;
  final bool feetVisible;
  final bool headVisible;
  final bool poseStable;
  final double bodyScalePercent; // 0-100, body box height as % of frame

  /// 0..1 view of [lowerBodyQuality], kept for callers that want a fraction
  /// (e.g. paint opacity) instead of a percentage.
  double get legQuality => (lowerBodyQuality / 100).clamp(0.0, 1.0);
}

/// Real READY gate for jump-test setup: computes ONE weighted quality score
/// (0-100) from body-scale, feet/knees/hips/head visibility, stability,
/// lighting and blur — and gates READY on that score alone, so no other
/// debug surface can show a contradictory "fine" reading.
///
/// Weights: full body in frame 25, feet visible 20, knees visible 15, hips
/// visible 10, head visible 10, motion stability 10, lighting 5, no blur 5.
/// `isReady` additionally requires the score to hold ≥
/// [PoseAssessmentConfig.gateReadyQualityThreshold] for
/// [PoseAssessmentConfig.gateReadyConsecutiveRequired] consecutive frames,
/// with the rejected-frame ratio over a rolling window staying low.
class PoseQualityGate {
  int _streak = 0;
  final List<bool> _window = [];
  PoseSnapshot? _prevSnapshot;

  static const _feetKeys = ['leftHeel', 'rightHeel', 'leftFootIndex', 'rightFootIndex'];
  static const _kneeKeys = ['leftKnee', 'rightKnee'];
  static const _hipKeys = ['leftHip', 'rightHip'];
  static const _headKeys = ['nose', 'leftEye', 'rightEye', 'leftEar', 'rightEar'];

  void reset() {
    _streak = 0;
    _window.clear();
    _prevSnapshot = null;
  }

  PoseGateResult evaluate(PoseSnapshot? snapshot, double brightness) {
    final likelihoods = snapshot?.likelihoods ?? const <String, double>{};
    final landmarks = snapshot?.landmarks ?? const <String, Offset>{};
    final bodyPresent = snapshot != null && snapshot.landmarkCount > 0;
    final minLike = PoseAssessmentConfig.gateMinLandmarkLikelihood;

    bool clears(String key) => (likelihoods[key] ?? 0) >= minLike;

    final box = snapshot?.bodyBox;
    final bodyHeight = box?.height ?? 0.0;
    final heightOk = bodyPresent &&
        box != null &&
        bodyHeight >= PoseAssessmentConfig.gateBodyHeightMin &&
        bodyHeight <= PoseAssessmentConfig.gateBodyHeightMax;

    final margin = PoseAssessmentConfig.gateEdgeMargin;
    final edgeOk = bodyPresent &&
        box != null &&
        box.top >= margin &&
        box.bottom <= 1.0 - margin &&
        box.left >= margin &&
        box.right <= 1.0 - margin;

    final feetVisibleCount = _feetKeys.where(clears).length;
    final kneesVisibleCount = _kneeKeys.where(clears).length;
    final hipsVisibleCount = _hipKeys.where(clears).length;
    final headVisible = _headKeys.any((k) => (likelihoods[k] ?? 0) >= 0.5);
    final feetOk = feetVisibleCount >= 2; // at least one full foot (heel+toe)

    // "Full body in frame" also requires feet to actually be DETECTED, not
    // just the box-of-visible-landmarks staying inside the frame margins —
    // otherwise a body with undetected feet still shrinks its own box to
    // fit, reading as "full body: true" while feet are genuinely absent.
    final fullBodyOk = heightOk && edgeOk && feetOk;

    // ── Stability: mean displacement of required landmarks vs previous frame ──
    double landmarkDrift = 0.0;
    double boxDrift = 0.0;
    if (_prevSnapshot != null && bodyPresent) {
      final prevLandmarks = _prevSnapshot!.landmarks;
      final drifts = <double>[];
      for (final key in PoseAssessmentConfig.gateRequiredLandmarks) {
        final curr = landmarks[key];
        final prev = prevLandmarks[key];
        if (curr != null && prev != null) drifts.add((curr - prev).distance);
      }
      if (drifts.isNotEmpty) {
        landmarkDrift = drifts.reduce((a, b) => a + b) / drifts.length;
      }
      final prevBox = _prevSnapshot!.bodyBox;
      if (box != null && prevBox != null) {
        boxDrift = (box.center - prevBox.center).distance;
      }
    }
    final stabilityFactor =
        (1.0 - (landmarkDrift / (PoseAssessmentConfig.gateStabilityMaxDrift * 3))).clamp(0.0, 1.0);

    final lightOk = brightness < 0 || brightness >= PoseAssessmentConfig.brightnessThreshold;
    final blurFactor =
        (1.0 - (boxDrift / (PoseAssessmentConfig.gateStabilityMaxDrift * 4))).clamp(0.0, 1.0);

    // ── Weighted 0-100 quality score — the single source of truth ──────────
    final fullBodyScore = fullBodyOk ? 25.0 : 0.0;
    final feetScore = (feetVisibleCount / _feetKeys.length) * 20.0;
    final kneesScore = (kneesVisibleCount / _kneeKeys.length) * 15.0;
    final hipsScore = (hipsVisibleCount / _hipKeys.length) * 10.0;
    final headScore = headVisible ? 10.0 : 0.0;
    final stabilityScore = stabilityFactor * 10.0;
    final lightingScore = lightOk ? 5.0 : (brightness < 0 ? 2.5 : 0.0);
    final noBlurScore = blurFactor * 5.0;

    final qualityScore = bodyPresent
        ? (fullBodyScore + feetScore + kneesScore + hipsScore + headScore +
                stabilityScore + lightingScore + noBlurScore)
            .clamp(0.0, 100.0)
        : 0.0;

    // Feet and full-body-in-frame are non-negotiable for a jump test — no
    // combination of good lighting/stability/head-visibility can compensate
    // for missing feet, so they're hard requirements on top of the score
    // (otherwise a first frame with no prior-frame drift to penalize can
    // score exactly at the threshold despite missing feet entirely).
    final frameValid = qualityScore >= PoseAssessmentConfig.gateReadyQualityThreshold &&
        feetOk &&
        fullBodyOk;

    final lowerBodyQuality = ((hipsScore + kneesScore + feetScore) / 45.0 * 100.0).clamp(0.0, 100.0);
    final upperBodyQuality = (headScore / 10.0 * 100.0).clamp(0.0, 100.0);

    // ── Streak + rolling rejection window ───────────────────────────────────
    if (frameValid) {
      _streak++;
    } else {
      _streak = 0;
    }
    _window.add(frameValid);
    if (_window.length > PoseAssessmentConfig.gateWindowSize) _window.removeAt(0);
    final rejectedCount = _window.where((v) => !v).length;
    final rejectedRatio = _window.isEmpty ? 0.0 : rejectedCount / _window.length;

    final isReady = _streak >= PoseAssessmentConfig.gateReadyConsecutiveRequired &&
        rejectedRatio <= PoseAssessmentConfig.gateMaxRejectedRatio;

    // ── Guidance priority (explains WHY qualityScore is low) ───────────────
    PoseGateGuidance guidance;
    String failReason;
    if (!bodyPresent) {
      guidance = PoseGateGuidance.noBody;
      failReason = 'No body detected';
    } else if (bodyHeight > PoseAssessmentConfig.gateBodyHeightMax) {
      guidance = PoseGateGuidance.stepBack;
      failReason = 'Too close (H=${bodyHeight.toStringAsFixed(2)})';
    } else if (bodyHeight < PoseAssessmentConfig.gateBodyHeightMin) {
      guidance = PoseGateGuidance.stepCloser;
      failReason = 'Too far (H=${bodyHeight.toStringAsFixed(2)})';
    } else if (!feetOk || !edgeOk) {
      guidance = PoseGateGuidance.showFeet;
      failReason = 'Feet not clearly visible';
    } else if (!lightOk) {
      guidance = PoseGateGuidance.improveLighting;
      failReason = 'Low light (${brightness.toStringAsFixed(0)})';
    } else if (boxDrift > PoseAssessmentConfig.gateStabilityMaxDrift * 2) {
      guidance = PoseGateGuidance.holdPhoneSteady;
      failReason = 'Camera/body box unstable';
    } else if (!frameValid) {
      guidance = PoseGateGuidance.holdStill;
      failReason = 'Quality ${qualityScore.round()}% — landmarks not stable/confident yet';
    } else {
      guidance = PoseGateGuidance.none;
      failReason = '';
    }

    _prevSnapshot = snapshot;

    return PoseGateResult(
      frameValid: frameValid,
      readyStreak: _streak,
      rejectedRatio: rejectedRatio,
      isReady: isReady,
      guidance: guidance,
      failReason: failReason,
      qualityScore: qualityScore,
      upperBodyQuality: upperBodyQuality,
      lowerBodyQuality: lowerBodyQuality,
      bodyFull: fullBodyOk,
      feetVisible: feetOk,
      headVisible: headVisible,
      poseStable: stabilityFactor >= 0.7,
      bodyScalePercent: (bodyHeight * 100).clamp(0.0, 100.0),
    );
  }
}
