import 'package:flutter_test/flutter_test.dart';
import 'package:smart_sport_scribe_main/utils/metric_formatter.dart';

void main() {
  test('uses the approved fitness precision and units', () {
    expect(MetricFormatter.weight(75.54), '75.5 كجم');
    expect(MetricFormatter.height(180.4), '180 سم');
    expect(MetricFormatter.skinfold(10.14), '10.1 مم');
    expect(MetricFormatter.bodyFat(16.155), '16.16%');
    expect(MetricFormatter.fatMass(12.195), '12.20 كجم');
    expect(MetricFormatter.fatFreeMass(63.295), '63.30 كجم');
    expect(MetricFormatter.rpe(6.45), '6.5');
    expect(MetricFormatter.load(390), '390 CE');
    expect(MetricFormatter.average(55.714), '55.71');
    expect(MetricFormatter.standardDeviation(147.406), '147.41');
    expect(MetricFormatter.monotony(0.3779), '0.38');
    expect(MetricFormatter.strain(147.406), '147.41');
    expect(MetricFormatter.acwr(1.236), '1.24');
  });

  test('never converts missing values to zero', () {
    expect(MetricFormatter.bodyFat(null), MetricFormatter.unavailable);
    expect(
      MetricFormatter.number(0, digits: 1, zeroIsUnavailable: true),
      MetricFormatter.unavailable,
    );
    expect(MetricFormatter.duration(null), MetricFormatter.unavailable);
  });
}
