import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';
import 'camera_service.dart';

/// Buffers the same frames already used for pose detection as a grayscale
/// JPEG sequence, so a coach can scrub through the capture before certifying
/// the AI result — without touching the camera pipeline itself (no parallel
/// video recording). Frames live only on-device and are deleted once the
/// result is approved (or discarded if the capture is invalid/retried).
class AssessmentVideoService {
  Directory? _dir;
  int _frameIndex = 0;
  int _savedCount = 0;
  final List<Future<void>> _pending = [];
  static const int _saveEveryNth = 2; // keep file count/IO bounded

  Future<void> start(String assessmentId) async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/assessment_review/$assessmentId');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      _dir = dir;
      _frameIndex = 0;
      _savedCount = 0;
    } catch (e) {
      AppLogger.e('AssessmentVideoService', 'start failed', e);
      _dir = null;
    }
  }

  /// Call once per accepted pose-detection frame; internally throttled.
  void addFrame(dynamic rawFrame) {
    final dir = _dir;
    if (dir == null) return;
    if (rawFrame is! CameraFrame) return;
    final image = rawFrame.image;
    if (image is! CameraImage) return;
    _frameIndex++;
    if (_frameIndex % _saveEveryNth != 0) return;

    final index = _savedCount++;
    final plane = image.planes.first;
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;
    final yBytes = plane.bytes;
    final path = '${dir.path}/frame_${index.toString().padLeft(4, '0')}.jpg';

    _pending.add(_encodeAndWrite(yBytes, width, height, rowStride, path));
  }

  static Future<void> _encodeAndWrite(
    Uint8List yBytes,
    int width,
    int height,
    int rowStride,
    String path,
  ) async {
    try {
      final gray = Uint8List(width * height);
      // Y plane may be row-padded (rowStride >= width) — copy row by row.
      for (int y = 0; y < height; y++) {
        final srcStart = y * rowStride;
        final srcEnd = srcStart + width;
        if (srcEnd > yBytes.length) break;
        gray.setRange(y * width, y * width + width, yBytes, srcStart);
      }
      final frame = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: gray.buffer,
        numChannels: 1,
      );
      final jpg = img.encodeJpg(frame, quality: 55);
      await File(path).writeAsBytes(jpg, flush: false);
    } catch (e) {
      AppLogger.e('AssessmentVideoService', 'frame encode failed', e);
    }
  }

  /// Waits for buffered frames to finish writing and returns the folder path
  /// (null if nothing was captured). Caller owns cleanup from here on.
  Future<String?> finish() async {
    final dir = _dir;
    _dir = null;
    if (dir == null) return null;
    try {
      await Future.wait(_pending);
    } catch (_) {}
    _pending.clear();
    if (_savedCount == 0) {
      await deleteFolder(dir.path);
      return null;
    }
    return dir.path;
  }

  /// Drops everything captured so far (analysis failed / player retried).
  Future<void> discard() async {
    final dir = _dir;
    _dir = null;
    _pending.clear();
    if (dir != null) await deleteFolder(dir.path);
  }

  static Future<void> deleteFolder(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      AppLogger.e('AssessmentVideoService', 'deleteFolder failed', e);
    }
  }

  static Future<List<String>> listFrames(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return [];
      final files = await dir
          .list()
          .where((e) => e.path.endsWith('.jpg'))
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      return files.map((e) => e.path).toList();
    } catch (e) {
      AppLogger.e('AssessmentVideoService', 'listFrames failed', e);
      return [];
    }
  }
}
