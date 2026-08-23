import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/fms_model.dart';
import '../../services/fms_service.dart';
import '../../services/report_service.dart';
import 'fms_detail_screen.dart';

/// List of a player's past FMS assessments (newest first). Tapping a row
/// opens FmsDetailScreen with that assessment and the one right after it in
/// this list (i.e. chronologically previous) for the comparison view.
class FmsHistoryScreen extends StatefulWidget {
  const FmsHistoryScreen({super.key, required this.playerId, required this.playerName});
  final String playerId;
  final String playerName;

  @override
  State<FmsHistoryScreen> createState() => _FmsHistoryScreenState();
}

class _FmsHistoryScreenState extends State<FmsHistoryScreen> {
  List<FmsAssessment> _history = [];
  bool _loading = true;
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 365));
  DateTime _dateTo = DateTime.now();
  bool _detailed = true;
  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final h = await FmsService.getFmsHistory(widget.playerId, limit: 30);
    if (!mounted) return;
    setState(() { _history = h; _loading = false; });
  }

  List<FmsAssessment> get _filteredHistory => _history.where((assessment) {
        final day = DateTime(
          assessment.createdAt.year,
          assessment.createdAt.month,
          assessment.createdAt.day,
        );
        final from = DateTime(_dateFrom.year, _dateFrom.month, _dateFrom.day);
        final to = DateTime(_dateTo.year, _dateTo.month, _dateTo.day);
        return !day.isBefore(from) && !day.isAfter(to);
      }).toList();

  String _shortDate(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _dateFrom : _dateTo,
      firstDate: DateTime.now().subtract(const Duration(days: 1825)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _dateFrom = picked;
        if (_dateFrom.isAfter(_dateTo)) _dateTo = picked;
      } else {
        _dateTo = picked;
        if (_dateTo.isBefore(_dateFrom)) _dateFrom = picked;
      }
    });
  }

  Future<void> _downloadPdf() async {
    final items = _filteredHistory;
    if (_exportingPdf || items.isEmpty) return;
    setState(() => _exportingPdf = true);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'تنزيل تقرير FMS',
        fileName: 'fms_${widget.playerId}.pdf',
        bytes: await ReportService.instance.generateFmsHistoryReportPdf(
          playerName: widget.playerName,
          assessments: items,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          detailed: _detailed,
        ),
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ تقرير FMS: $path')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تنزيل تقرير FMS بصيغة PDF')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text('سجل تقييمات FMS — ${widget.playerName}',
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          actions: [
            IconButton(
              tooltip: 'تنزيل تقرير FMS بصيغة PDF',
              onPressed:
                  _loading || _exportingPdf || _filteredHistory.isEmpty
                      ? null
                      : _downloadPdf,
              icon: _exportingPdf
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: AppColors.primary,
                    ),
            ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.card,
                  onRefresh: _load,
                  child: Builder(
                    builder: (_) {
                      final items = _filteredHistory;
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildReportControls(),
                          const SizedBox(height: 12),
                          if (items.isNotEmpty) _buildSummary(items),
                          const SizedBox(height: 12),
                          if (items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 36),
                              child: Center(
                                child: Text(
                                  'لا توجد تقييمات FMS في الفترة المحددة',
                                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                                ),
                              ),
                            )
                          else
                            ...List.generate(items.length, (i) {
                              final assessment = items[i];
                              final previous = i + 1 < items.length ? items[i + 1] : null;
                              return _historyRow(assessment, previous);
                            }),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildReportControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _dateButton('من', _shortDate(_dateFrom), () => _pickDate(from: true)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateButton('إلى', _shortDate(_dateTo), () => _pickDate(from: false)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'مستوى التفاصيل',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              ChoiceChip(
                label: const Text('مختصر'),
                selected: !_detailed,
                onSelected: (_) => setState(() => _detailed = false),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('تفصيلي'),
                selected: _detailed,
                onSelected: (_) => setState(() => _detailed = true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateButton(String label, String value, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.date_range_rounded, color: AppColors.primary, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 9.5)),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(List<FmsAssessment> items) {
    final average = items.fold<int>(0, (sum, item) => sum + item.totalScore) / items.length;
    final painCount = items.where((item) => item.movements.any((m) => m.pain)).length;
    return Row(
      children: [
        Expanded(child: _summaryTile('عدد التقييمات', '${items.length}', AppColors.coachAccent)),
        const SizedBox(width: 8),
        Expanded(child: _summaryTile('المتوسط', average.toStringAsFixed(1), AppColors.primary)),
        const SizedBox(width: 8),
        Expanded(child: _summaryTile('تقييمات بألم', '$painCount', AppColors.destructive)),
      ],
    );
  }

  Widget _summaryTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
          ),
        ],
      ),
    );
  }

  Widget _historyRow(FmsAssessment a, FmsAssessment? previous) {
    final d = a.createdAt;
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final color = a.totalScore >= 17
        ? AppColors.success
        : a.totalScore >= 12 ? AppColors.warning : AppColors.destructive;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FmsDetailScreen(assessment: a, previous: previous)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text('${a.totalScore}',
                style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateStr, style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
                if (_detailed) ...[
                  const SizedBox(height: 3),
                  Text(
                    a.assessorName != null ? 'المقيّم: ${a.assessorName}' : 'المقيّم: —',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${a.status} · ألم: ${a.movements.where((m) => m.pain).length} · حركات منخفضة: ${a.movements.where((m) => m.finalScore < 2).length}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                  ),
                  if (a.notes != null && a.notes!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      a.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.muted, size: 13),
        ]),
      ),
    );
  }
}
