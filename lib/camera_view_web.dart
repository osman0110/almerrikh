import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class CameraPreviewView extends StatefulWidget {
  const CameraPreviewView({super.key});

  @override
  State<CameraPreviewView> createState() => _CameraPreviewViewState();
}

class _CameraPreviewViewState extends State<CameraPreviewView> {
  late final String _viewType;
  html.MediaStream? _stream;

  @override
  void initState() {
    super.initState();
    _viewType = 'ssot-camera-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final video = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.backgroundColor = '#000';

      html.window.navigator.mediaDevices
          ?.getUserMedia({
            'video': {'facingMode': 'user'},
            'audio': false,
          })
          .then((stream) {
            _stream = stream;
            video.srcObject = stream;
          })
          .catchError((_) {});
      return video;
    });
  }

  @override
  void dispose() {
    _stream?.getTracks().forEach((track) => track.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
