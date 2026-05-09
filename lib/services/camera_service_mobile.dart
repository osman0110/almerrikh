import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraFrame {
  const CameraFrame({
    required this.image,
    required this.width,
    required this.height,
    required this.rotation,
    this.isFront = true,
  });

  final CameraImage? image;
  final int width;
  final int height;
  final int rotation;
  final bool isFront;
}

class CameraService {
  CameraController? _controller;
  CameraDescription? _cameraDescription;
  final _frames = StreamController<CameraFrame>.broadcast();
  bool _streaming = false;

  Stream<CameraFrame> get frames => _frames.stream;
  bool get isDemoMode => false;

  Future<bool> requestPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _cameraDescription = camera;
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      // Use nv21 on Android (Safe now since we are using Camera 1 API, not CameraX)
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await _controller!.initialize();
  }

  Future<void> startImageStream({bool landscapeLeft = true}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _streaming) {
      return;
    }
    _streaming = true;
    final sensorOrientation = _cameraDescription?.sensorOrientation ?? 0;
    final isFront =
        _cameraDescription?.lensDirection == CameraLensDirection.front;
    // Device is forced into landscape; compute the rotation ML Kit needs.
    // Formula (from Google ML Kit Flutter examples):
    //   front : (sensorOrientation + deviceDeg)        % 360
    //   rear  : (sensorOrientation - deviceDeg + 360)  % 360
    final deviceDeg = landscapeLeft ? 90 : 270;
    final mlKitRotation = Platform.isAndroid
        ? isFront
            ? (sensorOrientation + deviceDeg) % 360
            : (sensorOrientation - deviceDeg + 360) % 360
        : sensorOrientation;
    debugPrint(
        'Camera: sensor=$sensorOrientation front=$isFront device=${deviceDeg}° → mlKit=${mlKitRotation}°');
    await controller.startImageStream((image) {
      if (_frames.isClosed) return;
      _frames.add(CameraFrame(
        image: image,
        width: image.width,
        height: image.height,
        rotation: mlKitRotation,
        isFront: isFront,
      ));
    });
  }

  Future<void> stopImageStream() async {
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    _streaming = false;
  }

  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return CameraPreview(controller);
  }

  Future<void> dispose() async {
    await stopImageStream();
    await _controller?.dispose();
    await _frames.close();
  }
}
