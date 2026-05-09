class AIPlan {
  AIPlan({
    required this.id,
    required this.weekNumber,
    required this.focus,
    required this.days,
  });

  final String id;
  final int weekNumber;
  final String focus;
  final List<PlanDay> days;

  factory AIPlan.fromJson(Map<String, dynamic> json) {
    return AIPlan(
      id: json['id'] as String? ?? '',
      weekNumber: json['weekNumber'] as int? ?? 1,
      focus: json['focus'] as String? ?? '',
      days: (json['days'] as List<dynamic>?)
              ?.map((e) => PlanDay.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class PlanDay {
  PlanDay({
    required this.dayName,
    required this.title,
    required this.durationMinutes,
    required this.drills,
  });

  final String dayName;
  final String title;
  final int durationMinutes;
  final List<PlanDrill> drills;

  factory PlanDay.fromJson(Map<String, dynamic> json) {
    return PlanDay(
      dayName: json['dayName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      durationMinutes: json['durationMinutes'] as int? ?? 0,
      drills: (json['drills'] as List<dynamic>?)
              ?.map((e) => PlanDrill.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class PlanDrill {
  PlanDrill({required this.id, required this.name, required this.durationMinutes});
  final String id;
  final String name;
  final int durationMinutes;

  factory PlanDrill.fromJson(Map<String, dynamic> json) => PlanDrill(id: json['id'] as String? ?? '', name: json['name'] as String? ?? '', durationMinutes: json['durationMinutes'] as int? ?? 0);
}