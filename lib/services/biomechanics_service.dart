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

class BiomechanicsService {
  static const double _minConfidence = 0.30;

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
}
