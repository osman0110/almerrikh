import 'dart:math' as math;

/// Live-preview mirror of api/includes/body_composition_calculator.php.
/// Only ever used for instant UI feedback before saving — the backend's
/// computed result from save.php/update.php is always what gets persisted
/// and displayed afterward, so this and the PHP version drifting slightly
/// is not a correctness risk, only a preview-accuracy one.
class BodyCompositionFormula {
  final String code;
  final String name;
  final int minAge;
  final int maxAge;
  final double coefficientA;
  final double coefficientB;

  const BodyCompositionFormula({
    required this.code,
    required this.name,
    required this.minAge,
    required this.maxAge,
    required this.coefficientA,
    required this.coefficientB,
  });
}

class BodyCompositionCalculator {
  static const double attemptSpreadLimitMm = 2.0;

  static const List<BodyCompositionFormula> _formulas = [
    BodyCompositionFormula(code: 'age_17_19', name: 'Durnin-Womersley 17-19', minAge: 17, maxAge: 19, coefficientA: 27.409, coefficientB: -26.789),
    BodyCompositionFormula(code: 'age_20_29', name: 'Durnin-Womersley 20-29', minAge: 20, maxAge: 29, coefficientA: 27.775, coefficientB: -27.203),
    BodyCompositionFormula(code: 'age_30_39', name: 'Durnin-Womersley 30-39', minAge: 30, maxAge: 39, coefficientA: 26.781, coefficientB: -27.203),
  ];

  static double log10(double x) => math.log(x) / math.ln10;

  static int? calcAge(DateTime dob, DateTime assessmentDate) {
    if (assessmentDate.isBefore(dob)) return null;
    int age = assessmentDate.year - dob.year;
    final hadBirthdayThisYear = (assessmentDate.month > dob.month) ||
        (assessmentDate.month == dob.month && assessmentDate.day >= dob.day);
    if (!hadBirthdayThisYear) age--;
    return age;
  }

  static double? averageAttempts(List<double?> attempts) {
    final vals = attempts.whereType<double>().toList();
    if (vals.isEmpty) return null;
    return double.parse((vals.reduce((a, b) => a + b) / vals.length).toStringAsFixed(1));
  }

  static bool attemptSpreadFlag(List<double?> attempts) {
    final vals = attempts.whereType<double>().toList();
    if (vals.length < 2) return false;
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    final minV = vals.reduce((a, b) => a < b ? a : b);
    return (maxV - minV) > attemptSpreadLimitMm;
  }

  static BodyCompositionFormula? selectFormula(int age) {
    for (final f in _formulas) {
      if (age >= f.minAge && age <= f.maxAge) return f;
    }
    return null;
  }

  /// Returns null if no formula covers this age — caller should show
  /// "unsupported age band" rather than a fabricated number.
  static double? calculateBodyFatPercentage(double skinfoldSum, int age) {
    if (skinfoldSum <= 0) return null;
    final formula = selectFormula(age);
    if (formula == null) return null;
    final bf = formula.coefficientA * log10(skinfoldSum) + formula.coefficientB;
    return double.parse(bf.toStringAsFixed(2));
  }

  static double bmi(double weightKg, double heightCm) {
    final heightM = heightCm / 100;
    return double.parse((weightKg / (heightM * heightM)).toStringAsFixed(2));
  }

  static double fatMassKg(double weightKg, double bodyFatPercentage) {
    return double.parse((weightKg * bodyFatPercentage / 100).toStringAsFixed(2));
  }

  static double fatFreeMassKg(double weightKg, double fatMassKg) {
    return double.parse((weightKg - fatMassKg).toStringAsFixed(2));
  }
}
