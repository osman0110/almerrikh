import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/body_composition_service.dart';
import '../../services/club_service.dart';
import '../../widgets/common_widgets.dart';

/// One parsed spreadsheet row, matched (or not) against the club roster.
class _ImportRow {
  _ImportRow({required this.rowIndex, required this.rawName, this.data = const {}});
  final int rowIndex;
  final String rawName;
  final Map<String, dynamic> data;
  ClubPlayer? matchedPlayer;
  String? error; // set after a failed commit, or if unmatched
  bool committed = false;
}

const _templateColumns = [
  'player_name', 'weight_kg', 'height_cm', 'assessment_date',
  'biceps_attempt_1_mm', 'biceps_attempt_2_mm', 'biceps_attempt_3_mm',
  'triceps_attempt_1_mm', 'triceps_attempt_2_mm', 'triceps_attempt_3_mm',
  'subscapular_attempt_1_mm', 'subscapular_attempt_2_mm', 'subscapular_attempt_3_mm',
  'suprailiac_attempt_1_mm', 'suprailiac_attempt_2_mm', 'suprailiac_attempt_3_mm',
  'notes',
];

class BodyCompositionBulkImportPage extends StatefulWidget {
  const BodyCompositionBulkImportPage({super.key});

  @override
  State<BodyCompositionBulkImportPage> createState() => _BodyCompositionBulkImportPageState();
}

class _BodyCompositionBulkImportPageState extends State<BodyCompositionBulkImportPage> {
  List<ClubPlayer> _roster = [];
  List<_ImportRow> _rows = [];
  bool _loadingRoster = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    final players = await ClubService().getPlayers();
    if (mounted) setState(() { _roster = players; _loadingRoster = false; });
  }

  Future<void> _downloadTemplate() async {
    final excelFile = xls.Excel.createExcel();
    final sheet = excelFile['Template'];
    sheet.appendRow(_templateColumns.map((c) => xls.TextCellValue(c)).toList());
    excelFile.delete('Sheet1');

    final bytes = excelFile.encode();
    if (bytes == null) return;

    final path = await FilePicker.platform.saveFile(
      dialogTitle: AppLocalizations.get('bc_bulk_download_template'),
      fileName: 'body_composition_template.xlsx',
      bytes: Uint8List.fromList(bytes),
    );
    if (mounted && path != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(path)));
    }
  }

  void _notify(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.destructive : AppColors.card,
    ));
  }

  Future<void> _pickAndParseFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null) return; // user cancelled the picker — nothing to report
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      _notify(AppLocalizations.get('bc_bulk_read_error'));
      return;
    }

    final excelFile = xls.Excel.decodeBytes(bytes);
    final sheet = excelFile.tables.values.isNotEmpty ? excelFile.tables.values.first : null;
    if (sheet == null || sheet.rows.isEmpty) {
      _notify(AppLocalizations.get('bc_bulk_file_empty'));
      return;
    }

    final header = sheet.rows.first
        .map((c) => c?.value?.toString().trim() ?? '')
        .toList();
    final colIndex = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      if (header[i].isNotEmpty) colIndex[header[i]] = i;
    }

    final parsed = <_ImportRow>[];
    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      String cell(String col) {
        final idx = colIndex[col];
        if (idx == null || idx >= row.length) return '';
        return row[idx]?.value?.toString().trim() ?? '';
      }

      final name = cell('player_name');
      if (name.isEmpty) continue;

      final data = <String, dynamic>{};
      for (final col in _templateColumns) {
        if (col == 'player_name') continue;
        final v = cell(col);
        if (v.isNotEmpty) data[col] = v;
      }

      final importRow = _ImportRow(rowIndex: r, rawName: name, data: data);
      importRow.matchedPlayer = _matchPlayer(name);
      if (importRow.matchedPlayer == null) {
        importRow.error = AppLocalizations.get('bc_bulk_player_not_matched');
      }
      parsed.add(importRow);
    }

    if (parsed.isEmpty) {
      _notify(AppLocalizations.get('bc_bulk_no_valid_rows'));
    }
    setState(() => _rows = parsed);
  }

  ClubPlayer? _matchPlayer(String name) {
    final normalized = name.trim().toLowerCase();
    for (final p in _roster) {
      if (p.fullName.trim().toLowerCase() == normalized) return p;
    }
    return null;
  }

  Future<void> _commit() async {
    final validRows = _rows.where((r) => r.matchedPlayer != null).toList();
    if (validRows.isEmpty) return;

    setState(() => _importing = true);
    final payload = validRows.map((r) => {
          'player_id': r.matchedPlayer!.id,
          'weight_kg': double.tryParse('${r.data['weight_kg'] ?? ''}'),
          'height_cm': double.tryParse('${r.data['height_cm'] ?? ''}'),
          'assessment_date': r.data['assessment_date'],
          'notes': r.data['notes'],
          for (final site in ['biceps', 'triceps', 'subscapular', 'suprailiac'])
            for (final n in [1, 2, 3])
              '${site}_attempt_${n}_mm': double.tryParse('${r.data['${site}_attempt_${n}_mm'] ?? ''}'),
        }).toList();

    final res = await BodyCompositionService.bulkSave(payload);
    final results = (res['results'] as List?) ?? [];
    for (var i = 0; i < results.length && i < validRows.length; i++) {
      final r = results[i] as Map<String, dynamic>;
      validRows[i].committed = r['success'] == true;
      validRows[i].error = r['success'] == true ? null : r['error']?.toString();
    }

    if (!mounted) return;
    setState(() => _importing = false);

    final importedCount = res['imported'] as int? ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${AppLocalizations.get('bc_bulk_commit')}: $importedCount'),
      backgroundColor: AppColors.card,
    ));
    if (importedCount > 0) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (!canManageBodyComposition) return const RoleAccessDeniedPage();
    final isRtl = getAppLanguage() == 'ar';
    final matchedCount = _rows.where((r) => r.matchedPlayer != null).length;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          elevation: 0,
          title: Text(AppLocalizations.get('bc_bulk_import_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        body: _loadingRoster
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _downloadTemplate,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: Text(AppLocalizations.get('bc_bulk_download_template')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickAndParseFile,
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.foreground),
                            icon: const Icon(Icons.upload_file_rounded, size: 18),
                            label: Text(AppLocalizations.get('bc_bulk_upload_file')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_rows.isNotEmpty) ...[
                      Text('${AppLocalizations.get('bc_bulk_preview')}: $matchedCount / ${_rows.length}',
                          style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (context, i) => _buildRow(_rows[i]),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (matchedCount == 0 || _importing) ? null : _commit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.foreground,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _importing
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(AppLocalizations.get('bc_bulk_commit')),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildRow(_ImportRow r) {
    final ok = r.matchedPlayer != null && r.error == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ok ? AppColors.border : AppColors.destructive.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(r.committed
              ? Icons.check_circle_rounded
              : ok
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              color: r.committed ? AppColors.success : (ok ? AppColors.primary : AppColors.destructive), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.matchedPlayer?.fullName ?? r.rawName,
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w600, fontSize: 13)),
                if (r.error != null)
                  Text(r.error!, style: const TextStyle(color: AppColors.destructive, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
