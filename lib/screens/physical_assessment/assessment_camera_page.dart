import 'dart:async';

import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/assessment_result_model.dart';
import '../../models/player_profile_model.dart';
import '../../services/camera_service.dart';
import '../../services/physical_assessment_service.dart';
import '../../services/pose_detection_service_mobile.dart';
import '../../services/assessment_storage_service.dart';
import '../../services/exercise_engine.dart';
import '../../widgets/common_widgets.dart';

class AssessmentCameraArguments {
  const AssessmentCameraArguments({required this.player, required this.testType});

  final PlayerProfile player;
  final AssessmentTestType testType;
}

class AssessmentCameraPage extends StatefulWidget {
  const AssessmentCameraPage({super.key, required this.player, required this.testType});

  final PlayerProfile player;
  final AssessmentTestType testType;

  @override
  State<AssessmentCameraPage> createState() => _AssessmentCameraPageState();
}

class _AssessmentCameraPageState extends State<AssessmentCameraPage> {
  final CameraService _cameraService = CameraService();
  final PoseDetectionService _poseService = PoseDetectionService();
  final List<PoseSnapshot> _capturedFrames = [];
  StreamSubscription? _frameSubscription;
  bool _cameraReady = false;
  bool _capturing = false;
  String _statusLabel = 'Preparing camera…';
  int _validFrames = 0;
  PoseSnapshot? _latestPose;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _cameraService.dispose();
    _poseService.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    final granted = await _cameraService.requestPermission();
    if (!granted) {
      setState(() {
        _statusLabel = AppLocalizations.get('camera_permission_denied');
      });
      return;
    }

    try {
      await _cameraService.initialize();
      await _cameraService.startImageStream();
      _frameSubscription = _cameraService.frames.listen(_onFrameReceived);
      setState(() {
        _cameraReady = true;
        _statusLabel = AppLocalizations.get('camera_ready');
      });
    } catch (error) {
      setState(() {
        _statusLabel = AppLocalizations.get('camera_initialization_failed');
      });
    }
  }

  Future<void> _onFrameReceived(dynamic rawFrame) async {
    if (!_cameraReady) return;
    if (!_capturing) return;
    if (rawFrame is! CameraFrame) return;

    final snapshot = await _poseService.detect(rawFrame);
    if (snapshot == null) return;
    setState(() {
      _latestPose = snapshot;
      if (snapshot.bodyFullyVisible) {
        _validFrames += 1;
        _capturedFrames.add(snapshot);
        _statusLabel = AppLocalizations.get('assessment_capturing');
      } else {
        _statusLabel = AppLocalizations.get('assessment_align_body');
      }
    });

    if (_capturedFrames.length >= 18) {
      await _finishAssessment();
    }
  }

  Future<void> _finishAssessment() async {
    if (_saving) return;
    if (_capturedFrames.isEmpty) {
      setState(() {
        _statusLabel = AppLocalizations.get('assessment_no_valid_frames');
      });
      return;
    }

    setState(() {
      _saving = true;
      _statusLabel = AppLocalizations.get('assessment_processing');
    });

    final result = PhysicalAssessmentService.analyzeSquat(
      widget.testType,
      widget.player.id,
      widget.player.name,
      _capturedFrames,
    );

    await AssessmentStorageService.instance.saveAssessment(result);
    setState(() {
      _saving = false;
    });

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      '/physical-assessment/result',
      arguments: result,
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_validFrames / 18).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(AppLocalizations.get('assessment_camera_title')),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _cameraReady
                  ? Stack(
                      children: [
                        _cameraService.buildPreview(),
                        if (_latestPose != null)
                          CustomPaint(
                            painter: _PoseOverlayPainter(_latestPose!),
                            size: Size.infinite,
                          ),
                      ],
                    )
                  : const ColoredBox(color: Colors.black),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _statusLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: _capturing
                                ? AppLocalizations.get('assessment_stop')
                                : AppLocalizations.get('assessment_start_capture'),
                            onTap: _capturing
                                ? () => setState(() => _capturing = false)
                                : () => setState(() {
                                      _capturing = true;
                                      _statusLabel = AppLocalizations.get('assessment_follow_instructions');
                                    }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PoseOverlayPainter extends CustomPainter {
  const _PoseOverlayPainter(this.pose);

  final PoseSnapshot pose;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;
    if (pose.bodyBox != null) {
      paint
        ..color = AppColors.primary.withOpacity(0.9)
        ..strokeWidth = 2;
      final rect = Rect.fromLTWH(
        pose.bodyBox!.left * size.width,
        pose.bodyBox!.top * size.height,
        pose.bodyBox!.width * size.width,
        pose.bodyBox!.height * size.height,
      );
      canvas.drawRect(rect, paint);
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    dotPaint.color = AppColors.primary.withOpacity(0.9);
    for (final point in [
      pose.leftWrist,
      pose.rightWrist,
      pose.leftAnkle,
      pose.rightAnkle,
      pose.center,
    ]) {
      if (point != null) {
        canvas.drawCircle(Offset(point.dx * size.width, point.dy * size.height), 6, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PoseOverlayPainter oldDelegate) {
    return oldDelegate.pose != pose;
  }
}
