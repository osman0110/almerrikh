class WellnessData {
  final int fatigue;      // 1–7
  final int stress;       // 1–7
  final int soreness;     // 1–7
  final int sleepQuality; // 1–7
  final int preRpe;       // 1–10
  final bool painToday;
  final String? notes;

  const WellnessData({
    required this.fatigue,
    required this.stress,
    required this.soreness,
    required this.sleepQuality,
    required this.preRpe,
    required this.painToday,
    this.notes,
  });

  int get hooperIndex => fatigue + stress + soreness + sleepQuality;

  String get hooperStatus {
    if (hooperIndex <= 10) return 'normal';
    if (hooperIndex <= 16) return 'moderate';
    return 'high_risk';
  }

  String get recommendation {
    if (hooperIndex >= 17) return 'Recovery recommended. Consider a lighter session today.';
    if (hooperIndex >= 11) return 'Moderate fatigue detected. Reduce intensity by ~20%.';
    return 'Good readiness. Proceed with planned session.';
  }

  String get recommendationAr {
    if (hooperIndex >= 17) return 'يُنصح بجلسة استشفاء اليوم وتخفيف الحمل.';
    if (hooperIndex >= 11) return 'تعب متوسط — قلّل الشدة بنسبة 20%.';
    return 'جاهز للتدريب. تابع كما هو مخطط.';
  }
}

class PostTrainingData {
  final int postRpe;          // 1–10
  final bool painAfter;
  final String difficulty;    // easy | good | hard | too_hard
  final int mood;             // 1–5
  final String? notes;

  const PostTrainingData({
    required this.postRpe,
    required this.painAfter,
    required this.difficulty,
    required this.mood,
    this.notes,
  });

  String get nextSessionRecommendationAr {
    if (postRpe >= 8) return 'الجلسة القادمة يجب أن تكون أخف نسبياً.';
    if (postRpe <= 3) return 'يمكنك زيادة الشدة في الجلسة القادمة.';
    return 'استمر على نفس الإيقاع.';
  }
}
