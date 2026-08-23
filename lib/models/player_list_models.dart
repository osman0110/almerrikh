// Player list + detail models — NextKick coach players module

class PlayerSummary {
  final String id;
  final int number;
  final String name;
  final String position;
  final String status; // ready | fatigue | injured | high_risk
  final int readinessPct;
  final int loadPct;
  final int attendancePct;
  final int aiScore;
  final bool injuryFlag;
  final String lastSession;

  const PlayerSummary({
    required this.id,
    required this.number,
    required this.name,
    required this.position,
    required this.status,
    required this.readinessPct,
    required this.loadPct,
    required this.attendancePct,
    required this.aiScore,
    required this.injuryFlag,
    required this.lastSession,
  });

  factory PlayerSummary.fromJson(Map<String, dynamic> j) => PlayerSummary(
        id: j['id']?.toString() ?? '',
        number: j['number'] as int? ?? 0,
        name: j['name'] as String? ?? '',
        position: j['position'] as String? ?? '',
        status: j['status'] as String? ?? 'ready',
        readinessPct: j['readiness_pct'] as int? ?? 0,
        loadPct: j['load_pct'] as int? ?? 0,
        attendancePct: j['attendance_pct'] as int? ?? 0,
        aiScore: j['ai_score'] as int? ?? 0,
        injuryFlag: j['injury_flag'] as bool? ?? false,
        lastSession: j['last_session'] as String? ?? '',
      );

  static const List<PlayerSummary> mockList = [
    PlayerSummary(
        id: '1', number: 10, name: 'أحمد كمال', position: 'ST',
        status: 'injured', readinessPct: 15, loadPct: 88,
        attendancePct: 82, aiScore: 72, injuryFlag: true,
        lastSession: 'تدريب القوة'),
    PlayerSummary(
        id: '2', number: 7, name: 'محمد علي', position: 'CM',
        status: 'high_risk', readinessPct: 35, loadPct: 92,
        attendancePct: 90, aiScore: 68, injuryFlag: false,
        lastSession: 'تدريب التكتيك'),
    PlayerSummary(
        id: '3', number: 4, name: 'إبراهيم حسن', position: 'CB',
        status: 'fatigue', readinessPct: 55, loadPct: 73,
        attendancePct: 88, aiScore: 76, injuryFlag: false,
        lastSession: 'تدريب القوة والسرعة'),
    PlayerSummary(
        id: '4', number: 11, name: 'عمر خالد', position: 'LW',
        status: 'fatigue', readinessPct: 62, loadPct: 67,
        attendancePct: 85, aiScore: 80, injuryFlag: false,
        lastSession: 'تدريب الكرة'),
    PlayerSummary(
        id: '5', number: 14, name: 'وليد علي', position: 'RM',
        status: 'fatigue', readinessPct: 60, loadPct: 69,
        attendancePct: 86, aiScore: 75, injuryFlag: false,
        lastSession: 'تدريب الكرة'),
    PlayerSummary(
        id: '6', number: 9, name: 'خالد عمر', position: 'ST',
        status: 'ready', readinessPct: 86, loadPct: 55,
        attendancePct: 96, aiScore: 88, injuryFlag: false,
        lastSession: 'تدريب القوة والسرعة'),
    PlayerSummary(
        id: '7', number: 3, name: 'عبدالله محمود', position: 'LB',
        status: 'ready', readinessPct: 90, loadPct: 48,
        attendancePct: 100, aiScore: 91, injuryFlag: false,
        lastSession: 'تدريب الكرة'),
    PlayerSummary(
        id: '8', number: 5, name: 'يوسف أحمد', position: 'CDM',
        status: 'ready', readinessPct: 78, loadPct: 58,
        attendancePct: 92, aiScore: 84, injuryFlag: false,
        lastSession: 'تدريب التكتيك'),
    PlayerSummary(
        id: '9', number: 1, name: 'محمد الأمين', position: 'GK',
        status: 'ready', readinessPct: 88, loadPct: 42,
        attendancePct: 98, aiScore: 86, injuryFlag: false,
        lastSession: 'تدريب الحراسة'),
    PlayerSummary(
        id: '10', number: 17, name: 'سامي النور', position: 'RW',
        status: 'ready', readinessPct: 84, loadPct: 60,
        attendancePct: 94, aiScore: 82, injuryFlag: false,
        lastSession: 'تدريب القوة والسرعة'),
    PlayerSummary(
        id: '11', number: 6, name: 'أنس طارق', position: 'CB',
        status: 'ready', readinessPct: 80, loadPct: 52,
        attendancePct: 90, aiScore: 78, injuryFlag: false,
        lastSession: 'تدريب التكتيك'),
    PlayerSummary(
        id: '12', number: 8, name: 'حسن الرشيد', position: 'CM',
        status: 'ready', readinessPct: 82, loadPct: 50,
        attendancePct: 96, aiScore: 85, injuryFlag: false,
        lastSession: 'تدريب القوة والسرعة'),
  ];
}

class PlayerListSummary {
  final int total;
  final int ready;
  final int fatigue;
  final int injured;
  final int highRisk;

  const PlayerListSummary({
    required this.total,
    required this.ready,
    required this.fatigue,
    required this.injured,
    required this.highRisk,
  });

  factory PlayerListSummary.fromPlayers(List<PlayerSummary> players) =>
      PlayerListSummary(
        total: players.length,
        ready: players.where((p) => p.status == 'ready').length,
        fatigue: players.where((p) => p.status == 'fatigue').length,
        injured: players.where((p) => p.status == 'injured').length,
        highRisk: players.where((p) => p.status == 'high_risk').length,
      );
}

class PlayerFull {
  final String id;
  final int number;
  final String name;
  final String position;
  final int age;
  final int heightCm;
  final double weightKg;
  final String status;
  final int readinessPct;
  final int loadPct;
  final int attendancePct;
  final int aiScore;
  // Wellness
  final int sleep;
  final int fatigueScore;
  final int soreness;
  final int mood;
  final int hooperIndex;
  final int rpeBefore;
  final int rpeAfter;
  // Training load — null means api/coach/players.php has no data for this
  // player yet (it does not currently compute these); show a clear "no data"
  // state in the UI rather than a misleading zero.
  final int? weeklyLoad;
  final int? acuteLoad;
  final int? chronicLoad;
  final double? acwr;
  // Injury
  final String injuryStatus; // none | injured | recovering
  final String? injuryBodyPart;
  final String? injurySeverity;
  final String recommendation;
  // Attendance
  final int attendanceLast30;
  final int sessionsAttended;
  final int absences;
  final int lateCount;
  // AI Assessment
  final String aiLastTest;
  final int aiTestScore;
  final String aiSummary;

  const PlayerFull({
    required this.id,
    required this.number,
    required this.name,
    required this.position,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.status,
    required this.readinessPct,
    required this.loadPct,
    required this.attendancePct,
    required this.aiScore,
    required this.sleep,
    required this.fatigueScore,
    required this.soreness,
    required this.mood,
    required this.hooperIndex,
    required this.rpeBefore,
    required this.rpeAfter,
    this.weeklyLoad,
    this.acuteLoad,
    this.chronicLoad,
    this.acwr,
    required this.injuryStatus,
    this.injuryBodyPart,
    this.injurySeverity,
    required this.recommendation,
    required this.attendanceLast30,
    required this.sessionsAttended,
    required this.absences,
    required this.lateCount,
    required this.aiLastTest,
    required this.aiTestScore,
    required this.aiSummary,
  });

  factory PlayerFull.fromApiJson(Map<String, dynamic> j) {
    final status     = j['status'] as String? ?? 'ready';
    final isInjured  = status == 'injured';
    final aiScore    = j['ai_score'] as int? ?? 0;
    final injNotes   = j['injury_notes'] as String?;
    return PlayerFull(
      id:             j['id']?.toString() ?? '',
      number:         j['number'] as int? ?? 0,
      name:           j['name'] as String? ?? '',
      position:       j['position'] as String? ?? '—',
      age:            j['age'] as int? ?? 0,
      heightCm:       j['height_cm'] as int? ?? 0,
      weightKg:       (j['weight_kg'] as num?)?.toDouble() ?? 0,
      status:         status,
      readinessPct:   j['readiness_pct'] as int? ?? (isInjured ? 20 : 80),
      loadPct:        j['load_pct'] as int? ?? 50,
      attendancePct:  j['attendance_pct'] as int? ?? 85,
      aiScore:        aiScore,
      sleep:          0,
      fatigueScore:   0,
      soreness:       0,
      mood:           0,
      hooperIndex:    0,
      rpeBefore:      0,
      rpeAfter:       0,
      weeklyLoad:     (j['weekly_load'] as num?)?.toInt(),
      acuteLoad:      (j['acute_load'] as num?)?.toInt(),
      chronicLoad:    (j['chronic_load'] as num?)?.toInt(),
      acwr:           (j['acwr'] as num?)?.toDouble(),
      injuryStatus:   isInjured ? 'injured' : 'none',
      injuryBodyPart: isInjured && injNotes != null ? injNotes : null,
      injurySeverity: null,
      recommendation: isInjured
          ? 'مراجعة الجهاز الطبي'
          : (aiScore < 60 ? 'تحتاج إلى تحسين الأداء الحركي' : 'جاهز للتدريب'),
      attendanceLast30:   85,
      sessionsAttended:   0,
      absences:           0,
      lateCount:          0,
      aiLastTest:         j['ai_type'] as String? ?? '—',
      aiTestScore:        aiScore,
      aiSummary:          aiScore >= 85
          ? 'الحركة مستقرة وممتازة'
          : (aiScore >= 70
              ? 'الحركة جيدة مع ملاحظة في الاتزان'
              : (aiScore > 0 ? 'تحتاج الحركة إلى تحسين في الاستقرار' : 'لا يوجد تقييم حركي بعد')),
    );
  }
}
