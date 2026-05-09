import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'camera_service.dart';
import 'exercise_engine.dart';

class PoseDetectionService {
  PoseDetectionService()
      : _detector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: PoseDetectionModel.base,
          ),
        );

  final PoseDetector _detector;
  bool _busy = false;

  Future<PoseSnapshot?> detect(CameraFrame frame) async {
    if (_busy) return null;
    _busy = true;
    try {
      final input = _inputImageFromFrame(frame);
      if (input == null) return null;
      final poses = await _detector.processImage(input);
      debugPrint('POSES COUNT: ${poses.length}');
      if (poses.isNotEmpty) {
        debugPrint('LANDMARKS COUNT (first pose): ${poses.first.landmarks.length}');
      }
      if (poses.isEmpty) {
        return const PoseSnapshot(
          bodyBox: null,
          center: null,
          leftWrist: null,
          rightWrist: null,
          leftAnkle: null,
          rightAnkle: null,
          bodyFullyVisible: false,
          headVisible: false,
          shouldersVisible: false,
          hipsVisible: false,
          lowerBodyVisible: false,
          insideGuideFrame: false,
          confidence: 0,
          detectionScore: 0,
          landmarkCount: 0,
          imageSize: Size.zero,
          rotation: 0,
          landmarks: {},
          tooClose: false,
          tooFar: false,
          lowLight: false,
        );
      }
      return _snapshotFromPose(poses.first, frame.width, frame.height, frame.rotation, frame.isFront);
    } finally {
      _busy = false;
    }
  }

  InputImage? _inputImageFromFrame(CameraFrame frame) {
    final rawImage = frame.image;
    if (rawImage == null || rawImage is! CameraImage) return null;
    final image = rawImage;
    final rotation =
        InputImageRotationValue.fromRawValue(frame.rotation) ??
            InputImageRotation.rotation0deg;
    // Detect actual camera image format instead of assuming platform.
    final formatGroup = image.format.group;
    final bytes = _concatPlanes(image.planes);
    InputImageFormat inputFormat;
    if (formatGroup == ImageFormatGroup.nv21) {
      inputFormat = InputImageFormat.nv21;
    } else {
      // Fallback to bgra8888 for other cases (iOS simulators, etc.).
      inputFormat = InputImageFormat.bgra8888;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: inputFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatPlanes(List<Plane> planes) {
    final buffer = WriteBuffer();
    for (final plane in planes) {
      buffer.putUint8List(plane.bytes);
    }
    return buffer.done().buffer.asUint8List();
  }

  PoseSnapshot _snapshotFromPose(
    Pose pose,
    int frameWidth,
    int frameHeight,
    int rotation,
    bool isFront,
  ) {
    final landmarks = pose.landmarks;
    final visible = landmarks.values.where((l) => l.likelihood > 0.30).toList();

    // Transforms a raw camera pixel (px, py) into screen-normalised [0,1]×[0,1]
    // coords that match the on-screen target coordinate system.
    //   1. Divide by image dimensions → [0,1] in image space.
    //   2. Apply the ML Kit rotation so the axes align with the landscape display.
    //   3. Mirror horizontally for the front (selfie) camera.
    final rot = ((rotation % 360) + 360) % 360;
    Offset toScreen(double px, double py) {
      final nx = (px / frameWidth).clamp(0.0, 1.0);
      final ny = (py / frameHeight).clamp(0.0, 1.0);
      double rx, ry;
      switch (rot) {
        case 90:  rx = ny;        ry = 1.0 - nx; break;
        case 180: rx = 1.0 - nx; ry = 1.0 - ny; break;
        case 270: rx = 1.0 - ny; ry = nx;        break;
        default:  rx = nx;        ry = ny;
      }
      if (isFront) rx = 1.0 - rx;
      return Offset(rx.clamp(0.0, 1.0), ry.clamp(0.0, 1.0));
    }

    // After rotation the effective image dimensions swap for 90/270.
    // The debug painter uses this size for BoxFit.cover offset calculations.
    final screenImageSize = (rot == 90 || rot == 270)
        ? Size(frameHeight.toDouble(), frameWidth.toDouble())
        : Size(frameWidth.toDouble(), frameHeight.toDouble());

    if (visible.isEmpty) {
      return PoseSnapshot(
        bodyBox: null,
        center: null,
        leftWrist: null,
        rightWrist: null,
        leftAnkle: null,
        rightAnkle: null,
        bodyFullyVisible: false,
        headVisible: false,
        shouldersVisible: false,
        hipsVisible: false,
        lowerBodyVisible: false,
        insideGuideFrame: false,
        confidence: 0,
        detectionScore: 0,
        landmarkCount: 0,
        imageSize: screenImageSize,
        rotation: 0,
        landmarks: {},
        tooClose: false,
        tooFar: false,
        lowLight: false,
      );
    }

    // Compute the body bounding box in screen-normalised space.
    final screenPoints = visible.map((l) => toScreen(l.x, l.y)).toList();
    final minX = screenPoints.map((p) => p.dx).reduce(math.min);
    final maxX = screenPoints.map((p) => p.dx).reduce(math.max);
    final minY = screenPoints.map((p) => p.dy).reduce(math.min);
    final maxY = screenPoints.map((p) => p.dy).reduce(math.max);
    final normBox = Rect.fromLTRB(
      minX.clamp(0.0, 1.0),
      minY.clamp(0.0, 1.0),
      maxX.clamp(0.0, 1.0),
      maxY.clamp(0.0, 1.0),
    );

    Offset? point(PoseLandmarkType type) {
      final item = landmarks[type];
      if (item == null || item.likelihood < 0.35) return null;
      return toScreen(item.x, item.y);
    }

    bool visiblePoint(PoseLandmarkType type, [double threshold = 0.25]) {
      return (landmarks[type]?.likelihood ?? 0) >= threshold;
    }

    final headVisible = visiblePoint(PoseLandmarkType.nose) ||
        visiblePoint(PoseLandmarkType.leftEye, 0.28) ||
        visiblePoint(PoseLandmarkType.rightEye, 0.28) ||
        visiblePoint(PoseLandmarkType.leftEar, 0.28) ||
        visiblePoint(PoseLandmarkType.rightEar, 0.28);
    final shouldersVisible = visiblePoint(PoseLandmarkType.leftShoulder) &&
        visiblePoint(PoseLandmarkType.rightShoulder);
    final hipsVisible =
        visiblePoint(PoseLandmarkType.leftHip) && visiblePoint(PoseLandmarkType.rightHip);
    final kneesVisible = visiblePoint(PoseLandmarkType.leftKnee) ||
        visiblePoint(PoseLandmarkType.rightKnee);
    final anklesVisible = visiblePoint(PoseLandmarkType.leftAnkle) ||
        visiblePoint(PoseLandmarkType.rightAnkle);
    final lowerBodyVisible = kneesVisible || anklesVisible;
    final detectionScore = (headVisible ? 1 : 0) +
        (shouldersVisible ? 2 : 0) +
        (hipsVisible ? 2 : 0) +
        (lowerBodyVisible ? 2 : 0);
    final confidence = visible
            .map((l) => l.likelihood)
            .fold<double>(0, (sum, value) => sum + value) /
        visible.length;
    final guide = ExerciseEngine.guideFrame;
    final insideGuide = _insideRatio(normBox, guide) >= 0.60;
    final full = headVisible &&
        shouldersVisible &&
        hipsVisible &&
        lowerBodyVisible &&
        insideGuide &&
        confidence >= 0.30;

    return PoseSnapshot(
      bodyBox: normBox,
      center: normBox.center,
      leftWrist: point(PoseLandmarkType.leftWrist),
      rightWrist: point(PoseLandmarkType.rightWrist),
      leftAnkle: point(PoseLandmarkType.leftAnkle),
      rightAnkle: point(PoseLandmarkType.rightAnkle),
      bodyFullyVisible: full,
      headVisible: headVisible,
      shouldersVisible: shouldersVisible,
      hipsVisible: hipsVisible,
      lowerBodyVisible: lowerBodyVisible,
      insideGuideFrame: insideGuide,
      confidence: confidence,
      detectionScore: detectionScore,
      landmarkCount: visible.length,
      imageSize: screenImageSize,
      rotation: 0, // coords are already screen-normalised; rotation baked in
      landmarks: {
        for (final entry in landmarks.entries)
          if (entry.value.likelihood >= 0.25)
            entry.key.name: toScreen(entry.value.x, entry.value.y),
      },
      tooClose: normBox.height > 0.85 || normBox.width > 0.75,
      tooFar: normBox.height < 0.35,
      lowLight: false,
    );
  }

  double _insideRatio(Rect body, Rect guide) {
    final overlap = body.intersect(guide);
    if (overlap.isEmpty) return 0;
    final bodyArea = body.width * body.height;
    if (bodyArea <= 0) return 0;
    return (overlap.width * overlap.height) / bodyArea;
  }

  Future<void> dispose() => _detector.close();
}

