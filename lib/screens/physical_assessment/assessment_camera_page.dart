import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';
import '../../models/assessment_result_model.dart';
import '../../models/player_profile_model.dart';
import '../../models/club_models.dart';
import '../../services/camera_service.dart';
import '../../services/physical_assessment_service.dart';
import '../../services/pose_detection_service_mobile.dart';
import '../../services/assessment_storage_service.dart';
import '../../services/club_service.dart';
import '../../services/exercise_engine.dart';

enum AssessmentCameraState { setup, ready, countdown, capturing, processing }

enum _SquatPhase { standing, descent, bottom, ascent }

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

  AssessmentCameraState _state = AssessmentCameraState.setup;
  bool _cameraSelected = false; // camera picker shown until user picks
  bool _useFrontCamera = false; // back camera is default
  bool _cameraReady = false;
  bool _capturing = false;
  int _validFrames = 0;
  PoseSnapshot? _latestPose;
  PoseSnapshot? _prevPose;
  bool _saving = false;

  // Live squat metrics
  _SquatPhase _squatPhase = _SquatPhase.standing;
  double _squatDepth = 0.0; // 0 = standing, 1 = deep squat
  double? _prevAvgKneeAngle;
  // Rep-completion tracking
  bool _repDescended    = false; // has gone below 130° this rep
  bool _repBottomDone   = false; // has been in bottom phase (<100°)
  int  _framesAtReturn  = 0;     // consecutive standing frames after bottom
  int  _repCount        = 0;

  // ── Calibration state ────────────────────────────────────────────────────
  // HARD blockers (must pass to start)
  bool _poseDetected    = false;
  bool _kneesVisible    = false;
  bool _hipsVisible     = false;
  bool _ankleVisible    = false; // at least one ankle/foot

  // SOFT warnings (show warning, but do NOT block start)
  bool _bothKneesVisible  = false;
  bool _bothAnklesVisible = false;
  bool _fullBodyVisible   = false;
  bool _athleteCentered   = false;
  bool _distanceValid     = false;
  bool? _goodLighting;           // null = not yet measured

  // Computed calibration summary (updated per-frame)
  bool   _requiredPass    = false;
  int    _softWarningCount = 0;
  String _blockingReason  = 'Waiting for pose…';

  // Countdown
  Timer? _countdownTimer;
  int _countdown = 3;

  // Calibration debounce / hysteresis
  int _validStreak   = 0;
  int _invalidStreak = 0;

  // Thresholds
  static const int _readyStreakRequired   = 2; // 2 consecutive valid frames → near-instant
  static const int _cancelStreakRequired  = 8; // sustained athlete-loss to cancel countdown
  static const int _seriousStreakRequired = 3; // fast-cancel when no pose at all

  // Lower-body temporal smoothing — display only; scoring uses raw validated frames
  final Map<String, Offset> _displayLandmarks = {};
  Rect? _displayBox;
  int _rejectedFrames = 0;
  int _acceptedFrames = 0;

  static const int _targetFrameCount = 90;
  static const double _brightnessThreshold = 70.0; // 0–255 Y-plane scale

  // EMA weight for new frame (lower = smoother but more lag)
  static const double _emaAlpha = 0.22;
  static const double _emaAlphaUpper = 0.45; // less smoothing for upper body
  static const Set<String> _lowerBodyKeys = {
    'leftHip', 'rightHip',
    'leftKnee', 'rightKnee',
    'leftAnkle', 'rightAnkle',
  };

  @override
  void initState() {
    super.initState();
    _setLandscape();
    // Camera initialisation waits for user to pick front/back
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _frameSubscription?.cancel();
    _cameraService.dispose();
    _poseService.dispose();
    _restoreOrientation();
    super.dispose();
  }

  void _setLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreOrientation() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _selectCamera(bool front) {
    setState(() {
      _useFrontCamera = front;
      _cameraSelected = true;
    });
    _initializeCamera(preferFront: front);
  }

  Future<void> _initializeCamera({bool preferFront = false}) async {
    final granted = await _cameraService.requestPermission();
    if (!granted) return;

    try {
      await _cameraService.initialize(preferFront: preferFront);
      await _cameraService.startImageStream();
      _frameSubscription = _cameraService.frames.listen(_onFrameReceived);
      setState(() => _cameraReady = true);
    } catch (_) {
      // Camera failed — UI shows black preview, setup checks stay false
    }
  }

  /// Samples the Y-plane (luminance) of the raw camera frame and returns
  /// an average brightness value in [0, 255]. Returns -1 if unavailable.
  /// Uses dynamic access so we don't need to import package:camera directly.
  static double _computeFrameBrightness(CameraFrame frame) {
    try {
      final raw = frame.image;
      if (raw == null) return -1;
      final planes = (raw as dynamic).planes as List<dynamic>;
      if (planes.isEmpty) return -1;
      final bytes = (planes.first as dynamic).bytes as List<int>;
      if (bytes.isEmpty) return -1;
      int sum = 0;
      int count = 0;
      for (int i = 0; i < bytes.length; i += 32) {
        sum += bytes[i];
        count++;
      }
      return count > 0 ? sum / count : -1.0;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _onFrameReceived(dynamic rawFrame) async {
    if (!_cameraReady) return;
    if (rawFrame is! CameraFrame) return;

    // Always measure brightness so the calibration checklist reflects reality.
    final brightness = _computeFrameBrightness(rawFrame);

    final snapshot = await _poseService.detect(rawFrame);

    // ── Countdown: skeleton update + catastrophic-cancel check only ──────────
    if (_state == AssessmentCameraState.countdown) {
      _checkCancelDuringCountdown(snapshot);
      return;
    }

    // ── Setup calibration phase ───────────────────────────────────────────────
    if (!_capturing) {
      _updateCalibration(snapshot, brightness);
      return;
    }

    // ── Recording phase ────────────────────────────────────────────────────
    if (snapshot == null) return;
    if (_capturedFrames.length >= _targetFrameCount) return; // overflow guard

    // Multi-gate rejection before touching smoothing state
    final bool lowerBodyOk = _isLowerBodyValid(snapshot);
    final bool noSpike = !_hasLandmarkSpike(snapshot);
    final bool noAngleGlitch = !_hasImpossibleAngle(snapshot);
    final bool validFrame = snapshot.bodyFullyVisible &&
        snapshot.confidence > 0.45 &&
        snapshot.landmarkCount >= 10 &&
        lowerBodyOk &&
        noSpike &&
        noAngleGlitch;

    // Only update smoothing on non-spiking frames to avoid contaminating EMA
    if (noSpike && lowerBodyOk) {
      _applySmoothing(snapshot);
      _updateSquatMetrics();
    }

    setState(() {
      _latestPose = snapshot;
      if (validFrame) {
        _validFrames += 1;
        _capturedFrames.add(snapshot);
        _acceptedFrames += 1;
      } else {
        _rejectedFrames += 1;
      }
    });

    _prevPose = snapshot;

    if (_capturedFrames.length >= _targetFrameCount) {
      await _finishAssessment();
    }
  }

  void _updateCalibration(PoseSnapshot? snapshot, double brightness) {
    final lm = snapshot?.landmarks ?? {};

    // ── HARD blockers — evaluated every frame ─────────────────────────────────
    final poseOk = snapshot != null &&
        snapshot.confidence > 0.15 &&
        snapshot.landmarkCount >= 4;

    final kneesOk  = poseOk &&
        (lm.containsKey('leftKnee') || lm.containsKey('rightKnee'));
    final hipsOk   = poseOk &&
        (lm.containsKey('leftHip')  || lm.containsKey('rightHip'));
    final ankleOk  = poseOk &&
        (lm.containsKey('leftAnkle') || lm.containsKey('rightAnkle'));

    // Lower-body average confidence: use snapshot confidence as proxy
    final lbConf   = poseOk ? snapshot.confidence : 0.0;

    final requiredOk = poseOk && kneesOk && hipsOk && ankleOk && lbConf >= 0.40;

    // ── SOFT warnings — never block start ────────────────────────────────────
    final bothKnees  = poseOk &&
        lm.containsKey('leftKnee') && lm.containsKey('rightKnee');
    final bothAnkles = poseOk &&
        lm.containsKey('leftAnkle') && lm.containsKey('rightAnkle');
    final fullBody   = poseOk && snapshot.bodyFullyVisible;
    final centered   = poseOk &&
        snapshot.center != null &&
        (snapshot.center!.dx - 0.5).abs() < 0.25;
    final distOk     = poseOk && !snapshot.tooClose && !snapshot.tooFar;
    final bool? lightOk = brightness >= 0
        ? brightness >= _brightnessThreshold
        : null;

    int softWarnings = 0;
    if (!bothKnees)        softWarnings++;
    if (!bothAnkles)       softWarnings++;
    if (!fullBody)         softWarnings++;
    if (!centered)         softWarnings++;
    if (!distOk)           softWarnings++;
    if (lightOk == false)  softWarnings++;

    // Blocking reason (shown in debug + hint)
    String blocking = '';
    if (!poseOk)   blocking = 'No pose detected';
    else if (!hipsOk)   blocking = 'Hips not visible';
    else if (!kneesOk)  blocking = 'Knees not visible';
    else if (!ankleOk)  blocking = 'No ankle/foot detected';
    else if (lbConf < 0.40) blocking = 'Low confidence (${(lbConf * 100).round()}%)';

    // Serious hard failure for fast cancel during countdown
    final seriousFailure = !poseOk ||
        snapshot.confidence < 0.20 ||
        snapshot.landmarkCount < 4;

    if (poseOk) _applySmoothing(snapshot);

    // ── Update streaks ────────────────────────────────────────────────────────
    if (requiredOk) {
      _validStreak++;
      _invalidStreak = 0;
    } else {
      _invalidStreak++;
      _validStreak = 0;
      if (seriousFailure && _invalidStreak < _seriousStreakRequired) {
        _invalidStreak = _seriousStreakRequired;
      }
    }

    debugPrint(
      '[Calib] req=$requiredOk valid=$_validStreak invalid=$_invalidStreak '
      'soft=$softWarnings conf=${lbConf.toStringAsFixed(2)} '
      'state=$_state ${blocking.isNotEmpty ? "BLOCK: $blocking" : ""}',
    );

    setState(() {
      _latestPose = snapshot;

      // ── Update calibration fields (always outside countdown) ───────────────
      if (_state != AssessmentCameraState.countdown) {
        _poseDetected     = poseOk;
        _kneesVisible     = kneesOk;
        _hipsVisible      = hipsOk;
        _ankleVisible     = ankleOk;
        _bothKneesVisible  = bothKnees;
        _bothAnklesVisible = bothAnkles;
        _fullBodyVisible   = fullBody;
        _athleteCentered   = centered;
        _distanceValid     = distOk;
        _requiredPass      = requiredOk;
        _softWarningCount  = softWarnings;
        _blockingReason    = blocking;
        if (brightness >= 0) _goodLighting = lightOk;
      }

      // ── State transitions (debounced) ──────────────────────────────────────
      if (_state == AssessmentCameraState.setup) {
        if (_validStreak >= _readyStreakRequired && _countdownTimer == null) {
          debugPrint('[Calib] → COUNTDOWN START (streak=$_validStreak)');
          _startCountdown();
        }
      } else if (_state == AssessmentCameraState.countdown) {
        // Only cancel on sustained HARD failures — soft misses are ignored
        final hardFail = !requiredOk;
        final sustainedHard  = hardFail && _invalidStreak >= _cancelStreakRequired;
        final seriousSustain = seriousFailure && _invalidStreak >= _seriousStreakRequired;

        if (sustainedHard || seriousSustain) {
          debugPrint(
            '[Calib] → CANCELLED (invalid=$_invalidStreak '
            'serious=$seriousFailure reason="$blocking")',
          );
          _state = AssessmentCameraState.setup;
          _cancelCountdown();
          // Refresh all fields after cancel
          _poseDetected     = poseOk;
          _kneesVisible     = kneesOk;
          _hipsVisible      = hipsOk;
          _ankleVisible     = ankleOk;
          _bothKneesVisible  = bothKnees;
          _bothAnklesVisible = bothAnkles;
          _fullBodyVisible   = fullBody;
          _athleteCentered   = centered;
          _distanceValid     = distOk;
          _requiredPass      = requiredOk;
          _softWarningCount  = softWarnings;
          _blockingReason    = blocking;
          if (brightness >= 0) _goodLighting = lightOk;
        }
      }
    });
  }

  void _startCountdown() {
    // Guard: never create a second timer if one is already running
    if (_countdownTimer != null) return;
    _countdown = 3;
    _state = AssessmentCameraState.countdown;
    debugPrint('[Calib] countdown timer created');
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown--;
        debugPrint('[Calib] tick → $_countdown');
        if (_countdown <= 0) {
          t.cancel();
          _countdownTimer = null;
          _beginCapture();
        }
      });
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdown = 3;
    _validStreak = 0;
    _invalidStreak = 0;
  }

  /// Lightweight check called every frame DURING countdown.
  /// Only cancels for catastrophic hard failures — athlete fully lost.
  /// Soft conditions (lighting, distance, centering) are completely ignored.
  void _checkCancelDuringCountdown(PoseSnapshot? snapshot) {
    final lm = snapshot?.landmarks ?? {};

    // Catastrophic: no pose at all, or both knees AND both hips gone
    final athleteLost = snapshot == null ||
        snapshot.confidence < 0.15 ||
        snapshot.landmarkCount < 3;

    final coreLost = !athleteLost &&
        !lm.containsKey('leftKnee') &&
        !lm.containsKey('rightKnee') &&
        !lm.containsKey('leftHip') &&
        !lm.containsKey('rightHip');

    final hardLost = athleteLost || coreLost;

    if (hardLost) {
      _invalidStreak++;
    } else {
      _invalidStreak = 0;
      _applySmoothing(snapshot);
    }

    debugPrint('[Countdown] hardLost=$hardLost invalidStreak=$_invalidStreak');

    final shouldCancel = _invalidStreak >= _cancelStreakRequired ||
        (athleteLost && _invalidStreak >= _seriousStreakRequired);

    if (shouldCancel) {
      debugPrint('[Countdown] CANCELLED — athlete lost for $_invalidStreak frames');
      setState(() {
        _state = AssessmentCameraState.setup;
        _cancelCountdown();
        _latestPose = snapshot;
        // Unfreeze checklist
        _poseDetected  = false;
        _kneesVisible  = false;
        _hipsVisible   = false;
        _ankleVisible  = false;
        _requiredPass  = false;
        _blockingReason = 'Step back into frame';
      });
    } else if (snapshot != null && mounted) {
      setState(() => _latestPose = snapshot);
    }
  }

  void _beginCapture() {
    _capturing = true;
    _state = AssessmentCameraState.capturing;
    _capturedFrames.clear();
    _validFrames = 0;
  }

  void _stopCapture() {
    setState(() {
      _capturing = false;
      _state = AssessmentCameraState.setup;
      _capturedFrames.clear();
      _validFrames = 0;
    });
  }

  // ── Smoothing ────────────────────────────────────────────────────────────

  void _applySmoothing(PoseSnapshot snapshot) {
    final raw = snapshot.landmarks;
    for (final key in raw.keys) {
      final curr = raw[key]!;
      final prev = _displayLandmarks[key];
      if (prev == null) {
        _displayLandmarks[key] = curr;
        continue;
      }
      final double alpha;
      if (_lowerBodyKeys.contains(key)) {
        // Adaptive: faster movement → more responsive (higher alpha = less lag)
        final velocity = (curr - prev).distance;
        // velocity in normalised space; typical squat motion ≈ 0.01–0.05/frame
        alpha = (_emaAlpha + velocity * 10.0).clamp(_emaAlpha, 0.62);
      } else {
        alpha = _emaAlphaUpper;
      }
      _displayLandmarks[key] = Offset(
        prev.dx * (1 - alpha) + curr.dx * alpha,
        prev.dy * (1 - alpha) + curr.dy * alpha,
      );
    }
    // Remove landmarks that disappeared
    _displayLandmarks.removeWhere((k, _) => !raw.containsKey(k));

    // Smooth bounding box
    final box = snapshot.bodyBox;
    if (box != null) {
      final prev = _displayBox;
      _displayBox = prev == null
          ? box
          : Rect.fromLTRB(
              prev.left * 0.7 + box.left * 0.3,
              prev.top * 0.7 + box.top * 0.3,
              prev.right * 0.7 + box.right * 0.3,
              prev.bottom * 0.7 + box.bottom * 0.3,
            );
    }
  }

  // ── Frame validation ─────────────────────────────────────────────────────

  /// Loose check used during frame recording — any hip + knee + ankle.
  bool _isLowerBodyValid(PoseSnapshot snapshot) {
    final lm = snapshot.landmarks;
    return (lm.containsKey('leftHip') || lm.containsKey('rightHip')) &&
        (lm.containsKey('leftKnee') || lm.containsKey('rightKnee')) &&
        (lm.containsKey('leftAnkle') || lm.containsKey('rightAnkle'));
  }

  /// Returns true when a knee angle is physiologically impossible (glitch frame).
  bool _hasImpossibleAngle(PoseSnapshot snapshot) {
    final lm = snapshot.landmarks;
    for (final side in [['leftHip', 'leftKnee', 'leftAnkle'],
                         ['rightHip', 'rightKnee', 'rightAnkle']]) {
      final h = lm[side[0]];
      final k = lm[side[1]];
      final a = lm[side[2]];
      if (h != null && k != null && a != null) {
        final angle = _calcAngle(h, k, a);
        if (angle < 25 || angle > 190) return true; // physiologically impossible
      }
    }
    return false;
  }

  bool _hasLandmarkSpike(PoseSnapshot current) {
    if (_prevPose == null) return false;

    // Tighter threshold: >12% of body height for knees/hips, >18% for ankles
    final bodyH = _prevPose!.bodyBox?.height ?? 0.3;
    final thresholdKnee = bodyH * 0.12;
    final thresholdAnkle = bodyH * 0.18;
    if (thresholdKnee <= 0) return false;

    final checks = {
      'leftKnee': thresholdKnee,
      'rightKnee': thresholdKnee,
      'leftHip': thresholdKnee,
      'rightHip': thresholdKnee,
      'leftAnkle': thresholdAnkle,
      'rightAnkle': thresholdAnkle,
    };
    for (final entry in checks.entries) {
      final curr = current.landmarks[entry.key];
      final prev = _prevPose!.landmarks[entry.key];
      if (curr != null && prev != null) {
        if ((curr - prev).distance > entry.value) return true;
      }
    }
    return false;
  }

  Future<void> _finishAssessment() async {
    if (_saving) return;
    if (_capturedFrames.length < 12) {
      setState(() {
        _capturing = false;
        _state = AssessmentCameraState.setup;
      });
      return;
    }

    setState(() {
      _saving = true;
      _capturing = false; // stop accumulating frames immediately
      _state = AssessmentCameraState.processing;
    });

    final result = PhysicalAssessmentService.analyzeSquat(
      widget.testType,
      widget.player.id,
      widget.player.name,
      _capturedFrames,
    );

    // Save to both storage services
    await AssessmentStorageService.instance.saveAssessment(result);

    // Also save to club service so it appears in player profile history
    final assessmentType = _testTypeToAssessmentType(widget.testType);
    await ClubService().addAssessment(PlayerAssessment(
      id: '',
      playerId: result.playerId,
      playerName: result.playerName,
      sessionId: '',
      sessionName: '',
      type: assessmentType,
      date: result.createdAt,
      movementQualityScore: result.movementQualityScore.toDouble(),
      stabilityScore: result.stabilityScore.toDouble(),
      symmetryScore: result.symmetryScore.toDouble(),
      controlScore: result.controlScore.toDouble(),
      overallScore: result.overallScore.toDouble(),
      assessmentQuality: result.qualityScore.toDouble(),
      detectedIssues: result.issues,
      recommendations: result.correctionTips,
    ));

    setState(() {
      _saving = false;
    });

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      '/physical-assessment/result',
      arguments: result,
    );
  }

  AssessmentType _testTypeToAssessmentType(AssessmentTestType testType) {
    switch (testType) {
      case AssessmentTestType.squat:
        return AssessmentType.squat;
      case AssessmentTestType.singleLegBalance:
        return AssessmentType.singleLegBalance;
      case AssessmentTestType.jumpLanding:
        return AssessmentType.jumpLanding;
      case AssessmentTestType.lunge:
        return AssessmentType.lunge;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).orientation == Orientation.portrait) {
      return _buildRotatePrompt();
    }

    if (!_cameraSelected) return _buildCameraSelector();

    final progress = (_validFrames / _targetFrameCount).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview (fills entire screen) ─────────────────────────
          if (_cameraReady)
            _cameraService.buildPreview()
          else
            const ColoredBox(color: Colors.black),

          // ── Skeleton overlay (matches preview bounds exactly) ─────────────
          if (_latestPose != null && _state != AssessmentCameraState.processing)
            CustomPaint(
              painter: _SquatSkeletonPainter(
                _latestPose!,
                _displayLandmarks.isNotEmpty
                    ? Map.unmodifiable(_displayLandmarks)
                    : _latestPose!.landmarks,
                rejectedFrames: _rejectedFrames,
                acceptedFrames: _acceptedFrames,
              ),
              size: Size.infinite,
            ),

          // ── Setup checklist HUD (top-left) ────────────────────────────────
          if (_state == AssessmentCameraState.setup)
            Positioned(
              top: 16,
              left: 16,
              child: _buildSetupHUD(),
            ),

          // ── Countdown overlay (centre screen) ─────────────────────────────
          if (_state == AssessmentCameraState.countdown)
            _buildCountdownOverlay(),

          // ── Processing spinner ────────────────────────────────────────────
          if (_state == AssessmentCameraState.processing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('Analysing movement…',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),

          // ── Back button (top-right) ───────────────────────────────────────
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),

          // ── Bottom HUD ────────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomHUD(progress),
          ),
        ],
      ),
    );
  }

  // ── Setup checklist HUD ───────────────────────────────────────────────────

  Widget _buildSetupHUD() {
    // Primary hint driven by first failing hard blocker
    final String hint;
    if (!_poseDetected) {
      hint = 'Step into frame — face the camera';
    } else if (!_hipsVisible) {
      hint = 'Move back — hips not detected';
    } else if (!_kneesVisible) {
      hint = 'Ensure knees are visible';
    } else if (!_ankleVisible) {
      hint = 'Move back until at least one foot is visible';
    } else if (_requiredPass) {
      hint = 'Hold still… starting soon';
    } else {
      hint = 'Adjust position';
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _requiredPass
              ? AppColors.primary.withOpacity(0.6)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Text(
                'SETUP',
                style: TextStyle(
                  color: _requiredPass ? AppColors.primary : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (_requiredPass)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'READY',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),

          // ── REQUIRED ──────────────────────────────────────────────────────
          const Text(
            'REQUIRED',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          _checkRow('Pose detected',   _poseDetected,  required: true),
          _checkRow('Hips visible',    _hipsVisible,   required: true),
          _checkRow('Knees visible',   _kneesVisible,  required: true),
          _checkRow('Foot detected',   _ankleVisible,  required: true),
          const SizedBox(height: 9),

          // ── RECOMMENDED ───────────────────────────────────────────────────
          const Text(
            'RECOMMENDED',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          _checkRow('Both knees visible',  _bothKneesVisible,  required: false),
          _checkRow('Both feet visible',   _bothAnklesVisible, required: false),
          _checkRow('Full body in frame',  _fullBodyVisible,   required: false),
          _checkRow('Athlete centered',    _athleteCentered,   required: false),
          _checkRow('Distance ok (2–3m)',  _distanceValid,     required: false),
          _checkRow('Good lighting',
              _goodLighting == true,
              required: false,
              pending: _goodLighting == null),
          const SizedBox(height: 9),

          // Hint
          Text(
            hint,
            style: TextStyle(
              color: _requiredPass ? Colors.white70 : Colors.white54,
              fontSize: 11,
              fontStyle: _requiredPass ? FontStyle.normal : FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _useFrontCamera
                ? 'Tip: bright room · contrasting clothing'
                : 'Tip: phone at hip height · 2–3 m away',
            style: const TextStyle(color: Colors.white24, fontSize: 9.5),
          ),

          // ── Debug strip ──────────────────────────────────────────────────
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            Container(height: 0.5, color: Colors.white12),
            const SizedBox(height: 6),
            Text(
              'req=$_requiredPass  warn=$_softWarningCount\n'
              'streak=$_validStreak  inv=$_invalidStreak\n'
              '${_blockingReason.isNotEmpty ? "block: $_blockingReason" : ""}',
              style: const TextStyle(
                color: Colors.yellow,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _checkRow(
    String label,
    bool pass, {
    required bool required,
    bool pending = false,
  }) {
    final IconData icon;
    final Color color;
    if (pending) {
      icon = Icons.circle_outlined;
      color = Colors.amber;
    } else if (pass) {
      icon = Icons.check_circle_rounded;
      color = required ? AppColors.primary : Colors.greenAccent.shade400;
    } else {
      icon = required ? Icons.cancel_rounded : Icons.warning_amber_rounded;
      color = required ? Colors.white30 : Colors.amber.withOpacity(0.65);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: pass ? Colors.white : Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }

  // ── Countdown overlay ─────────────────────────────────────────────────────

  Widget _buildCountdownOverlay() {
    return Container(
      color: Colors.black45,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_countdown',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 96,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Colors.black, blurRadius: 24)],
              ),
            ),
            const SizedBox(height: 8),
            const Text('Get ready…',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Bottom HUD ────────────────────────────────────────────────────────────

  Widget _buildBottomHUD(double progress) {
    final isCapturing = _state == AssessmentCameraState.capturing;
    final isProcessing = _state == AssessmentCameraState.processing;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isCapturing) ...[
            // Frame progress bar
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              minHeight: 4,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Perform one controlled squat',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      _buildLiveComparison(),
                    ],
                  ),
                ),
                Text(
                  '${_capturedFrames.length}/$_targetFrameCount',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 12, fontFamily: 'monospace'),
                ),
                TextButton.icon(
                  onPressed: _stopCapture,
                  icon: const Icon(Icons.stop_circle_outlined,
                      color: Colors.white54, size: 18),
                  label: const Text('Stop',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ],
            ),
          ] else if (!isProcessing) ...[
            _buildStatusBadge(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final String label;
    final Color color;

    switch (_state) {
      case AssessmentCameraState.setup:
        label = _cameraReady ? 'Waiting for athlete…' : 'Initialising camera…';
        color = Colors.white38;
      case AssessmentCameraState.ready:
        label = 'Ready';
        color = AppColors.primary;
      case AssessmentCameraState.countdown:
        label = 'Starting in $_countdown…';
        color = AppColors.primary;
      default:
        label = '';
        color = Colors.transparent;
    }

    if (label.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildCameraSelector() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'SELECT CAMERA',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Back camera provides higher\ntracking accuracy for squat assessment.',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    _cameraOptionButton(
                      label: 'Back Camera',
                      sublabel: 'Recommended — highest accuracy',
                      icon: Icons.camera_rear,
                      selected: true,
                      onTap: () => _selectCamera(false),
                    ),
                    const SizedBox(height: 12),
                    _cameraOptionButton(
                      label: 'Front Camera',
                      sublabel: 'Selfie mode — lower accuracy',
                      icon: Icons.camera_front,
                      selected: false,
                      onTap: () => _selectCamera(true),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Tips: place phone at hip/chest height\non a stable surface or tripod',
                      style: TextStyle(color: Colors.white30, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 8, right: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraOptionButton({
    required String label,
    required String sublabel,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.12)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary.withOpacity(0.6)
                : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppColors.primary : Colors.white54, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sublabel,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            if (selected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                ),
                child: const Text('RECOMMENDED',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotatePrompt() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.screen_rotation, color: Colors.white54, size: 64),
            const SizedBox(height: 20),
            const Text(
              'Rotate your phone to landscape',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Landscape mode is required for\naccurate squat assessment',
              style: TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveComparison() {
    final lm = _displayLandmarks;
    if (lm.isEmpty) return const SizedBox.shrink();

    // Knee angles from smoothed landmarks
    double? lAngle, rAngle;
    final lh = lm['leftHip'], lk = lm['leftKnee'], la = lm['leftAnkle'];
    if (lh != null && lk != null && la != null) lAngle = _calcAngle(lh, lk, la);
    final rh = lm['rightHip'], rk = lm['rightKnee'], ra = lm['rightAnkle'];
    if (rh != null && rk != null && ra != null) rAngle = _calcAngle(rh, rk, ra);

    final lStr = lAngle != null ? '${lAngle.round()}°' : '--';
    final rStr = rAngle != null ? '${rAngle.round()}°' : '--';

    // Phase label + colour
    final (phaseLabel, phaseColor) = switch (_squatPhase) {
      _SquatPhase.standing => ('STANDING', Colors.white54),
      _SquatPhase.descent  => ('▼ DESCENT', Colors.orangeAccent),
      _SquatPhase.bottom   => ('◆ BOTTOM',  AppColors.primary),
      _SquatPhase.ascent   => ('▲ ASCENT',  Colors.greenAccent),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(phaseLabel,
                style: TextStyle(
                    color: phaseColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(width: 12),
            Text('L: $lStr  R: $rStr',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 5),
        // Squat depth bar
        Row(
          children: [
            const Text('Depth ', style: TextStyle(color: Colors.white38, fontSize: 11)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _squatDepth,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(
                      Color.lerp(Colors.white54, AppColors.primary, _squatDepth)!),
                  minHeight: 5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('${(_squatDepth * 100).round()}%',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  void _updateSquatMetrics() {
    final lm = _displayLandmarks;
    final angles = <double>[];
    for (final side in [
      ['leftHip', 'leftKnee', 'leftAnkle'],
      ['rightHip', 'rightKnee', 'rightAnkle'],
    ]) {
      final h = lm[side[0]];
      final k = lm[side[1]];
      final a = lm[side[2]];
      if (h != null && k != null && a != null) angles.add(_calcAngle(h, k, a));
    }
    if (angles.isEmpty) return;

    final avg = angles.reduce((a, b) => a + b) / angles.length;
    final prev = _prevAvgKneeAngle;

    _SquatPhase phase;
    if (avg > 158) {
      phase = _SquatPhase.standing;
    } else if (avg < 95) {
      phase = _SquatPhase.bottom;
    } else if (prev != null && avg < prev - 1.5) {
      phase = _SquatPhase.descent;
    } else if (prev != null && avg > prev + 1.5) {
      phase = _SquatPhase.ascent;
    } else {
      phase = _squatPhase; // hold current
    }

    // Depth: 0 = standing (180°), 1 = deep squat (60°)
    final depth = ((180 - avg) / 120.0).clamp(0.0, 1.0);

    // Rep-completion detection
    if (avg < 130) _repDescended = true;
    if (avg < 100) _repBottomDone = true;
    if (_repBottomDone && avg > 158) {
      _framesAtReturn++;
      if (_framesAtReturn >= 4) {
        _repCount++;
        _repDescended  = false;
        _repBottomDone = false;
        _framesAtReturn = 0;
      }
    } else if (avg <= 158) {
      _framesAtReturn = 0;
    }

    _squatPhase = phase;
    _squatDepth = depth;
    _prevAvgKneeAngle = avg;
  }

  /// Interior angle at [joint] formed by vectors joint→[a] and joint→[b], in degrees.
  double _calcAngle(Offset a, Offset joint, Offset b) {
    final v1 = a - joint;
    final v2 = b - joint;
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final mag = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy) *
        math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy);
    if (mag < 0.0001) return 0;
    return math.acos((dot / mag).clamp(-1.0, 1.0)) * 180 / math.pi;
  }
}

class _SquatSkeletonPainter extends CustomPainter {
  const _SquatSkeletonPainter(
    this.pose,
    this.displayLandmarks, {
    this.rejectedFrames = 0,
    this.acceptedFrames = 0,
  });

  final PoseSnapshot pose;
  // Smoothed landmarks used for rendering (may differ from pose.landmarks).
  final Map<String, Offset> displayLandmarks;
  final int rejectedFrames;
  final int acceptedFrames;

  static const bool _debug = kDebugMode;

  Offset _toCanvas(Offset norm, Size canvas) =>
      Offset(norm.dx * canvas.width, norm.dy * canvas.height);

  // Returns opacity [0.3, 1.0] scaled by how many lower-body landmarks are present.
  double _lowerBodyOpacity() {
    const keys = ['leftHip', 'rightHip', 'leftKnee', 'rightKnee',
                   'leftAnkle', 'rightAnkle'];
    final count = keys.where(displayLandmarks.containsKey).length;
    if (count >= 5) return 1.0;
    if (count >= 3) return 0.55;
    return 0.25;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts =
        displayLandmarks.map((k, v) => MapEntry(k, _toCanvas(v, size)));

    final legOpacity = _lowerBodyOpacity();

    // ── Bones ─────────────────────────────────────────────────────────────
    final bonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5
      ..color = Colors.white.withOpacity(0.70);

    // Leg paint strength reflects confidence — hides bad frames naturally
    final legPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5
      ..color = AppColors.primary.withOpacity(legOpacity);

    void line(String a, String b, [Paint? paint]) {
      final pa = pts[a];
      final pb = pts[b];
      if (pa != null && pb != null) canvas.drawLine(pa, pb, paint ?? bonePaint);
    }

    // Torso
    line('leftShoulder', 'rightShoulder');
    line('leftHip', 'rightHip');
    line('leftShoulder', 'leftHip');
    line('rightShoulder', 'rightHip');
    // Arms
    line('leftShoulder', 'leftElbow');
    line('leftElbow', 'leftWrist');
    line('rightShoulder', 'rightElbow');
    line('rightElbow', 'rightWrist');
    // Legs — drawn only when opacity is meaningful
    if (legOpacity > 0.28) {
      line('leftHip', 'leftKnee', legPaint);
      line('leftKnee', 'leftAnkle', legPaint);
      line('rightHip', 'rightKnee', legPaint);
      line('rightKnee', 'rightAnkle', legPaint);
    }

    // ── Joints ────────────────────────────────────────────────────────────
    for (final entry in pts.entries) {
      final key = entry.key;
      final isKnee = key == 'leftKnee' || key == 'rightKnee';
      final isAnkle = key == 'leftAnkle' || key == 'rightAnkle';
      final isHip = key == 'leftHip' || key == 'rightHip';
      final isLower = isKnee || isAnkle || isHip;

      final radius = isKnee ? 10.0 : isAnkle ? 8.0 : isHip ? 7.0 : 5.0;
      final color = isKnee
          ? AppColors.primary.withOpacity(legOpacity)
          : isAnkle
              ? Colors.orangeAccent.withOpacity(legOpacity)
              : isHip
                  ? Colors.white.withOpacity(legOpacity)
                  : Colors.white.withOpacity(0.80);

      if (isLower && legOpacity <= 0.28) continue; // hide unstable lower joints

      canvas.drawCircle(entry.value, radius,
          Paint()..style = PaintingStyle.fill..color = color);
      // Ring outline for knees and ankles
      if (isKnee || isAnkle) {
        canvas.drawCircle(
          entry.value,
          radius + 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withOpacity(0.5),
        );
      }
    }

    // ── Knee angle labels (only when lower body is confident) ─────────────
    if (legOpacity >= 0.55) {
      _drawKneeAngle(canvas, pts, 'leftHip', 'leftKnee', 'leftAnkle', 'L');
      _drawKneeAngle(canvas, pts, 'rightHip', 'rightKnee', 'rightAnkle', 'R');
    }

    // ── Trunk lean ────────────────────────────────────────────────────────
    _drawTrunkLean(canvas, pts);

    // ── Debug overlay (kDebugMode only) ───────────────────────────────────
    if (_debug) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.yellow.withOpacity(0.4)
          ..strokeWidth = 2,
      );
      final bb = pose.bodyBox;
      if (bb != null) {
        canvas.drawRect(
          Rect.fromLTRB(bb.left * size.width, bb.top * size.height,
              bb.right * size.width, bb.bottom * size.height),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.cyanAccent.withOpacity(0.6)
            ..strokeWidth = 1.5,
        );
      }
      for (final p in pts.values) {
        canvas.drawCircle(
            p, 3.5, Paint()..color = Colors.greenAccent.withOpacity(0.7));
      }
      _paintLabel(
        canvas,
        const Offset(4, 4),
        'img:${pose.imageSize.width.round()}×${pose.imageSize.height.round()} '
        'lm:${pose.landmarkCount} '
        'ok:$acceptedFrames rej:$rejectedFrames '
        'legQ:${(legOpacity * 100).round()}%',
        fontSize: 11,
        bold: false,
        color: Colors.yellow,
      );
    }
  }

  void _drawKneeAngle(
    Canvas canvas,
    Map<String, Offset> pts,
    String hipKey,
    String kneeKey,
    String ankleKey,
    String side,
  ) {
    final hip = pts[hipKey];
    final knee = pts[kneeKey];
    final ankle = pts[ankleKey];
    if (hip == null || knee == null || ankle == null) return;

    final v1 = hip - knee;
    final v2 = ankle - knee;
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final mag = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy) *
        math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy);
    if (mag < 0.1) return;
    final angle = (math.acos((dot / mag).clamp(-1.0, 1.0)) * 180 / math.pi).round();

    _paintLabel(canvas, knee + const Offset(10, -10), '$side: $angle°',
        fontSize: 13, bold: true, color: AppColors.primary);
  }

  void _drawTrunkLean(Canvas canvas, Map<String, Offset> pts) {
    final ls = pts['leftShoulder'];
    final rs = pts['rightShoulder'];
    final lh = pts['leftHip'];
    final rh = pts['rightHip'];
    if (ls == null || rs == null || lh == null || rh == null) return;

    final shoulder = Offset((ls.dx + rs.dx) / 2, (ls.dy + rs.dy) / 2);
    final hip = Offset((lh.dx + rh.dx) / 2, (lh.dy + rh.dy) / 2);
    final spine = shoulder - hip;
    final mag = math.sqrt(spine.dx * spine.dx + spine.dy * spine.dy);
    if (mag < 1) return;
    // Angle from vertical (upward = Offset(0, -1))
    final cos = (-spine.dy / mag).clamp(-1.0, 1.0);
    final lean = (math.acos(cos) * 180 / math.pi).round();

    _paintLabel(canvas, shoulder + const Offset(6, -6), 'Trunk: $lean°',
        fontSize: 12, bold: false, color: Colors.white70);
  }

  void _paintLabel(
    Canvas canvas,
    Offset pos,
    String text, {
    required double fontSize,
    required bool bold,
    required Color color,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _SquatSkeletonPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.rejectedFrames != rejectedFrames ||
      oldDelegate.acceptedFrames != acceptedFrames;
}
