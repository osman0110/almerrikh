import 'squat_phase_detector.dart';
import 'biomechanics_service.dart' show BiomechanicsMetrics, SquatBiomechanicsMetrics;

enum RuleSeverity { minor, moderate, critical }

class SquatRule {
  const SquatRule({
    required this.id,
    required this.title,
    required this.explanation,
    required this.tip,
    required this.drill,
    required this.severity,
    required this.penalty,
  });

  final String id;
  final String title;
  final String explanation;
  final String tip;
  final String drill;
  final RuleSeverity severity;
  final double penalty;
}

class SquatRuleViolation {
  const SquatRuleViolation({
    required this.rule,
    required this.triggeredValue,
    required this.threshold,
  });

  final SquatRule rule;
  final double triggeredValue;
  final double threshold;

  String get description => rule.explanation;
}

class SquatRulesEngine {
  static const _rules = [
    SquatRule(
      id: 'poor_depth',
      title: 'Poor Squat Depth',
      explanation: 'Knee angle never reached below 140° — inadequate range of motion.',
      tip: 'Increase hip mobility through dynamic stretching and depth work.',
      drill: 'Box squat — 3×8 to a box 2 inches below parallel, 3-second eccentric.',
      severity: RuleSeverity.critical,
      penalty: 28,
    ),
    SquatRule(
      id: 'insufficient_depth',
      title: 'Insufficient Squat Depth',
      explanation: 'Knee angle remained above 120° — did not reach parallel depth.',
      tip: 'Focus on controlled descent: lower with 2–3 second tempo.',
      drill: 'Tempo squat — 3×8 with 3-second descent, 1-second pause at bottom.',
      severity: RuleSeverity.moderate,
      penalty: 15,
    ),
    SquatRule(
      id: 'severe_valgus',
      title: 'Severe Medial Knee Collapse',
      explanation: 'Knees collapsed inward significantly during descent — risk of injury.',
      tip: "Cue: 'Push knees outward' — drive through outer foot edge.",
      drill: 'Banded squat — resistance band above knees, 3×10 with focus on outward pressure.',
      severity: RuleSeverity.critical,
      penalty: 28,
    ),
    SquatRule(
      id: 'knee_valgus',
      title: 'Medial Knee Deviation',
      explanation: 'Knees tracked inward during descent — kinetic chain imbalance.',
      tip: 'Strengthen glute medius: side-lying clams, monster walks, band work.',
      drill: 'Single-leg squat progression — 3×6 per side with controlled tempo.',
      severity: RuleSeverity.moderate,
      penalty: 18,
    ),
    SquatRule(
      id: 'excessive_lean',
      title: 'Excessive Forward Trunk Lean',
      explanation: 'Trunk lean exceeded 35° — spinal load stress and compromised posture.',
      tip: 'Improve ankle and thoracic mobility; strengthen posterior chain.',
      drill: 'Goblet squat — 3×10 holding weight at chest, elbows high.',
      severity: RuleSeverity.critical,
      penalty: 22,
    ),
    SquatRule(
      id: 'trunk_lean',
      title: 'Forward Trunk Lean',
      explanation: 'Trunk lean exceeded 20° — suboptimal spinal alignment.',
      tip: 'Practice upright posture cue: "Chest up, shoulders back."',
      drill: 'Anderson squat — 3×5 from pins at parallel, explosive concentric.',
      severity: RuleSeverity.moderate,
      penalty: 12,
    ),
    SquatRule(
      id: 'bilateral_asymmetry',
      title: 'Left/Right Asymmetry',
      explanation: 'L/R knee angles differed significantly — unilateral loading imbalance.',
      tip: 'Identify and address mobility/strength asymmetries with unilateral work.',
      drill: 'Single-leg squat progression — 3×6 per side to address asymmetry.',
      severity: RuleSeverity.moderate,
      penalty: 14,
    ),
    SquatRule(
      id: 'movement_inconsistency',
      title: 'Movement Inconsistency',
      explanation: 'High variance in squat depth across reps — unstable pattern.',
      tip: 'Focus on motor control: practice slow, controlled descent.',
      drill: 'Paused squat — 3×6 with 2-second pause at bottom, emphasize consistency.',
      severity: RuleSeverity.minor,
      penalty: 8,
    ),
    SquatRule(
      id: 'no_rep_detected',
      title: 'No Squat Motion Detected',
      explanation: 'No valid descent-bottom-ascent phase sequence found.',
      tip: 'Perform a full squat: lower until hip crease passes knee level.',
      drill: 'Perform 2–3 full-range squats with controlled tempo.',
      severity: RuleSeverity.critical,
      penalty: 40,
    ),
  ];

  static List<SquatRuleViolation> evaluate(
    SquatRepMetrics repMetrics,
    BiomechanicsMetrics biomechanics,
  ) {
    final violations = <SquatRuleViolation>[];

    // Rule: no_rep_detected
    if (!repMetrics.repDetected) {
      violations.add(
        SquatRuleViolation(
          rule: _rules.firstWhere((r) => r.id == 'no_rep_detected'),
          triggeredValue: repMetrics.minKneeAngle,
          threshold: 120,
        ),
      );
      return violations; // Short-circuit: can't evaluate other rules if no rep
    }

    // Rule: poor_depth (minKneeAngle > 140°)
    if (repMetrics.minKneeAngle > 140) {
      violations.add(
        SquatRuleViolation(
          rule: _rules.firstWhere((r) => r.id == 'poor_depth'),
          triggeredValue: repMetrics.minKneeAngle,
          threshold: 140,
        ),
      );
    }
    // Rule: insufficient_depth (minKneeAngle > 120°, but <= 140°)
    else if (repMetrics.minKneeAngle > 120) {
      violations.add(
        SquatRuleViolation(
          rule: _rules.firstWhere((r) => r.id == 'insufficient_depth'),
          triggeredValue: repMetrics.minKneeAngle,
          threshold: 120,
        ),
      );
    }

    // For extended biomechanics metrics (if available as extended class)
    // We'll check if we can access kneeAlignmentScore
    final kneeAlignment = _getKneeAlignmentScore(biomechanics);
    if (kneeAlignment >= 0) {
      if (kneeAlignment < 0.50) {
        violations.add(
          SquatRuleViolation(
            rule: _rules.firstWhere((r) => r.id == 'severe_valgus'),
            triggeredValue: kneeAlignment,
            threshold: 0.50,
          ),
        );
      } else if (kneeAlignment < 0.70) {
        violations.add(
          SquatRuleViolation(
            rule: _rules.firstWhere((r) => r.id == 'knee_valgus'),
            triggeredValue: kneeAlignment,
            threshold: 0.70,
          ),
        );
      }
    }

    // For trunk lean (if available as extended class)
    final trunkLean = _getTrunkLeanDeg(biomechanics);
    if (trunkLean >= 0) {
      if (trunkLean > 35) {
        violations.add(
          SquatRuleViolation(
            rule: _rules.firstWhere((r) => r.id == 'excessive_lean'),
            triggeredValue: trunkLean,
            threshold: 35,
          ),
        );
      } else if (trunkLean > 20) {
        violations.add(
          SquatRuleViolation(
            rule: _rules.firstWhere((r) => r.id == 'trunk_lean'),
            triggeredValue: trunkLean,
            threshold: 20,
          ),
        );
      }
    }

    // Rule: bilateral_asymmetry
    if (repMetrics.bottomSymmetryDelta > 12) {
      violations.add(
        SquatRuleViolation(
          rule: _rules.firstWhere((r) => r.id == 'bilateral_asymmetry'),
          triggeredValue: repMetrics.bottomSymmetryDelta,
          threshold: 12,
        ),
      );
    }

    // Rule: movement_inconsistency (requires variance calculation)
    final variance = _getMovementVariance(biomechanics);
    if (variance >= 0 && variance > 18) {
      violations.add(
        SquatRuleViolation(
          rule: _rules.firstWhere((r) => r.id == 'movement_inconsistency'),
          triggeredValue: variance,
          threshold: 18,
        ),
      );
    }

    // Sort by severity: critical → moderate → minor
    violations.sort((a, b) {
      final severityOrder = {
        RuleSeverity.critical: 0,
        RuleSeverity.moderate: 1,
        RuleSeverity.minor: 2,
      };
      return (severityOrder[a.rule.severity] ?? 3).compareTo(severityOrder[b.rule.severity] ?? 3);
    });

    return violations;
  }

  // Helper: safely extract kneeAlignmentScore if available
  static double _getKneeAlignmentScore(BiomechanicsMetrics bio) {
    // If bio has extended fields, return them; otherwise -1
    if (bio is SquatBiomechanicsMetrics) {
      return bio.kneeAlignmentScore;
    }
    return -1;
  }

  // Helper: safely extract trunkLeanDeg if available
  static double _getTrunkLeanDeg(BiomechanicsMetrics bio) {
    if (bio is SquatBiomechanicsMetrics) {
      return bio.trunkLeanDeg;
    }
    return -1;
  }

  // Helper: safely extract movementVariance if available
  static double _getMovementVariance(BiomechanicsMetrics bio) {
    if (bio is SquatBiomechanicsMetrics) {
      return bio.movementVariance;
    }
    return -1;
  }
}
