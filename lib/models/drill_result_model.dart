class DrillResultModel {
  const DrillResultModel({
    required this.drillId,
    required this.totalReps,
    required this.misses,
    required this.score,
    required this.accuracy,
    this.averageReactionTime,
  });

  final String drillId;
  final int totalReps;
  final int misses;
  final int score;
  final double accuracy;
  final Duration? averageReactionTime;
}
