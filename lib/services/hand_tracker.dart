import 'package:flutter/material.dart';
import 'exercise_engine.dart';

/// All screen-normalised hand landmark positions for one frame.
class HandPoints {
  const HandPoints({
    required this.rightPoints,
    required this.leftPoints,
    required this.rightVelocity,
    required this.leftVelocity,
    required this.rightVisible,
    required this.leftVisible,
  });

  final List<Offset> rightPoints; // wrist, index, thumb, pinky, palmCentre
  final List<Offset> leftPoints;
  final Offset rightVelocity; // normalised units / second
  final Offset leftVelocity;
  final bool rightVisible;
  final bool leftVisible;

  bool get anyHandVisible => rightVisible || leftVisible;

  /// Every detected hand point (both hands combined).
  List<Offset> get allPoints => [...rightPoints, ...leftPoints];

  /// Dominant velocity (whichever hand is moving faster).
  Offset get dominantVelocity =>
      rightVelocity.distance >= leftVelocity.distance
          ? rightVelocity
          : leftVelocity;

  static const HandPoints empty = HandPoints(
    rightPoints: [],
    leftPoints: [],
    rightVelocity: Offset.zero,
    leftVelocity: Offset.zero,
    rightVisible: false,
    leftVisible: false,
  );
}

/// Extracts and smooths hand landmark positions from a [PoseSnapshot].
///
/// Uses an Exponential Moving Average (EMA) filter per landmark to reduce
/// per-frame jitter while keeping latency low.
/// Calculates per-hand velocity for predictive hit detection.
///
/// Only uses hand/finger landmarks — never hip, shoulder, or body centre.
/// Falls back to wrist + elbow-direction projection if fingertip landmarks
/// are unavailable (low-quality pose), but never falls back to body centre.
class HandTracker {
  static const double _alpha = 0.40; // EMA weight (higher = faster, noisier)
  static const double _projectionFactor = 0.40; // elbow→wrist extension ratio

  final Map<String, Offset> _ema = {};
  final Map<String, Offset> _prev = {};
  DateTime _lastTs = DateTime.now();

  // ── Public API ──────────────────────────────────────────────────────────

  HandPoints update(PoseSnapshot pose) {
    final dt = _dt();
    final lm = pose.landmarks;

    final rWrist  = _smooth('rightWrist',  lm['rightWrist']);
    final rIndex  = _smooth('rightIndex',  lm['rightIndex']);
    final rThumb  = _smooth('rightThumb',  lm['rightThumb']);
    final rPinky  = _smooth('rightPinky',  lm['rightPinky']);
    final rElbow  = _smooth('rightElbow',  lm['rightElbow']);

    final lWrist  = _smooth('leftWrist',   lm['leftWrist']);
    final lIndex  = _smooth('leftIndex',   lm['leftIndex']);
    final lThumb  = _smooth('leftThumb',   lm['leftThumb']);
    final lPinky  = _smooth('leftPinky',   lm['leftPinky']);
    final lElbow  = _smooth('leftElbow',   lm['leftElbow']);

    final rightPts = _buildHandPoints(rWrist, rIndex, rThumb, rPinky, rElbow);
    final leftPts  = _buildHandPoints(lWrist, lIndex, lThumb, lPinky, lElbow);

    final rVel = _velocity('rightWrist', rWrist, dt);
    final lVel = _velocity('leftWrist',  lWrist, dt);

    return HandPoints(
      rightPoints: rightPts,
      leftPoints: leftPts,
      rightVelocity: rVel,
      leftVelocity: lVel,
      rightVisible: rightPts.isNotEmpty,
      leftVisible: leftPts.isNotEmpty,
    );
  }

  void reset() {
    _ema.clear();
    _prev.clear();
    _lastTs = DateTime.now();
  }

  // ── Private helpers ─────────────────────────────────────────────────────

  double _dt() {
    final now = DateTime.now();
    final dt = now.difference(_lastTs).inMilliseconds / 1000.0;
    _lastTs = now;
    return dt.clamp(0.001, 0.2);
  }

  Offset? _smooth(String key, Offset? raw) {
    if (raw == null) return null;
    final prev = _ema[key];
    final s = prev == null
        ? raw
        : Offset(
            prev.dx * (1 - _alpha) + raw.dx * _alpha,
            prev.dy * (1 - _alpha) + raw.dy * _alpha,
          );
    _ema[key] = s;
    return s;
  }

  Offset _velocity(String key, Offset? current, double dt) {
    if (current == null) return Offset.zero;
    final prev = _prev[key];
    _prev[key] = current;
    if (prev == null || dt <= 0) return Offset.zero;
    return (current - prev) / dt;
  }

  /// Builds the list of hand points from available landmarks.
  /// Never accepts shoulder/hip as a source; if nothing hand-related is
  /// available returns an empty list (hand not visible).
  List<Offset> _buildHandPoints(
    Offset? wrist,
    Offset? index,
    Offset? thumb,
    Offset? pinky,
    Offset? elbow,
  ) {
    if (wrist == null && index == null) return []; // no hand data at all

    final pts = <Offset>[];

    if (wrist != null) pts.add(wrist);
    if (index != null) pts.add(index);
    if (thumb != null) pts.add(thumb);
    if (pinky != null) pts.add(pinky);

    // Palm centre: average of wrist + index + pinky (if all available).
    if (wrist != null && index != null && pinky != null) {
      pts.add(Offset(
        (wrist.dx + index.dx + pinky.dx) / 3,
        (wrist.dy + index.dy + pinky.dy) / 3,
      ));
    }

    // Elbow-direction projection: extend beyond the wrist when only the
    // wrist is available (fingertips not detected at this confidence level).
    if (wrist != null && pts.length == 1 && elbow != null) {
      final dir = wrist - elbow;
      final len = dir.distance;
      if (len > 0.01) {
        pts.add(wrist + (dir / len) * (len * _projectionFactor));
      }
    }

    return pts;
  }
}
