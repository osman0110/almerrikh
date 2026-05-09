import 'package:flutter/material.dart';
import 'exercise_engine.dart';
import 'hand_tracker.dart';

enum CalibrationIssue {
  noPlayer,
  partialBody,
  tooClose,
  tooFar,
  poorLight,
  lowConfidence,
  handsNotVisible,
}

class CalibrationResult {
  const CalibrationResult.pass() : passed = true, issue = null, message = '';
  const CalibrationResult.fail(this.issue, this.message) : passed = false;

  final bool passed;
  final CalibrationIssue? issue;
  final String message;
}

/// Runs all pre-exercise checks and returns the first failing condition.
/// All checks must pass simultaneously before training may begin.
class CalibrationController {
  static const double _minConfidence = 0.52;

  CalibrationResult check(PoseSnapshot? pose, HandPoints hands, Size screenSize) {
    if (pose == null || pose.bodyBox == null || pose.detectionScore == 0) {
      return const CalibrationResult.fail(
        CalibrationIssue.noPlayer,
        'قف أمام الكاميرا',
      );
    }

    if (!pose.bodyFullyVisible || pose.detectionScore < 6) {
      return const CalibrationResult.fail(
        CalibrationIssue.partialBody,
        'أظهر جسمك كاملاً داخل الكادر',
      );
    }

    if (pose.tooClose) {
      return const CalibrationResult.fail(
        CalibrationIssue.tooClose,
        'ارجع خطوتين للخلف',
      );
    }

    if (pose.tooFar) {
      return const CalibrationResult.fail(
        CalibrationIssue.tooFar,
        'اقترب قليلاً من الكاميرا',
      );
    }

    if (pose.lowLight || pose.confidence < _minConfidence * 0.6) {
      return const CalibrationResult.fail(
        CalibrationIssue.poorLight,
        'حسّن الإضاءة، النور يكون أمامك',
      );
    }

    if (pose.confidence < _minConfidence) {
      return const CalibrationResult.fail(
        CalibrationIssue.lowConfidence,
        'تحرك ببطء حتى يقرأ الجهاز وضعيتك بدقة',
      );
    }

    if (!hands.anyHandVisible) {
      return const CalibrationResult.fail(
        CalibrationIssue.handsNotVisible,
        'أظهر يديك بوضوح',
      );
    }

    return const CalibrationResult.pass();
  }

  /// Icon that matches the current calibration issue.
  static IconData iconFor(CalibrationIssue issue) => switch (issue) {
    CalibrationIssue.noPlayer        => Icons.person_search_rounded,
    CalibrationIssue.partialBody     => Icons.accessibility_new_rounded,
    CalibrationIssue.tooClose        => Icons.zoom_out_map_rounded,
    CalibrationIssue.tooFar          => Icons.zoom_in_rounded,
    CalibrationIssue.poorLight       => Icons.light_mode_rounded,
    CalibrationIssue.lowConfidence   => Icons.sensors_rounded,
    CalibrationIssue.handsNotVisible => Icons.pan_tool_rounded,
  };
}
