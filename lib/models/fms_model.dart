import 'package:flutter/material.dart';

/// The 7 FMS (Functional Movement Screen) movements. Each is scored 0-3;
/// bilateral movements are scored per side and the final score is the
/// weaker side (per official FMS rules) — a positive pain flag on the
/// movement's clearing test forces a final score of 0 regardless.
enum FmsMovement {
  deepSquat,
  hurdleStep,
  inlineLunge,
  shoulderMobility,
  activeStraightLegRaise,
  trunkStabilityPushup,
  rotaryStability,
}

extension FmsMovementExt on FmsMovement {
  String get id {
    switch (this) {
      case FmsMovement.deepSquat: return 'deep_squat';
      case FmsMovement.hurdleStep: return 'hurdle_step';
      case FmsMovement.inlineLunge: return 'inline_lunge';
      case FmsMovement.shoulderMobility: return 'shoulder_mobility';
      case FmsMovement.activeStraightLegRaise: return 'active_straight_leg_raise';
      case FmsMovement.trunkStabilityPushup: return 'trunk_stability_pushup';
      case FmsMovement.rotaryStability: return 'rotary_stability';
    }
  }

  String get label {
    switch (this) {
      case FmsMovement.deepSquat: return 'القرفصاء العميق (Deep Squat)';
      case FmsMovement.hurdleStep: return 'خطوة الحاجز (Hurdle Step)';
      case FmsMovement.inlineLunge: return 'الاندفاع المستقيم (Inline Lunge)';
      case FmsMovement.shoulderMobility: return 'مرونة الكتف (Shoulder Mobility)';
      case FmsMovement.activeStraightLegRaise: return 'رفع الساق المستقيمة (ASLR)';
      case FmsMovement.trunkStabilityPushup: return 'ثبات الجذع (Push-Up)';
      case FmsMovement.rotaryStability: return 'الثبات الدوراني (Rotary Stability)';
    }
  }

  bool get isBilateral => this != FmsMovement.deepSquat && this != FmsMovement.trunkStabilityPushup;

  /// English name shown alongside the Arabic label per exercise card.
  String get nameEn {
    switch (this) {
      case FmsMovement.deepSquat: return 'Deep Squat';
      case FmsMovement.hurdleStep: return 'Hurdle Step';
      case FmsMovement.inlineLunge: return 'Inline Lunge';
      case FmsMovement.shoulderMobility: return 'Shoulder Mobility';
      case FmsMovement.activeStraightLegRaise: return 'Active Straight-Leg Raise';
      case FmsMovement.trunkStabilityPushup: return 'Trunk Stability Push-Up';
      case FmsMovement.rotaryStability: return 'Rotary Stability';
    }
  }

  String get nameAr {
    switch (this) {
      case FmsMovement.deepSquat: return 'القرفصاء العميق';
      case FmsMovement.hurdleStep: return 'تخطي الحاجز';
      case FmsMovement.inlineLunge: return 'الاندفاع الخطي';
      case FmsMovement.shoulderMobility: return 'مرونة الكتف';
      case FmsMovement.activeStraightLegRaise: return 'رفع الساق المستقيمة';
      case FmsMovement.trunkStabilityPushup: return 'ضغط ثبات الجذع';
      case FmsMovement.rotaryStability: return 'الثبات الدوراني';
    }
  }

  /// Short performance-cue description shown on the exercise card.
  String get description {
    switch (this) {
      case FmsMovement.deepSquat:
        return 'يقيس التناسق الحركي والثبات والمرونة الثنائية للكتفين والوركين والكاحلين أثناء القرفصاء الكامل.';
      case FmsMovement.hurdleStep:
        return 'يقيس ميكانيكا المشي والتوازن وثبات الحوض والجذع أثناء تخطي حاجز بارتفاع الركبة.';
      case FmsMovement.inlineLunge:
        return 'يقيس التوازن والتحكم في الجذع ومرونة الورك والكاحل في وضعية اندفاع على خط مستقيم.';
      case FmsMovement.shoulderMobility:
        return 'يقيس المدى الحركي الطبيعي للكتف مع التنسيق الحركي المتبادل.';
      case FmsMovement.activeStraightLegRaise:
        return 'يقيس مرونة الفخذ الخلفي وعضلة السمانة النشطة مع الحفاظ على ثبات الحوض والجذع.';
      case FmsMovement.trunkStabilityPushup:
        return 'يقيس القدرة على تثبيت العمود الفقري في المستوى الأمامي أثناء حركة دفع أفقية متناظرة.';
      case FmsMovement.rotaryStability:
        return 'يقيس الثبات الدوراني للجذع والحوض والتنسيق الحركي بين الأطراف العلوية والسفلية.';
    }
  }

  /// A simple, deterministic coaching cue derived from the final score and
  /// pain flag — no separate DB field needed since it's a pure function of
  /// (movement, score, pain).
  String recommendationFor(int finalScore, bool pain) {
    if (pain) return 'يوجد ألم — يوصى بالإحالة لتقييم طبي/علاج طبيعي قبل إعادة الاختبار';
    if (finalScore >= 3) return 'أداء ممتاز — حافظ على البرنامج التدريبي الحالي';
    switch (this) {
      case FmsMovement.deepSquat:
        return finalScore == 2
            ? 'يحتاج تحسين مرونة الكاحل والورك (Ankle/Hip Mobility Drills)'
            : 'يحتاج برنامج تصحيحي شامل لمرونة الكتف والورك والكاحل قبل تحميل الحركة';
      case FmsMovement.hurdleStep:
        return finalScore == 2
            ? 'يحتاج تحسين ثبات الحوض أثناء المشي (Single-Leg Stability Work)'
            : 'يحتاج تمارين توازن أساسية وتحكم بالجذع قبل تعقيد الحركة';
      case FmsMovement.inlineLunge:
        return finalScore == 2
            ? 'يحتاج تحسين التوازن والتحكم في الجذع (Split-Stance Stability)'
            : 'يحتاج تمارين تصحيحية للتوازن والمرونة قبل التحميل';
      case FmsMovement.shoulderMobility:
        return finalScore == 2
            ? 'يحتاج تمارين مرونة للكتف (Shoulder Mobility Drills)'
            : 'يحتاج برنامج تصحيحي مكثف لمرونة الكتف والعمود الفقري الصدري';
      case FmsMovement.activeStraightLegRaise:
        return finalScore == 2
            ? 'يحتاج تمارين إطالة للفخذ الخلفي (Hamstring Flexibility)'
            : 'يحتاج برنامج إطالة تدريجي للفخذ الخلفي مع تثبيت الحوض';
      case FmsMovement.trunkStabilityPushup:
        return finalScore == 2
            ? 'يحتاج تقوية عضلات الجذع الأساسية (Core Stability Work)'
            : 'يحتاج برنامج تصحيحي لتقوية الجذع قبل حركات الدفع المحملة';
      case FmsMovement.rotaryStability:
        return finalScore == 2
            ? 'يحتاج تحسين التوازن والتنسيق الدوراني (Rotary Stability Drills)'
            : 'يحتاج تمارين تصحيحية للتوازن والثبات الدوراني والتنسيق الحركي';
    }
  }

  /// Icon-based visual placeholder for the exercise card — no photo assets
  /// are bundled yet; swap for a real pw.Image/Image.asset per exercise_key
  /// once photos are uploaded (see recommendation in FMS section README).
  IconData get placeholderIcon {
    switch (this) {
      case FmsMovement.deepSquat: return Icons.accessibility_new_rounded;
      case FmsMovement.hurdleStep: return Icons.directions_walk_rounded;
      case FmsMovement.inlineLunge: return Icons.directions_run_rounded;
      case FmsMovement.shoulderMobility: return Icons.accessibility_rounded;
      case FmsMovement.activeStraightLegRaise: return Icons.self_improvement_rounded;
      case FmsMovement.trunkStabilityPushup: return Icons.fitness_center_rounded;
      case FmsMovement.rotaryStability: return Icons.sync_alt_rounded;
    }
  }

  static FmsMovement fromId(String id) => FmsMovement.values.firstWhere(
        (m) => m.id == id,
        orElse: () => FmsMovement.deepSquat,
      );
}

class FmsMovementScore {
  const FmsMovementScore({
    required this.movement,
    this.leftScore,
    this.rightScore,
    required this.finalScore,
    this.pain = false,
    this.notes,
  });

  final FmsMovement movement;
  final int? leftScore;
  final int? rightScore;
  final int finalScore;
  final bool pain;
  final String? notes;

  factory FmsMovementScore.fromJson(Map<String, dynamic> j) => FmsMovementScore(
        movement: FmsMovementExt.fromId(j['movement'] as String? ?? ''),
        leftScore: (j['left_score'] as num?)?.toInt(),
        rightScore: (j['right_score'] as num?)?.toInt(),
        finalScore: (j['final_score'] as num?)?.toInt() ?? 0,
        pain: (j['pain'] as bool?) ?? false,
        notes: j['notes'] as String?,
      );
}

class FmsAssessment {
  const FmsAssessment({
    required this.id,
    required this.playerId,
    required this.playerName,
    this.sessionId,
    required this.totalScore,
    this.notes,
    this.assessorName,
    required this.createdAt,
    this.movements = const [],
  });

  final String id;
  final String playerId;
  final String playerName;
  final String? sessionId;
  final int totalScore;
  final String? notes;
  final String? assessorName;
  final DateTime createdAt;
  final List<FmsMovementScore> movements;

  /// Status per the FMS spec: complete once all 7 movements have a row.
  String get status => movements.length >= 7 ? 'مكتمل' : 'غير مكتمل';

  factory FmsAssessment.fromJson(Map<String, dynamic> j) => FmsAssessment(
        id: j['id'] as String? ?? '',
        playerId: j['player_id'] as String? ?? '',
        playerName: j['player_name'] as String? ?? '',
        assessorName: j['assessor_name'] as String?,
        sessionId: j['session_id'] as String?,
        totalScore: (j['total_score'] as num?)?.toInt() ?? 0,
        notes: j['notes'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String) ?? DateTime.now()
            : DateTime.now(),
        movements: (j['movements'] as List<dynamic>? ?? [])
            .map((m) => FmsMovementScore.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
      );
}
