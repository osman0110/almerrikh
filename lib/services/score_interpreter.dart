import '../app_localizations.dart';
import '../models/club_models.dart';

class ScoreInterpretation {
  final String headline;
  final List<String> details;
  final String nextStep;

  const ScoreInterpretation({
    required this.headline,
    required this.details,
    required this.nextStep,
  });
}

/// Provides context-sensitive score interpretation per assessment type.
/// Uses simple threshold rules — no server or ML required.
class ScoreInterpreter {
  static ScoreInterpretation interpret({
    required AssessmentType type,
    required double score,
    double? movementQuality,
    double? stability,
    double? symmetry,
  }) {
    switch (type) {
      case AssessmentType.squat:
        return _squat(score, movementQuality, stability, symmetry);
      case AssessmentType.jumpLanding:
        return _jumpLanding(score, stability, symmetry);
      case AssessmentType.singleLegBalance:
        return _balance(score, stability, symmetry);
      default:
        return _generic(score);
    }
  }

  static ScoreInterpretation _squat(
      double score, double? mov, double? stab, double? sym) {
    final details = <String>[];

    if (mov != null) {
      if (mov >= 75) details.add(AppLocalizations.get('interp_squat_mov_good'));
      else if (mov >= 55) details.add(AppLocalizations.get('interp_squat_mov_fair'));
      else details.add(AppLocalizations.get('interp_squat_mov_poor'));
    }
    if (sym != null && sym < 65) details.add(AppLocalizations.get('interp_squat_sym_issue'));
    if (stab != null && stab < 60) details.add(AppLocalizations.get('interp_squat_mobility'));

    return ScoreInterpretation(
      headline: _scoreHeadline(score, 'squat'),
      details: details,
      nextStep: _nextStep(score),
    );
  }

  static ScoreInterpretation _jumpLanding(
      double score, double? stab, double? sym) {
    final details = <String>[];

    if (stab != null) {
      if (stab >= 75) details.add(AppLocalizations.get('interp_jump_landing_good'));
      else if (stab >= 55) details.add(AppLocalizations.get('interp_jump_landing_fair'));
      else details.add(AppLocalizations.get('interp_jump_landing_poor'));
    }
    if (sym != null && sym < 65) details.add(AppLocalizations.get('interp_jump_sym_issue'));
    if (score < 55) details.add(AppLocalizations.get('interp_jump_risk'));

    return ScoreInterpretation(
      headline: _scoreHeadline(score, 'jump'),
      details: details,
      nextStep: _nextStep(score),
    );
  }

  static ScoreInterpretation _balance(
      double score, double? stab, double? sym) {
    final details = <String>[];

    if (sym != null) {
      if (sym >= 75) details.add(AppLocalizations.get('interp_balance_sym_good'));
      else details.add(AppLocalizations.get('interp_balance_sym_issue'));
    }
    if (stab != null && stab < 60) details.add(AppLocalizations.get('interp_balance_ankle'));

    return ScoreInterpretation(
      headline: _scoreHeadline(score, 'balance'),
      details: details,
      nextStep: _nextStep(score),
    );
  }

  static ScoreInterpretation _generic(double score) => ScoreInterpretation(
    headline: score >= 75
        ? AppLocalizations.get('insight_generic_good')
        : score >= 55
            ? AppLocalizations.get('insight_generic_fair')
            : AppLocalizations.get('insight_generic_poor'),
    details: [],
    nextStep: _nextStep(score),
  );

  static String _scoreHeadline(double score, String type) {
    final suffix = score >= 75 ? 'good' : score >= 55 ? 'fair' : 'poor';
    return AppLocalizations.get('interp_${type}_headline_$suffix');
  }

  static String _nextStep(double score) {
    if (score >= 75) return AppLocalizations.get('next_step_good');
    if (score >= 55) return AppLocalizations.get('next_step_fair');
    return AppLocalizations.get('next_step_poor');
  }
}
