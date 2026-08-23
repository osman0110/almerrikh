class MetricFormatter {
  const MetricFormatter._();

  static const unavailable = 'غير متوفر';
  static const insufficientData = 'بيانات غير كافية';
  static const incompleteData = 'بيانات ناقصة';

  static String number(
    num? value, {
    required int digits,
    String unit = '',
    bool zeroIsUnavailable = false,
  }) {
    final numeric = value?.toDouble();
    if (numeric == null ||
        !numeric.isFinite ||
        (zeroIsUnavailable && numeric == 0)) {
      return unavailable;
    }
    final formatted = numeric.toStringAsFixed(digits);
    return unit.isEmpty ? formatted : '$formatted $unit';
  }

  static String weight(num? value) => number(value, digits: 1, unit: 'كجم');

  static String height(num? value) => number(value, digits: 0, unit: 'سم');

  static String skinfold(num? value) => number(value, digits: 1, unit: 'مم');

  static String bodyFat(num? value) {
    final formatted = number(value, digits: 2);
    return formatted == unavailable ? formatted : '$formatted%';
  }

  static String fatMass(num? value) => number(value, digits: 2, unit: 'كجم');

  static String fatFreeMass(num? value) =>
      number(value, digits: 2, unit: 'كجم');

  static String bmi(num? value) => number(value, digits: 1);

  static String rpe(num? value) => number(value, digits: 1);

  static String load(num? value) => number(value, digits: 0, unit: 'CE');

  static String loadValue(num? value) => number(value, digits: 0);

  static String average(num? value) => number(value, digits: 2);

  static String standardDeviation(num? value) => number(value, digits: 2);

  static String monotony(num? value) => number(value, digits: 2);

  static String strain(num? value) => number(value, digits: 2);

  static String acwr(num? value) => number(value, digits: 2);

  static String duration(int? value) =>
      value == null ? unavailable : '$value دقيقة';

  static String delta(num? value, {required int digits, String unit = ''}) {
    if (value == null || !value.toDouble().isFinite) return unavailable;
    final sign = value > 0 ? '+' : '';
    final formatted = '$sign${value.toStringAsFixed(digits)}';
    if (unit == '%') return '$formatted%';
    return unit.isEmpty ? formatted : '$formatted $unit';
  }
}
