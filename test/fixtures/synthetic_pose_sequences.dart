import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smart_sport_scribe_main/services/exercise_engine.dart';

/// Builders for synthetic [PoseSnapshot] sequences used to unit-test the
/// pose pipeline (smoothing, quality gate, state machine, jump measurement)
/// without a real camera or ML Kit.

const List<String> requiredLowerBodyKeys = [
  'leftHip', 'rightHip',
  'leftKnee', 'rightKnee',
  'leftAnkle', 'rightAnkle',
  'leftHeel', 'rightHeel',
  'leftFootIndex', 'rightFootIndex',
];

/// Builds one [PoseSnapshot]. [landmarks] and [likelihoods] default to a
/// full, high-confidence standing pose so tests only need to override what
/// they care about.
PoseSnapshot buildSnapshot({
  Map<String, Offset>? landmarks,
  Map<String, double>? likelihoods,
  Rect? bodyBox,
  int timestampMs = 0,
  double confidence = 0.9,
  bool bodyFullyVisible = true,
  int? landmarkCount,
}) {
  final lm = landmarks ?? standingLandmarks();
  final lk = likelihoods ?? {for (final k in lm.keys) k: 0.9};
  final box = bodyBox ?? const Rect.fromLTWH(0.3, 0.15, 0.4, 0.7);
  return PoseSnapshot(
    bodyBox: box,
    center: box.center,
    leftWrist: lm['leftWrist'],
    rightWrist: lm['rightWrist'],
    leftAnkle: lm['leftAnkle'],
    rightAnkle: lm['rightAnkle'],
    bodyFullyVisible: bodyFullyVisible,
    headVisible: true,
    shouldersVisible: true,
    hipsVisible: true,
    lowerBodyVisible: true,
    insideGuideFrame: true,
    confidence: confidence,
    detectionScore: 7,
    landmarkCount: landmarkCount ?? lm.length,
    imageSize: const Size(1280, 720),
    rotation: 0,
    landmarks: lm,
    tooClose: box.height > 0.85,
    tooFar: box.height < 0.35,
    lowLight: false,
    timestampMs: timestampMs,
    likelihoods: lk,
  );
}

/// A full-body standing pose, normalised [0,1] frame coords.
/// hipY≈0.50, kneeY≈0.65, ankleY≈0.80 (image Y increases downward).
Map<String, Offset> standingLandmarks({double hipY = 0.50, double sway = 0.0}) {
  return {
    'nose': const Offset(0.50, 0.18),
    'leftShoulder': const Offset(0.44, 0.28),
    'rightShoulder': const Offset(0.56, 0.28),
    'leftElbow': const Offset(0.42, 0.38),
    'rightElbow': const Offset(0.58, 0.38),
    'leftWrist': const Offset(0.41, 0.46),
    'rightWrist': const Offset(0.59, 0.46),
    'leftHip': Offset(0.46 + sway, hipY),
    'rightHip': Offset(0.54 + sway, hipY),
    'leftKnee': Offset(0.46 + sway, hipY + 0.15),
    'rightKnee': Offset(0.54 + sway, hipY + 0.15),
    'leftAnkle': Offset(0.46 + sway, hipY + 0.30),
    'rightAnkle': Offset(0.54 + sway, hipY + 0.30),
    'leftHeel': Offset(0.46 + sway, hipY + 0.31),
    'rightHeel': Offset(0.54 + sway, hipY + 0.31),
    'leftFootIndex': Offset(0.47 + sway, hipY + 0.32),
    'rightFootIndex': Offset(0.53 + sway, hipY + 0.32),
  };
}

/// All required landmarks at high likelihood (≥0.75) — a clean, valid frame.
Map<String, double> fullLikelihoods({double value = 0.9}) => {
      for (final k in [...requiredLowerBodyKeys, 'leftShoulder', 'rightShoulder', 'nose'])
        k: value,
    };

/// Likelihoods with feet (heel/footIndex) missing — "partial feet" case.
Map<String, double> partialFeetLikelihoods() {
  final lk = fullLikelihoods();
  lk['leftHeel'] = 0.1;
  lk['rightHeel'] = 0.1;
  lk['leftFootIndex'] = 0.1;
  lk['rightFootIndex'] = 0.1;
  return lk;
}

/// A stable standing sequence of [count] frames, ~33ms apart (30fps),
/// starting at [startTsMs].
List<PoseSnapshot> stableStandingSequence({
  int count = 20,
  int startTsMs = 0,
  double hipY = 0.50,
}) {
  return List.generate(count, (i) {
    final ts = startTsMs + i * 33;
    return buildSnapshot(
      landmarks: standingLandmarks(hipY: hipY),
      likelihoods: fullLikelihoods(),
      timestampMs: ts,
    );
  });
}

/// A full jump sequence: stable stand → crouch → takeoff → airborne (peak)
/// → landing → stable stand. Hip Y and ankle Y move together, roughly
/// simulating a real vertical jump. ~33ms per frame (30fps).
List<PoseSnapshot> jumpSequence({
  // 40 frames * 33ms ≈ 1.3s, comfortably past JumpStateMachine's
  // stabilizingMinMs (700ms) so the baseline freezes while still standing.
  int standFrames = 40,
  int crouchFrames = 8,
  int airborneFrames = 10,
  int landFrames = 15,
  double standHipY = 0.50,
  double crouchHipY = 0.60,
  double peakHipY = 0.30,
  int startTsMs = 0,
  int frameStepMs = 33,
}) {
  final frames = <PoseSnapshot>[];
  int ts = startTsMs;

  void addFrame(double hipY, {double ankleLift = 0.0}) {
    final lm = standingLandmarks(hipY: hipY);
    if (ankleLift != 0.0) {
      lm['leftAnkle'] = Offset(lm['leftAnkle']!.dx, lm['leftAnkle']!.dy - ankleLift);
      lm['rightAnkle'] = Offset(lm['rightAnkle']!.dx, lm['rightAnkle']!.dy - ankleLift);
      lm['leftHeel'] = Offset(lm['leftHeel']!.dx, lm['leftHeel']!.dy - ankleLift);
      lm['rightHeel'] = Offset(lm['rightHeel']!.dx, lm['rightHeel']!.dy - ankleLift);
    }
    frames.add(buildSnapshot(landmarks: lm, likelihoods: fullLikelihoods(), timestampMs: ts));
    ts += frameStepMs;
  }

  for (int i = 0; i < standFrames; i++) {
    addFrame(standHipY);
  }
  for (int i = 0; i < crouchFrames; i++) {
    final t = (i + 1) / crouchFrames;
    addFrame(standHipY + (crouchHipY - standHipY) * t);
  }
  for (int i = 0; i < airborneFrames; i++) {
    final t = (i + 1) / airborneFrames;
    // Rise from crouch to peak, feet lift off the ground.
    final hipY = crouchHipY + (peakHipY - crouchHipY) * t;
    addFrame(hipY, ankleLift: 0.10 * t);
  }
  for (int i = 0; i < landFrames; i++) {
    // Ease-out: spends more relative time near the standing baseline at the
    // end, like a real landing settling rather than a straight linear return.
    final t = (i + 1) / landFrames;
    final eased = 1 - math.pow(1 - t, 3);
    final hipY = peakHipY + (standHipY - peakHipY) * eased;
    addFrame(hipY);
  }
  // Settle fully at the standing baseline — gives the landing/completed
  // confirmation windows enough consecutive stable frames to trigger.
  for (int i = 0; i < 15; i++) {
    addFrame(standHipY);
  }
  return frames;
}
