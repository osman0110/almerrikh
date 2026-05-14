import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/exercise_engine.dart';

class BiomechanicsMetrics {
  BiomechanicsMetrics({
    required this.leftKneeAngle,
    required this.rightKneeAngle,
    required this.leftHipAngle,
    required this.rightHipAngle,
    required this.trunkAngle,
    required this.shoulderLevelDifference,
    required this.hipLevelDifference,
    required this.centerStability,
    required this.visibilityScore,
  });

  final double leftKneeAngle;
  final double rightKneeAngle;
  final double leftHipAngle;
  final double rightHipAngle;
  final double trunkAngle;
  final double shoulderLevelDifference;
  final double hipLevelDifference;
  final double centerStability;
  final double visibilityScore;

  double get averageKneeAngle => (leftKneeAngle + rightKneeAngle) / 2;
  double get averageHipAngle => (leftHipAngle + rightHipAngle) / 2;
  double get symmetryDelta => (leftKneeAngle - rightKneeAngle).abs() +
      (leftHipAngle - rightHipAngle).abs();
}

class SquatBiomechanicsMetrics extends BiomechanicsMetrics {
  SquatBiomechanicsMetrics({
    required super.leftKneeAngle,
    required super.rightKneeAngle,
    required super.leftHipAngle,
    required super.rightHipAngle,
    required super.trunkAngle,
    required super.shoulderLevelDifference,
    required super.hipLevelDifference,
    required super.centerStability,
    required super.visibilityScore,
    required this.minKneeAngle,
    required this.kneeAlignmentScore,
    required this.trunkLeanDeg,
    required this.movementVariance,
    required this.minLeftKneeAngle,
    required this.minRightKneeAngle,
    required this.bottomKneeAngle,
    required this.hipDepthAtBottom,
    required this.bottomFrameIndex,
    required this.avgLowerBodyConf,
  });

  final double minKneeAngle;
  final double kneeAlignmentScore;
  final double trunkLeanDeg;
  final double movementVariance;
  // Bottom-phase specific metrics
  final double minLeftKneeAngle;
  final double minRightKneeAngle;
  final double bottomKneeAngle;   // avg knee angle during bottom phase
  final double hipDepthAtBottom;  // avg hip Y (0=top, 1=bottom of frame)
  final int    bottomFrameIndex;  // index in validFrames of the deepest frame
  final double avgLowerBodyConf;  // avg confidence across captured frames
}

class BiomechanicsService {

  static BiomechanicsMetrics analyzePose(PoseSnapshot pose) {
    final leftHip = pose.landmarks['leftHip'];
    final rightHip = pose.landmarks['rightHip'];
    final leftKnee = pose.landmarks['leftKnee'];
    final rightKnee = pose.landmarks['rightKnee'];
    final leftAnkle = pose.landmarks['leftAnkle'];
    final rightAnkle = pose.landmarks['rightAnkle'];
    final leftShoulder = pose.landmarks['leftShoulder'];
    final rightShoulder = pose.landmarks['rightShoulder'];

    final leftKneeAngle = _angleBetween(leftHip, leftKnee, leftAnkle);
    final rightKneeAngle = _angleBetween(rightHip, rightKnee, rightAnkle);
    final leftHipAngle = _angleBetween(leftShoulder, leftHip, leftKnee);
    final rightHipAngle = _angleBetween(rightShoulder, rightHip, rightKnee);
    final trunkAngle = _angleBetween(leftShoulder, leftHip, rightHip);

    final shoulderLevelDifference = _horizontalDistance(leftShoulder, rightShoulder);
    final hipLevelDifference = _horizontalDistance(leftHip, rightHip);

    final centerStability = _centerStability(pose.center);
    final visibilityScore = _visibilityScore(pose);

    return BiomechanicsMetrics(
      leftKneeAngle: leftKneeAngle,
      rightKneeAngle: rightKneeAngle,
      leftHipAngle: leftHipAngle,
      rightHipAngle: rightHipAngle,
      trunkAngle: trunkAngle,
      shoulderLevelDifference: shoulderLevelDifference,
      hipLevelDifference: hipLevelDifference,
      centerStability: centerStability,
      visibilityScore: visibilityScore,
    );
  }

  static double _angleBetween(Offset? a, Offset? b, Offset? c) {
    if (a == null || b == null || c == null) return 0.0;
    final ab = a - b;
    final cb = c - b;
    final dot = ab.dx * cb.dx + ab.dy * cb.dy;
    final mag = (ab.distance * cb.distance).clamp(0.001, double.infinity);
    final cos = (dot / mag).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  static double _horizontalDistance(Offset? a, Offset? b) {
    if (a == null || b == null) return 999.0;
    return (a.dy - b.dy).abs();
  }

  static double _centerStability(Offset? center) {
    if (center == null) return 0.0;
    final dx = (center.dx - 0.5).abs();
    return (1.0 - dx * 2).clamp(0.0, 1.0);
  }

  static double _visibilityScore(PoseSnapshot pose) {
    final count = pose.landmarks.length;
    if (count == 0) return 0.0;
    return pose.landmarks.values.fold<double>(0, (sum, point) {
      return sum + 1.0;
    }) /
        14.0;
  }

  static SquatBiomechanicsMetrics _zeroSquat() => SquatBiomechanicsMetrics(
        leftKneeAngle: 0, rightKneeAngle: 0, leftHipAngle: 0,
        rightHipAngle: 0, trunkAngle: 0, shoulderLevelDifference: 0,
        hipLevelDifference: 0, centerStability: 0, visibilityScore: 0,
        minKneeAngle: 0, kneeAlignmentScore: 0, trunkLeanDeg: 0,
        movementVariance: 0, minLeftKneeAngle: 0, minRightKneeAngle: 0,
        bottomKneeAngle: 0, hipDepthAtBottom: 0, bottomFrameIndex: -1,
        avgLowerBodyConf: 0,
      );

  static bool _hasLowerBody(PoseSnapshot pose) =>
      (pose.landmarks.containsKey('leftKnee') || pose.landmarks.containsKey('rightKnee')) &&
      (pose.landmarks.containsKey('leftHip') || pose.landmarks.containsKey('rightHip'));

  static SquatBiomechanicsMetrics analyzeSquatSequence(List<PoseSnapshot> frames) {
    if (frames.isEmpty) return _zeroSquat();

    // Keep frames that have lower-body landmarks and acceptable confidence
    final validFrames = frames
        .where((f) => f.confidence > 0.25 && _hasLowerBody(f))
        .toList();

    if (validFrames.isEmpty) return _zeroSquat();

    // Per-frame average knee angle (left+right) for finding bottom phase
    final frameAvgKnee = validFrames.map((f) {
      final lk = _angleBetween(f.landmarks['leftHip'], f.landmarks['leftKnee'], f.landmarks['leftAnkle']);
      final rk = _angleBetween(f.landmarks['rightHip'], f.landmarks['rightKnee'], f.landmarks['rightAnkle']);
      final count = (lk > 0 ? 1 : 0) + (rk > 0 ? 1 : 0);
      return count > 0 ? (lk + rk) / count : 180.0;
    }).toList();

    // Bottom frame = minimum avg knee angle (deepest squat)
    int bottomIdx = 0;
    double minAvgKnee = double.infinity;
    for (int i = 0; i < frameAvgKnee.length; i++) {
      if (frameAvgKnee[i] < minAvgKnee) {
        minAvgKnee = frameAvgKnee[i];
        bottomIdx = i;
      }
    }

    // Bottom-phase window: ±15% of valid frames, min 3 frames each side
    final halfWin = math.max(3, (validFrames.length * 0.15).round());
    final bStart = math.max(0, bottomIdx - halfWin);
    final bEnd = math.min(validFrames.length - 1, bottomIdx + halfWin);
    final bottomFrames = validFrames.sublist(bStart, bEnd + 1);

    // Average metrics over all valid frames
    final allMetrics = validFrames.map(analyzePose).toList();
    final average = _averageMetrics(allMetrics);

    // Bottom-phase specific metrics
    double minLeftKnee = double.infinity;
    double minRightKnee = double.infinity;
    double sumBottomKnee = 0;
    double sumHipDepth = 0;
    double sumConf = 0;

    for (final f in bottomFrames) {
      final lk = _angleBetween(f.landmarks['leftHip'], f.landmarks['leftKnee'], f.landmarks['leftAnkle']);
      final rk = _angleBetween(f.landmarks['rightHip'], f.landmarks['rightKnee'], f.landmarks['rightAnkle']);
      if (lk > 0) minLeftKnee = math.min(minLeftKnee, lk);
      if (rk > 0) minRightKnee = math.min(minRightKnee, rk);
      final cnt = (lk > 0 ? 1 : 0) + (rk > 0 ? 1 : 0);
      sumBottomKnee += cnt > 0 ? (lk + rk) / cnt : 0;
      final lh = f.landmarks['leftHip'];
      final rh = f.landmarks['rightHip'];
      if (lh != null && rh != null) {
        sumHipDepth += (lh.dy + rh.dy) / 2;
      } else {
        sumHipDepth += (lh ?? rh)?.dy ?? 0.5;
      }
      sumConf += f.confidence;
    }

    final bc = bottomFrames.length.toDouble();

    // Trunk lean from bottom frames (more meaningful at deepest point)
    double totalTrunkLean = 0;
    int trunkCount = 0;
    for (final pose in bottomFrames) {
      final tilt = _computeTrunkLeanDegrees(pose);
      if (tilt >= 0) { totalTrunkLean += tilt; trunkCount++; }
    }
    final trunkLeanDeg = trunkCount > 0 ? totalTrunkLean / trunkCount : 0;

    // Knee alignment across all frames
    double totalKneeAlignment = 0;
    int alignmentCount = 0;
    for (final pose in validFrames) {
      final l = _computeKneeAlignment(pose, 'left');
      final r = _computeKneeAlignment(pose, 'right');
      if (l >= 0) { totalKneeAlignment += l; alignmentCount++; }
      if (r >= 0) { totalKneeAlignment += r; alignmentCount++; }
    }
    final kneeAlignmentScore = alignmentCount > 0 ? totalKneeAlignment / alignmentCount : 0.5;

    // Movement variance across all frames
    final kneeAngles = allMetrics.expand((m) => [m.leftKneeAngle, m.rightKneeAngle]).toList();
    final movementVariance = _standardDeviation(kneeAngles);

    return SquatBiomechanicsMetrics(
      leftKneeAngle: average.leftKneeAngle,
      rightKneeAngle: average.rightKneeAngle,
      leftHipAngle: average.leftHipAngle,
      rightHipAngle: average.rightHipAngle,
      trunkAngle: average.trunkAngle,
      shoulderLevelDifference: average.shoulderLevelDifference,
      hipLevelDifference: average.hipLevelDifference,
      centerStability: average.centerStability,
      visibilityScore: average.visibilityScore,
      minKneeAngle: minAvgKnee == double.infinity ? 0 : minAvgKnee,
      kneeAlignmentScore: kneeAlignmentScore,
      trunkLeanDeg: trunkLeanDeg.toDouble(),
      movementVariance: movementVariance.toDouble(),
      minLeftKneeAngle: minLeftKnee == double.infinity ? 0 : minLeftKnee,
      minRightKneeAngle: minRightKnee == double.infinity ? 0 : minRightKnee,
      bottomKneeAngle: bc > 0 ? sumBottomKnee / bc : 0,
      hipDepthAtBottom: bc > 0 ? sumHipDepth / bc : 0,
      bottomFrameIndex: bottomIdx,
      avgLowerBodyConf: bc > 0 ? sumConf / bc : 0,
    );
  }

  static double _computeKneeAlignment(PoseSnapshot pose, String side) {
    final knee = side == 'left' ? pose.landmarks['leftKnee'] : pose.landmarks['rightKnee'];
    final ankle = side == 'left' ? pose.landmarks['leftAnkle'] : pose.landmarks['rightAnkle'];

    if (knee == null || ankle == null) return -1;

    // Valgus proxy: how far knee x deviates from ankle x
    // Left side: knee should be ~aligned or slightly lateral to ankle
    // Right side: knee should be ~aligned or slightly lateral to ankle
    final deviation = (knee.dx - ankle.dx).abs();
    // Good alignment: deviation < 0.05 of frame width
    // Poor alignment: deviation > 0.15
    return (1.0 - (deviation * 8).clamp(0, 1)).clamp(0, 1);
  }

  static double _computeTrunkLeanDegrees(PoseSnapshot pose) {
    final lShoulder = pose.landmarks['leftShoulder'];
    final rShoulder = pose.landmarks['rightShoulder'];
    final lHip = pose.landmarks['leftHip'];
    final rHip = pose.landmarks['rightHip'];

    if ((lShoulder == null && rShoulder == null) ||
        (lHip == null && rHip == null)) return -1;

    // Midpoint coordinates (fall back to single side if one is missing)
    final sx = (lShoulder != null && rShoulder != null)
        ? (lShoulder.dx + rShoulder.dx) / 2
        : (lShoulder ?? rShoulder)!.dx;
    final sy = (lShoulder != null && rShoulder != null)
        ? (lShoulder.dy + rShoulder.dy) / 2
        : (lShoulder ?? rShoulder)!.dy;
    final hx = (lHip != null && rHip != null)
        ? (lHip.dx + rHip.dx) / 2
        : (lHip ?? rHip)!.dx;
    final hy = (lHip != null && rHip != null)
        ? (lHip.dy + rHip.dy) / 2
        : (lHip ?? rHip)!.dy;

    final dx = sx - hx;
    final dy = sy - hy; // negative in screen coords (shoulder above hip)

    // Lean from vertical: atan2(|horizontal|, height)
    // -dy is positive because shoulder.dy < hip.dy in screen coords
    final angleRad = math.atan2(dx.abs(), -dy);
    return (angleRad * 180 / math.pi).abs();
  }

  static double _standardDeviation(List<double> values) {
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.fold<double>(0, (sum, v) => sum + (v - mean) * (v - mean)) / values.length;
    return math.sqrt(variance);
  }

  static BiomechanicsMetrics _averageMetrics(List<BiomechanicsMetrics> metrics) {
    if (metrics.isEmpty) {
      return BiomechanicsMetrics(
        leftKneeAngle: 0,
        rightKneeAngle: 0,
        leftHipAngle: 0,
        rightHipAngle: 0,
        trunkAngle: 0,
        shoulderLevelDifference: 0,
        hipLevelDifference: 0,
        centerStability: 0,
        visibilityScore: 0,
      );
    }
    final count = metrics.length.toDouble();
    return BiomechanicsMetrics(
      leftKneeAngle: metrics.map((m) => m.leftKneeAngle).reduce((a, b) => a + b) / count,
      rightKneeAngle: metrics.map((m) => m.rightKneeAngle).reduce((a, b) => a + b) / count,
      leftHipAngle: metrics.map((m) => m.leftHipAngle).reduce((a, b) => a + b) / count,
      rightHipAngle: metrics.map((m) => m.rightHipAngle).reduce((a, b) => a + b) / count,
      trunkAngle: metrics.map((m) => m.trunkAngle).reduce((a, b) => a + b) / count,
      shoulderLevelDifference:
          metrics.map((m) => m.shoulderLevelDifference).reduce((a, b) => a + b) / count,
      hipLevelDifference: metrics.map((m) => m.hipLevelDifference).reduce((a, b) => a + b) / count,
      centerStability: metrics.map((m) => m.centerStability).reduce((a, b) => a + b) / count,
      visibilityScore: metrics.map((m) => m.visibilityScore).reduce((a, b) => a + b) / count,
    );
  }
}
