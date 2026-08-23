import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/assessment_result_model.dart';
import '../../models/player_profile_model.dart';
import '../../services/camera_service.dart';
import '../../services/physical_assessment_service.dart';
import '../../services/pose_assessment_config.dart';
import '../../services/pose_detection_service.dart';
import '../../services/pose_quality_gate.dart';
import '../../services/pose_smoothing_service.dart';
import '../../services/jump_state_machine.dart';
import '../../services/assessment_storage_service.dart';
import '../../services/assessment_video_service.dart';
import '../../services/exercise_engine.dart';
import '../../utils/app_logger.dart';
import '../../widgets/pose_debug_overlay.dart';
import 'assessment_result_page.dart';

enum AssessmentCameraState { setup, ready, countdown, capturing, processing }

/// Camera failure categories the UI must communicate distinctly (RB4):
/// permission denied, init failure, unsupported device, and a runtime
/// failure after the camera was already streaming.
enum _CameraFailureKind { permission, initFailed, unsupported, runtime }

enum _SquatPhase { standing, descent, bottom, ascent }

class AssessmentCameraArguments {
  const AssessmentCameraArguments({
    required this.player,
    required this.testType,
    this.sessionId,
    this.attemptGroupId,
    this.attemptNumber,
  });

  final PlayerProfile player;
  final AssessmentTestType testType;
  final String? sessionId;
  /// When retrying the same test, pass the previous attempt's group id so
  /// all captures can be compared as attempts of the same test-taking session.
  final String? attemptGroupId;
  final int? attemptNumber;
}

class AssessmentCameraPage extends StatefulWidget {
  const AssessmentCameraPage({
    super.key,
    required this.player,
    required this.testType,
    this.sessionId,
    this.onNextPlayer,
    this.attemptGroupId,
    this.attemptNumber,
  });

  final PlayerProfile player;
  final AssessmentTestType testType;
  final String? sessionId;
  final VoidCallback? onNextPlayer;
  final String? attemptGroupId;
  final int? attemptNumber;

  @override
  State<AssessmentCameraPage> createState() => _AssessmentCameraPageState();
}

class _AssessmentCameraPageState extends State<AssessmentCameraPage>
    with SingleTickerProviderStateMixin {
  final CameraService _cameraService = CameraService();
  final PoseDetectionService _poseService = PoseDetectionService();
  final AssessmentVideoService _videoService = AssessmentVideoService();
  final List<PoseSnapshot> _capturedFrames = [];
  StreamSubscription? _frameSubscription;

  // Real READY gate for jump tests — squat tests keep the legacy heuristics.
  final PoseQualityGate _qualityGate = PoseQualityGate();
  PoseGateResult? _lastGateResult;

  // One Euro smoothing for jump tests (mobile only) — squat/web keep the EMA.
  final PoseSmoothingService _smoothingService = PoseSmoothingService();

  // Overlay interpolation (jump tests only): lets the skeleton render at UI
  // frame rate even though inference only produces a new pose every ~30-50ms.
  final _SkeletonAnimator _skeletonAnimator = _SkeletonAnimator();
  Ticker? _skeletonTicker;

  AssessmentCameraState _state = AssessmentCameraState.setup;
  bool _prepGuideShown = false; // preparation guide shown first
  bool _cameraSelected = false; // camera picker shown until user picks
  bool _useFrontCamera = false; // back camera is default
  bool _cameraReady = false;
  _CameraFailureKind? _cameraFailure;
  bool _capturing = false;
  int _validFrames = 0;
  PoseSnapshot? _latestPose;
  PoseSnapshot? _prevPose;
  bool _saving = false;
  bool _disposed = false;
  bool _frameProcessing = false; // drop frames when pose detection is still running
  int _lastFrameMs = 0;          // timestamp of last processed frame (ms since epoch)
  static const int _frameThrottleMs = PoseAssessmentConfig.mobileFrameThrottleMs;

  // ── FPS / latency diagnostics (kDebugMode HUD) ──────────────────────────
  final List<int> _inferenceTimestamps = []; // rolling window, last 30
  double _inferenceFps = 0.0;
  int _lastInferenceLatencyMs = 0;
  final List<int> _uiTickTimestamps = []; // rolling window, last 30
  double _uiFps = 0.0;

  // Live squat metrics
  _SquatPhase _squatPhase = _SquatPhase.standing;
  double _squatDepth = 0.0; // 0 = standing, 1 = deep squat
  double? _prevAvgKneeAngle;
  // Rep-completion tracking
  bool _repBottomDone   = false;
  int  _framesAtReturn  = 0;

  // Live jump metrics (used for CMJ / SJ live display) — formal state machine
  // with hysteresis + a frozen baseline, replacing the old single-frame
  // heuristic that had no minimum durations and drifted its baseline.
  JumpStateMachine? _jumpStateMachine;
  double _jumpElevation = 0.0; // 0 = on ground, 1 = peak (derived from frozen baseline)

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

  // Thresholds — from PoseAssessmentConfig (no magic numbers here)
  static const int _cancelStreakRequired  = PoseAssessmentConfig.cancelStreakRequired;
  static const int _seriousStreakRequired = PoseAssessmentConfig.seriousStreakRequired;

  // Lower-body temporal smoothing — display only; scoring uses raw validated frames
  final Map<String, Offset> _displayLandmarks = {};
  Rect? _displayBox;
  int _rejectedFrames = 0;
  int _acceptedFrames = 0;

  static const int    _targetFrameCount    = PoseAssessmentConfig.targetFrameCount;
  static const double _brightnessThreshold = PoseAssessmentConfig.brightnessThreshold;

  static const double _emaAlpha      = PoseAssessmentConfig.emaAlphaLower;
  static const double _emaAlphaUpper = PoseAssessmentConfig.emaAlphaUpper;
  static const Set<String> _lowerBodyKeys = PoseAssessmentConfig.lowerBodyKeys;

  // Groups multiple captures of the same test-taking session together so a
  // best/average attempt can be computed. A fresh group starts unless the
  // caller explicitly passed one in (i.e. this is a retry of a prior attempt).
  late final String _attemptGroupId = widget.attemptGroupId ??
      '${widget.player.id}_${widget.testType.name}_${DateTime.now().millisecondsSinceEpoch}';
  late final int _attemptNumber = widget.attemptNumber ?? 1;

  @override
  void initState() {
    super.initState();
    _setLandscape();
    // Camera initialisation waits for user to pick front/back
    if (widget.testType.isJumpTest) {
      _skeletonTicker = createTicker(_onSkeletonTick)..start();
      _jumpStateMachine = JumpStateMachine(
        isSquatJump: widget.testType == AssessmentTestType.squatJump,
      );
    }
  }

  void _onSkeletonTick(Duration elapsed) {
    if (!mounted) return;
    _skeletonAnimator.tick();
    if (kDebugMode) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _uiTickTimestamps.add(nowMs);
      if (_uiTickTimestamps.length > 30) _uiTickTimestamps.removeAt(0);
      if (_uiTickTimestamps.length >= 2) {
        final spanMs = _uiTickTimestamps.last - _uiTickTimestamps.first;
        if (spanMs > 0) {
          _uiFps = (_uiTickTimestamps.length - 1) * 1000.0 / spanMs;
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _countdownTimer?.cancel();
    _frameSubscription?.cancel();
    // No-op if finish()/discard() already ran (e.g. after a successful capture).
    unawaited(_videoService.discard());
    _skeletonTicker?.dispose();
    _skeletonAnimator.dispose();
    _cameraService.dispose();
    _poseService.dispose();
    _restoreOrientation();
    super.dispose();
  }

  void _setLandscape() {
    if (kIsWeb) return; // SystemChrome has no effect on browsers.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreOrientation() {
    if (kIsWeb) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _selectCamera(bool front) {
    _qualityGate.reset();
    _smoothingService.reset();
    _skeletonAnimator.reset();
    _jumpStateMachine?.reset();
    setState(() {
      _useFrontCamera = front;
      _cameraSelected = true;
    });
    _initializeCamera(preferFront: front);
  }

  Future<void> _initializeCamera({bool preferFront = false}) async {
    setState(() => _cameraFailure = null);

    final granted = await _cameraService.requestPermission();
    if (!granted) {
      AppLogger.w('Camera', 'Permission request denied by user/OS');
      if (mounted) setState(() => _cameraFailure = _CameraFailureKind.permission);
      return;
    }

    try {
      await _cameraService.initialize(preferFront: preferFront);
      await _cameraService.startImageStream();
      _frameSubscription = _cameraService.frames.listen(
        _onFrameReceived,
        onError: (Object e, StackTrace st) {
          AppLogger.e('Camera', 'Frame stream error after camera was running', e);
          if (_disposed || !mounted) return;
          setState(() {
            _cameraReady = false;
            _cameraFailure = _CameraFailureKind.runtime;
          });
        },
      );
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      AppLogger.e('Camera', 'Camera initialization failed', e);
      if (!mounted) return;
      setState(() => _cameraFailure = _classifyCameraError(e));
    }
  }

  _CameraFailureKind _classifyCameraError(Object e) {
    final name = e.runtimeType.toString();
    if (name == 'CameraPermissionDeniedException') return _CameraFailureKind.permission;
    if (name == 'CameraUnsupportedException') return _CameraFailureKind.unsupported;
    return _CameraFailureKind.initFailed;
  }

  Future<void> _retryCameraInit() async {
    AppLogger.i('Camera', 'User requested retry after failure');
    _frameSubscription?.cancel();
    _frameSubscription = null;
    if (!mounted) return;
    setState(() {
      _cameraReady = false;
      _cameraFailure = null;
    });
    await _initializeCamera(preferFront: _useFrontCamera);
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

  /// Updates rolling inference FPS/latency stats used by the debug HUD.
  void _recordInferenceMetrics(int inferenceStartMs) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastInferenceLatencyMs = nowMs - inferenceStartMs;
    _inferenceTimestamps.add(nowMs);
    if (_inferenceTimestamps.length > 30) _inferenceTimestamps.removeAt(0);
    if (_inferenceTimestamps.length >= 2) {
      final spanMs = _inferenceTimestamps.last - _inferenceTimestamps.first;
      if (spanMs > 0) {
        _inferenceFps =
            (_inferenceTimestamps.length - 1) * 1000.0 / spanMs;
      }
    }
  }

  Future<void> _onFrameReceived(dynamic rawFrame) async {
    if (_disposed || !_cameraReady) return;
    if (rawFrame is! CameraFrame) return;
    // Drop frame if previous pose detection is still running — prevents
    // BLASTBufferQueue overflow ("Already acquired max frames").
    if (_frameProcessing) return;
    // Throttle: skip frame if processed one too recently (reduces BLASTBufferQueue pressure)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastFrameMs < _frameThrottleMs) return;
    _lastFrameMs = nowMs;
    _frameProcessing = true;
    try {
      // Always measure brightness so the calibration checklist reflects reality.
      final brightness = _computeFrameBrightness(rawFrame);

      final inferenceStartMs = DateTime.now().millisecondsSinceEpoch;
      final snapshot = await _poseService.detect(rawFrame);
      _recordInferenceMetrics(inferenceStartMs);

      // Guard: widget may have been disposed while pose detection was in flight.
      if (_disposed || !mounted) return;

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
      // Same PoseQualityGate definition for every test type, so ok:/rej:
      // counters, READY, and every debug surface (skeleton legQ,
      // PoseDebugOverlay) share one definition — squat tests no longer run a
      // separate, looser "legacy" check that let a too-far body through.
      final gateResult = _qualityGate.evaluate(snapshot, brightness);
      _lastGateResult = gateResult;
      final bool validFrame;
      if (widget.testType.isJumpTest) {
        validFrame = gateResult.frameValid;
      } else {
        // Squat tests additionally reject frame-to-frame landmark spikes and
        // anatomically impossible angles — signals PoseQualityGate doesn't
        // check but that JumpStateMachine handles separately for jump tests.
        validFrame = gateResult.frameValid &&
            lowerBodyOk &&
            noSpike &&
            noAngleGlitch;
      }

      // Only update smoothing on non-spiking frames to avoid contaminating EMA.
      // Squat phase (STANDING/BOTTOM/etc.) must never be derived from an
      // invalid frame — freeze the last known phase instead of transitioning
      // off a too-far/too-close/glitched reading.
      if (noSpike && lowerBodyOk && (widget.testType.isJumpTest || validFrame)) {
        _applySmoothing(snapshot);
        if (widget.testType.isJumpTest) {
          _updateJumpMetrics(snapshot, validFrame);
        } else {
          _updateSquatMetrics();
        }
      }

      if (_disposed || !mounted) return;
      setState(() {
        _latestPose = snapshot;
        if (validFrame) {
          _validFrames += 1;
          _capturedFrames.add(snapshot);
          _acceptedFrames += 1;
          _videoService.addFrame(rawFrame);
        } else {
          _rejectedFrames += 1;
        }
      });

      _prevPose = snapshot;

      if (_capturedFrames.length >= _targetFrameCount) {
        await _finishAssessment();
      }
    } finally {
      _frameProcessing = false;
    }
  }

  /// True when [key] clears the jump-test required-landmark likelihood floor.
  bool _hasLikelihood(Map<String, double> likelihoods, String key) =>
      (likelihoods[key] ?? 0) >= PoseAssessmentConfig.gateMinLandmarkLikelihood;

  void _updateCalibration(PoseSnapshot? snapshot, double brightness) {
    final likelihoods = snapshot?.likelihoods ?? {};

    // ── Single READY gate for every test type: 20-frame streak, rejection
    // ratio, per-landmark likelihood, body scale, edge margin — see
    // PoseQualityGate. Squat tests used to run a separate, looser "legacy"
    // check that let a too-far/cropped body through; now every test shares
    // the exact same pass/fail definition. ─────────────────────────────────
    final gateResult = _qualityGate.evaluate(snapshot, brightness);
    final bool poseOk    = snapshot != null && snapshot.landmarkCount > 0;
    final bool kneesOk   = _hasLikelihood(likelihoods, 'leftKnee') || _hasLikelihood(likelihoods, 'rightKnee');
    final bool hipsOk    = _hasLikelihood(likelihoods, 'leftHip')  || _hasLikelihood(likelihoods, 'rightHip');
    final bool ankleOk   = _hasLikelihood(likelihoods, 'leftAnkle') || _hasLikelihood(likelihoods, 'rightAnkle');
    final bool bothKnees = _hasLikelihood(likelihoods, 'leftKnee') && _hasLikelihood(likelihoods, 'rightKnee');
    final bool bothAnkles = _hasLikelihood(likelihoods, 'leftAnkle') && _hasLikelihood(likelihoods, 'rightAnkle');
    final bool fullBody  = gateResult.frameValid;
    final bool centered  = poseOk &&
        snapshot.center != null &&
        (snapshot.center!.dx - 0.5).abs() < 0.25;
    final h = snapshot?.bodyBox?.height ?? 0;
    final bool distOk    = poseOk &&
        h >= PoseAssessmentConfig.gateBodyHeightMin &&
        h <= PoseAssessmentConfig.gateBodyHeightMax;
    final bool? lightOk  = brightness >= 0 ? brightness >= _brightnessThreshold : null;
    final double lbConf  = gateResult.legQuality;
    final bool requiredOk = gateResult.frameValid;
    final bool seriousFailure = !poseOk;
    final String blocking = gateResult.failReason;
    final bool readyToStart = gateResult.isReady;

    _lastGateResult = gateResult;

    int softWarnings = 0;
    if (!bothKnees)        softWarnings++;
    if (!bothAnkles)       softWarnings++;
    if (!fullBody)         softWarnings++;
    if (!centered)         softWarnings++;
    if (!distOk)           softWarnings++;
    if (lightOk == false)  softWarnings++;

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

    AppLogger.i('Camera.calib',
      'req=$requiredOk valid=$_validStreak invalid=$_invalidStreak '
      'conf=${lbConf.toStringAsFixed(2)} state=$_state');

    if (_disposed || !mounted) return;
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
        // Header chip reflects true cumulative readiness (streak + rejection
        // ratio), not just this single frame — same gate for every test type.
        _requiredPass      = readyToStart;
        _softWarningCount  = softWarnings;
        _blockingReason    = blocking;
        if (brightness >= 0) _goodLighting = lightOk;
      }

      // ── State transitions (debounced) ──────────────────────────────────────
      if (_state == AssessmentCameraState.setup) {
        final shouldStart = readyToStart;
        if (shouldStart && _countdownTimer == null) {
          AppLogger.i('Camera.calib', 'COUNTDOWN START streak=$_validStreak ready=$readyToStart');
          _startCountdown();
        }
      } else if (_state == AssessmentCameraState.countdown) {
        // Only cancel on sustained HARD failures — soft misses are ignored
        final hardFail = !requiredOk;
        final sustainedHard  = hardFail && _invalidStreak >= _cancelStreakRequired;
        final seriousSustain = seriousFailure && _invalidStreak >= _seriousStreakRequired;

        if (sustainedHard || seriousSustain) {
          AppLogger.i('Camera.calib', 'CANCELLED invalid=$_invalidStreak serious=$seriousFailure');
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
          _requiredPass      = readyToStart;
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
    AppLogger.i('Camera.calib', 'Countdown timer created');
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown--;
        AppLogger.i('Camera.calib', 'tick=$_countdown');
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
    _qualityGate.reset();
    _smoothingService.reset();
    _skeletonAnimator.reset();
    _jumpStateMachine?.reset();
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

    AppLogger.i('Camera.countdown', 'hardLost=$hardLost invalidStreak=$_invalidStreak');

    final shouldCancel = _invalidStreak >= _cancelStreakRequired ||
        (athleteLost && _invalidStreak >= _seriousStreakRequired);

    if (shouldCancel) {
      AppLogger.w('Camera.countdown', 'CANCELLED — lost for $_invalidStreak frames');
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
    _qualityGate.reset();
    _smoothingService.reset();
    _skeletonAnimator.reset();
    _jumpStateMachine?.reset();
    // Fire-and-forget: a frame or two may be dropped by addFrame() while the
    // temp dir is being created, which is fine for a review-only sequence.
    unawaited(_videoService.start(
        '${widget.player.id}_${DateTime.now().millisecondsSinceEpoch}'));
  }

  void _stopCapture() {
    setState(() {
      _capturing = false;
      _state = AssessmentCameraState.setup;
      _capturedFrames.clear();
      _validFrames = 0;
    });
    unawaited(_videoService.discard());
    _qualityGate.reset();
    _smoothingService.reset();
    _skeletonAnimator.reset();
    _jumpStateMachine?.reset();
  }

  // ── Smoothing ────────────────────────────────────────────────────────────

  void _applySmoothing(PoseSnapshot snapshot) {
    // Jump tests on mobile use the One Euro filter (better jitter/lag
    // trade-off); squat tests and web keep the original adaptive EMA.
    if (!kIsWeb && widget.testType.isJumpTest) {
      final smoothed = _smoothingService.smooth(snapshot);
      _displayLandmarks
        ..clear()
        ..addAll(smoothed);
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
      _skeletonAnimator.push(smoothed, _displayBox, snapshot.timestampMs);
      return;
    }

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
      unawaited(_videoService.discard());
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
      playerHeightCm: widget.player.heightCm?.toDouble(),
    );

    // Session assessments stay separate from wellness, RPE and training load.
    final sessionAssessmentResult = result
        .copyWithSession(widget.sessionId)
        .copyWithAttempt(attemptGroupId: _attemptGroupId, attemptNumber: _attemptNumber);
    await AssessmentStorageService.instance.saveAssessment(sessionAssessmentResult);

    // Keep the review video only for a usable capture — an invalid attempt
    // gets retried anyway, so there's nothing for a coach to certify.
    String? videoFramesDir;
    if (sessionAssessmentResult.isValidAttempt) {
      videoFramesDir = await _videoService.finish();
    } else {
      unawaited(_videoService.discard());
    }

    if (_disposed || !mounted) return;
    // Stop camera stream before pushing result page — prevents BLASTBufferQueue
    // overflow from frames arriving while result page is rendering.
    _frameSubscription?.cancel();
    _frameSubscription = null;
    setState(() => _saving = false);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => AssessmentResultPage(
          result: sessionAssessmentResult,
          videoFramesDir: videoFramesDir,
          onNextPlayer: widget.onNextPlayer,
          onRetry: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AssessmentCameraPage(
                player: widget.player,
                testType: widget.testType,
                sessionId: widget.sessionId,
                onNextPlayer: widget.onNextPlayer,
                attemptGroupId: _attemptGroupId,
                attemptNumber: _attemptNumber + 1,
              ),
            ),
          ),
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Orientation lock only applies on native; SystemChrome has no effect on web.
    if (!kIsWeb &&
        MediaQuery.of(context).orientation == Orientation.portrait) {
      return _buildRotatePrompt();
    }

    if (_cameraFailure != null) return _buildCameraErrorScreen(_cameraFailure!);
    if (!_prepGuideShown) return _buildPrepGuide();
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
                animator: widget.testType.isJumpTest ? _skeletonAnimator : null,
                hideFacePoints: widget.testType.isJumpTest,
                medianLeftKneeAngle: _jumpStateMachine?.medianLeftKneeAngle,
                medianRightKneeAngle: _jumpStateMachine?.medianRightKneeAngle,
                debugState: kDebugMode ? _jumpStateMachine?.state.name : null,
                lowerBodyQualityOverride:
                    widget.testType.isJumpTest ? _lastGateResult?.legQuality : null,
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
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(AppLocalizations.get('assessment_processing'),
                        style: const TextStyle(color: Colors.white, fontSize: 16)),
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
            child: SafeArea(
              top: false,
              child: _buildBottomHUD(progress),
            ),
          ),

          // ── Debug overlay (kDebugMode only) ──────────────────────────────
          PoseDebugOverlay(
            enabled: true,
            snapshot: _latestPose,
            engineName:   kIsWeb ? PoseDetectionService.engineName   : 'ML Kit',
            engineStatus: kIsWeb ? PoseDetectionService.engineStatus : 'running',
            engineFps:    kIsWeb ? PoseDetectionService.engineFps    : null,
            engineError:  kIsWeb ? PoseDetectionService.lastError    : null,
            gateResult:   widget.testType.isJumpTest ? _lastGateResult : null,
          ),
        ],
      ),
    );
  }

  // ── Setup checklist HUD ───────────────────────────────────────────────────

  /// Compact per-landmark likelihood row for the required jump-test joints,
  /// e.g. "LH:82 RH:79 LK:91 RK:88 LA:70 RA:65 HE:40 FI:35". Never shows a
  /// single global confidence value as the sole quality signal.
  String _likelihoodRow() {
    final lm = _latestPose?.likelihoods ?? const {};
    String pct(String key) => ((lm[key] ?? 0) * 100).round().toString();
    return 'LH:${pct('leftHip')} RH:${pct('rightHip')} '
        'LK:${pct('leftKnee')} RK:${pct('rightKnee')} '
        'LA:${pct('leftAnkle')} RA:${pct('rightAnkle')} '
        'HE:${pct('leftHeel')}/${pct('rightHeel')} '
        'FI:${pct('leftFootIndex')}/${pct('rightFootIndex')}\n';
  }

  String _guidanceHint(PoseGateGuidance guidance) {
    switch (guidance) {
      case PoseGateGuidance.noBody:
        return AppLocalizations.get('guidance_no_body');
      case PoseGateGuidance.stepBack:
        return AppLocalizations.get('guidance_step_back');
      case PoseGateGuidance.stepCloser:
        return AppLocalizations.get('guidance_step_closer');
      case PoseGateGuidance.showFeet:
        return AppLocalizations.get('guidance_show_feet');
      case PoseGateGuidance.improveLighting:
        return AppLocalizations.get('guidance_improve_lighting');
      case PoseGateGuidance.holdPhoneSteady:
        return AppLocalizations.get('guidance_hold_phone_steady');
      case PoseGateGuidance.holdStill:
        return AppLocalizations.get('guidance_hold_still');
      case PoseGateGuidance.none:
        return AppLocalizations.get('calibration_ready_message');
    }
  }

  Widget _buildSetupHUD() {
    // Primary hint driven by first failing hard blocker
    final String hint;
    if (widget.testType.isJumpTest && _lastGateResult != null) {
      hint = _guidanceHint(_lastGateResult!.guidance);
    } else if (!_poseDetected) {
      hint = AppLocalizations.get('status_not_visible_hint');
    } else if (!_hipsVisible) {
      hint = AppLocalizations.get('calibration_full_body_hint');
    } else if (!_kneesVisible) {
      hint = AppLocalizations.get('calibration_full_body_hint');
    } else if (!_ankleVisible) {
      hint = AppLocalizations.get('calibration_distance_hint');
    } else if (_requiredPass) {
      hint = AppLocalizations.get('calibration_ready_message');
    } else {
      hint = AppLocalizations.get('calibration_setup_body');
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

          // ── Web: AI loading / low-FPS indicators ─────────────────────────
          if (kIsWeb) ...[
            const SizedBox(height: 8),
            Container(height: 0.5, color: Colors.white12),
            const SizedBox(height: 6),
            if (!_poseDetected)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 10, height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppColors.primary),
                  ),
                  SizedBox(width: 6),
                  Text('Initializing AI model…',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              )
            else if (PoseDetectionService.engineFps > 0 &&
                     PoseDetectionService.engineFps < PoseAssessmentConfig.lowFpsWarning)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.amber, size: 11),
                  const SizedBox(width: 4),
                  Text(
                    'Slow device — ${PoseDetectionService.engineFps.toStringAsFixed(0)} FPS',
                    style: const TextStyle(color: Colors.amber, fontSize: 10),
                  ),
                ],
              ),
            // ── Camera stream status (always visible on web) ───────────────
            const SizedBox(height: 6),
            _buildWebCameraStatus(),
          ],

          // ── Debug strip ──────────────────────────────────────────────────
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            Container(height: 0.5, color: Colors.white12),
            const SizedBox(height: 6),
            // Quality breakdown (Overall/Upper/Lower/Stable/Feet/Head/Scale)
            // lives in PoseDebugOverlay only — this strip covers what that
            // widget doesn't: FPS/latency, the setup streak, and (for jump
            // tests) the state machine + per-landmark likelihoods.
            Text(
              'req=$_requiredPass  warn=$_softWarningCount\n'
              'streak=$_validStreak  inv=$_invalidStreak\n'
              'infFPS=${_inferenceFps.toStringAsFixed(1)}  uiFPS=${_uiFps.toStringAsFixed(1)}  lat=${_lastInferenceLatencyMs}ms\n'
              '${widget.testType.isJumpTest ? "jumpState=${_jumpStateMachine?.state.name ?? '-'}\n" : ""}'
              '${widget.testType.isJumpTest ? _likelihoodRow() : ""}'
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
            Text(AppLocalizations.get('calibration_start_countdown'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Web camera stream status widget ──────────────────────────────────────

  Widget _buildWebCameraStatus() {
    if (!kIsWeb) return const SizedBox.shrink();
    final status = _cameraService.getVideoStatus();
    final found      = status['videoFound']   as bool?   ?? false;
    final trackState = status['trackState']   as String? ?? 'none';
    final paused     = status['paused']       as bool?   ?? true;
    final w          = status['videoWidth']   as int?    ?? 0;
    final h          = status['videoHeight']  as int?    ?? 0;

    final camLive   = found && trackState == 'live' && !paused;
    final modelReady = PoseDetectionService.isModelReady;

    Color _dot(bool ok) => ok ? Colors.greenAccent : Colors.redAccent;

    Widget _row(String label, bool ok, [String? detail]) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: _dot(ok), size: 7),
        const SizedBox(width: 5),
        Text(
          '$label${detail != null ? " ($detail)" : ""}',
          style: TextStyle(
            color: ok ? Colors.white54 : Colors.redAccent,
            fontSize: 9,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _row('Camera live',   camLive,    trackState),
        const SizedBox(height: 2),
        _row('Track live',    trackState == 'live'),
        const SizedBox(height: 2),
        _row('Video playing', !paused, w > 0 ? '${w}×$h' : null),
        const SizedBox(height: 2),
        _row('Model ready',   modelReady),
      ],
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
          // ── Web: body not visible warning during capture ─────────────────
          if (isCapturing && kIsWeb && !_fullBodyVisible) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Body not fully visible — step back\n'
                      'الجسم غير مرئي بالكامل — ابتعد قليلاً',
                      style: TextStyle(color: Colors.amber, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

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
                      Text(
                        widget.testType.isJumpTest
                            ? _jumpInstruction(widget.testType)
                            : 'Perform one controlled squat',
                        style: const TextStyle(
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
        if (!_cameraReady) {
          label = AppLocalizations.get('loading_camera');
        } else if (!_poseDetected) {
          label = AppLocalizations.get('calibrating_pose');
        } else {
          label = AppLocalizations.get('full_body_visible');
        }
        color = Colors.white38;
      case AssessmentCameraState.ready:
        label = AppLocalizations.get('status_ready_title');
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

  // ── Preparation Guide ─────────────────────────────────────────────────────

  String _testObjective() {
    return switch (widget.testType) {
      AssessmentTestType.squat              => AppLocalizations.get('assessment_squat_objective'),
      AssessmentTestType.countermovementJump => AppLocalizations.get('assessment_cmj_objective'),
      AssessmentTestType.squatJump          => AppLocalizations.get('assessment_cmj_objective'),
      AssessmentTestType.dropJump           => AppLocalizations.get('assessment_sldj_objective'),
      AssessmentTestType.singleLegDropJump  => AppLocalizations.get('assessment_sldj_objective'),
      AssessmentTestType.singleLegBalance   => AppLocalizations.get('assessment_slb_objective'),
      AssessmentTestType.jumpLanding        => AppLocalizations.get('assessment_jl_objective'),
    };
  }

  String _testInstructions() {
    return switch (widget.testType) {
      AssessmentTestType.squat              => AppLocalizations.get('assessment_squat_instructions'),
      AssessmentTestType.countermovementJump => AppLocalizations.get('assessment_cmj_instructions'),
      AssessmentTestType.squatJump          => AppLocalizations.get('assessment_cmj_instructions'),
      AssessmentTestType.dropJump           => AppLocalizations.get('assessment_sldj_instructions'),
      AssessmentTestType.singleLegDropJump  => AppLocalizations.get('assessment_sldj_instructions'),
      AssessmentTestType.singleLegBalance   => AppLocalizations.get('assessment_slb_instructions'),
      AssessmentTestType.jumpLanding        => AppLocalizations.get('assessment_jl_instructions'),
    };
  }

  String _testSafetyTip() {
    return switch (widget.testType) {
      AssessmentTestType.squat              => AppLocalizations.get('assessment_squat_safety'),
      AssessmentTestType.countermovementJump => AppLocalizations.get('assessment_cmj_safety'),
      AssessmentTestType.squatJump          => AppLocalizations.get('assessment_cmj_safety'),
      AssessmentTestType.dropJump           => AppLocalizations.get('assessment_sldj_safety'),
      AssessmentTestType.singleLegDropJump  => AppLocalizations.get('assessment_sldj_safety'),
      AssessmentTestType.singleLegBalance   => AppLocalizations.get('assessment_slb_safety'),
      AssessmentTestType.jumpLanding        => AppLocalizations.get('assessment_jl_safety'),
    };
  }

  bool get _isHighRiskTest =>
      widget.testType == AssessmentTestType.singleLegDropJump ||
      widget.testType == AssessmentTestType.dropJump;

  Future<void> _showSafetyDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.health_and_safety_rounded, color: Colors.amber, size: 22),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.get('safety_dialog_title'),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Text(
          AppLocalizations.get('safety_dialog_body'),
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.get('safety_no_pain'),
              style: const TextStyle(color: Color(0xff2DBF6C), fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.get('safety_has_pain'),
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == true) {
      // No pain: proceed to camera selector
      setState(() => _prepGuideShown = true);
    } else {
      // Has pain: show warning then let them choose
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xff1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.warning_rounded, color: Colors.red, size: 22),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.get('safety_screening_warning_title'),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: Text(
            AppLocalizations.get('safety_screening_warning_body'),
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                AppLocalizations.get('safety_go_back'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                AppLocalizations.get('safety_warning_proceed'),
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (proceed == true) {
        setState(() => _prepGuideShown = true);
      }
      // else: stay on prep guide
    }
  }

  Widget _buildPrepGuide() {
    final testName = widget.testType.displayName;
    final objective = _testObjective();
    final instructions = _testInstructions();
    final safetyTip = _testSafetyTip();
    final highRisk = _isHighRiskTest;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                          ),
                          child: Text(
                            AppLocalizations.get('prep_guide_title').toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (highRisk)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withOpacity(0.4)),
                            ),
                            child: Text(
                              AppLocalizations.get('high_intensity_label').toUpperCase(),
                              style: const TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      testName,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      objective,
                      style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 20),

                    // Camera setup checklist
                    _prepSection(
                      icon: Icons.videocam_rounded,
                      color: AppColors.primary,
                      title: AppLocalizations.get('calibration_guide_title'),
                      items: [
                        AppLocalizations.get('calibration_full_body_hint'),
                        AppLocalizations.get('calibration_distance_hint'),
                        AppLocalizations.get('calibration_lighting_hint'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Instructions
                    _prepSection(
                      icon: Icons.format_list_numbered_rounded,
                      color: Colors.amber,
                      title: AppLocalizations.get('instruction_label'),
                      body: instructions,
                    ),
                    const SizedBox(height: 16),

                    // Safety tip
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (highRisk ? Colors.red : Colors.amber).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (highRisk ? Colors.red : Colors.amber).withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_rounded,
                              color: highRisk ? Colors.red : Colors.amber, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              safetyTip,
                              style: TextStyle(
                                color: highRisk ? Colors.red.shade300 : Colors.amber.shade300,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    GestureDetector(
                      onTap: _showSafetyDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.get('prep_guide_btn'),
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 8, right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _prepSection({
    required IconData icon,
    required Color color,
    required String title,
    List<String>? items,
    String? body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (body != null)
            Text(body, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.6))
          else if (items != null)
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, color: color, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  ],
                ),
              ),
        ],
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
                    if (kIsWeb) ...[
                      const SizedBox(height: 16),
                      // ── Setup instructions (Arabic + English) ──────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'ضع الهاتف على مسافة 2–3 متر\n'
                          'اجعل الجسم كاملاً ظاهراً داخل الإطار\n'
                          'استخدم إضاءة جيدة\n'
                          'ثبّت الهاتف — لا تمسكه أثناء الاختبار\n\n'
                          'Place phone 2–3 m away · full body visible\n'
                          'Good lighting · keep phone stable',
                          style: TextStyle(color: Colors.white60, fontSize: 11.5),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // ── Browser recommendation ─────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.white24, size: 14),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Best results: Chrome on Android · Safari on iPhone · HTTPS required',
                                style: TextStyle(
                                    color: Colors.white30, fontSize: 10.5),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

  Widget _buildCameraErrorScreen(_CameraFailureKind kind) {
    final String titleKey;
    final String bodyKey;
    switch (kind) {
      case _CameraFailureKind.permission:
        titleKey = 'camera_error_permission_title';
        bodyKey = 'camera_error_permission_body';
        break;
      case _CameraFailureKind.unsupported:
        titleKey = 'camera_error_unsupported_title';
        bodyKey = 'camera_error_unsupported_body';
        break;
      case _CameraFailureKind.runtime:
        titleKey = 'camera_error_runtime_title';
        bodyKey = 'camera_error_runtime_body';
        break;
      case _CameraFailureKind.initFailed:
        titleKey = 'camera_error_init_title';
        bodyKey = 'camera_error_init_body';
        break;
    }

    // Retrying can't help when there's simply no camera hardware.
    final canRetry = kind != _CameraFailureKind.unsupported;
    // Settings only make sense for a permission denial, and only on
    // platforms where permission_handler can deep-link into OS settings.
    final canOpenSettings = kind == _CameraFailureKind.permission && !kIsWeb;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, color: Colors.red, size: 64),
                const SizedBox(height: 20),
                Text(
                  AppLocalizations.get(titleKey),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.get(bodyKey),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                if (canRetry)
                  ElevatedButton.icon(
                    onPressed: _retryCameraInit,
                    icon: const Icon(Icons.refresh),
                    label: Text(AppLocalizations.get('camera_error_retry')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                    ),
                  ),
                if (canOpenSettings) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => openAppSettings(),
                    icon: const Icon(Icons.settings, color: Colors.white70),
                    label: Text(
                      AppLocalizations.get('camera_error_open_settings'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white54),
                  label: Text(
                    AppLocalizations.get('camera_error_go_back'),
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
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

  Widget _buildJumpLiveDisplay() {
    final state = _jumpStateMachine?.state ?? JumpState.searchingBody;
    final (label, color, icon) = switch (state) {
      JumpState.searchingBody => ('READY',      Colors.white54,        '◎'),
      JumpState.positioning   => ('READY',      Colors.white54,        '◎'),
      JumpState.stabilizing   => ('READY',      Colors.white54,        '◎'),
      JumpState.ready         => ('READY',      Colors.white54,        '◎'),
      JumpState.squatHold     => ('▼ CROUCH',   Colors.orangeAccent,   '▼'),
      JumpState.takeoff       => ('↑ JUMP!',    AppColors.primary,     '↑'),
      JumpState.airborne      => ('◆ AIRBORNE', Colors.lightBlueAccent,'◆'),
      JumpState.landing       => ('▽ LAND',     Colors.amberAccent,    '▽'),
      JumpState.completed     => ('✓ STABLE',   Colors.greenAccent,    '✓'),
      JumpState.invalid       => ('⚠ LOST',     Colors.redAccent,      '⚠'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$icon $label',
            style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
        const SizedBox(height: 5),
        Row(
          children: [
            const Text('Elevation ', style: TextStyle(color: Colors.white38, fontSize: 11)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _jumpElevation,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(
                      Color.lerp(Colors.white54, Colors.lightBlueAccent, _jumpElevation)!),
                  minHeight: 5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('${(_jumpElevation * 100).round()}%',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveComparison() {
    if (widget.testType.isJumpTest) return _buildJumpLiveDisplay();
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
            Flexible(
              child: Text(phaseLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: phaseColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text('L: $lStr  R: $rStr',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
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

  String _jumpInstruction(AssessmentTestType type) {
    switch (type) {
      case AssessmentTestType.countermovementJump:
        return 'Dip down then jump as high as possible';
      case AssessmentTestType.squatJump:
        return 'Hold squat → jump explosively from static position';
      case AssessmentTestType.dropJump:
        return 'Step off box → land and immediately rebound';
      case AssessmentTestType.singleLegDropJump:
        return 'Single-leg landing → hold balance';
      default:
        return 'Perform the jump test';
    }
  }

  void _updateJumpMetrics(PoseSnapshot snapshot, bool frameValid) {
    final machine = _jumpStateMachine;
    if (machine == null) return;

    final lm = snapshot.landmarks;
    final lh = lm['leftHip'], rh = lm['rightHip'];
    final la = lm['leftAnkle'], ra = lm['rightAnkle'];
    final hipY = (lh != null && rh != null)
        ? (lh.dy + rh.dy) / 2
        : (lh ?? rh)?.dy;

    double? leftKneeAngle, rightKneeAngle;
    final lk = lm['leftKnee'];
    if (lh != null && lk != null && la != null) leftKneeAngle = _calcAngle(lh, lk, la);
    final rk = lm['rightKnee'];
    if (rh != null && rk != null && ra != null) rightKneeAngle = _calcAngle(rh, rk, ra);

    final tsMs = snapshot.timestampMs > 0
        ? snapshot.timestampMs
        : DateTime.now().millisecondsSinceEpoch;

    machine.update(
      frameValid: frameValid,
      hipY: hipY,
      leftAnkleY: la?.dy,
      rightAnkleY: ra?.dy,
      leftKneeAngle: leftKneeAngle,
      rightKneeAngle: rightKneeAngle,
      tsMs: tsMs,
    );

    // Live elevation display: only meaningful once the baseline is frozen.
    final baseline = machine.baselineHipY;
    final leg = machine.legLength;
    if (baseline != null && leg != null && leg > 0 && hipY != null) {
      _jumpElevation = ((baseline - hipY) / leg).clamp(0.0, 1.0);
    }
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
    if (avg < 100) _repBottomDone = true;
    if (_repBottomDone && avg > 158) {
      _framesAtReturn++;
      if (_framesAtReturn >= 4) {
        _repBottomDone  = false;
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

/// Holds the last two smoothed poses and lerps between them so the skeleton
/// overlay can be repainted at UI frame rate (via a [Ticker]) even though
/// inference only produces a new pose every ~30-50ms. Jump tests only.
class _SkeletonAnimator extends ChangeNotifier {
  Map<String, Offset> _prevPoints = const {};
  int _prevTsMs = 0;
  Map<String, Offset> _latestPoints = const {};
  int _latestTsMs = 0;
  Rect? _prevBox;
  Rect? _latestBox;

  void push(Map<String, Offset> points, Rect? box, int tsMs) {
    final effectiveTsMs = tsMs > 0 ? tsMs : DateTime.now().millisecondsSinceEpoch;
    if (_latestTsMs == 0) {
      // First frame: seed both prev and latest so there's nothing to lerp from.
      _prevPoints = points;
      _prevTsMs = effectiveTsMs;
      _prevBox = box;
    } else {
      _prevPoints = _latestPoints;
      _prevTsMs = _latestTsMs;
      _prevBox = _latestBox;
    }
    _latestPoints = points;
    _latestTsMs = effectiveTsMs;
    _latestBox = box;
  }

  void tick() => notifyListeners();

  void reset() {
    _prevPoints = const {};
    _prevTsMs = 0;
    _latestPoints = const {};
    _latestTsMs = 0;
    _prevBox = null;
    _latestBox = null;
  }

  Map<String, Offset> interpolated(int nowMs) {
    if (_latestPoints.isEmpty) return _latestPoints;
    if (_latestTsMs <= _prevTsMs) return _latestPoints;
    final t = ((nowMs - _prevTsMs) / (_latestTsMs - _prevTsMs)).clamp(0.0, 1.0);
    final result = <String, Offset>{};
    for (final entry in _latestPoints.entries) {
      final prev = _prevPoints[entry.key];
      result[entry.key] = prev != null ? Offset.lerp(prev, entry.value, t)! : entry.value;
    }
    return result;
  }

  Rect? interpolatedBox(int nowMs) {
    if (_latestBox == null) return null;
    if (_prevBox == null || _latestTsMs <= _prevTsMs) return _latestBox;
    final t = ((nowMs - _prevTsMs) / (_latestTsMs - _prevTsMs)).clamp(0.0, 1.0);
    return Rect.lerp(_prevBox, _latestBox, t);
  }
}

// Face/hand landmarks hidden from the overlay during jump tests to reduce
// visual clutter — only the joints relevant to jump biomechanics matter.
const _faceHandKeys = {
  'nose', 'leftEyeInner', 'leftEye', 'leftEyeOuter',
  'rightEyeInner', 'rightEye', 'rightEyeOuter',
  'leftEar', 'rightEar', 'mouthLeft', 'mouthRight',
  'leftPinky', 'rightPinky', 'leftIndex', 'rightIndex',
  'leftThumb', 'rightThumb',
};

class _SquatSkeletonPainter extends CustomPainter {
  _SquatSkeletonPainter(
    this.pose,
    this.displayLandmarks, {
    this.rejectedFrames = 0,
    this.acceptedFrames = 0,
    this.animator,
    this.hideFacePoints = false,
    this.medianLeftKneeAngle,
    this.medianRightKneeAngle,
    this.debugState,
    this.lowerBodyQualityOverride,
  }) : super(repaint: animator);

  final PoseSnapshot pose;
  // Smoothed landmarks used for rendering (may differ from pose.landmarks).
  final Map<String, Offset> displayLandmarks;
  final int rejectedFrames;
  final int acceptedFrames;
  // When set (jump tests), paint() pulls interpolated points from the
  // animator each tick instead of the static displayLandmarks snapshot.
  final _SkeletonAnimator? animator;
  final bool hideFacePoints;
  // Jump tests: median-of-5 knee angles from JumpStateMachine, used for the
  // on-screen L:/R: labels instead of a single noisy frame's raw angle
  // (fixes glitch readings like "L: 9° R: 77°").
  final double? medianLeftKneeAngle;
  final double? medianRightKneeAngle;
  // Jump-test state machine state name, shown in the kDebugMode label.
  final String? debugState;
  // Jump tests: PoseQualityGate.lowerBodyQuality (0..1) — the SAME number
  // shown as "Lower Body: X%" in PoseDebugOverlay. Replaces the old
  // landmark-COUNT heuristic, which could read legQ:100% while the feet
  // were barely visible (present in the map at low likelihood is enough to
  // count, but not enough to actually trust).
  final double? lowerBodyQualityOverride;

  static const bool _debug = kDebugMode;

  Offset _toCanvas(Offset norm, Size canvas) =>
      Offset(norm.dx * canvas.width, norm.dy * canvas.height);

  // Fallback for squat tests / web (no gate quality available): opacity
  // scaled by how many lower-body landmarks are present.
  double _lowerBodyOpacity(Map<String, Offset> points) {
    const keys = ['leftHip', 'rightHip', 'leftKnee', 'rightKnee',
                   'leftAnkle', 'rightAnkle'];
    final count = keys.where(points.containsKey).length;
    if (count >= 5) return 1.0;
    if (count >= 3) return 0.55;
    return 0.25;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final sourcePoints = animator != null
        ? animator!.interpolated(nowMs)
        : displayLandmarks;
    final points = hideFacePoints
        ? (Map.of(sourcePoints)..removeWhere((k, _) => _faceHandKeys.contains(k)))
        : sourcePoints;
    final pts = points.map((k, v) => MapEntry(k, _toCanvas(v, size)));

    final legOpacity = lowerBodyQualityOverride ?? _lowerBodyOpacity(points);

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
      if (medianLeftKneeAngle != null || medianRightKneeAngle != null) {
        // Jump tests: use the state machine's median-of-5 angle, not a
        // single noisy frame's raw angle.
        _drawKneeAngleValue(canvas, pts['leftKnee'], medianLeftKneeAngle, 'L');
        _drawKneeAngleValue(canvas, pts['rightKnee'], medianRightKneeAngle, 'R');
      } else {
        _drawKneeAngle(canvas, pts, 'leftHip', 'leftKnee', 'leftAnkle', 'L');
        _drawKneeAngle(canvas, pts, 'rightHip', 'rightKnee', 'rightAnkle', 'R');
      }
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
        'legQ:${(legOpacity * 100).round()}%'
        '${debugState != null ? '\nstate:$debugState' : ''}',
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

  void _drawKneeAngleValue(Canvas canvas, Offset? knee, double? angle, String side) {
    if (knee == null || angle == null) return;
    _paintLabel(canvas, knee + const Offset(10, -10), '$side: ${angle.round()}°',
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
