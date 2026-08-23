double? _bodyDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

int? _bodyInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

class BodyCompositionDelta {
  final double? weightKg;
  final double? bodyFatPercentage;
  final double? fatMassKg;
  final double? fatFreeMassKg;
  final double? skinfoldSumMm;
  final String? previousDate;

  BodyCompositionDelta({
    this.weightKg,
    this.bodyFatPercentage,
    this.fatMassKg,
    this.fatFreeMassKg,
    this.skinfoldSumMm,
    this.previousDate,
  });

  factory BodyCompositionDelta.fromJson(Map<String, dynamic> j) =>
      BodyCompositionDelta(
        weightKg: _bodyDouble(j['weight_kg']),
        bodyFatPercentage: _bodyDouble(j['body_fat_percentage']),
        fatMassKg: _bodyDouble(j['fat_mass_kg']),
        fatFreeMassKg: _bodyDouble(j['fat_free_mass_kg']),
        skinfoldSumMm: _bodyDouble(j['skinfold_sum_mm']),
        previousDate: j['previous_date'] as String?,
      );
}

class BodyCompositionGoalStatus {
  final double? targetWeightKg;
  final double? targetBodyFatPercentage;
  final double? targetFatMassKg;
  final String? targetDate;
  final int? daysRemaining;
  final String status; // on_track | needs_follow_up | behind | achieved

  BodyCompositionGoalStatus({
    this.targetWeightKg,
    this.targetBodyFatPercentage,
    this.targetFatMassKg,
    this.targetDate,
    this.daysRemaining,
    required this.status,
  });

  factory BodyCompositionGoalStatus.fromJson(Map<String, dynamic> j) =>
      BodyCompositionGoalStatus(
        targetWeightKg: _bodyDouble(j['target_weight_kg']),
        targetBodyFatPercentage: _bodyDouble(j['target_body_fat_percentage']),
        targetFatMassKg: _bodyDouble(j['target_fat_mass_kg']),
        targetDate: j['target_date'] as String?,
        daysRemaining: _bodyInt(j['days_remaining']),
        status: j['status'] as String? ?? 'on_track',
      );
}

class BodyCompositionGoal {
  final String id;
  final String linkedPlayerId;
  final double? targetWeightKg;
  final double? targetBodyFatPercentage;
  final double? targetFatMassKg;
  final double? minAcceptableBodyFat;
  final double? maxAcceptableBodyFat;
  final String? targetDate;
  final String? notes;

  BodyCompositionGoal({
    required this.id,
    required this.linkedPlayerId,
    this.targetWeightKg,
    this.targetBodyFatPercentage,
    this.targetFatMassKg,
    this.minAcceptableBodyFat,
    this.maxAcceptableBodyFat,
    this.targetDate,
    this.notes,
  });

  factory BodyCompositionGoal.fromJson(Map<String, dynamic> j) =>
      BodyCompositionGoal(
        id: j['id'] as String? ?? '',
        linkedPlayerId: j['linked_player_id'] as String? ?? '',
        targetWeightKg: _bodyDouble(j['target_weight_kg']),
        targetBodyFatPercentage: _bodyDouble(j['target_body_fat_percentage']),
        targetFatMassKg: _bodyDouble(j['target_fat_mass_kg']),
        minAcceptableBodyFat: _bodyDouble(j['min_acceptable_body_fat']),
        maxAcceptableBodyFat: _bodyDouble(j['max_acceptable_body_fat']),
        targetDate: j['target_date'] as String?,
        notes: j['notes'] as String?,
      );
}

class BodyCompositionEntry {
  final String id;
  final String? linkedPlayerId;
  final String? playerName;
  final String? playerPhotoUrl;
  final String? teamName;
  final String? position;
  final String assessmentDate;
  final String? assessmentTime;
  final String assessmentType;
  final double heightCm;
  final double weightKg;
  final int? ageAtAssessment;

  final double? bicepsMm;
  final double? tricepsMm;
  final double? subscapularMm;
  final double? suprailiacMm;
  final double? skinfoldSumMm;

  final String? calculationFormulaCode;
  final String? calculationAgeGroup;
  final double? bodyFatPercentage;
  final double? fatMassKg;
  final double? fatFreeMassKg;
  final double? bmi;

  final String? notes;
  final String? assessedBy;
  final String sourceSystem;
  final bool isLegacy;
  final bool readOnly;
  final String approvalStatus;
  final String calculationStatus;

  final BodyCompositionDelta? delta;
  final BodyCompositionGoalStatus? goalStatus;

  BodyCompositionEntry({
    required this.id,
    this.linkedPlayerId,
    this.playerName,
    this.playerPhotoUrl,
    this.teamName,
    this.position,
    required this.assessmentDate,
    this.assessmentTime,
    required this.assessmentType,
    required this.heightCm,
    required this.weightKg,
    this.ageAtAssessment,
    this.bicepsMm,
    this.tricepsMm,
    this.subscapularMm,
    this.suprailiacMm,
    this.skinfoldSumMm,
    this.calculationFormulaCode,
    this.calculationAgeGroup,
    this.bodyFatPercentage,
    this.fatMassKg,
    this.fatFreeMassKg,
    this.bmi,
    this.notes,
    this.assessedBy,
    this.sourceSystem = 'NEW_SYSTEM',
    this.isLegacy = false,
    this.readOnly = false,
    this.approvalStatus = 'draft',
    this.calculationStatus = 'complete',
    this.delta,
    this.goalStatus,
  });

  factory BodyCompositionEntry.fromJson(Map<String, dynamic> j) =>
      BodyCompositionEntry(
        id: j['id'] as String? ?? '',
        linkedPlayerId: j['linked_player_id'] as String?,
        playerName: j['player_name'] as String?,
        playerPhotoUrl: j['player_photo_url'] as String?,
        teamName: j['team_name'] as String?,
        position: j['position'] as String?,
        assessmentDate: j['assessment_date'] as String? ?? '',
        assessmentTime: j['assessment_time'] as String?,
        assessmentType: j['assessment_type'] as String? ?? 'periodic',
        heightCm: _bodyDouble(j['height_cm']) ?? 0,
        weightKg: _bodyDouble(j['weight_kg']) ?? 0,
        ageAtAssessment: _bodyInt(j['age_at_assessment']),
        bicepsMm: _bodyDouble(j['biceps_mm']),
        tricepsMm: _bodyDouble(j['triceps_mm']),
        subscapularMm: _bodyDouble(j['subscapular_mm']),
        suprailiacMm: _bodyDouble(j['suprailiac_mm']),
        skinfoldSumMm: _bodyDouble(j['skinfold_sum_mm']),
        calculationFormulaCode: j['calculation_formula_code'] as String?,
        calculationAgeGroup: j['calculation_age_group'] as String?,
        bodyFatPercentage: _bodyDouble(j['body_fat_percentage']),
        fatMassKg: _bodyDouble(j['fat_mass_kg']),
        fatFreeMassKg: _bodyDouble(j['fat_free_mass_kg']),
        bmi: _bodyDouble(j['bmi']),
        notes: j['notes'] as String?,
        assessedBy: j['assessed_by'] as String?,
        sourceSystem: j['source_system'] as String? ?? 'NEW_SYSTEM',
        isLegacy: j['is_legacy'] as bool? ?? false,
        readOnly: j['read_only'] as bool? ?? false,
        approvalStatus: j['approval_status'] as String? ?? 'draft',
        calculationStatus: j['calculation_status'] as String? ?? 'complete',
        delta: j['delta'] != null
            ? BodyCompositionDelta.fromJson(j['delta'] as Map<String, dynamic>)
            : null,
        goalStatus: j['goal_status'] != null
            ? BodyCompositionGoalStatus.fromJson(
                j['goal_status'] as Map<String, dynamic>,
              )
            : null,
      );
}

class BodyCompositionCompareRow {
  final String label;
  final double? start;
  final double? end;
  final double? diff;
  final double? pctChange;

  BodyCompositionCompareRow({
    required this.label,
    this.start,
    this.end,
    this.diff,
    this.pctChange,
  });

  factory BodyCompositionCompareRow.fromJson(Map<String, dynamic> j) =>
      BodyCompositionCompareRow(
        label: j['label'] as String? ?? '',
        start: _bodyDouble(j['start']),
        end: _bodyDouble(j['end']),
        diff: _bodyDouble(j['diff']),
        pctChange: _bodyDouble(j['pct_change']),
      );
}

class TeamBodyCompositionSummary {
  final int rosterSize;
  final int measuredThisMonth;
  final int overdueCount;
  final double? avgWeightKg;
  final double? avgBodyFatPercentage;
  final double? avgFatMassKg;
  final double? avgFatFreeMassKg;
  final int inGoalCount;
  final int needsFollowUpCount;
  final Map<String, dynamic>? biggestImprovement;
  final Map<String, dynamic>? biggestRegression;

  TeamBodyCompositionSummary({
    required this.rosterSize,
    required this.measuredThisMonth,
    required this.overdueCount,
    this.avgWeightKg,
    this.avgBodyFatPercentage,
    this.avgFatMassKg,
    this.avgFatFreeMassKg,
    required this.inGoalCount,
    required this.needsFollowUpCount,
    this.biggestImprovement,
    this.biggestRegression,
  });

  factory TeamBodyCompositionSummary.fromJson(Map<String, dynamic> j) =>
      TeamBodyCompositionSummary(
        rosterSize: _bodyInt(j['roster_size']) ?? 0,
        measuredThisMonth: _bodyInt(j['measured_this_month']) ?? 0,
        overdueCount: _bodyInt(j['overdue_count']) ?? 0,
        avgWeightKg: _bodyDouble(j['avg_weight_kg']),
        avgBodyFatPercentage: _bodyDouble(j['avg_body_fat_percentage']),
        avgFatMassKg: _bodyDouble(j['avg_fat_mass_kg']),
        avgFatFreeMassKg: _bodyDouble(j['avg_fat_free_mass_kg']),
        inGoalCount: _bodyInt(j['in_goal_count']) ?? 0,
        needsFollowUpCount: _bodyInt(j['needs_follow_up_count']) ?? 0,
        biggestImprovement: j['biggest_improvement'] as Map<String, dynamic>?,
        biggestRegression: j['biggest_regression'] as Map<String, dynamic>?,
      );
}
