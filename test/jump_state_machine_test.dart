import 'package:flutter_test/flutter_test.dart';
import 'package:al_merrikh/services/jump_state_machine.dart';
import 'package:al_merrikh/services/pose_assessment_config.dart';

import 'fixtures/synthetic_pose_sequences.dart';

void main() {
  group('JumpStateMachine', () {
    test('happy path: searchingBody -> ... -> completed for a full CMJ', () {
      final machine = JumpStateMachine(isSquatJump: false);
      // standFrames must cover positioning + stabilizingMinMs (700ms) before
      // the crouch begins, or the baseline freezes on a crouched frame.
      final frames = jumpSequence(
        standFrames: 40,
        crouchFrames: 8,
        airborneFrames: 10,
        landFrames: 20,
      );

      final statesSeen = <JumpState>{};
      for (final f in frames) {
        final lh = f.landmarks['leftHip']!, rh = f.landmarks['rightHip']!;
        final la = f.landmarks['leftAnkle']!, ra = f.landmarks['rightAnkle']!;
        final state = machine.update(
          frameValid: true,
          hipY: (lh.dy + rh.dy) / 2,
          leftAnkleY: la.dy,
          rightAnkleY: ra.dy,
          leftKneeAngle: 170,
          rightKneeAngle: 170,
          tsMs: f.timestampMs,
        );
        statesSeen.add(state);
      }

      expect(statesSeen, contains(JumpState.stabilizing));
      expect(statesSeen, contains(JumpState.ready));
      expect(statesSeen, contains(JumpState.airborne));
      expect(machine.state, JumpState.completed);
    });

    test('stabilizing does not transition to ready before stabilizingMinMs', () {
      final machine = JumpStateMachine(isSquatJump: false);
      // Feed exactly enough frames to fill the median window (positioning ->
      // stabilizing) but well under stabilizingMinMs of elapsed time.
      final seq = stableStandingSequence(count: PoseAssessmentConfig.medianWindowFrames + 1);
      for (final f in seq) {
        final lh = f.landmarks['leftHip']!, rh = f.landmarks['rightHip']!;
        machine.update(
          frameValid: true,
          hipY: (lh.dy + rh.dy) / 2,
          leftAnkleY: f.landmarks['leftAnkle']!.dy,
          rightAnkleY: f.landmarks['rightAnkle']!.dy,
          leftKneeAngle: 170,
          rightKneeAngle: 170,
          tsMs: f.timestampMs,
        );
      }
      expect(machine.state, JumpState.stabilizing);
      expect(machine.baselineHipY, isNull); // baseline not frozen yet
    });

    test('freezes baseline once stabilizingMinMs has elapsed', () {
      final machine = JumpStateMachine(isSquatJump: false);
      final seq = stableStandingSequence(count: 40); // ~1.3s at 33ms/frame
      JumpState? last;
      for (final f in seq) {
        final lh = f.landmarks['leftHip']!, rh = f.landmarks['rightHip']!;
        last = machine.update(
          frameValid: true,
          hipY: (lh.dy + rh.dy) / 2,
          leftAnkleY: f.landmarks['leftAnkle']!.dy,
          rightAnkleY: f.landmarks['rightAnkle']!.dy,
          leftKneeAngle: 170,
          rightKneeAngle: 170,
          tsMs: f.timestampMs,
        );
      }
      expect(last, JumpState.ready);
      expect(machine.baselineHipY, isNotNull);
      expect(machine.legLength, isNotNull);
      expect(machine.legLength, greaterThan(0));
    });

    test('completed latches — further updates do not leave completed', () {
      final machine = JumpStateMachine(isSquatJump: false);
      final frames = jumpSequence();
      for (final f in frames) {
        final lh = f.landmarks['leftHip']!, rh = f.landmarks['rightHip']!;
        machine.update(
          frameValid: true,
          hipY: (lh.dy + rh.dy) / 2,
          leftAnkleY: f.landmarks['leftAnkle']!.dy,
          rightAnkleY: f.landmarks['rightAnkle']!.dy,
          leftKneeAngle: 170,
          rightKneeAngle: 170,
          tsMs: f.timestampMs,
        );
      }
      expect(machine.state, JumpState.completed);

      // Feed a few more (even wildly different) frames — should stay latched.
      final result = machine.update(
        frameValid: true,
        hipY: 0.1,
        leftAnkleY: 0.1,
        rightAnkleY: 0.1,
        leftKneeAngle: 90,
        rightKneeAngle: 90,
        tsMs: frames.last.timestampMs + 1000,
      );
      expect(result, JumpState.completed);
    });

    test('invalid when tracking is lost for too long mid-flight', () {
      final machine = JumpStateMachine(isSquatJump: false);
      final frames = jumpSequence(
        standFrames: 40,
        crouchFrames: 8,
        airborneFrames: 4, // short — we'll interrupt mid-air
        landFrames: 20,
      );

      JumpState? state;
      int airborneEnteredAtIdx = -1;
      for (int i = 0; i < frames.length; i++) {
        final f = frames[i];
        final lh = f.landmarks['leftHip']!, rh = f.landmarks['rightHip']!;
        state = machine.update(
          frameValid: true,
          hipY: (lh.dy + rh.dy) / 2,
          leftAnkleY: f.landmarks['leftAnkle']!.dy,
          rightAnkleY: f.landmarks['rightAnkle']!.dy,
          leftKneeAngle: 170,
          rightKneeAngle: 170,
          tsMs: f.timestampMs,
        );
        if (state == JumpState.airborne && airborneEnteredAtIdx == -1) {
          airborneEnteredAtIdx = i;
          break;
        }
      }
      expect(airborneEnteredAtIdx, greaterThan(0), reason: 'test setup should reach airborne');

      // Now simulate tracking loss for > jumpInvalidGapMs while airborne.
      final lastTs = frames[airborneEnteredAtIdx].timestampMs;
      state = machine.update(
        frameValid: false,
        tsMs: lastTs + PoseAssessmentConfig.jumpInvalidGapMs + 100,
      );
      expect(state, JumpState.invalid);
    });

    test('reset() returns the machine to searchingBody', () {
      final machine = JumpStateMachine(isSquatJump: false);
      final seq = stableStandingSequence(count: 40);
      for (final f in seq) {
        final lh = f.landmarks['leftHip']!, rh = f.landmarks['rightHip']!;
        machine.update(
          frameValid: true,
          hipY: (lh.dy + rh.dy) / 2,
          leftAnkleY: f.landmarks['leftAnkle']!.dy,
          rightAnkleY: f.landmarks['rightAnkle']!.dy,
          leftKneeAngle: 170,
          rightKneeAngle: 170,
          tsMs: f.timestampMs,
        );
      }
      expect(machine.state, JumpState.ready);
      machine.reset();
      expect(machine.state, JumpState.searchingBody);
      expect(machine.baselineHipY, isNull);
    });

    test('squat jump enters squatHold before takeoff is checked', () {
      final machine = JumpStateMachine(isSquatJump: true);
      final seq = stableStandingSequence(count: 40);
      for (final f in seq) {
        final lh = f.landmarks['leftHip']!, rh = f.landmarks['rightHip']!;
        machine.update(
          frameValid: true,
          hipY: (lh.dy + rh.dy) / 2,
          leftAnkleY: f.landmarks['leftAnkle']!.dy,
          rightAnkleY: f.landmarks['rightAnkle']!.dy,
          leftKneeAngle: 170,
          rightKneeAngle: 170,
          tsMs: f.timestampMs,
        );
      }
      expect(machine.state, JumpState.ready);

      // Knee angle drops into squat range.
      int ts = seq.last.timestampMs + 33;
      JumpState? state;
      for (int i = 0; i < 5; i++) {
        state = machine.update(
          frameValid: true,
          hipY: 0.55,
          leftAnkleY: 0.80,
          rightAnkleY: 0.80,
          leftKneeAngle: 90,
          rightKneeAngle: 90,
          tsMs: ts,
        );
        ts += 33;
      }
      expect(state, JumpState.squatHold);
    });
  });
}
