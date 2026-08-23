import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/assessment_result_model.dart';
import '../../models/club_models.dart';
import '../../services/assessment_storage_service.dart';
import '../../services/assessment_video_service.dart';
import '../../services/club_service.dart';
import '../../widgets/assessment_frame_player.dart';
import '../../services/score_interpreter.dart';
import '../../widgets/common_widgets.dart';

class AssessmentResultPage extends StatefulWidget {
  const AssessmentResultPage({
    super.key,
    required this.result,
    this.videoFramesDir,
    this.onNextPlayer,
    this.onRetry,
  });

  final AssessmentResult result;
  /// Folder of locally-captured review frames, if any — deleted once approved.
  final String? videoFramesDir;
  final VoidCallback? onNextPlayer;
  final VoidCallback? onRetry;

  @override
  State<AssessmentResultPage> createState() => _AssessmentResultPageState();
}

class _AssessmentResultPageState extends State<AssessmentResultPage> {
  bool _saving = false;
  bool _saved  = false;
  int? _bestScore;
  double? _averageScore;
  int _attemptCount = 1;

  // ── Coach review/certification ────────────────────────────────────────────
  late String _status;
  int? _editedScore;
  String? _videoFramesDir;
  List<String> _framePaths = [];
  bool _approving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.result.status;
    _videoFramesDir = widget.result.isValidAttempt ? widget.videoFramesDir : null;
    _loadAttemptGroup();
    _loadFrames();
  }

  Future<void> _loadFrames() async {
    final dir = _videoFramesDir;
    if (dir == null) return;
    final frames = await AssessmentVideoService.listFrames(dir);
    if (!mounted) return;
    setState(() => _framePaths = frames);
  }

  bool get _isApproved => _status == 'approved';

  Future<void> _loadAttemptGroup() async {
    final groupId = widget.result.attemptGroupId;
    if (groupId == null || groupId.isEmpty) return;
    try {
      final res = await ApiService.getAssessmentAttemptGroup(groupId);
      if (!mounted) return;
      setState(() {
        _bestScore = res['best_score'] as int?;
        _averageScore = (res['average_score'] as num?)?.toDouble();
        _attemptCount = (res['attempt_count'] as int?) ?? 1;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(AppLocalizations.get('assessment_result_title')),
      ),
      body: SafeArea(
        child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                // Hero score section
                _buildHeroScore(),
                const SizedBox(height: 12),
                if (!widget.result.isValidAttempt) ...[
                  _buildInvalidReasonBanner(),
                  const SizedBox(height: 12),
                ] else ...[
                  _buildReviewSection(),
                  const SizedBox(height: 12),
                ],
                if (_attemptCount > 1) ...[
                  _buildAttemptSummaryCard(),
                  const SizedBox(height: 12),
                ],
                // Score interpretation + coach insight (Phase 1)
                _buildScoreInterpretation(),
                const SizedBox(height: 20),
                // Three metric bars
                _buildMetricBars(),
                const SizedBox(height: 20),
                // Angle metrics table / Jump metrics
                _buildAngleMetricsTable(),
                const SizedBox(height: 20),
                // L/R comparison card for Single Leg Drop Jump
                if (widget.result.testType == AssessmentTestType.singleLegDropJump) ...[
                  _buildLRComparisonCard(),
                  const SizedBox(height: 20),
                ],
                // Issues section
                if (widget.result.issues.isNotEmpty) ...[
                  _buildIssuesSection(),
                  const SizedBox(height: 16),
                ],
                // Recommendations
                if (widget.result.correctionTips.isNotEmpty) ...[
                  _buildRecommendationsSection(),
                  const SizedBox(height: 20),
                ],
                if (widget.onRetry != null) ...[
                  GestureDetector(
                    onTap: widget.onRetry,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.replay_rounded, color: AppColors.foreground, size: 20),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.format('assessment_retry_attempt',
                                  {'n': widget.result.attemptNumber + 1}),
                              style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w900, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (widget.onNextPlayer != null) ...[
                  GestureDetector(
                    onTap: widget.onNextPlayer,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.coachAccent,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.coachAccent.withOpacity(0.35),
                              blurRadius: 14, offset: const Offset(0, 5))
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Arrow direction follows text direction (RTL = left arrow)
                          Icon(
                            Directionality.of(context) == TextDirection.rtl
                                ? Icons.arrow_back_rounded
                                : Icons.arrow_forward_rounded,
                            color: AppColors.foreground, size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.get('next_player'),
                              style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                // Save button: shows spinner while saving, success state when saved
                if (_saving)
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2.5),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _saved ? null : _saveAgain,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 52,
                      decoration: BoxDecoration(
                        color: _saved
                            ? const Color(0xff1A3A28)
                            : AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _saved
                              ? const Color(0xff2DBF6C)
                              : AppColors.primary,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _saved
                                ? Icons.check_circle_rounded
                                : Icons.save_rounded,
                            color: _saved
                                ? const Color(0xff2DBF6C)
                                : AppColors.foreground,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _saved
                                ? AppLocalizations.get('assessment_saved')
                                : AppLocalizations.get('assessment_save_result'),
                            style: TextStyle(
                                color: _saved
                                    ? const Color(0xff2DBF6C)
                                    : AppColors.foreground,
                                fontWeight: FontWeight.w900,
                                fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (kDebugMode && widget.result.debugData.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildDebugPanel(),
                ],
                const SizedBox(height: 16),
              ],
        ),
      ),
    );
  }

  // ── Score interpretation helpers ──────────────────────────────────────────

  static String _scoreStatus(int s) {
    if (s >= 85) return AppLocalizations.get('score_excellent');
    if (s >= 70) return AppLocalizations.get('score_good');
    if (s >= 50) return AppLocalizations.get('score_needs_improvement');
    return AppLocalizations.get('score_at_risk');
  }

  static Color _scoreColor(int s) {
    if (s >= 85) return const Color(0xff2DBF6C);
    if (s >= 70) return Colors.amber;
    if (s >= 50) return Colors.orange;
    return Colors.red;
  }

  // Maps assessment test type to club model type for ScoreInterpreter
  static AssessmentType _mapType(AssessmentTestType t) {
    switch (t) {
      case AssessmentTestType.squat:            return AssessmentType.squat;
      case AssessmentTestType.singleLegBalance: return AssessmentType.singleLegBalance;
      case AssessmentTestType.jumpLanding:      return AssessmentType.jumpLanding;
      // All jump variants share landing mechanics interpretation
      case AssessmentTestType.countermovementJump:
      case AssessmentTestType.squatJump:
      case AssessmentTestType.dropJump:
      case AssessmentTestType.singleLegDropJump:
        return AssessmentType.jumpLanding;
    }
  }

  String _nextStep() {
    final s = widget.result.overallScore;
    if (s < 50) return AppLocalizations.get('next_step_poor');
    if (s < 70) return AppLocalizations.get('next_step_fair');
    if (s < 85) return AppLocalizations.get('next_step_good');
    return AppLocalizations.get('next_step_excellent');
  }

  Widget _buildScoreInterpretation() {
    final score    = widget.result.overallScore;
    final status   = _scoreStatus(score);
    final color    = _scoreColor(score);
    final nextStep = _nextStep();
    final hasIssues = widget.result.issues.isNotEmpty;
    final mainIssue = hasIssues ? widget.result.issues.first : '';

    // ScoreInterpreter provides type-specific headline + details bullets
    final interp = ScoreInterpreter.interpret(
      type:            _mapType(widget.result.testType),
      score:           score.toDouble(),
      movementQuality: widget.result.movementQualityScore.toDouble(),
      stability:       widget.result.stabilityScore.toDouble(),
      symmetry:        widget.result.symmetryScore.toDouble(),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$score / 100',
                style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          // Main issue (if any)
          if (mainIssue.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.muted, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mainIssue,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const Divider(color: AppColors.border, height: 20),
          // Coach insight — from ScoreInterpreter (type-specific)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sports_rounded, color: AppColors.muted, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.get('score_coach_insight'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      interp.headline,
                      style: const TextStyle(color: AppColors.foreground, fontSize: 12, height: 1.4),
                    ),
                    // Type-specific detail bullets (max 2)
                    if (interp.details.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...interp.details.take(2).map((d) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                                Expanded(
                                  child: Text(d,
                                      style: const TextStyle(
                                          color: AppColors.muted, fontSize: 11, height: 1.35)),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Next step
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.arrow_forward_rounded, color: AppColors.muted, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.get('score_recommendation'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextStep,
                      style: const TextStyle(color: AppColors.textSoft, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _invalidReasonLabel(String reason) {
    switch (reason) {
      case 'insufficient_frames':  return 'عدد الإطارات الصالحة غير كافٍ — أعد المحاولة.';
      case 'low_visibility':       return 'رؤية ضعيفة لمفاصل الجسم — أعد المحاولة بإضاءة/زاوية أفضل.';
      case 'movement_not_detected': return 'لم يتم رصد الحركة بوضوح — أعد المحاولة.';
      default: return 'هذه المحاولة غير صالحة ولن تُحتسب ضمن أفضل/متوسط النتائج.';
    }
  }

  Widget _buildInvalidReasonBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_rounded, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'محاولة غير صالحة: ${_invalidReasonLabel(widget.result.invalidReason ?? '')}',
              style: const TextStyle(color: Colors.red, fontSize: 12, height: 1.4, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Coach review: watch capture, edit, certify ────────────────────────────

  Widget _buildReviewSection() {
    final approved = _isApproved;
    final color = approved ? const Color(0xff2DBF6C) : Colors.amber;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(approved ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                  color: color, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  approved
                      ? AppLocalizations.get('assessment_approved_by_coach')
                      : AppLocalizations.get('assessment_pending_coach_review'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_editedScore != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(AppLocalizations.format(
                          'assessment_edited_score', {'score': _editedScore!}),
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
          if (_framePaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            AssessmentFramePlayer(framePaths: _framePaths),
          ],
          if (!approved) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _approving ? null : _openEditScoreDialog,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: Text(AppLocalizations.get('assessment_edit_score_btn')),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.foreground),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _approving ? null : _approve,
                    icon: _approving
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 16),
                    label: Text(AppLocalizations.get('assessment_approve_score_btn')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff2DBF6C),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openEditScoreDialog() async {
    final scoreCtrl = TextEditingController(
        text: (_editedScore ?? widget.result.effectiveScore).toString());
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(AppLocalizations.get('assessment_edit_score_dialog_title'),
            style: const TextStyle(color: AppColors.foreground)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.get('assessment_new_score_label'),
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: scoreCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.foreground),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            Text(AppLocalizations.get('assessment_edit_reason_label'),
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              style: const TextStyle(color: AppColors.foreground),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: AppLocalizations.get('assessment_edit_reason_hint'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.get('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.get('assessment_edit_score_save'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final newScore = int.tryParse(scoreCtrl.text);
    final reason = reasonCtrl.text.trim();
    if (newScore == null || newScore < 0 || newScore > 100 || reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('assessment_edit_score_invalid'))),
      );
      return;
    }

    final ok = await ClubService().overrideAssessmentScore(
      assessmentId: widget.result.id,
      overrideScore: newScore,
      reason: reason,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _editedScore = newScore);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('assessment_score_update_failed'))),
      );
    }
  }

  Future<void> _approve() async {
    setState(() => _approving = true);
    final ok = await ClubService().approveAssessment(widget.result.id);
    if (!mounted) return;
    if (ok) {
      final dir = _videoFramesDir;
      if (dir != null) {
        await AssessmentVideoService.deleteFolder(dir);
      }
      setState(() {
        _status = 'approved';
        _videoFramesDir = null;
        _framePaths = [];
        _approving = false;
      });
    } else {
      setState(() => _approving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('assessment_approve_failed'))),
      );
    }
  }

  Widget _buildAttemptSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _attemptStat('المحاولة', '${widget.result.attemptNumber} / $_attemptCount'),
          ),
          if (_bestScore != null)
            Expanded(child: _attemptStat('الأفضل', '$_bestScore')),
          if (_averageScore != null)
            Expanded(child: _attemptStat('المتوسط', _averageScore!.toStringAsFixed(1))),
        ],
      ),
    );
  }

  Widget _attemptStat(String label, String value) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ],
      );

  Widget _buildHeroScore() {
    final grade = _scoreStatus(widget.result.overallScore);
    final gradeColor = _scoreColor(widget.result.overallScore);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.maroon, AppColors.maroonDark],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            widget.result.playerName,
            style: const TextStyle(color: AppColors.onDarkMuted, fontSize: 14, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  painter: RingPainter(
                    widget.result.overallScore / 100,
                    color: gradeColor,
                  ),
                  size: const Size(140, 140),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${widget.result.overallScore}',
                      style: const TextStyle(
                        color: AppColors.onDark,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      grade,
                      style: TextStyle(
                        color: gradeColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${widget.result.testType.displayName} • ${DateTime.now().toString().split(' ')[0]}',
            style: const TextStyle(color: AppColors.onDarkMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBars() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _metricBar(AppLocalizations.get('assessment_movement_quality'), widget.result.movementQualityScore),
          const SizedBox(height: 16),
          _metricBar(AppLocalizations.get('assessment_stability'), widget.result.stabilityScore),
          const SizedBox(height: 16),
          _metricBar(AppLocalizations.get('assessment_symmetry'), widget.result.symmetryScore),
        ],
      ),
    );
  }

  Widget _metricBar(String label, int score) {
    final color = _scoreColor(score);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSoft, fontSize: 13)),
            Text('$score', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        RoundedProgress(value: score / 100, dark: false),
      ],
    );
  }

  Widget _buildAngleMetricsTable() {
    if (widget.result.angleMetrics.isEmpty) return const SizedBox.shrink();
    final isJump = widget.result.testType.isJumpTest;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppLocalizations.get(isJump ? 'assessment_jump_metrics' : 'assessment_joint_angles'),
                style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 16),
              ),
              if (isJump) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                  ),
                  child: Text(AppLocalizations.get('assessment_camera_estimate'),
                      style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ...widget.result.angleMetrics.entries.map((entry) {
            final value = entry.value;
            final key   = entry.key;
            Color dotColor = AppColors.muted;
            if (key.contains('Trunk') || key.contains('lean')) {
              dotColor = value > 25 ? Colors.red : value > 15 ? Colors.amber : Colors.greenAccent;
            } else if (key.contains('valgus') || key.contains('Valgus')) {
              dotColor = value < 55 ? Colors.red : value < 72 ? Colors.amber : Colors.greenAccent;
            } else if (key.contains('height') || key.contains('Height')) {
              dotColor = value >= 40 ? AppColors.primary : value >= 25 ? Colors.amber : Colors.red;
            }

            // Format value — jump metrics use different units
            final String valStr;
            if (isJump) {
              if (key.contains('cm')) {
                valStr = '${value.toStringAsFixed(1)} cm';
              } else if (key.contains('ms')) {
                valStr = '${value.toStringAsFixed(0)} ms';
              } else if (key.contains('score') || key.contains('stability')) {
                valStr = '${value.toStringAsFixed(0)}/100';
              } else if (key.contains('Δ') || key.contains('delta')) {
                valStr = '${value.toStringAsFixed(1)}°';
              } else {
                valStr = value.toStringAsFixed(1);
              }
            } else {
              valStr = '${value.toStringAsFixed(0)}°';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(key, style: const TextStyle(color: AppColors.textSoft, fontSize: 13)),
                  ),
                  Text(valStr, style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildIssuesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.get('assessment_issues_title'),
          style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 12),
        ...widget.result.issues.map((issue) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      issue,
                      style: const TextStyle(color: AppColors.foreground, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRecommendationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.get('assessment_drills_title'),
          style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 12),
        ...List.generate(widget.result.correctionTips.length, (i) {
          final tip = widget.result.correctionTips[i];
          final drill = i < widget.result.recommendedDrills.length ? widget.result.recommendedDrills[i] : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${i + 1}.',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tip,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (drill.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Protocol: $drill',
                        style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDebugPanel() {
    final d = widget.result.debugData;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellow.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DEBUG', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2)),
          const SizedBox(height: 8),
          ...d.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(child: Text(e.key, style: const TextStyle(color: Colors.white54, fontSize: 11))),
                Text(e.value.toStringAsFixed(2), style: const TextStyle(color: Colors.yellow, fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Future<void> _saveAgain() async {
    setState(() => _saving = true);
    await AssessmentStorageService.instance.saveAssessment(widget.result);
    setState(() { _saving = false; _saved = true; });
  }

  // ── L/R Comparison Card (Single Leg Drop Jump) ─────────────────────────────

  Widget _buildLRComparisonCard() {
    final m = widget.result.angleMetrics;
    double g(String key) => m[key] ?? 0.0;

    final vL = g('Left knee valgus');
    final vR = g('Right knee valgus');
    final sL = g('Left stability');
    final sR = g('Right stability');
    final aL = g('Left ankle control');
    final aR = g('Right ankle control');
    final asymmetry = g('L/R asymmetry score');

    Color scoreColor(double v) => v >= 75
        ? Colors.greenAccent
        : v >= 55
            ? Colors.amber
            : Colors.redAccent;

    Widget legColumn(String side, double valgus, double stability, double ankle) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(side.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 10),
              _lrRow(AppLocalizations.get('assessment_lr_valgus'),    valgus,    scoreColor(valgus)),
              const SizedBox(height: 7),
              _lrRow(AppLocalizations.get('assessment_lr_stability'), stability, scoreColor(stability)),
              const SizedBox(height: 7),
              _lrRow(AppLocalizations.get('assessment_lr_ankle'),     ankle,     scoreColor(ankle)),
            ],
          ),
        ),
      );
    }

    final asymColor = asymmetry >= 80
        ? Colors.greenAccent
        : asymmetry >= 60
            ? Colors.amber
            : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(AppLocalizations.get('assessment_left_vs_right'),
                  style: const TextStyle(color: AppColors.foreground,
                      fontWeight: FontWeight.w900, fontSize: 16)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: asymColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: asymColor.withOpacity(0.35)),
                ),
                child: Text(AppLocalizations.format(
                        'assessment_symmetry_pct', {'pct': asymmetry.round()}),
                    style: TextStyle(color: asymColor, fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            legColumn('Left',  vL, sL, aL),
            const SizedBox(width: 10),
            legColumn('Right', vR, sR, aR),
          ]),
        ],
      ),
    );
  }

  Widget _lrRow(String label, double value, Color color) {
    return Row(
      children: [
        Expanded(child: Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12))),
        Text('${value.round()}',
            style: TextStyle(color: color, fontWeight: FontWeight.w800,
                fontSize: 13)),
      ],
    );
  }
}
