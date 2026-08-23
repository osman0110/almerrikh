import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:al_merrikh/services/pose_quality_gate.dart';

import 'fixtures/synthetic_pose_sequences.dart';

void main() {
  group('PoseQualityGate', () {
    test('requires 20 consecutive valid frames before isReady', () {
      final gate = PoseQualityGate();
      final seq = stableStandingSequence(count: 25);
      var lastResult = gate.evaluate(seq.first, 120);
      for (int i = 1; i < seq.length; i++) {
        lastResult = gate.evaluate(seq[i], 120);
        if (i < 19) {
          expect(lastResult.isReady, isFalse, reason: 'frame $i should not be ready yet');
        }
      }
      expect(lastResult.readyStreak, greaterThanOrEqualTo(20));
      expect(lastResult.isReady, isTrue);
    });

    test('resets the streak on a single invalid frame', () {
      final gate = PoseQualityGate();
      final seq = stableStandingSequence(count: 15);
      for (final s in seq) {
        gate.evaluate(s, 120);
      }
      // Body lost entirely — invalid frame.
      final result = gate.evaluate(null, 120);
      expect(result.frameValid, isFalse);
      expect(result.readyStreak, 0);
    });

    test('blocks isReady when rejected ratio over the window exceeds 30%', () {
      final gate = PoseQualityGate();
      // 15 invalid (no body) frames, then a run of valid ones — even once the
      // streak reaches 20, the 30-frame window still contains rejected frames.
      for (int i = 0; i < 15; i++) {
        gate.evaluate(null, 120);
      }
      final seq = stableStandingSequence(count: 20, startTsMs: 1000);
      PoseGateResult? result;
      for (final s in seq) {
        result = gate.evaluate(s, 120);
      }
      // Window (last 30) = 10 invalid (trailing from the first 15) + 20 valid
      // -> rejectedRatio = 10/30 = 33% > 30% -> not ready despite a long streak.
      expect(result!.readyStreak, greaterThanOrEqualTo(20));
      expect(result.rejectedRatio, greaterThan(0.30));
      expect(result.isReady, isFalse);
    });

    test('guidance is noBody when no snapshot is present', () {
      final gate = PoseQualityGate();
      final result = gate.evaluate(null, 120);
      expect(result.guidance, PoseGateGuidance.noBody);
    });

    test('guidance is showFeet when feet landmarks are missing', () {
      final gate = PoseQualityGate();
      final snapshot = buildSnapshot(
        landmarks: standingLandmarks(),
        likelihoods: partialFeetLikelihoods(),
        timestampMs: 0,
      );
      final result = gate.evaluate(snapshot, 120);
      expect(result.frameValid, isFalse);
      expect(result.guidance, PoseGateGuidance.showFeet);
      // Regression guard: with feet not visible, bodyFull/legQ must NOT
      // read as "everything is fine" even though hips/knees/head/lighting
      // are all perfect — this is exactly the contradiction (bodyFull:true,
      // legQ:100% while feet were out of frame) reported from the app.
      expect(result.bodyFull, isFalse);
      expect(result.feetVisible, isFalse);
      expect(result.lowerBodyQuality, lessThan(70));
    });

    test('guidance is stepBack when the body fills too much of the frame', () {
      final gate = PoseQualityGate();
      final snapshot = buildSnapshot(
        landmarks: standingLandmarks(),
        likelihoods: fullLikelihoods(),
        bodyBox: const Rect.fromLTWH(0.2, 0.05, 0.6, 0.92),
        timestampMs: 0,
      );
      final result = gate.evaluate(snapshot, 120);
      expect(result.guidance, PoseGateGuidance.stepBack);
    });

    test('guidance is stepCloser when the body is too small in frame', () {
      final gate = PoseQualityGate();
      final snapshot = buildSnapshot(
        landmarks: standingLandmarks(),
        likelihoods: fullLikelihoods(),
        bodyBox: const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2),
        timestampMs: 0,
      );
      final result = gate.evaluate(snapshot, 120);
      expect(result.guidance, PoseGateGuidance.stepCloser);
    });

    test('legQ increases with landmark likelihood', () {
      final gateHigh = PoseQualityGate();
      final gateLow = PoseQualityGate();
      final highLikelihoodResult = gateHigh.evaluate(
        buildSnapshot(landmarks: standingLandmarks(), likelihoods: fullLikelihoods(value: 0.95)),
        120,
      );
      final lowLikelihoodResult = gateLow.evaluate(
        buildSnapshot(landmarks: standingLandmarks(), likelihoods: fullLikelihoods(value: 0.5)),
        120,
      );
      expect(highLikelihoodResult.legQuality, greaterThan(lowLikelihoodResult.legQuality));
    });

    test('reset() clears streak and window', () {
      final gate = PoseQualityGate();
      final seq = stableStandingSequence(count: 10);
      for (final s in seq) {
        gate.evaluate(s, 120);
      }
      gate.reset();
      final result = gate.evaluate(seq.first, 120);
      expect(result.readyStreak, lessThanOrEqualTo(1));
      expect(result.rejectedRatio, lessThanOrEqualTo(0.0));
    });
  });
}
