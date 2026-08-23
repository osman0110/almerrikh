import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'camera_service.dart';
import 'exercise_engine.dart';
import 'pose_assessment_config.dart';

// ── JS interop ───────────────────────────────────────────────────────────────
//
// Maps to window.NextKickPoseWeb exposed by nextkick_pose_web.js.
// Only compiled on web (this file is never imported by native builds).

@JS('NextKickPoseWeb')
external _NKPoseWebApi? get _nkPoseWebOrNull;

extension type _NKPoseWebApi._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> initialize(JSObject config);
  external void start();
  external void stop();
  external void dispose();
  external JSString  get status;
  external JSString? get lastError;
  external double    get fps;
  external JSFloat32Array? getLatestLandmarks();
  // Setup / preload API
  external JSPromise<JSAny?> preload(JSAny? config);
  external double     getProgress();
  external JSBoolean  isReady();
  external JSString   getStatus();
  external JSObject   checkBrowserSupport();
  external JSPromise<JSAny?> testCameraAccess();
  external JSPromise<JSString?> getCameraPermissionState();
  external JSPromise<JSAny?>  verifyAssets();
}

// ── Preload / setup result types ─────────────────────────────────────────────

class PosePreloadResult {
  const PosePreloadResult({required this.success, this.error});
  final bool    success;
  final String? error;
}

class BrowserSupportResult {
  const BrowserSupportResult({
    required this.supported,
    this.isSecureContext = true,
    this.hasMediaDevices = true,
    this.hasWebAssembly  = true,
    this.reason,
  });
  final bool    supported;
  final bool    isSecureContext;
  final bool    hasMediaDevices;
  final bool    hasWebAssembly;
  final String? reason;
}

class CameraTestResult {
  const CameraTestResult({required this.ok, this.error, this.state});
  final bool    ok;
  final String? error;
  final String? state; // 'granted' | 'denied' | 'prompt'
}

class AssetVerifyResult {
  const AssetVerifyResult({required this.ok, this.missing = const []});
  final bool         ok;
  final List<String> missing;
}

// ── MediaPipe 33-point landmark names (index matches model output) ────────────

const List<String> _lmNames = [
  'nose',          // 0
  'leftEyeInner',  // 1
  'leftEye',       // 2
  'leftEyeOuter',  // 3
  'rightEyeInner', // 4
  'rightEye',      // 5
  'rightEyeOuter', // 6
  'leftEar',       // 7
  'rightEar',      // 8
  'mouthLeft',     // 9
  'mouthRight',    // 10
  'leftShoulder',  // 11
  'rightShoulder', // 12
  'leftElbow',     // 13
  'rightElbow',    // 14
  'leftWrist',     // 15
  'rightWrist',    // 16
  'leftPinky',     // 17
  'rightPinky',    // 18
  'leftIndex',     // 19
  'rightIndex',    // 20
  'leftThumb',     // 21
  'rightThumb',    // 22
  'leftHip',       // 23
  'rightHip',      // 24
  'leftKnee',      // 25
  'rightKnee',     // 26
  'leftAnkle',     // 27
  'rightAnkle',    // 28
  'leftHeel',      // 29
  'rightHeel',     // 30
  'leftFootIndex', // 31
  'rightFootIndex',// 32
];

// ── Service ───────────────────────────────────────────────────────────────────

class PoseDetectionService {
  // Statics allow single-session JS initialization across page navigations.
  static bool _initStarted = false;
  static bool _initialized = false;
  static bool _running     = false;

  // ── Diagnostics (exposed to debug overlay) ──────────────────────────────
  static String get engineStatus  => _nkPoseWebOrNull?.getStatus().toDart ?? 'unavailable';
  static double get engineFps     => _nkPoseWebOrNull?.fps ?? 0.0;
  static String get engineName    => 'MediaPipe Web';
  static String? get lastError    => _nkPoseWebOrNull?.lastError?.toDart;

  // ── Preload / setup API (used by WebPoseSetupScreen) ─────────────────────

  /// True when JS model is loaded and ready to run inference.
  static bool get isModelReady {
    final api = _nkPoseWebOrNull;
    return api != null && api.isReady().toDart;
  }

  /// JS-side load progress 0–100.
  static double get modelLoadProgress => _nkPoseWebOrNull?.getProgress() ?? 0.0;

  /// Preload the pose model without starting camera or RAF loop.
  /// Resolves when model is ready (or fails with error).
  static Future<PosePreloadResult> preloadModel() async {
    final api = _nkPoseWebOrNull;
    if (api == null) {
      return const PosePreloadResult(success: false, error: 'JS module unavailable');
    }
    try {
      final jsResult = await api.preload(null).toDart
          .timeout(const Duration(seconds: 90));
      final map = jsResult?.dartify();
      if (map is! Map) {
        return const PosePreloadResult(success: false, error: 'Unexpected result');
      }
      final success = map['success'] as bool? ?? false;
      final error   = map['error']   as String?;
      if (success) {
        // Mark Dart service initialized so camera page skips redundant init.
        _initStarted = true;
        _initialized = true;
        _running     = false;
      }
      return PosePreloadResult(success: success, error: error);
    } on TimeoutException {
      return const PosePreloadResult(success: false, error: 'timeout');
    } catch (e) {
      return PosePreloadResult(success: false, error: e.toString());
    }
  }

  /// Synchronous browser capability check — no permissions requested.
  static BrowserSupportResult checkBrowserSupport() {
    final api = _nkPoseWebOrNull;
    if (api == null) {
      return const BrowserSupportResult(supported: false, reason: 'JS unavailable');
    }
    try {
      final raw = api.checkBrowserSupport().dartify();
      if (raw is! Map) return const BrowserSupportResult(supported: false);
      return BrowserSupportResult(
        supported:       raw['supported']       as bool? ?? false,
        isSecureContext: raw['isSecureContext']  as bool? ?? true,
        hasMediaDevices: raw['hasMediaDevices']  as bool? ?? true,
        hasWebAssembly:  raw['hasWebAssembly']   as bool? ?? true,
      );
    } catch (_) {
      return const BrowserSupportResult(supported: false);
    }
  }

  /// HEAD-check local MediaPipe asset files.
  static Future<AssetVerifyResult> verifyAssets() async {
    final api = _nkPoseWebOrNull;
    if (api == null) return const AssetVerifyResult(ok: true); // skip silently
    try {
      final jsResult = await api.verifyAssets().toDart
          .timeout(const Duration(seconds: 10));
      final raw = jsResult?.dartify();
      if (raw is! Map) return const AssetVerifyResult(ok: true);
      final ok      = raw['ok']      as bool?   ?? true;
      final missing = (raw['missing'] as List?)?.map((e) => e.toString()).toList() ?? [];
      return AssetVerifyResult(ok: ok, missing: missing);
    } catch (_) {
      return const AssetVerifyResult(ok: true); // fail silently — model load will catch it
    }
  }

  /// Test camera access (MUST be called from a user gesture).
  static Future<CameraTestResult> testCameraAccess() async {
    final api = _nkPoseWebOrNull;
    if (api == null) return const CameraTestResult(ok: false, error: 'JS unavailable');
    try {
      final jsResult = await api.testCameraAccess().toDart
          .timeout(const Duration(seconds: 15));
      final raw = jsResult?.dartify();
      if (raw is! Map) return const CameraTestResult(ok: false);
      final ok    = raw['ok']    as bool?   ?? false;
      final error = raw['error'] as String?;
      final state = raw['state'] as String?;
      return CameraTestResult(ok: ok, error: error, state: state);
    } on TimeoutException {
      return const CameraTestResult(ok: false, error: 'timeout');
    } catch (e) {
      return CameraTestResult(ok: false, error: e.toString());
    }
  }

  /// Query camera permission state without requesting (uses Permissions API).
  static Future<String> getCameraPermissionState() async {
    final api = _nkPoseWebOrNull;
    if (api == null) return 'unknown';
    try {
      final result = await api.getCameraPermissionState().toDart
          .timeout(const Duration(seconds: 3));
      return result?.toDart ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  // ── Core interface ────────────────────────────────────────────────────────

  Future<PoseSnapshot?> detect(CameraFrame frame) async {
    // Lazily start initialization on first detect() call.
    if (!_initStarted) _startInit();

    // Not ready yet → return null; caller retries next tick.
    if (!_initialized) return null;

    // Resume after dispose().
    if (!_running) {
      _nkPoseWebOrNull?.start();
      _running = true;
    }

    final jsArr = _nkPoseWebOrNull?.getLatestLandmarks();
    if (jsArr == null) return _emptySnapshot(frame);

    final Float32List data = jsArr.toDart;
    if (data.length < _lmNames.length * 4) return _emptySnapshot(frame);

    return _snapshotFromBuffer(data, frame.width, frame.height);
  }

  Future<void> dispose() async {
    if (_initialized && _running) {
      _nkPoseWebOrNull?.stop();
      _running = false;
    }
  }

  // ── Initialization ────────────────────────────────────────────────────────

  static void _startInit() {
    _initStarted = true;
    _doInit();
  }

  static Future<void> _doInit() async {
    try {
      final api = _nkPoseWebOrNull;
      if (api == null) {
        // JS module not yet loaded — retry on next detect() call.
        _initStarted = false;
        return;
      }

      final config = {
        'videoElementId': 'nk-pose-video',
      }.jsify()! as JSObject;

      await api.initialize(config).toDart;

      final status = api.getStatus().toDart;
      if (status == 'ready' || status == 'running') {
        api.start();
        _initialized = true;
        _running     = true;
      } else {
        // Initialization failed (HTTPS error, model load failed, etc.)
        // Allow retry by resetting flag.
        _initStarted = false;
      }
    } catch (_) {
      _initStarted = false; // Allow retry.
    }
  }

  // ── PoseSnapshot construction ─────────────────────────────────────────────

  static PoseSnapshot _emptySnapshot(CameraFrame frame) => PoseSnapshot(
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
        imageSize: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: 0,
        landmarks: const {},
        tooClose: false,
        tooFar: false,
        lowLight: false,
      );

  PoseSnapshot _snapshotFromBuffer(Float32List data, int w, int h) {
    final Map<String, Offset> landmarks = {};
    double sumVis = 0;

    for (var i = 0; i < _lmNames.length; i++) {
      final base = i * 4;
      final vis = data[base + 3];
      sumVis += vis;
      if (vis < PoseAssessmentConfig.minLandmarkVisibility) continue;
      final x = data[base].clamp(0.0, 1.0);
      final y = data[base + 1].clamp(0.0, 1.0);
      landmarks[_lmNames[i]] = Offset(x, y);
    }

    if (landmarks.isEmpty) return _emptySnapshot(CameraFrame(image: null, width: w, height: h, rotation: 0));

    // Bounding box
    final xs = landmarks.values.map((p) => p.dx).toList();
    final ys = landmarks.values.map((p) => p.dy).toList();
    final bodyBox = Rect.fromLTRB(
      xs.reduce(math.min), ys.reduce(math.min),
      xs.reduce(math.max), ys.reduce(math.max),
    );

    bool has(String k) => landmarks.containsKey(k);

    final headVisible      = has('nose') || has('leftEye') || has('rightEye');
    final shouldersVisible = has('leftShoulder') && has('rightShoulder');
    final hipsVisible      = has('leftHip') && has('rightHip');
    final kneesVisible     = has('leftKnee') || has('rightKnee');
    final anklesVisible    = has('leftAnkle') || has('rightAnkle');
    final lowerBodyVisible = kneesVisible || anklesVisible;

    final guide    = ExerciseEngine.guideFrame;
    final overlap  = bodyBox.intersect(guide);
    final bodyArea = bodyBox.width * bodyBox.height;
    final insideGuide = !overlap.isEmpty &&
        bodyArea > 0 &&
        (overlap.width * overlap.height) / bodyArea >= PoseAssessmentConfig.insideGuideRatio;

    final confidence    = sumVis / _lmNames.length;
    final detectionScore = (headVisible ? 1 : 0) +
        (shouldersVisible ? 2 : 0) +
        (hipsVisible      ? 2 : 0) +
        (lowerBodyVisible ? 2 : 0);

    final tooClose = bodyBox.height > PoseAssessmentConfig.tooCloseBoundH ||
                bodyBox.width  > PoseAssessmentConfig.tooCloseBoundW;
    final tooFar   = bodyBox.height < PoseAssessmentConfig.tooFarBoundH;

    // A body that's too far/close to measure reliably is never "fully
    // visible" — otherwise a tiny, distant silhouette can still pass this
    // check purely on landmark presence and feed garbage angles downstream.
    final full = headVisible && shouldersVisible && hipsVisible &&
        lowerBodyVisible && insideGuide && !tooClose && !tooFar &&
        confidence >= PoseAssessmentConfig.minLandmarkVisibility;

    return PoseSnapshot(
      bodyBox:         bodyBox,
      center:          bodyBox.center,
      leftWrist:       landmarks['leftWrist'],
      rightWrist:      landmarks['rightWrist'],
      leftAnkle:       landmarks['leftAnkle'],
      rightAnkle:      landmarks['rightAnkle'],
      bodyFullyVisible: full,
      headVisible:     headVisible,
      shouldersVisible: shouldersVisible,
      hipsVisible:     hipsVisible,
      lowerBodyVisible: lowerBodyVisible,
      insideGuideFrame: insideGuide,
      confidence:      confidence,
      detectionScore:  detectionScore,
      landmarkCount:   landmarks.length,
      imageSize:       Size(w.toDouble(), h.toDouble()),
      rotation:        0,
      landmarks:       landmarks,
      tooClose: tooClose,
      tooFar:   tooFar,
      lowLight: false,
    );
  }
}
