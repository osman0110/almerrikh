import 'dart:ui';

import 'exercise_engine.dart';
import 'pose_assessment_config.dart';

/// Low-pass filter that adapts its cutoff to signal speed — see
/// https://cristal.univ-lille.fr/~casiez/1euro/ . Fast movement gets less
/// smoothing (less lag); near-stationary points get heavier smoothing
/// (less jitter).
class _OneEuroFilter1D {
  final double minCutoff = PoseAssessmentConfig.oneEuroMinCutoff;
  final double beta = PoseAssessmentConfig.oneEuroBeta;
  final double dCutoff = PoseAssessmentConfig.oneEuroDCutoff;

  double? _xPrev;
  double? _dxPrev;
  int? _tPrevMs;

  double _alpha(double cutoffHz, double dtSec) {
    final tau = 1.0 / (2 * 3.14159265358979 * cutoffHz);
    return 1.0 / (1.0 + tau / dtSec);
  }

  double filter(double x, int tMs) {
    if (_tPrevMs == null) {
      _xPrev = x;
      _dxPrev = 0.0;
      _tPrevMs = tMs;
      return x;
    }
    final dtMs = tMs - _tPrevMs!;
    final dtSec = dtMs > 0 ? dtMs / 1000.0 : 1.0 / 30.0;

    final dx = (x - _xPrev!) / dtSec;
    final dxAlpha = _alpha(dCutoff, dtSec);
    final dxHat = dxAlpha * dx + (1 - dxAlpha) * (_dxPrev ?? 0.0);

    final cutoff = minCutoff + beta * dxHat.abs();
    final xAlpha = _alpha(cutoff, dtSec);
    final xHat = xAlpha * x + (1 - xAlpha) * _xPrev!;

    _xPrev = xHat;
    _dxPrev = dxHat;
    _tPrevMs = tMs;
    return xHat;
  }

  void reset() {
    _xPrev = null;
    _dxPrev = null;
    _tPrevMs = null;
  }
}

class _LandmarkFilterState {
  final _OneEuroFilter1D x = _OneEuroFilter1D();
  final _OneEuroFilter1D y = _OneEuroFilter1D();
  Offset? lastOutput;
  int missingFrames = 0;
}

/// Per-landmark One Euro smoothing for the live skeleton overlay.
///
/// Confidence-weighted: landmarks below [PoseAssessmentConfig.smoothingMinLikelihood]
/// are not fed into the filter — the last good output is held for up to
/// [PoseAssessmentConfig.smoothingHoldMaxFrames] frames, then the landmark is
/// dropped. A single-frame displacement larger than
/// [PoseAssessmentConfig.smoothingMaxJumpTorsoRatio] × torso length is treated
/// as a glitch: the filter state is held, not updated. Display only — scoring
/// always uses raw captured frames.
class PoseSmoothingService {
  final Map<String, _LandmarkFilterState> _filters = {};

  void reset() {
    _filters.clear();
  }

  double? _torsoLength(PoseSnapshot snapshot) {
    final ls = snapshot.landmarks['leftShoulder'];
    final rs = snapshot.landmarks['rightShoulder'];
    final lh = snapshot.landmarks['leftHip'];
    final rh = snapshot.landmarks['rightHip'];
    if (ls == null || rs == null || lh == null || rh == null) return null;
    final midShoulder = Offset((ls.dx + rs.dx) / 2, (ls.dy + rs.dy) / 2);
    final midHip = Offset((lh.dx + rh.dx) / 2, (lh.dy + rh.dy) / 2);
    return (midShoulder - midHip).distance;
  }

  Map<String, Offset> smooth(PoseSnapshot snapshot) {
    final tMs = snapshot.timestampMs > 0
        ? snapshot.timestampMs
        : DateTime.now().millisecondsSinceEpoch;
    final torso = _torsoLength(snapshot) ?? 0.25;
    final maxJump = torso * PoseAssessmentConfig.smoothingMaxJumpTorsoRatio;

    final out = <String, Offset>{};
    final seenKeys = <String>{};

    for (final entry in snapshot.landmarks.entries) {
      final key = entry.key;
      final raw = entry.value;
      final likelihood = snapshot.likelihoods[key] ?? 1.0;
      seenKeys.add(key);

      final state = _filters.putIfAbsent(key, () => _LandmarkFilterState());

      if (likelihood < PoseAssessmentConfig.smoothingMinLikelihood) {
        // Too uncertain to trust — hold last good output briefly, then drop.
        if (state.lastOutput != null &&
            state.missingFrames < PoseAssessmentConfig.smoothingHoldMaxFrames) {
          state.missingFrames++;
          out[key] = state.lastOutput!;
        }
        continue;
      }

      if (state.lastOutput != null && (raw - state.lastOutput!).distance > maxJump) {
        // Single-frame glitch: hold the last output, don't feed the filter.
        state.missingFrames++;
        if (state.missingFrames <= PoseAssessmentConfig.smoothingHoldMaxFrames) {
          out[key] = state.lastOutput!;
        } else {
          // Sustained large displacement — accept it as real movement.
          final fx = state.x.filter(raw.dx, tMs);
          final fy = state.y.filter(raw.dy, tMs);
          final smoothed = Offset(fx, fy);
          state.lastOutput = smoothed;
          state.missingFrames = 0;
          out[key] = smoothed;
        }
        continue;
      }

      final fx = state.x.filter(raw.dx, tMs);
      final fy = state.y.filter(raw.dy, tMs);
      final smoothed = Offset(fx, fy);
      state.lastOutput = smoothed;
      state.missingFrames = 0;
      out[key] = smoothed;
    }

    // Drop filter state for landmarks no longer present at all.
    _filters.removeWhere((k, _) => !seenKeys.contains(k));

    return out;
  }
}
