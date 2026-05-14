enum SquatPhase { standing, descent, bottom, ascent }

class SquatRepMetrics {
  const SquatRepMetrics({
    required this.phases,
    required this.minKneeAngle,
    required this.descentFrameCount,
    required this.bottomFrameCount,
    required this.ascentFrameCount,
    required this.bottomSymmetryDelta,
    required this.repDetected,
  });

  final List<SquatPhase> phases;
  final double minKneeAngle;
  final int descentFrameCount;
  final int bottomFrameCount;
  final int ascentFrameCount;
  final double bottomSymmetryDelta;
  final bool repDetected;

  bool get hasValidPhases => descentFrameCount > 0 && bottomFrameCount > 0 && ascentFrameCount > 0;
}

class SquatPhaseDetector {
  static SquatRepMetrics detectPhases(
    List<double> leftKneeAngles,
    List<double> rightKneeAngles,
  ) {
    if (leftKneeAngles.isEmpty || rightKneeAngles.isEmpty) {
      return SquatRepMetrics(
        phases: [],
        minKneeAngle: 0,
        descentFrameCount: 0,
        bottomFrameCount: 0,
        ascentFrameCount: 0,
        bottomSymmetryDelta: 0,
        repDetected: false,
      );
    }

    final length = leftKneeAngles.length;

    // Compute average knee angle (both legs)
    final avgAngles = List<double>.generate(
      length,
      (i) => (leftKneeAngles[i] + rightKneeAngles[i]) / 2,
    );

    // Apply 5-frame rolling average to smooth noise
    final smoothed = _smoothAngles(avgAngles, windowSize: 5);

    // Find global minimum (bottom of squat)
    double minAngle = double.infinity;
    int minIndex = -1;
    for (int i = 0; i < smoothed.length; i++) {
      if (smoothed[i] < minAngle) {
        minAngle = smoothed[i];
        minIndex = i;
      }
    }

    if (minIndex == -1 || minAngle > 155) {
      // No valid squat detected (knee never bent enough)
      return SquatRepMetrics(
        phases: List.filled(length, SquatPhase.standing),
        minKneeAngle: minAngle,
        descentFrameCount: 0,
        bottomFrameCount: 0,
        ascentFrameCount: 0,
        bottomSymmetryDelta: 0,
        repDetected: false,
      );
    }

    // Classify frames into phases
    final phases = List<SquatPhase>.filled(length, SquatPhase.standing);
    final descentIndices = <int>[];
    final bottomIndices = <int>[];
    final ascentIndices = <int>[];

    // Descent: frames before bottom where angle is decreasing >= 3°/frame
    for (int i = 0; i < minIndex; i++) {
      if (i == 0 || smoothed[i] < smoothed[i - 1] - 3) {
        phases[i] = SquatPhase.descent;
        descentIndices.add(i);
      }
    }

    // Bottom: frames near minimum (within 10° of min)
    for (int i = 0; i < length; i++) {
      if ((smoothed[i] - minAngle).abs() <= 10) {
        phases[i] = SquatPhase.bottom;
        bottomIndices.add(i);
      }
    }

    // Ascent: frames after bottom where angle is increasing >= 3°/frame
    for (int i = minIndex + 1; i < length; i++) {
      if (smoothed[i] > smoothed[i - 1] + 3) {
        phases[i] = SquatPhase.ascent;
        ascentIndices.add(i);
      }
    }

    // Compute bottom symmetry delta (L/R knee diff at bottom frames)
    double bottomSymmetryDelta = 0;
    if (bottomIndices.isNotEmpty) {
      final bottomDeltas = bottomIndices
          .map((i) => (leftKneeAngles[i] - rightKneeAngles[i]).abs())
          .toList();
      bottomSymmetryDelta = bottomDeltas.reduce((a, b) => a + b) / bottomDeltas.length;
    }

    final repDetected = descentIndices.isNotEmpty && bottomIndices.isNotEmpty && ascentIndices.isNotEmpty;

    return SquatRepMetrics(
      phases: phases,
      minKneeAngle: minAngle,
      descentFrameCount: descentIndices.length,
      bottomFrameCount: bottomIndices.length,
      ascentFrameCount: ascentIndices.length,
      bottomSymmetryDelta: bottomSymmetryDelta,
      repDetected: repDetected,
    );
  }

  static List<double> _smoothAngles(List<double> angles, {int windowSize = 5}) {
    if (angles.isEmpty) return [];
    if (windowSize <= 1) return angles;

    final smoothed = <double>[];
    final half = windowSize ~/ 2;

    for (int i = 0; i < angles.length; i++) {
      final start = (i - half).clamp(0, angles.length - 1);
      final end = (i + half + 1).clamp(0, angles.length);
      final window = angles.sublist(start, end);
      final avg = window.reduce((a, b) => a + b) / window.length;
      smoothed.add(avg);
    }

    return smoothed;
  }
}
