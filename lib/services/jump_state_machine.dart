import 'pose_assessment_config.dart';

enum JumpState {
  searchingBody,
  positioning,
  stabilizing,
  ready,
  squatHold,
  takeoff,
  airborne,
  landing,
  completed,
  invalid,
}

/// Formal jump-test state machine with hysteresis and a frozen baseline —
/// replaces the old single-frame `_JumpPhase` heuristic, which had no
/// minimum durations and kept updating its "baseline" during capture
/// (causing drift) and computed knee angles from a single noisy frame
/// (causing glitch readings like "L: 9° R: 77°").
///
/// Angles and hip height are tracked as a median over the last
/// [PoseAssessmentConfig.medianWindowFrames] valid frames, so a single bad
/// frame can't swing the reading. The standing baseline (hip height, ankle
/// height, leg length) is frozen once at the stabilizing→ready transition
/// and never updated again during the rep.
class JumpStateMachine {
  JumpStateMachine({required this.isSquatJump});

  final bool isSquatJump;

  JumpState _state = JumpState.searchingBody;
  JumpState get state => _state;

  static const int _medianWindow = PoseAssessmentConfig.medianWindowFrames;

  final List<double> _hipYWindow = [];
  final List<double> _leftKneeWindow = [];
  final List<double> _rightKneeWindow = [];

  double? _medianHipY;
  double? medianLeftKneeAngle;
  double? medianRightKneeAngle;

  int? _stateEnteredAtMs;
  int? _lastValidMs;

  double? baselineHipY;
  double? baselineLeftAnkleY;
  double? baselineRightAnkleY;
  double? legLength;

  double _prevHipY = 0;
  int _prevHipTsMs = 0;

  /// Hip vertical velocity, units/sec in normalised-frame space; positive = moving up.
  double hipVelocity = 0;

  int _takeoffConfirm = 0;
  int _landingConfirm = 0;

  void reset() {
    _state = JumpState.searchingBody;
    _hipYWindow.clear();
    _leftKneeWindow.clear();
    _rightKneeWindow.clear();
    _medianHipY = null;
    medianLeftKneeAngle = null;
    medianRightKneeAngle = null;
    _stateEnteredAtMs = null;
    _lastValidMs = null;
    baselineHipY = null;
    baselineLeftAnkleY = null;
    baselineRightAnkleY = null;
    legLength = null;
    _prevHipY = 0;
    _prevHipTsMs = 0;
    hipVelocity = 0;
    _takeoffConfirm = 0;
    _landingConfirm = 0;
  }

  void _setState(JumpState next, int tsMs) {
    if (_state != next) {
      _state = next;
      _stateEnteredAtMs = tsMs;
    }
  }

  int _msInState(int tsMs) => _stateEnteredAtMs == null ? 0 : tsMs - _stateEnteredAtMs!;

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static void _push(List<double> window, double value) {
    window.add(value);
    if (window.length > _medianWindow) window.removeAt(0);
  }

  double? _avgKnee() {
    if (medianLeftKneeAngle != null && medianRightKneeAngle != null) {
      return (medianLeftKneeAngle! + medianRightKneeAngle!) / 2;
    }
    return medianLeftKneeAngle ?? medianRightKneeAngle;
  }

  /// Feeds one frame's data in and returns the (possibly updated) state.
  /// [hipY]/[leftAnkleY]/[rightAnkleY] are normalised [0,1] frame coords
  /// (image Y increases downward); [leftKneeAngle]/[rightKneeAngle] are in
  /// degrees. Pass nulls for landmarks not present this frame.
  JumpState update({
    required bool frameValid,
    double? hipY,
    double? leftAnkleY,
    double? rightAnkleY,
    double? leftKneeAngle,
    double? rightKneeAngle,
    required int tsMs,
  }) {
    if (_state == JumpState.completed || _state == JumpState.invalid) return _state;

    if (frameValid) {
      _lastValidMs = tsMs;
      if (hipY != null) {
        _push(_hipYWindow, hipY);
        _medianHipY = _median(_hipYWindow);
        if (_prevHipTsMs > 0) {
          final dtSec = (tsMs - _prevHipTsMs) / 1000.0;
          if (dtSec > 0) hipVelocity = (_prevHipY - hipY) / dtSec;
        }
        _prevHipY = hipY;
        _prevHipTsMs = tsMs;
      }
      if (leftKneeAngle != null) {
        _push(_leftKneeWindow, leftKneeAngle);
        medianLeftKneeAngle = _median(_leftKneeWindow);
      }
      if (rightKneeAngle != null) {
        _push(_rightKneeWindow, rightKneeAngle);
        medianRightKneeAngle = _median(_rightKneeWindow);
      }
    }

    // Tracking lost mid-flight for too long → invalid (don't guess a result).
    final midFlight = _state == JumpState.takeoff ||
        _state == JumpState.airborne ||
        _state == JumpState.landing;
    if (!frameValid && midFlight && _lastValidMs != null &&
        (tsMs - _lastValidMs!) > PoseAssessmentConfig.jumpInvalidGapMs) {
      _setState(JumpState.invalid, tsMs);
      return _state;
    }

    switch (_state) {
      case JumpState.searchingBody:
        if (frameValid) _setState(JumpState.positioning, tsMs);
        break;

      case JumpState.positioning:
        if (!frameValid) {
          _setState(JumpState.searchingBody, tsMs);
          break;
        }
        if (_hipYWindow.length >= _medianWindow) {
          _setState(JumpState.stabilizing, tsMs);
        }
        break;

      case JumpState.stabilizing:
        if (!frameValid) {
          _setState(JumpState.searchingBody, tsMs);
          break;
        }
        if (_msInState(tsMs) >= PoseAssessmentConfig.stabilizingMinMs) {
          baselineHipY = _medianHipY;
          baselineLeftAnkleY = leftAnkleY;
          baselineRightAnkleY = rightAnkleY;
          if (baselineHipY != null && baselineLeftAnkleY != null) {
            legLength = (baselineLeftAnkleY! - baselineHipY!).abs();
          } else if (baselineHipY != null && baselineRightAnkleY != null) {
            legLength = (baselineRightAnkleY! - baselineHipY!).abs();
          }
          _setState(JumpState.ready, tsMs);
        }
        break;

      case JumpState.ready:
        if (!frameValid) {
          _setState(JumpState.searchingBody, tsMs);
          break;
        }
        if (isSquatJump) {
          final avgKnee = _avgKnee();
          if (avgKnee != null && avgKnee < PoseAssessmentConfig.jumpSquatEnterKneeAngle) {
            _setState(JumpState.squatHold, tsMs);
          }
        } else {
          _checkTakeoff(tsMs, leftAnkleY, rightAnkleY);
        }
        break;

      case JumpState.squatHold:
        if (!frameValid) {
          _setState(JumpState.searchingBody, tsMs);
          break;
        }
        final avgKnee = _avgKnee();
        if (avgKnee != null && avgKnee >= PoseAssessmentConfig.jumpSquatExitKneeAngle) {
          _setState(JumpState.ready, tsMs); // stood back up without holding — retry
          break;
        }
        if (_msInState(tsMs) >= PoseAssessmentConfig.squatHoldMinMs) {
          _checkTakeoff(tsMs, leftAnkleY, rightAnkleY);
        }
        break;

      case JumpState.takeoff:
        _checkTakeoff(tsMs, leftAnkleY, rightAnkleY, alreadyInTakeoff: true);
        break;

      case JumpState.airborne:
        _checkLanding(tsMs, leftAnkleY, rightAnkleY);
        break;

      case JumpState.landing:
        _checkCompleted(tsMs);
        break;

      case JumpState.completed:
      case JumpState.invalid:
        break;
    }

    return _state;
  }

  void _checkTakeoff(int tsMs, double? leftAnkleY, double? rightAnkleY,
      {bool alreadyInTakeoff = false}) {
    final ll = legLength;
    final baseL = baselineLeftAnkleY;
    final baseR = baselineRightAnkleY;
    if (ll == null || ll <= 0 || leftAnkleY == null || rightAnkleY == null ||
        baseL == null || baseR == null) {
      if (alreadyInTakeoff) _takeoffConfirm = 0;
      return;
    }
    final liftMargin = ll * 0.05;
    final bothLifted = (leftAnkleY < baseL - liftMargin) && (rightAnkleY < baseR - liftMargin);
    final velocityOk = hipVelocity > 0.8 * ll;

    if (bothLifted && velocityOk) {
      _takeoffConfirm++;
      if (_takeoffConfirm >= PoseAssessmentConfig.takeoffConfirmFrames) {
        _setState(JumpState.airborne, tsMs);
        _takeoffConfirm = 0;
      } else {
        _setState(JumpState.takeoff, tsMs);
      }
    } else {
      _takeoffConfirm = 0;
      if (alreadyInTakeoff) _setState(JumpState.ready, tsMs); // false start
    }
  }

  void _checkLanding(int tsMs, double? leftAnkleY, double? rightAnkleY) {
    final ll = legLength;
    final baseL = baselineLeftAnkleY;
    final baseR = baselineRightAnkleY;
    if (ll == null || ll <= 0 || leftAnkleY == null || rightAnkleY == null ||
        baseL == null || baseR == null) {
      _landingConfirm = 0;
      return;
    }
    final margin = ll * 0.05;
    final bothDown = (leftAnkleY - baseL).abs() <= margin && (rightAnkleY - baseR).abs() <= margin;
    if (bothDown) {
      _landingConfirm++;
      if (_landingConfirm >= PoseAssessmentConfig.landingConfirmFrames) {
        _setState(JumpState.landing, tsMs);
        _landingConfirm = 0;
      }
    } else {
      _landingConfirm = 0;
    }
  }

  void _checkCompleted(int tsMs) {
    final ll = legLength ?? 1.0;
    final lowVelocity = hipVelocity.abs() < 0.15 * ll;
    if (lowVelocity) {
      _landingConfirm++;
      if (_landingConfirm >= PoseAssessmentConfig.landingConfirmFrames) {
        _setState(JumpState.completed, tsMs);
      }
    } else {
      _landingConfirm = 0;
    }
  }
}
