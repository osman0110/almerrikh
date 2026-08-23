import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/body_composition_models.dart';
import '../../services/body_composition_service.dart';
import '../../services/report_service.dart';

class BodyCompositionComparePage extends StatefulWidget {
  const BodyCompositionComparePage({super.key, required this.fromId, required this.toId});
  final String fromId;
  final String toId;

  @override
  State<BodyCompositionComparePage> createState() => _BodyCompositionComparePageState();
}

class _BodyCompositionComparePageState extends State<BodyCompositionComparePage> {
  bool _loading = true;
  List<BodyCompositionCompareRow> _rows = [];
  Map<String, dynamic>? _from;
  Map<String, dynamic>? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BodyCompositionService.compare(widget.fromId, widget.toId);
    final rows = (res['comparison'] as List?)
            ?.map((e) => BodyCompositionCompareRow.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    if (mounted) {
      setState(() {
        _rows = rows;
        _from = res['from'] as Map<String, dynamic>?;
        _to = res['to'] as Map<String, dynamic>?;
        _loading = false;
      });
    }
  }

  Future<void> _printReport() async {
    if (_from == null || _to == null) return;
    await Printing.layoutPdf(
      onLayout: (format) => ReportService.instance.generateBodyCompositionComparisonPdf(
        from: _from!,
        to: _to!,
        rows: _rows,
      ),
    );
  }

  String _labelFor(String key) {
    const map = {
      'weight_kg': 'bc_weight_kg',
      'bmi': 'bc_bmi',
      'body_fat_percentage': 'bc_body_fat_percentage',
      'fat_mass_kg': 'bc_fat_mass_kg',
      'fat_free_mass_kg': 'bc_fat_free_mass_kg',
      'biceps_mm': 'bc_site_biceps',
      'triceps_mm': 'bc_site_triceps',
      'subscapular_mm': 'bc_site_subscapular',
      'suprailiac_mm': 'bc_site_suprailiac',
      'skinfold_sum_mm': 'bc_skinfold_sum',
    };
    return AppLocalizations.get(map[key] ?? key);
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          elevation: 0,
          title: Text(AppLocalizations.get('bc_compare_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [
            IconButton(
              icon: const Icon(Icons.print_outlined, color: AppColors.primary),
              onPressed: _printReport,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_from != null && _to != null)
                      Row(
                        children: [
                          Expanded(child: _dateChip(AppLocalizations.get('bc_compare_start'), '${_from!['assessment_date']}')),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, color: AppColors.muted, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: _dateChip(AppLocalizations.get('bc_compare_end'), '${_to!['assessment_date']}')),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _tableHeader(),
                          ..._rows.map(_tableRow),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _dateChip(String label, String date) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: AppColors.foreground.withOpacity(0.5), fontSize: 11)),
            const SizedBox(height: 4),
            Text(date, style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _tableHeader() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(AppLocalizations.get('bc_compare_metric'), style: _headerStyle())),
            Expanded(flex: 2, child: Text(AppLocalizations.get('bc_compare_start'), textAlign: TextAlign.end, style: _headerStyle())),
            Expanded(flex: 2, child: Text(AppLocalizations.get('bc_compare_end'), textAlign: TextAlign.end, style: _headerStyle())),
            Expanded(flex: 2, child: Text(AppLocalizations.get('bc_compare_diff'), textAlign: TextAlign.end, style: _headerStyle())),
          ],
        ),
      );

  TextStyle _headerStyle() => TextStyle(color: AppColors.foreground.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w700);

  Widget _tableRow(BodyCompositionCompareRow r) {
    final diffColor = r.diff == null
        ? AppColors.muted
        : (r.label == 'fat_free_mass_kg'
            ? (r.diff! >= 0 ? AppColors.success : AppColors.warning)
            : (r.diff! <= 0 ? AppColors.success : AppColors.warning));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(_labelFor(r.label), style: const TextStyle(color: AppColors.foreground, fontSize: 12.5, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text(r.start?.toStringAsFixed(1) ?? '—', textAlign: TextAlign.end, style: const TextStyle(color: AppColors.foreground, fontSize: 12.5))),
          Expanded(flex: 2, child: Text(r.end?.toStringAsFixed(1) ?? '—', textAlign: TextAlign.end, style: const TextStyle(color: AppColors.foreground, fontSize: 12.5))),
          Expanded(
            flex: 2,
            child: Text(
              r.diff != null ? '${r.diff! > 0 ? '+' : ''}${r.diff!.toStringAsFixed(1)}' : '—',
              textAlign: TextAlign.end,
              style: TextStyle(color: diffColor, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
