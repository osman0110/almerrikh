import 'package:flutter/material.dart';

import '../models/drill_result_model.dart';
import 'exercise_engine.dart';
import 'hand_tracker.dart';
import 'target_zone_generator.dart';

/// Professional Hand Reaction Engine.
///
/// Replaces the generic [ExerciseEngine] logic for the hand-reaction drill.
/// Uses [HandTracker] (EMA-smoothed, multi-point) and [TargetZoneGenerator]
/// (body-based zones) for accurate, player-relative hit detection.
///
/// Output is the same [ExerciseFrameState] consumed by the existing HUD so
/// the display layer needs no changes.
class HandReactionEngine {
  HandReactionEngine({required this.drillId});

  static const int    totalTargets    = 20;
  static const double targetRadius    = 0.08;   // normalised
  static const Duration reactionTimeout = Duration(milliseconds: 1800);
  static const Duration hitCooldown    = Duration(milliseconds: 300);

  final String drillId;

  final _tracker  = HandTracker();
  final _zones    = TargetZoneGenerator();

  int reps    = 0;
  int misses  = 0;
  int attempts = 0;

  HandPoints get lastHands => _lastHands;
  HandPoints _lastHands = HandPoints.empty;

  /// The current target circle (screen-normalised).
  CircleTarget targetCircle = const CircleTarget(center: Offset(0.5, 0.35), radius: targetRadius);

  /// Rect kept for API compatibility with the generic engine (unused).
  Rect get targetRect => Rect.fromCenter(
    center: targetCircle.center,
    width: targetRadius * 2,
    height: targetRadius * 2,
  );

  // ── Internal state ──────────────────────────────────────────────────────

  DateTime _targetShownAt = DateTime.now();
  DateTime? _hitCooldownUntil;
  DateTime? _lastHitAt;
  bool _handsWarning = false;
  final List<Duration> _reactionTimes = [];

  // ── Public API ──────────────────────────────────────────────────────────

  /// Evaluate one camera frame.
  ///
  /// When [running] is false (not yet in training phase) the engine updates
  /// the tracker for smoothing but does not score anything.
  ExerciseFrameState evaluate(PoseSnapshot pose, bool running) {
    final hands = _tracker.update(pose);
    _lastHands = hands;

    if (!running) {
      return _state(hands: hands, guidance: '');
    }

    // ── Cooldown guard ──────────────────────────────────────────────────
    final now = DateTime.now();
    if (_hitCooldownUntil != null && now.isBefore(_hitCooldownUntil!)) {
      return _state(hands: hands, guidance: '');
    }

    // ── Hands-visible check ────────────────────────────────────────────
    if (!hands.anyHandVisible) {
      _handsWarning = true;
      // Do NOT count MISS — wait for player to show hands again.
      return _state(hands: hands, guidance: 'أظهر يديك بوضوح');
    }
    _handsWarning = false;

    // ── Adaptive hit radius ────────────────────────────────────────────
    // Scale radius with player's apparent size in frame so targets feel
    // the same difficulty regardless of distance from camera.
    final bodyHeight   = pose.bodyBox?.height ?? 0.70;
    final scaleFactor  = (bodyHeight / 0.70).clamp(0.70, 1.40);
    final effectiveR   = (targetRadius * scaleFactor + 0.04).clamp(0.08, 0.20);

    // ── Velocity-based prediction (40 ms look-ahead) ──────────────────
    const predictDt  = 0.040; // seconds
    final vel        = hands.dominantVelocity;
    final predictOff = Offset(vel.dx * predictDt, vel.dy * predictDt);

    // ── Hit test ───────────────────────────────────────────────────────
    final target = targetCircle.center;
    final hit = hands.allPoints.any((p) {
      final current   = (p - target).distance <= effectiveR;
      final predicted = (p + predictOff - target).distance <= effectiveR;
      return current || predicted;
    });

    if (hit) {
      reps++;
      attempts++;
      _reactionTimes.add(now.difference(_targetShownAt));
      _hitCooldownUntil = now.add(hitCooldown);
      _lastHitAt = now;
      _nextTarget(pose);
    } else if (now.difference(_targetShownAt) >= reactionTimeout) {
      misses++;
      attempts++;
      _nextTarget(pose);
    }

    return _state(hands: hands, guidance: '');
  }

  DrillResultModel result() => DrillResultModel(
    drillId: drillId,
    totalReps: reps,
    misses: misses,
    score: reps * 100 - misses * 20,
    accuracy: attempts == 0 ? 0 : reps / attempts * 100,
    averageReactionTime: _averageReactionTime,
  );

  Duration? get _averageReactionTime {
    if (_reactionTimes.isEmpty) return null;
    final ms = _reactionTimes.map((d) => d.inMilliseconds).reduce((a, b) => a + b) ~/
        _reactionTimes.length;
    return Duration(milliseconds: ms);
  }

  // ── Private ─────────────────────────────────────────────────────────────

  void _nextTarget(PoseSnapshot pose) {
    final center = _zones.next(pose.bodyBox);
    targetCircle = CircleTarget(center: center, radius: targetRadius);
    _targetShownAt = DateTime.now();
  }

  ExerciseFrameState _state({required HandPoints hands, required String guidance}) =>
      ExerciseFrameState(
        ready: true,
        guidance: guidance,
        targetRect: targetRect,
        targetCircle: targetCircle,
        reps: reps,
        misses: misses,
        score: reps * 100 - misses * 20,
        accuracy: attempts == 0 ? 0 : reps / attempts * 100,
        averageReactionTime: _averageReactionTime,
        totalTargets: totalTargets,
        lastHitAt: _lastHitAt,
        exerciseHint: _handsWarning ? 'أظهر يديك بوضوح' : null,
      );
}
