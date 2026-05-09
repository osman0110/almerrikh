import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'camera_service.dart';
import 'exercise_engine.dart';

class PoseDetectionService {
  double _t = 0;

  Future<PoseSnapshot?> detect(CameraFrame frame) async {
    _t += 0.08;
    final center = Offset(
      0.5 + math.sin(_t) * 0.25,
      0.52 + math.cos(_t * 0.7) * 0.18,
    );
    final bodyBox = Rect.fromCenter(
      center: center,
      width: 0.22,
      height: 0.36,
    );
    return PoseSnapshot(
      bodyBox: bodyBox,
      center: center,
      leftWrist: center + const Offset(-0.13, -0.09),
      rightWrist: center + const Offset(0.13, -0.09),
      leftAnkle: center + const Offset(-0.09, 0.18),
      rightAnkle: center + const Offset(0.09, 0.18),
      bodyFullyVisible: true,
      headVisible: true,
      shouldersVisible: true,
      hipsVisible: true,
      lowerBodyVisible: true,
      insideGuideFrame: true,
      confidence: 0.92,
      detectionScore: 7,
      landmarkCount: 8,
      imageSize: Size(frame.width.toDouble(), frame.height.toDouble()),
      rotation: frame.rotation,
      landmarks: {
        'nose': center + const Offset(0, -0.18),
        'leftShoulder': center + const Offset(-0.10, -0.09),
        'rightShoulder': center + const Offset(0.10, -0.09),
        'leftHip': center + const Offset(-0.08, 0.06),
        'rightHip': center + const Offset(0.08, 0.06),
        'leftWrist': center + const Offset(-0.13, -0.09),
        'rightWrist': center + const Offset(0.13, -0.09),
        'leftAnkle': center + const Offset(-0.09, 0.18),
        'rightAnkle': center + const Offset(0.09, 0.18),
      },
      tooClose: false,
      tooFar: false,
      lowLight: false,
    );
  }

  Future<void> dispose() async {}
}
