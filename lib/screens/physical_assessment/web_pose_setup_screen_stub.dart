// Native stub — WebPoseSetupScreen is web-only.
// This file is imported on Android/iOS via conditional import in main.dart.
// It is never instantiated at runtime (guarded by kIsWeb check).

import 'package:flutter/material.dart';
import 'assessment_camera_page.dart';

class WebPoseSetupScreen extends StatelessWidget {
  const WebPoseSetupScreen({super.key, required this.cameraArgs});
  final AssessmentCameraArguments cameraArgs;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
