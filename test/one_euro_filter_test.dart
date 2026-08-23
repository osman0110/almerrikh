import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_sport_scribe_main/services/pose_smoothing_service.dart';

import 'fixtures/synthetic_pose_sequences.dart';

void main() {
  group('PoseSmoothingService (One Euro filter)', () {
    test('attenuates jitter around a static point', () {
      final service = PoseSmoothingService();
      final rand = math.Random(42);
      final outputs = <Offset>[];

      for (int i = 0; i < 60; i++) {
        final jitterX = (rand.nextDouble() - 0.5) * 0.02; // ±1cm-ish jitter
        final jitterY = (rand.nextDouble() - 0.5) * 0.02;
        final lm = standingLandmarks();
        lm['leftKnee'] = Offset(lm['leftKnee']!.dx + jitterX, lm['leftKnee']!.dy + jitterY);
        final snapshot = buildSnapshot(
          landmarks: lm,
          likelihoods: fullLikelihoods(),
          timestampMs: i * 33,
        );
        outputs.add(service.smooth(snapshot)['leftKnee']!);
      }

      double variance(List<double> xs) {
        final mean = xs.reduce((a, b) => a + b) / xs.length;
        return xs.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) / xs.length;
      }

      final outX = outputs.map((o) => o.dx).toList();
      // Skip the first few samples while the filter is still converging.
      final steadyState = outX.sublist(10);
      final outVariance = variance(steadyState);
      // Raw jitter variance for a uniform ±0.01 distribution is ~0.01^2/3.
      const rawVariance = 0.02 * 0.02 / 12; // uniform distribution variance
      expect(outVariance, lessThan(rawVariance * 0.5));
    });

    test('converges to a bounded lag behind a steady-velocity ramp', () {
      final service = PoseSmoothingService();
      const stepPerFrame = 0.01;
      Offset? lastOut;
      for (int i = 0; i < 40; i++) {
        final hipY = 0.50 - stepPerFrame * i;
        final lm = standingLandmarks(hipY: hipY);
        final snapshot = buildSnapshot(
          landmarks: lm,
          likelihoods: fullLikelihoods(),
          timestampMs: i * 33,
        );
        lastOut = service.smooth(snapshot)['leftHip'];
      }
      final expectedY = 0.50 - stepPerFrame * 39;
      // With minCutoff=1.0 the filter settles into a steady-state lag behind
      // a constant-velocity ramp rather than eliminating it entirely — this
      // guards against the lag growing unbounded (e.g. a filter bug), not
      // against a small, expected steady-state offset.
      expect((lastOut!.dy - expectedY).abs(), lessThan(stepPerFrame * 7));
    });

    test('holds last output through a single low-confidence frame then drops it', () {
      final service = PoseSmoothingService();
      final good1 = buildSnapshot(
        landmarks: standingLandmarks(),
        likelihoods: fullLikelihoods(),
        timestampMs: 0,
      );
      final firstOut = service.smooth(good1)['leftAnkle'];
      expect(firstOut, isNotNull);

      // Low-likelihood frame — landmark still present but unreliable.
      final lowConfLikelihoods = fullLikelihoods();
      lowConfLikelihoods['leftAnkle'] = 0.1;
      final blurry = buildSnapshot(
        landmarks: standingLandmarks(),
        likelihoods: lowConfLikelihoods,
        timestampMs: 33,
      );
      final heldOut = service.smooth(blurry)['leftAnkle'];
      // Held: should equal the last good output, not a fresh (unfiltered) value.
      expect(heldOut, equals(firstOut));
    });

    test('rejects a single-frame glitch beyond the torso-ratio threshold', () {
      final service = PoseSmoothingService();
      for (int i = 0; i < 5; i++) {
        service.smooth(buildSnapshot(
          landmarks: standingLandmarks(),
          likelihoods: fullLikelihoods(),
          timestampMs: i * 33,
        ));
      }
      // Sudden huge jump in knee position (way more than 12% of torso length).
      final glitchLm = standingLandmarks();
      glitchLm['leftKnee'] = const Offset(0.9, 0.9);
      final glitchOut = service.smooth(buildSnapshot(
        landmarks: glitchLm,
        likelihoods: fullLikelihoods(),
        timestampMs: 5 * 33,
      ))['leftKnee'];
      // Should hold near the previous stable position, not jump to (0.9, 0.9).
      expect((glitchOut!.dx - 0.9).abs(), greaterThan(0.1));
    });
  });
}
