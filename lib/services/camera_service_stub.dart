import 'dart:async';

import 'package:flutter/material.dart';

import '../camera_view.dart';

class CameraFrame {
  const CameraFrame({
    required this.image,
    required this.width,
    required this.height,
    required this.rotation,
    this.isFront = true,
  });

  final Object? image;
  final int width;
  final int height;
  final int rotation;
  final bool isFront;
}

class CameraService {
  final _controller = StreamController<CameraFrame>.broadcast();

  Stream<CameraFrame> get frames => _controller.stream;
  bool get isDemoMode => true;

  Future<bool> requestPermission() async => true;
  Future<void> initialize() async {}
  Future<void> startImageStream({bool landscapeLeft = true}) async {}
  Future<void> stopImageStream() async {}

  Widget buildPreview() => const CameraPreviewView();

  Future<void> dispose() async {
    await _controller.close();
  }
}
