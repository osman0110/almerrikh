import 'dart:async';

import 'package:flutter/material.dart';

import '../camera_view.dart';

/// Declared here so the type exists uniformly across the mobile/web/stub
/// camera_service exports — never thrown on the (demo-mode) stub platform.
class CameraUnsupportedException implements Exception {
  const CameraUnsupportedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Declared here so the type exists uniformly across the mobile/web/stub
/// camera_service exports — never thrown on the (demo-mode) stub platform.
class CameraPermissionDeniedException implements Exception {
  const CameraPermissionDeniedException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CameraFrame {
  const CameraFrame({
    required this.image,
    required this.width,
    required this.height,
    required this.rotation,
    this.isFront = true,
    this.timestampMs = 0,
  });

  final Object? image;
  final int width;
  final int height;
  final int rotation;
  final bool isFront;
  final int timestampMs;
}

class CameraService {
  final _controller = StreamController<CameraFrame>.broadcast();

  Stream<CameraFrame> get frames => _controller.stream;
  bool get isDemoMode => true;

  Future<bool> requestPermission() async => true;
  Future<void> initialize({bool preferFront = false}) async {}
  Future<void> startImageStream({bool landscapeLeft = true}) async {}
  Future<void> stopImageStream() async {}

  Widget buildPreview() => const CameraPreviewView();

  Map<String, Object?> getVideoStatus() => const {
    'videoFound': false, 'trackState': 'none', 'paused': true,
    'videoWidth': 0, 'videoHeight': 0,
  };

  Future<void> dispose() async {
    await _controller.close();
  }
}
