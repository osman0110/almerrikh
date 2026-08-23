import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_state.dart';
import '../../models/fms_model.dart';
import '../../services/fms_service.dart';
import 'fms_assessment_screen.dart';
import 'fms_detail_screen.dart';
import 'fms_history_screen.dart';

/// Inline "الحمل التدريبي وRPE"-style summary section for the player profile:
/// latest FMS assessment (total/21, date, assessor, 7 mini badges) plus
/// buttons to add a new assessment or view the full history. Independent of
/// RPE/Hooper/training-load — FMS never feeds into those calculations.
class FmsSummarySection extends StatefulWidget {
  const FmsSummarySection({
    super.key,
    required this.playerId,
    required this.playerName,
    this.compact = false,
  });
  final String playerId;
  final String playerName;
  final bool compact;

  @override
  State<FmsSummarySection> createState() => _FmsSummarySectionState();
}

class _FmsSummarySectionState extends State<FmsSummarySection>
    with AutomaticKeepAliveClientMixin {
  List<FmsAssessment> _recent = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final h = await FmsService.getFmsHistory(widget.playerId, limit: 2);
    if (!mounted) return;
    setState(() { _recent = h; _loading = false; });
  }

  Future<void> _addNew() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FmsAssessmentScreen(playerId: widget.playerId, playerName: widget.playerName),
      ),
    );
    if (saved == true) _load();
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FmsHistoryScreen(playerId: widget.playerId, playerName: widget.playerName),
      ),
    );
  }

  void _openLatestDetail() {
    if (_recent.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FmsDetailScreen(
          assessment: _recent.first,
          previous: _recent.length > 1 ? _recent[1] : null,
        ),
      ),
    );
  }

  Color _scoreColor(int total) {
    if (total >= 17) return AppColors.success;
    if (total >= 12) return AppColors.warning;
    return AppColors.destructive;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
      );
    }

    final latest = _recent.isNotEmpty ? _recent.first : null;
    if (widget.compact) return _buildCompactSummary(latest);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (latest == null)
            const Row(children: [
              Icon(Icons.checklist_rtl_rounded, color: AppColors.muted, size: 16),
              SizedBox(width: 8),
              Text('لا توجد تقييمات FMS بعد', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ])
          else
            GestureDetector(
              onTap: _openLatestDetail,
              child: Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: _scoreColor(latest.totalScore).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text('${latest.totalScore}',
                        style: TextStyle(color: _scoreColor(latest.totalScore), fontWeight: FontWeight.w900, fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('آخر تقييم FMS — ${latest.totalScore} / 21',
                            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13.5)),
                        const SizedBox(height: 3),
                        Text(
                          '${_dateStr(latest.createdAt)}'
                          '${latest.assessorName != null ? ' — ${latest.assessorName}' : ''}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.muted, size: 13),
                ],
              ),
            ),
          if (latest != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: latest.movements.map((s) {
                final c = s.pain || s.finalScore <= 1
                    ? AppColors.destructive
                    : (s.finalScore == 2 ? AppColors.warning : AppColors.success);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(s.movement.placeholderIcon, color: c, size: 12),
                    const SizedBox(width: 4),
                    Text('${s.finalScore}', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
                  ]),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (canManageFms) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _addNew,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('إضافة تقييم جديد', style: TextStyle(color: AppColors.foreground, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton(
                onPressed: _openHistory,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('عرض السجل السابق', style: TextStyle(color: AppColors.foreground, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildCompactSummary(FmsAssessment? latest) {
    final color =
        latest == null ? AppColors.muted : _scoreColor(latest.totalScore);
    final ratingLabel = latest == null
        ? 'لا بيانات'
        : latest.totalScore >= 17
            ? 'جيد'
            : latest.totalScore >= 12
                ? 'مراقبة'
                : 'خطر مرتفع';
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.checklist_rtl_rounded,
                  color: AppColors.gold,
                  size: 13,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'FMS',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 5, height: 5,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ratingLabel,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 9,
                    ),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 9),
          GestureDetector(
            onTap: latest == null ? null : _openLatestDetail,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  latest == null ? '—' : '${latest.totalScore}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('/ 21',
                    style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              if (latest != null)
                Expanded(
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _dateStr(latest.createdAt),
                      style: const TextStyle(color: AppColors.muted, fontSize: 9),
                    ),
                  ),
                ),
              if (canManageFms) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _addNew,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 24),
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    child: const Text('إضافة تقييم',
                        style: TextStyle(color: AppColors.foreground, fontSize: 9.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: _openHistory,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 24),
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('السجل',
                      style: TextStyle(color: AppColors.foreground, fontSize: 9.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dateStr(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
