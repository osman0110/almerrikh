import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'pose_assessment_config.dart';

/// Thrown when the browser denies camera permission (getUserMedia
/// NotAllowedError/PermissionDeniedError).
class CameraPermissionDeniedException implements Exception {
  const CameraPermissionDeniedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when no camera hardware/device is available in the browser
/// (getUserMedia NotFoundError/DevicesNotFoundError), so callers can show
/// an "unsupported device" message instead of a silent black preview.
class CameraUnsupportedException implements Exception {
  const CameraUnsupportedException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ── Constants ──────────────────────────────────────────────────────────────────
const String _kVideoId  = 'nk-pose-video';
const String _kViewType = 'nk-camera-preview';

// Registered once per app session.
bool _viewFactoryRegistered = false;

// Module-level stream ref — factory is registered once and cannot capture
// a changing instance, so we pass the latest stream through this global.
html.MediaStream? _factoryStream;

// ── CameraFrame ───────────────────────────────────────────────────────────────

class CameraFrame {
  const CameraFrame({
    required this.image,
    required this.width,
    required this.height,
    required this.rotation,
    this.isFront = false,
    this.timestampMs = 0,
  });

  /// Always null on web — inference reads directly from the DOM video element.
  final Object? image;
  final int width;
  final int height;
  final int rotation;
  final bool isFront;
  final int timestampMs;
}

// ── CameraService (web) ───────────────────────────────────────────────────────

class CameraService {
  html.MediaStream? _stream;
  Timer?            _ticker;
  Timer?            _playWatcher;
  bool              _streaming = false;

  final _framesController = StreamController<CameraFrame>.broadcast();

  Stream<CameraFrame> get frames => _framesController.stream;
  bool get isDemoMode => false;

  /// Returns true — actual permission is requested in initialize().
  Future<bool> requestPermission() async => true;

  Future<void> initialize({bool preferFront = false}) async {
    // Remove any stale video element from a previous session.
    _cleanupVideoElement();

    // Register the platform-view factory exactly once for the app lifetime.
    // The factory creates the video element in-place inside <flt-platform-view>,
    // avoiding the DOM-move that can freeze video on some browsers.
    _registerPlatformViewFactory();

    final facingConstraint = preferFront
        ? 'user'
        : <String, Object>{'ideal': 'environment'};

    try {
      final stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {
          'facingMode': facingConstraint,
          'width':  {'ideal': 640},
          'height': {'ideal': 480},
        },
        'audio': false,
      });
      _stream = stream;

      // Make stream available for the factory closure (module-level ref).
      _factoryStream = stream;

      debugPrint('[NextKickCamera] stream created id=${stream.id}');
      final tracks = stream.getVideoTracks();
      debugPrint('[NextKickCamera] tracks count=${tracks.length} '
          'label=${tracks.isNotEmpty ? tracks.first.label : "none"} '
          'readyState=${tracks.isNotEmpty ? tracks.first.readyState : "none"}');

      // If factory already ran before initialize() (rare edge-case),
      // attach the stream to the existing element.
      final existing =
          html.document.getElementById(_kVideoId) as html.VideoElement?;
      if (existing != null) {
        debugPrint('[NextKickCamera] factory already ran — attaching stream to existing element');
        existing.srcObject = stream;
        debugPrint('[NextKickCamera] video srcObject assigned to existing element');
        _ensurePlayAfterMetadata(existing);
      }
      // Normal path: factory runs after setState() triggers HtmlElementView mount.

      _startPlayWatcher();
    } on html.DomException catch (e) {
      debugPrint('[NextKickCamera] getUserMedia failed: ${e.name}: ${e.message}');
      if (e.name == 'NotAllowedError' || e.name == 'PermissionDeniedError') {
        throw CameraPermissionDeniedException(e.message ?? e.name);
      }
      if (e.name == 'NotFoundError' || e.name == 'DevicesNotFoundError') {
        throw CameraUnsupportedException(e.message ?? e.name);
      }
      rethrow;
    }
  }

  // ── Platform view factory ─────────────────────────────────────────────────

  void _registerPlatformViewFactory() {
    if (_viewFactoryRegistered) return;
    _viewFactoryRegistered = true;

    ui_web.platformViewRegistry.registerViewFactory(_kViewType, (_) {
      // Remove stale element left by a previous camera session.
      html.document.getElementById(_kVideoId)?.remove();

      debugPrint('[NextKickCamera] factory: creating video element');

      // Create the video element DIRECTLY inside the platform-view container.
      // No DOM move → no freeze risk.
      final video = html.VideoElement()
        ..id       = _kVideoId
        ..autoplay = true
        ..muted    = true
        ..setAttribute('playsinline', 'true')
        ..setAttribute('webkit-playsinline', 'true')
        ..style.width           = '100%'
        ..style.height          = '100%'
        ..style.objectFit       = 'cover'
        ..style.backgroundColor = '#000000'
        ..style.display         = 'block';

      final stream = _factoryStream;
      if (stream != null) {
        video.srcObject = stream;
        debugPrint('[NextKickCamera] video srcObject assigned in factory');
        _ensurePlayAfterMetadata(video);
      } else {
        debugPrint('[NextKickCamera] WARNING: factory ran before stream was ready — video will be black');
      }

      return video;
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Attach a loadedmetadata listener that calls play(), then also call play()
  /// immediately if metadata is already available.
  static void _ensurePlayAfterMetadata(html.VideoElement video) {
    video.onLoadedMetadata.listen((_) {
      debugPrint('[NextKickCamera] loadedmetadata '
          '${video.videoWidth}×${video.videoHeight}');
      video.play().then((_) {
        debugPrint('[NextKickCamera] play() resolved after loadedmetadata');
      }).catchError((Object e) {
        debugPrint('[NextKickCamera] play() failed after loadedmetadata: $e');
      });
    });

    // Also call canplay as a secondary attempt in case loadedmetadata was missed.
    video.onCanPlay.listen((_) {
      if (video.paused) {
        video.play().catchError((Object e) {
          debugPrint('[NextKickCamera] canplay play() failed: $e');
        });
      }
    });

    // Immediate attempt if metadata already loaded (readyState >= 1).
    if (video.readyState >= 1) {
      video.play().then((_) {
        debugPrint('[NextKickCamera] play() resolved (immediate, readyState=${video.readyState})');
      }).catchError((Object e) {
        debugPrint('[NextKickCamera] play() failed (immediate): $e');
      });
    }
  }

  // ── Play watcher — detects and recovers frozen video ─────────────────────

  void _startPlayWatcher() {
    _playWatcher?.cancel();
    double lastVideoTime = -1;

    _playWatcher = Timer.periodic(const Duration(seconds: 1), (_) {
      final video =
          html.document.getElementById(_kVideoId) as html.VideoElement?;
      if (video == null) {
        debugPrint('[NextKickCamera] watcher: video element NOT FOUND in DOM');
        return;
      }

      final double t = video.currentTime.toDouble();
      final stream = video.srcObject;
      final tracks = stream != null
          ? stream.getVideoTracks()
          : <html.MediaStreamTrack>[];
      final trackState   = tracks.isNotEmpty ? tracks.first.readyState : 'no-track';
      final trackEnabled = tracks.isNotEmpty ? tracks.first.enabled    : false;
      final trackMuted   = tracks.isNotEmpty ? tracks.first.muted      : true;

      if (lastVideoTime >= 0 && t == lastVideoTime) {
        // currentTime not advancing → frozen
        debugPrint('[NextKickCamera] currentTime FROZEN '
            'time=$t paused=${video.paused} ended=${video.ended} '
            'readyState=${video.readyState} trackState=$trackState '
            'trackEnabled=$trackEnabled trackMuted=$trackMuted');

        if (video.paused && !video.ended && trackState == 'live') {
          debugPrint('[NextKickCamera] Recovery: calling video.play()');
          video.play().then((_) {
            debugPrint('[NextKickCamera] Recovery play() resolved');
          }).catchError((Object e) {
            debugPrint('[NextKickCamera] Recovery play() failed: $e');
          });
        } else if (trackState != 'live') {
          debugPrint('[NextKickCamera] Stream track not live — trackState=$trackState');
        }
      } else {
        debugPrint('[NextKickCamera] currentTime tick '
            '$lastVideoTime → $t trackState=$trackState');
      }
      lastVideoTime = t;
    });
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> startImageStream({bool landscapeLeft = true}) async {
    if (_streaming) return;
    _streaming = true;
    _ticker = Timer.periodic(
      const Duration(milliseconds: PoseAssessmentConfig.webTickIntervalMs),
      (_) {
        if (_framesController.isClosed) return;
        // Look up the video element by ID each tick — avoids stale instance ref.
        final video =
            html.document.getElementById(_kVideoId) as html.VideoElement?;
        _framesController.add(CameraFrame(
          image:    null,
          width:    video?.videoWidth  ?? 640,
          height:   video?.videoHeight ?? 480,
          rotation: 0,
          isFront:  false,
        ));
      },
    );
  }

  Future<void> stopImageStream() async {
    _ticker?.cancel();
    _ticker    = null;
    _streaming = false;
  }

  /// Returns an HtmlElementView that renders the live camera feed.
  Widget buildPreview() => const HtmlElementView(viewType: _kViewType);

  /// Diagnostic snapshot — readable from the camera page for status overlay.
  Map<String, Object?> getVideoStatus() {
    final video =
        html.document.getElementById(_kVideoId) as html.VideoElement?;
    final tracks = _stream?.getVideoTracks() ?? <html.MediaStreamTrack>[];
    return {
      'videoFound':   video != null,
      'currentTime':  video?.currentTime,
      'paused':       video?.paused,
      'readyState':   video?.readyState,
      'videoWidth':   video?.videoWidth,
      'videoHeight':  video?.videoHeight,
      'trackCount':   tracks.length,
      'trackState':   tracks.isNotEmpty ? tracks.first.readyState : 'none',
      'trackEnabled': tracks.isNotEmpty ? tracks.first.enabled    : false,
    };
  }

  Future<void> dispose() async {
    _playWatcher?.cancel();
    _playWatcher = null;
    await stopImageStream();
    _cleanupStream();
    _cleanupVideoElement();
    _factoryStream = null;
    if (!_framesController.isClosed) await _framesController.close();
  }

  // ── Private cleanup ───────────────────────────────────────────────────────

  void _cleanupStream() {
    _stream?.getTracks().forEach((t) => t.stop());
    _stream = null;
  }

  void _cleanupVideoElement() {
    html.document.getElementById(_kVideoId)?.remove();
  }
}
