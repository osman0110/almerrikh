import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/drill_result_model.dart';

enum ExerciseType {
  getInTheBox,
  handReaction,
  footReaction,
  rainBody,    // rain-body: upper-body targets, faster timeout
  rainFeet,    // rain-feet: lower-body targets, faster timeout
  ballControl, // ball-control: fast alternating ankle taps
  firstTouch,  // first-touch: hold ankle in zone for 0.6s
  sprintCube,  // sprint-cube: smaller boxes, faster hold
  agilityGrid, // agility-grid: 4 fixed grid zones in sequence
  powerShot,   // power-shot: knee wind-up → ankle shoots target
  finisher,    // finisher: alternating upper + lower targets
}

class PoseSnapshot {
  const PoseSnapshot({
    required this.bodyBox,
    required this.center,
    required this.leftWrist,
    required this.rightWrist,
    required this.leftAnkle,
    required this.rightAnkle,
    required this.bodyFullyVisible,
    required this.headVisible,
    required this.shouldersVisible,
    required this.hipsVisible,
    required this.lowerBodyVisible,
    required this.insideGuideFrame,
    required this.confidence,
    required this.detectionScore,
    required this.landmarkCount,
    required this.imageSize,
    required this.rotation,
    required this.landmarks,
    required this.tooClose,
    required this.tooFar,
    required this.lowLight,
    this.timestampMs = 0,
    this.likelihoods = const <String, double>{},
  });

  final Rect? bodyBox;
  final Offset? center;
  final Offset? leftWrist;
  final Offset? rightWrist;
  final Offset? leftAnkle;
  final Offset? rightAnkle;
  final bool bodyFullyVisible;
  final bool headVisible;
  final bool shouldersVisible;
  final bool hipsVisible;
  final bool lowerBodyVisible;
  final bool insideGuideFrame;
  final double confidence;
  final int detectionScore;
  final int landmarkCount;
  final Size imageSize;
  final int rotation;
  final Map<String, Offset> landmarks;
  final bool tooClose;
  final bool tooFar;
  final bool lowLight;

  /// Wall-clock ms when the camera frame was received (0 = unknown, e.g. web).
  final int timestampMs;

  /// Raw per-landmark likelihoods, unfiltered — quality gates need low values
  /// too, unlike [landmarks] which drops points below the visibility cut.
  final Map<String, double> likelihoods;
}

class ExerciseFrameState {
  const ExerciseFrameState({
    required this.ready,
    required this.guidance,
    required this.targetRect,
    required this.targetCircle,
    required this.reps,
    required this.misses,
    required this.score,
    required this.accuracy,
    required this.averageReactionTime,
    required this.totalTargets,
    this.lastHitAt,
    this.exerciseHint,
  });

  final bool ready;
  final String guidance;
  final Rect targetRect;
  final CircleTarget? targetCircle;
  final int reps;
  final int misses;
  final int score;
  final double accuracy;
  final Duration? averageReactionTime;
  final int totalTargets;
  final DateTime? lastHitAt;
  final String? exerciseHint;
}

class CircleTarget {
  const CircleTarget({required this.center, required this.radius});

  final Offset center;
  final double radius;
}

class ExerciseEngine {
  ExerciseEngine({required this.type, required this.drillId}) {
    if (type == ExerciseType.agilityGrid) _initGridPositions();
    _moveTarget();
  }

  static const Rect guideFrame = Rect.fromLTWH(0.18, 0.12, 0.64, 0.76);

  final ExerciseType type;
  final String drillId;
  final _random = math.Random();

  Rect targetRect = const Rect.fromLTWH(0.34, 0.32, 0.32, 0.30);
  CircleTarget targetCircle = const CircleTarget(
    center: Offset(0.5, 0.45),
    radius: 0.09,
  );

  int reps = 0;
  int misses = 0;
  int attempts = 0;
  DateTime? _insideSince;
  DateTime? _outsideSince;
  DateTime? _ankleInsideSince;
  DateTime _targetShownAt = DateTime.now();
  final List<Duration> _reactionTimes = [];

  // Hit detection state
  DateTime? _hitCooldownUntil;
  DateTime? _lastHitAt;

  // Per-exercise state
  bool _ballControlLeft = true;
  int _gridIndex = 0;
  final List<Offset> _gridPositions = [];
  int _powerShotPhase = 0; // 0 = wait for knee wind-up, 1 = wait for ankle shot
  bool _finisherUpper = true;
  String _exerciseHint = '';

  void _initGridPositions() {
    _gridPositions.addAll([
      const Offset(0.30, 0.35),
      const Offset(0.70, 0.35),
      const Offset(0.70, 0.68),
      const Offset(0.30, 0.68),
    ]);
  }

  bool get _usesRect =>
      type == ExerciseType.getInTheBox || type == ExerciseType.sprintCube;

  int get totalTargets => switch (type) {
    ExerciseType.handReaction  => 20,
    ExerciseType.rainBody      => 25,
    ExerciseType.footReaction  => 15,
    ExerciseType.rainFeet      => 20,
    ExerciseType.ballControl   => 30,
    ExerciseType.firstTouch    => 10,
    ExerciseType.agilityGrid   => 20,
    ExerciseType.powerShot     => 10,
    ExerciseType.finisher      => 20,
    ExerciseType.getInTheBox   => 10,
    ExerciseType.sprintCube    => 15,
  };

  // Extra hit tolerance added on top of the visual radius (normalized 0-1 coords).
  double get _hitTolerance => switch (type) {
    ExerciseType.handReaction  => 0.05,
    ExerciseType.rainBody      => 0.05,
    ExerciseType.footReaction  => 0.04,
    ExerciseType.rainFeet      => 0.04,
    ExerciseType.finisher      => 0.04,
    _                          => 0.03,
  };

  // Min gap between two consecutive hits (prevents same-frame double-count).
  Duration get _hitCooldown => switch (type) {
    ExerciseType.handReaction => const Duration(milliseconds: 350),
    _                         => const Duration(milliseconds: 280),
  };

  Duration get _reactionTimeout => switch (type) {
        ExerciseType.rainBody || ExerciseType.rainFeet =>
          const Duration(milliseconds: 1200),
        ExerciseType.ballControl => const Duration(milliseconds: 900),
        ExerciseType.finisher => const Duration(milliseconds: 1400),
        _ => const Duration(milliseconds: 1600),
      };

  // Exercise scoring happens only while `running` is true. Positioning uses
  // the same pose snapshot but does not modify score, hits, or misses.
  ExerciseFrameState evaluate(PoseSnapshot pose, bool running) {
    final guidance = _guidanceFor(pose);
    final ready = guidance.isEmpty;
    if (!running || !ready) {
      _exerciseHint = '';
      return _state(ready: ready, guidance: guidance);
    }

    switch (type) {
      case ExerciseType.getInTheBox:
        _evaluateBox(pose, holdMs: 500, missMs: 2000);
      case ExerciseType.sprintCube:
        _evaluateBox(pose, holdMs: 300, missMs: 1500);
      case ExerciseType.handReaction:
      case ExerciseType.rainBody:
        _evaluateReaction(pose, upper: true);
      case ExerciseType.footReaction:
      case ExerciseType.rainFeet:
        _evaluateReaction(pose, upper: false);
      case ExerciseType.ballControl:
        _evaluateBallControl(pose);
      case ExerciseType.firstTouch:
        _evaluateFirstTouch(pose);
      case ExerciseType.agilityGrid:
        _evaluateAgilityGrid(pose);
      case ExerciseType.powerShot:
        _evaluatePowerShot(pose);
      case ExerciseType.finisher:
        _evaluateFinisher(pose);
    }

    return _state(ready: true, guidance: guidance);
  }

  DrillResultModel result() {
    return DrillResultModel(
      drillId: drillId,
      totalReps: reps,
      misses: misses,
      score: reps * 100 - misses * 20,
      accuracy: attempts == 0 ? 0 : reps / attempts * 100,
      averageReactionTime: averageReactionTime,
    );
  }

  Duration? get averageReactionTime {
    if (_reactionTimes.isEmpty) return null;
    final ms = _reactionTimes
            .map((d) => d.inMilliseconds)
            .reduce((a, b) => a + b) ~/
        _reactionTimes.length;
    return Duration(milliseconds: ms);
  }

  String _guidanceFor(PoseSnapshot pose) {
    if (pose.bodyBox == null || pose.detectionScore == 0) {
      return 'ما شايفك، قف أمام الكاميرا';
    }
    if (pose.detectionScore < 5) {
      return pose.headVisible
          ? 'رأسك ظاهر، ارجع للخلف حتى تظهر القدمين'
          : 'جزء من الجسم ظاهر، خليك داخل الإطار';
    }
    if (pose.lowLight || pose.confidence < 0.30) {
      return 'الإضاءة ضعيفة، خلي النور أمامك';
    }
    if (pose.tooClose) return 'أنت قريب جدًا، ارجع للخلف';
    if (pose.tooFar) return 'أنت بعيد جدًا، اقترب قليلًا';
    if (!pose.insideGuideFrame) return 'جسمك خارج الإطار، تحرك لمنتصف الشاشة';
    if (!pose.lowerBodyVisible) return 'القدمين غير ظاهرة، ارجع للخلف';
    if (!pose.bodyFullyVisible) return 'خلّي جسمك كامل ظاهر في الكاميرا';
    return '';
  }

  // Get In The Box / Sprint Cube: body center must stay inside the box for
  // holdMs before a hit is counted; missing for missMs counts as a miss.
  void _evaluateBox(PoseSnapshot pose, {required int holdMs, required int missMs}) {
    final center = pose.center;
    if (center == null) return;

    if (targetRect.contains(center)) {
      _outsideSince = null;
      _insideSince ??= DateTime.now();
      if (DateTime.now().difference(_insideSince!) >= Duration(milliseconds: holdMs)) {
        reps++;
        attempts++;
        _insideSince = null;
        _moveTarget();
      }
    } else {
      _insideSince = null;
      _outsideSince ??= DateTime.now();
      if (DateTime.now().difference(_outsideSince!) >= Duration(milliseconds: missMs)) {
        registerMiss();
        _outsideSince = null;
        _moveTarget();
      }
    }
  }

  // Hand/Foot Reaction + Rain variants: wrist/ankle (or index finger) enters target.
  void _evaluateReaction(PoseSnapshot pose, {required bool upper}) {
    // Cooldown guard – prevents counting the same hit across multiple frames.
    if (_hitCooldownUntil != null && DateTime.now().isBefore(_hitCooldownUntil!)) return;

    final List<Offset?> points;
    if (upper) {
      // Prefer index fingertip (ML Kit landmark 'leftIndex'/'rightIndex') when
      // available – more precise than wrist for hand-tap exercises.
      points = [
        pose.landmarks['leftIndex'] ?? pose.leftWrist,
        pose.landmarks['rightIndex'] ?? pose.rightWrist,
      ];
    } else {
      points = [pose.leftAnkle, pose.rightAnkle];
    }

    // Effective radius = visual radius + extra tolerance (screen-size-independent).
    final effectiveRadius = targetCircle.radius + _hitTolerance;

    final hit = points.whereType<Offset>().any(
          (p) => (p - targetCircle.center).distance <= effectiveRadius,
        );

    if (hit) {
      reps++;
      attempts++;
      _reactionTimes.add(DateTime.now().difference(_targetShownAt));
      _hitCooldownUntil = DateTime.now().add(_hitCooldown);
      _lastHitAt = DateTime.now();
      _moveTarget();
    } else if (DateTime.now().difference(_targetShownAt) >= _reactionTimeout) {
      registerMiss();
      _moveTarget();
    }
  }

  // Ball Control: strict alternation between left ankle and right ankle zones.
  void _evaluateBallControl(PoseSnapshot pose) {
    final ankle = _ballControlLeft ? pose.leftAnkle : pose.rightAnkle;
    final elapsed = DateTime.now().difference(_targetShownAt);
    if (ankle != null && (ankle - targetCircle.center).distance <= targetCircle.radius) {
      reps++;
      attempts++;
      _reactionTimes.add(elapsed);
      _ballControlLeft = !_ballControlLeft;
      _moveTarget();
    } else if (elapsed >= _reactionTimeout) {
      registerMiss();
      _ballControlLeft = !_ballControlLeft;
      _moveTarget();
    }
  }

  // First Touch: ankle must stay inside the target zone for 0.6s to score.
  void _evaluateFirstTouch(PoseSnapshot pose) {
    final inside = [pose.leftAnkle, pose.rightAnkle].whereType<Offset>().any(
          (p) => (p - targetCircle.center).distance <= targetCircle.radius,
        );
    if (inside) {
      _ankleInsideSince ??= DateTime.now();
      if (DateTime.now().difference(_ankleInsideSince!) >=
          const Duration(milliseconds: 600)) {
        reps++;
        attempts++;
        _reactionTimes.add(DateTime.now().difference(_targetShownAt));
        _ankleInsideSince = null;
        _moveTarget();
      }
    } else {
      _ankleInsideSince = null;
      if (DateTime.now().difference(_targetShownAt) >=
          const Duration(milliseconds: 2500)) {
        registerMiss();
        _moveTarget();
      }
    }
  }

  // Agility Grid: body center cycles through 4 fixed grid positions in order.
  void _evaluateAgilityGrid(PoseSnapshot pose) {
    final center = pose.center;
    if (center == null) return;
    final target = _gridPositions[_gridIndex % _gridPositions.length];
    if ((center - target).distance <= 0.12) {
      reps++;
      attempts++;
      _reactionTimes.add(DateTime.now().difference(_targetShownAt));
      _gridIndex++;
      _moveTarget();
    } else if (DateTime.now().difference(_targetShownAt) >=
        const Duration(milliseconds: 2000)) {
      registerMiss();
      _gridIndex++;
      _moveTarget();
    }
  }

  // Power Shot: phase 0 — raise knee above hip to wind up; phase 1 — ankle
  // must enter the target circle within 1.5s to complete the shot.
  void _evaluatePowerShot(PoseSnapshot pose) {
    if (_powerShotPhase == 0) {
      _exerciseHint = 'ارفع ركبتك للتسديد';
      final lKnee = pose.landmarks['leftKnee'];
      final rKnee = pose.landmarks['rightKnee'];
      final lHip = pose.landmarks['leftHip'];
      final rHip = pose.landmarks['rightHip'];
      final windUp =
          (lKnee != null && lHip != null && lKnee.dy < lHip.dy - 0.04) ||
          (rKnee != null && rHip != null && rKnee.dy < rHip.dy - 0.04);
      if (windUp) {
        _powerShotPhase = 1;
        _targetShownAt = DateTime.now();
      } else if (DateTime.now().difference(_targetShownAt) >=
          const Duration(milliseconds: 3000)) {
        registerMiss();
        _moveTarget();
      }
    } else {
      _exerciseHint = 'سدد!';
      final hit = [pose.leftAnkle, pose.rightAnkle].whereType<Offset>().any(
            (p) => (p - targetCircle.center).distance <= targetCircle.radius,
          );
      if (hit) {
        reps++;
        attempts++;
        _reactionTimes.add(DateTime.now().difference(_targetShownAt));
        _powerShotPhase = 0;
        _exerciseHint = '';
        _moveTarget();
      } else if (DateTime.now().difference(_targetShownAt) >=
          const Duration(milliseconds: 1500)) {
        registerMiss();
        _powerShotPhase = 0;
        _moveTarget();
      }
    }
  }

  // Finisher: alternates between an upper-body target (wrists) and a
  // lower-body target (ankles) for a combined reaction challenge.
  void _evaluateFinisher(PoseSnapshot pose) {
    final points = _finisherUpper
        ? [pose.leftWrist, pose.rightWrist]
        : [pose.leftAnkle, pose.rightAnkle];
    final hit = points.whereType<Offset>().any(
          (p) => (p - targetCircle.center).distance <= targetCircle.radius,
        );
    if (hit) {
      reps++;
      attempts++;
      _reactionTimes.add(DateTime.now().difference(_targetShownAt));
      _finisherUpper = !_finisherUpper;
      _moveTarget();
    } else if (DateTime.now().difference(_targetShownAt) >= _reactionTimeout) {
      registerMiss();
      _finisherUpper = !_finisherUpper;
      _moveTarget();
    }
  }

  void registerMiss() {
    misses++;
    attempts++;
  }

  void _moveTarget() {
    switch (type) {
      case ExerciseType.getInTheBox:
        _moveBox(minW: 0.20, maxW: 0.32, minH: 0.22, maxH: 0.36);
      case ExerciseType.sprintCube:
        _moveBox(minW: 0.14, maxW: 0.22, minH: 0.16, maxH: 0.24);
      case ExerciseType.handReaction:
      case ExerciseType.rainBody:
        _moveCircle(yMin: 0.22, yMax: 0.62);
      case ExerciseType.footReaction:
      case ExerciseType.rainFeet:
        _moveCircle(yMin: 0.58, yMax: 0.82);
      case ExerciseType.ballControl:
        _moveBallControlTarget();
      case ExerciseType.firstTouch:
        _moveCircle(yMin: 0.60, yMax: 0.80, radius: 0.10);
      case ExerciseType.agilityGrid:
        _moveAgilityTarget();
      case ExerciseType.powerShot:
        _moveCircle(yMin: 0.55, yMax: 0.78);
        _powerShotPhase = 0;
      case ExerciseType.finisher:
        _moveFinisherTarget();
    }
    _targetShownAt = DateTime.now();
  }

  void _moveBox({
    required double minW,
    required double maxW,
    required double minH,
    required double maxH,
  }) {
    final width = minW + _random.nextDouble() * (maxW - minW);
    final height = minH + _random.nextDouble() * (maxH - minH);
    targetRect = Rect.fromLTWH(
      guideFrame.left + _random.nextDouble() * (guideFrame.width - width),
      guideFrame.top + _random.nextDouble() * (guideFrame.height - height),
      width,
      height,
    );
  }

  void _moveCircle({required double yMin, required double yMax, double radius = 0.075}) {
    targetCircle = CircleTarget(
      center: Offset(
        guideFrame.left + 0.08 + _random.nextDouble() * (guideFrame.width - 0.16),
        yMin + _random.nextDouble() * (yMax - yMin),
      ),
      radius: radius,
    );
  }

  void _moveBallControlTarget() {
    final x = _ballControlLeft
        ? guideFrame.left + 0.04 + _random.nextDouble() * 0.10
        : guideFrame.right - 0.04 - _random.nextDouble() * 0.10;
    targetCircle = CircleTarget(
      center: Offset(x, 0.65 + _random.nextDouble() * 0.12),
      radius: 0.07,
    );
  }

  void _moveAgilityTarget() {
    targetCircle = CircleTarget(
      center: _gridPositions[_gridIndex % _gridPositions.length],
      radius: 0.12,
    );
  }

  void _moveFinisherTarget() {
    if (_finisherUpper) {
      _moveCircle(yMin: 0.22, yMax: 0.55);
    } else {
      _moveCircle(yMin: 0.58, yMax: 0.78);
    }
  }

  ExerciseFrameState _state({required bool ready, required String guidance}) {
    return ExerciseFrameState(
      ready: ready,
      guidance: guidance,
      targetRect: targetRect,
      targetCircle: _usesRect ? null : targetCircle,
      reps: reps,
      misses: misses,
      score: reps * 100 - misses * 20,
      accuracy: attempts == 0 ? 0 : reps / attempts * 100,
      averageReactionTime: averageReactionTime,
      totalTargets: totalTargets,
      lastHitAt: _lastHitAt,
      exerciseHint: _exerciseHint.isEmpty ? null : _exerciseHint,
    );
  }
}
