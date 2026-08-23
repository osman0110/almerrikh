import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Individual Programs — lists a player's existing training_plans (created
// via api/coach/plans/create-manual.php or the AI flow; this screen doesn't
// create plans) and lets the coach add a weekly completion%/notes review on
// top of each one. See api/club/individual_program_reviews.php.
// ─────────────────────────────────────────────────────────────────────────────

String _lbl(String key) {
  final v = AppLocalizations.get(key);
  return v != key ? v : key;
}

class IndividualProgramPage extends StatefulWidget {
  const IndividualProgramPage({super.key, required this.playerId, required this.playerName});
  final String playerId;
  final String playerName;

  @override
  State<IndividualProgramPage> createState() => _IndividualProgramPageState();
}

class _IndividualProgramPageState extends State<IndividualProgramPage> {
  List<Map<String, dynamic>> _plans = [];
  final Map<String, List<Map<String, dynamic>>> _reviewsByPlan = {};
  final Set<String> _expanded = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final plans = await ApiService.getPlayerIndividualPlans(widget.playerId);
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _loading = false;
    });
  }

  Future<void> _toggleExpand(String planId) async {
    if (_expanded.contains(planId)) {
      setState(() => _expanded.remove(planId));
      return;
    }
    if (!_reviewsByPlan.containsKey(planId)) {
      final reviews = await ApiService.getProgramReviews(planId);
      if (!mounted) return;
      setState(() => _reviewsByPlan[planId] = reviews);
    }
    if (!mounted) return;
    setState(() => _expanded.add(planId));
  }

  void _openReviewSheet(String planId) {
    final notesCtrl = TextEditingController();
    final feedbackCtrl = TextEditingController();
    double completion = 0;
    int week = 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 20, left: 20, right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_lbl('program_review_add'),
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 16),
                Row(children: [
                  Text('${_lbl('program_review_week_label')}: $week',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.muted),
                    onPressed: week > 1 ? () => setSheetState(() => week--) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                    onPressed: () => setSheetState(() => week++),
                  ),
                ]),
                Text('${_lbl('rtp_phase_completion_label')}: ${completion.round()}%',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Slider(
                  value: completion, min: 0, max: 100, divisions: 20,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setSheetState(() => completion = v),
                ),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _lbl('program_review_coach_notes_hint'),
                    hintStyle: const TextStyle(color: AppColors.muted),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: feedbackCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _lbl('program_review_player_feedback_hint'),
                    hintStyle: const TextStyle(color: AppColors.muted),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final res = await ApiService.createProgramReview(
                        planId: planId,
                        weekNumber: week,
                        completionPercent: completion.round(),
                        coachNotes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                        playerFeedback: feedbackCtrl.text.trim().isEmpty ? null : feedbackCtrl.text.trim(),
                      );
                      if (!mounted) return;
                      if (res['success'] == true) {
                        Navigator.of(context).pop();
                        _reviewsByPlan.remove(planId);
                        await _toggleExpand(planId);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.foreground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(_lbl('program_review_add'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: getAppLanguage() == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.foreground, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(widget.playerName,
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _plans.isEmpty
                ? Center(
                    child: Text(_lbl('no_individual_programs'),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.card,
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _plans.length,
                      itemBuilder: (_, i) => _planCard(_plans[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final planId = plan['id'].toString();
    final isExpanded = _expanded.contains(planId);
    final reviews = _reviewsByPlan[planId] ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _toggleExpand(planId),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${plan['title']}',
                        style: const TextStyle(
                            color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 14)),
                    if ((plan['goal'] as String?)?.isNotEmpty == true)
                      Text('${plan['goal']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ],
                ),
              ),
              if (plan['num_weeks'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.coachAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${plan['num_weeks']}w',
                      style: const TextStyle(color: AppColors.coachAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.muted),
            ]),
          ),
          if (isExpanded) ...[
            const Divider(color: AppColors.border, height: 20),
            Row(children: [
              Expanded(
                child: Text(_lbl('program_reviews_label'),
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              TextButton(
                onPressed: () => _openReviewSheet(planId),
                child: Text(_lbl('program_review_add'),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            ]),
            if (reviews.isEmpty)
              Text(_lbl('no_program_reviews'), style: const TextStyle(color: AppColors.muted, fontSize: 12))
            else
              ...reviews.map((r) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('${_lbl('program_review_week_label')} ${r['week_number']}',
                              style: const TextStyle(
                                  color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12)),
                          const Spacer(),
                          Text('${r['completion_percent']}%',
                              style: const TextStyle(
                                  color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 12)),
                        ]),
                        if ((r['coach_notes'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text('${r['coach_notes']}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                        ],
                      ],
                    ),
                  )),
          ],
        ],
      ),
    );
  }
}
