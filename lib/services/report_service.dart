import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../app_localizations.dart';
import '../models/assessment_result_model.dart';
import '../models/body_composition_models.dart';
import '../models/club_models.dart';
import '../models/fms_model.dart';
import '../models/monitoring_models.dart';
import '../models/report_models.dart';
import '../models/training_load_models.dart';
import '../utils/metric_formatter.dart';

/// Al Merrikh SC brand colors — must match lib/app_colors.dart exactly
/// (AppColors.maroon / AppColors.gold) so PDFs match the in-app theme.
const _maroon = PdfColor.fromInt(0xFF8B0015);
const _maroonDark = PdfColor.fromInt(0xFF4A000D);
const _gold = PdfColor.fromInt(0xFFF6B82E);
const _ink = PdfColor.fromInt(0xFF171717);
const _muted = PdfColor.fromInt(0xFF7A7D85);
const _softBg = PdfColor.fromInt(0xFFF7F5EF);
const _acwrBlue = PdfColor.fromInt(0xFF1A6BEB);
const _acwrGreen = PdfColor.fromInt(0xFF16B889);
const _acwrYellow = PdfColor.fromInt(0xFFE5A315);
const _acwrRed = PdfColor.fromInt(0xFFE5484D);
const _pdfPageMargin = pw.EdgeInsets.fromLTRB(12, 12, 12, 16);

class ReportMetadata {
  const ReportMetadata({
    required this.team,
    required this.season,
    required this.period,
    required this.issuedBy,
    this.notes,
  });

  final String team;
  final String season;
  final String period;
  final String issuedBy;
  final String? notes;
}

/// Single source of truth for every report PDF in the app — do not build
/// raw pw.Document() layouts elsewhere; add a method here and reuse
/// _brandedDocument()/_sectionTitle()/_statRow() for a consistent,
/// professional Al Merrikh SC look across all report types.
class ReportService {
  ReportService._internal();
  static final ReportService instance = ReportService._internal();

  Future<pw.Font> _arabicFont() => Future(
    () async => pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo.ttf')),
  );

  Future<pw.ImageProvider?> _logo() async {
    try {
      final bytes = await rootBundle.load('assets/images/logo.png');
      return pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /// Themed pw.Document (Cairo font) — the maroon/gold Al Merrikh SC
  /// header/footer are applied per-page via MultiPage's header/footer
  /// callbacks in each generate*Pdf method below.
  Future<pw.Document> _brandedDocument() async {
    final font = await _arabicFont();
    return pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
  }

  pw.Widget _pageHeader(
    pw.ImageProvider? logo,
    String title,
    String subtitle,
    String generatedAt, [
    ReportMetadata? metadata,
  ]) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const pw.BoxDecoration(
            gradient: pw.LinearGradient(colors: [_maroon, _maroonDark]),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null) ...[
                pw.Container(
                  width: 40,
                  height: 40,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.white,
                    shape: pw.BoxShape.circle,
                  ),
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Image(logo),
                ),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      AppLocalizations.get('club_brand_name'),
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      AppLocalizations.get('brand_platform'),
                      style: const pw.TextStyle(color: _gold, fontSize: 8),
                    ),
                  ],
                ),
              ),
              pw.Text(
                generatedAt,
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
              ),
            ],
          ),
        ),
        pw.Container(height: 3, color: _gold),
        pw.Container(
          width: double.infinity,
          color: _softBg,
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: _maroon,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(fontSize: 10, color: _muted),
                ),
              ],
              if (metadata != null) ...[
                pw.SizedBox(height: 5),
                pw.Wrap(
                  spacing: 14,
                  runSpacing: 3,
                  children: [
                    pw.Text(
                      AppLocalizations.format('team_meta', {'value': metadata.team}),
                      style: const pw.TextStyle(fontSize: 8, color: _ink),
                    ),
                    pw.Text(
                      AppLocalizations.format('season_meta', {'value': metadata.season}),
                      style: const pw.TextStyle(fontSize: 8, color: _ink),
                    ),
                    pw.Text(
                      AppLocalizations.format('period_meta', {'value': metadata.period}),
                      style: const pw.TextStyle(fontSize: 8, color: _ink),
                    ),
                    pw.Text(
                      AppLocalizations.format('issued_by_meta', {'value': metadata.issuedBy}),
                      style: const pw.TextStyle(fontSize: 8, color: _ink),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _pageFooter(pw.Context context) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _gold, width: 0.6)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          '${AppLocalizations.get('club_brand_name')} — ${_now()} — '
          '${AppLocalizations.get('confidential_footer')}',
          style: const pw.TextStyle(fontSize: 7, color: _muted),
        ),
        pw.Text(
          AppLocalizations.format('page_of', {
            'current': context.pageNumber,
            'total': context.pagesCount,
          }),
          style: const pw.TextStyle(fontSize: 7, color: _muted),
        ),
      ],
    ),
  );

  pw.Widget _sectionTitle(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Row(
      children: [
        pw.Container(width: 3, height: 12, color: _gold),
        pw.SizedBox(width: 6),
        pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
      ],
    ),
  );

  pw.Widget _statCard(String label, String value) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 3),
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      decoration: pw.BoxDecoration(
        color: _softBg,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _gold, width: 0.6),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: _maroon,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ],
      ),
    ),
  );

  pw.TableRow _tableHeaderRow(List<String> headers) => pw.TableRow(
    repeat: true,
    decoration: const pw.BoxDecoration(color: _maroon),
    children: headers
        .map(
          (h) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              h,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        )
        .toList(),
  );

  pw.TableRow _tableDataRow(
    List<String> cells, {
    bool striped = false,
  }) => pw.TableRow(
    decoration: pw.BoxDecoration(color: striped ? _softBg : PdfColors.white),
    children: cells
        .map(
          (c) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: pw.Text(
              c,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8, color: _ink),
            ),
          ),
        )
        .toList(),
  );

  pw.Table _brandedTable(List<String> headers, List<List<String>> rows) =>
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        children: [
          _tableHeaderRow(headers),
          for (var i = 0; i < rows.length; i++)
            _tableDataRow(rows[i], striped: i.isOdd),
        ],
      );

  pw.Widget _barChart(
    List<MapEntry<String, double?>> values, {
    double height = 90,
    int digits = 0,
  }) {
    final available = values
        .map((entry) => entry.value)
        .whereType<double>()
        .map((value) => value.abs())
        .toList();
    final maxValue = available.isEmpty
        ? 1.0
        : available.reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);
    return pw.Container(
      height: height,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _softBg,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: values.map((entry) {
          final value = entry.value;
          final ratio = value == null
              ? 0.04
              : (value.abs() / maxValue).clamp(0.04, 1.0);
          return pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 2),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    value?.toStringAsFixed(digits) ?? '—',
                    style: const pw.TextStyle(fontSize: 6, color: _muted),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Container(
                    height: (height - 35) * ratio,
                    decoration: pw.BoxDecoration(
                      color: value == null
                          ? PdfColors.grey300
                          : value < 0
                          ? PdfColors.green700
                          : _maroon,
                      borderRadius: const pw.BorderRadius.vertical(
                        top: pw.Radius.circular(2),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    entry.key,
                    style: const pw.TextStyle(fontSize: 5.5, color: _muted),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  pw.Table _denseTable(
    List<String> headers,
    List<List<String>> rows, {
    Map<int, pw.TableColumnWidth>? columnWidths,
    List<bool>? warningRows,
    double fontSize = 6.3,
  }) {
    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.45),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _maroon),
          children: headers
              .map(
                (header) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 5,
                  ),
                  child: pw.Text(
                    header,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: fontSize,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        for (var index = 0; index < rows.length; index++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: warningRows?[index] == true
                  ? const PdfColor.fromInt(0xFFFFE1E1)
                  : index.isOdd
                  ? _softBg
                  : PdfColors.white,
            ),
            children: rows[index]
                .map(
                  (cell) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      cell,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        color: _ink,
                        fontSize: fontSize,
                        fontWeight: pw.FontWeight.normal,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  pw.Widget _trainingLoadExcelTable(List<PlayerTrainingLoadRow> rows) {
    final referenceDays = rows.isEmpty
        ? <TrainingLoadDay>[]
        : _weekDays(rows.first);
    const dayColors = [
      PdfColor.fromInt(0xFFE8D7F0),
      PdfColor.fromInt(0xFFFFE28A),
      PdfColor.fromInt(0xFFDDEBF7),
      PdfColor.fromInt(0xFFE2F0D9),
      PdfColor.fromInt(0xFFF4C7B8),
      PdfColor.fromInt(0xFFE6E6E6),
      PdfColor.fromInt(0xFFFFC7CE),
    ];
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(2.1),
      1: const pw.FlexColumnWidth(0.8),
      for (var index = 2; index < 23; index++)
        index: const pw.FlexColumnWidth(0.66),
      23: const pw.FlexColumnWidth(1.0),
      24: const pw.FlexColumnWidth(0.85),
      25: const pw.FlexColumnWidth(0.85),
      26: const pw.FlexColumnWidth(1.15),
      27: const pw.FlexColumnWidth(1.15),
    };
    final firstHeader = <pw.Widget>[
      _matrixHeaderCell(AppLocalizations.get('rpt_player_column'), _maroon, PdfColors.white),
      _matrixHeaderCell(AppLocalizations.get('position_label'), _maroon, PdfColors.white),
      for (var dayIndex = 0; dayIndex < 7; dayIndex++)
        for (var part = 0; part < 3; part++)
          _matrixHeaderCell(
            dayIndex < referenceDays.length
                ? '${_weekdayLabel(referenceDays[dayIndex].date.weekday)}\n'
                      '${referenceDays[dayIndex].date.day}/${referenceDays[dayIndex].date.month}'
                : _weekdayLabel(dayIndex + 1),
            dayColors[dayIndex],
            _ink,
          ),
      _matrixHeaderCell(AppLocalizations.get('rpt_weekly_column'), _maroon, PdfColors.white),
      _matrixHeaderCell(AppLocalizations.get('rpt_mean_column'), _maroon, PdfColors.white),
      _matrixHeaderCell(AppLocalizations.get('rpt_sd_column'), _maroon, PdfColors.white),
      _matrixHeaderCell('Monotony', _maroon, PdfColors.white),
      _matrixHeaderCell('Strain', _maroon, PdfColors.white),
    ];
    final secondHeader = <pw.Widget>[
      _matrixHeaderCell(AppLocalizations.get('rpt_name_column'), _maroonDark, PdfColors.white),
      _matrixHeaderCell(AppLocalizations.get('position_label'), _maroonDark, PdfColors.white),
      for (var dayIndex = 0; dayIndex < 7; dayIndex++) ...[
        _matrixHeaderCell('RPE', dayColors[dayIndex], _ink),
        _matrixHeaderCell(AppLocalizations.get('duration'), dayColors[dayIndex], _ink),
        _matrixHeaderCell('CE', dayColors[dayIndex], _ink),
      ],
      _matrixHeaderCell('CE', _maroonDark, PdfColors.white),
      _matrixHeaderCell('Mean', _maroonDark, PdfColors.white),
      _matrixHeaderCell('SD', _maroonDark, PdfColors.white),
      _matrixHeaderCell('M', _maroonDark, PdfColors.white),
      _matrixHeaderCell('S', _maroonDark, PdfColors.white),
    ];

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.45),
      children: [
        pw.TableRow(repeat: true, children: firstHeader),
        pw.TableRow(repeat: true, children: secondHeader),
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: rows[rowIndex].completenessStatus == 'INCOMPLETE'
                  ? const PdfColor.fromInt(0xFFFFE1E1)
                  : rowIndex.isOdd
                  ? _softBg
                  : PdfColors.white,
            ),
            children: _trainingMatrixCells(rows[rowIndex])
                .map(
                  (value) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 1,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      value,
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 4.3, color: _ink),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  pw.Widget _matrixHeaderCell(
    String text,
    PdfColor background,
    PdfColor foreground,
  ) {
    return pw.Container(
      color: background,
      padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 4.8,
          fontWeight: pw.FontWeight.bold,
          color: foreground,
        ),
      ),
    );
  }

  List<String> _trainingMatrixCells(PlayerTrainingLoadRow row) {
    final values = <String>[
      row.playerName ?? AppLocalizations.get('rpt_na'),
      row.position ?? '—',
    ];
    for (final day in _weekDays(row)) {
      values.addAll(_trainingDayCells(day));
    }
    while (values.length < 23) {
      values.addAll(const ['—', '—', '—']);
    }
    values.add(
      '${row.weeklyLoad.toStringAsFixed(0)}'
      '${row.completenessStatus == 'INCOMPLETE' ? '*' : ''}',
    );
    values.add(row.dailyMean.toStringAsFixed(2));
    values.add(row.standardDeviation.toStringAsFixed(2));
    values.add(_monotonyText(row));
    values.add(_strainText(row));
    return values;
  }

  List<TrainingLoadDay> _weekDays(PlayerTrainingLoadRow row) {
    if (row.days.length >= 7) return row.days.sublist(row.days.length - 7);
    if (row.days28.length >= 7) {
      return row.days28.sublist(row.days28.length - 7);
    }
    return row.days;
  }

  List<String> _trainingDayCells(TrainingLoadDay day) {
    if (day.sessions.isEmpty) {
      return [_dayStatusLabel(day.participationStatus), '—', '—'];
    }
    final rpe = day.sessions
        .map(
          (session) =>
              session.rpe?.toStringAsFixed(1) ?? AppLocalizations.get('rpt_na'),
        )
        .join('+');
    final duration = day.sessions
        .map(
          (session) =>
              session.actualDurationMinutes?.toString() ??
              AppLocalizations.get('rpt_na'),
        )
        .join('+');
    final load = day.dataQualityIssues.isEmpty
        ? day.dailyLoad.toStringAsFixed(0)
        : AppLocalizations.get('rpt_incomplete_data');
    return [rpe, duration, load];
  }

  String _weekdayLabel(int weekday) => AppLocalizations.weekdayName(weekday);

  String _decimal(
    double? value, {
    int digits = 1,
    String suffix = '',
    bool zeroIsUnavailable = false,
  }) {
    final formatted = MetricFormatter.number(
      value,
      digits: digits,
      zeroIsUnavailable: zeroIsUnavailable,
    );
    return formatted == MetricFormatter.unavailable
        ? formatted
        : '$formatted$suffix';
  }

  bool _hasCompleteBodyFat(BodyCompositionEntry entry) =>
      entry.bodyFatPercentage != null &&
      entry.calculationStatus.toUpperCase() == 'COMPLETE';

  String _monotonyText(PlayerTrainingLoadRow row) {
    if (row.completenessStatus == 'INCOMPLETE') {
      return AppLocalizations.get('rpt_incomplete_data');
    }
    if (row.calculationStatus == 'CONSTANT_NON_ZERO_LOAD') {
      return AppLocalizations.get('rpt_cannot_calculate');
    }
    if (row.calculationStatus == 'NO_LOAD') {
      return AppLocalizations.get('rpt_insufficient_data');
    }
    return MetricFormatter.monotony(row.monotony);
  }

  String _strainText(PlayerTrainingLoadRow row) {
    if (row.completenessStatus == 'INCOMPLETE') {
      return AppLocalizations.get('rpt_incomplete_data');
    }
    if (row.calculationStatus == 'CONSTANT_NON_ZERO_LOAD') {
      return AppLocalizations.get('rpt_cannot_calculate');
    }
    if (row.calculationStatus == 'NO_LOAD') {
      return AppLocalizations.get('rpt_insufficient_data');
    }
    return MetricFormatter.strain(row.strain);
  }

  String _compactDailyLoadText(TrainingLoadDay day) {
    switch (day.participationStatus) {
      case 'COMPLETE':
        if (day.dataQualityIssues.isNotEmpty) {
          return AppLocalizations.get('rpt_incomplete_short');
        }
        if (day.sessions.isEmpty) return '—';
        return day.dailyLoad.toStringAsFixed(0);
      case 'REST':
        return AppLocalizations.get('attendance_rest');
      case 'ABSENT':
        return AppLocalizations.get('rpt_absent');
      case 'UNAVAILABLE':
        return AppLocalizations.get('rpt_injury');
      case 'MISSING_RPE':
      case 'MATCH_MISSING_RPE':
        return AppLocalizations.get('rpt_missing_rpe_q');
      case 'MISSING_DURATION':
        return AppLocalizations.get('rpt_missing_duration_q');
      case 'SCHEDULED_SESSION_MISSING_RECORD':
        return AppLocalizations.get('rpt_missing_record_q');
      default:
        return '—';
    }
  }

  String _compactMonotonyText(PlayerTrainingLoadRow row) {
    if (row.completenessStatus == 'INCOMPLETE') {
      return AppLocalizations.get('rpt_incomplete_short');
    }
    if (row.calculationStatus == 'CONSTANT_NON_ZERO_LOAD') {
      return AppLocalizations.get('rpt_cannot_calc_short');
    }
    if (row.calculationStatus == 'NO_LOAD') {
      return AppLocalizations.get('rpt_insufficient_short');
    }
    return MetricFormatter.monotony(row.monotony);
  }

  String _compactStrainText(PlayerTrainingLoadRow row) {
    if (row.completenessStatus == 'INCOMPLETE') {
      return AppLocalizations.get('rpt_incomplete_short');
    }
    if (row.calculationStatus == 'CONSTANT_NON_ZERO_LOAD') {
      return AppLocalizations.get('rpt_cannot_calc_short');
    }
    if (row.calculationStatus == 'NO_LOAD') {
      return AppLocalizations.get('rpt_insufficient_short');
    }
    return MetricFormatter.strain(row.strain);
  }

  String _dayStatusLabel(String status) {
    switch (status) {
      case 'COMPLETE':
        return AppLocalizations.get('complete_label');
      case 'REST':
        return AppLocalizations.get('attendance_rest');
      case 'ABSENT':
        return AppLocalizations.get('rpt_absent');
      case 'UNAVAILABLE':
        return AppLocalizations.get('rpt_injury_unavailable');
      case 'MISSING_RPE':
      case 'MATCH_MISSING_RPE':
        return AppLocalizations.get('missing_rpe');
      case 'MISSING_DURATION':
        return AppLocalizations.get('missing_duration');
      case 'SCHEDULED_SESSION_MISSING_RECORD':
        return AppLocalizations.get('missing_session_record');
      case 'HISTORICAL_STATUS_UNKNOWN':
      case 'UNKNOWN_DAY_STATUS':
        return AppLocalizations.get('rpt_unknown_status');
      default:
        return AppLocalizations.get('rpt_na');
    }
  }

  double? _chartedDailyLoad(TrainingLoadDay day) {
    if (day.participationStatus == 'COMPLETE' ||
        day.participationStatus == 'REST') {
      return day.dailyLoad;
    }
    return null;
  }

  // ── Player Assessment Report ──────────────────────────────────────────────

  Future<Uint8List> generatePlayerAssessmentPdf(
    CoachAssessmentReport report,
  ) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.format('rpt_assessment_report_title', {
                  'value': report.player.name,
                }),
                report.player.position ?? '',
                now,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          pw.Row(
            children: [
              _statCard(
                AppLocalizations.get('rpt_best_label'),
                report.summary.bestScore?.toString() ?? '—',
              ),
              _statCard(
                AppLocalizations.get('rpt_worst_label'),
                report.summary.worstScore?.toString() ?? '—',
              ),
              _statCard(
                AppLocalizations.get('rpt_average_label'),
                report.summary.averageScore?.toStringAsFixed(1) ?? '—',
              ),
              _statCard(AppLocalizations.get('rpt_trend_label'), report.summary.trend),
            ],
          ),
          _sectionTitle(
            AppLocalizations.format('rpt_assessment_history_section', {
              'value': report.assessments.length,
            }),
          ),
          _brandedTable(
            [
              AppLocalizations.get('date_filter_label'),
              AppLocalizations.get('test_type_label'),
              AppLocalizations.get('rpt_total_score_column'),
              AppLocalizations.get('score_movement'),
              AppLocalizations.get('score_stability'),
              AppLocalizations.get('score_symmetry'),
              AppLocalizations.get('rpt_control_column'),
            ],
            report.assessments
                .map(
                  (a) => [
                    a.date,
                    a.assessmentType,
                    '${a.overallScore}',
                    '${a.movementScore}',
                    '${a.stabilityScore}',
                    '${a.symmetryScore}',
                    '${a.controlScore}',
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generateFmsHistoryReportPdf({
    required String playerName,
    required List<FmsAssessment> assessments,
    required DateTime dateFrom,
    required DateTime dateTo,
    required bool detailed,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    String date(DateTime value) =>
        '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
    final average = assessments.isEmpty
        ? 0.0
        : assessments.fold<int>(
              0,
              (sum, assessment) => sum + assessment.totalScore,
            ) /
            assessments.length;
    final painCount = assessments
        .where(
          (assessment) =>
              assessment.movements.any((movement) => movement.pain),
        )
        .length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat:
            detailed ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.format('rpt_fms_report_title', {
                  'value': playerName,
                }),
                AppLocalizations.format('period_meta', {
                  'value': '${date(dateFrom)} — ${date(dateTo)}',
                }),
                now,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          pw.Row(
            children: [
              _statCard(
                AppLocalizations.get('rpt_assessment_count_label'),
                '${assessments.length}',
              ),
              _statCard(
                AppLocalizations.get('rpt_average_score_label'),
                average.toStringAsFixed(1),
              ),
              _statCard(
                AppLocalizations.get('rpt_pain_assessments_label'),
                '$painCount',
              ),
            ],
          ),
          _sectionTitle(AppLocalizations.get('rpt_assessment_summary_section')),
          _brandedTable(
            [
              AppLocalizations.get('date_filter_label'),
              AppLocalizations.get('rpt_score_column'),
              AppLocalizations.get('status_label'),
              AppLocalizations.get('rpt_assessor_column'),
              AppLocalizations.get('rpt_pain_movements_column'),
              AppLocalizations.get('rpt_low_movements_column'),
              AppLocalizations.get('notes_column'),
            ],
            assessments
                .map(
                  (assessment) => [
                    date(assessment.createdAt),
                    '${assessment.totalScore} / 21',
                    assessment.status,
                    assessment.assessorName ?? '—',
                    '${assessment.movements.where((m) => m.pain).length}',
                    '${assessment.movements.where((m) => m.finalScore < 2).length}',
                    assessment.notes?.trim().isNotEmpty == true
                        ? assessment.notes!.trim()
                        : '—',
                  ],
                )
                .toList(),
          ),
          if (detailed) ...[
            _sectionTitle(AppLocalizations.get('rpt_movement_details_section')),
            _brandedTable(
              [
                AppLocalizations.get('date_filter_label'),
                AppLocalizations.get('score_movement'),
                AppLocalizations.get('rpt_right_column'),
                AppLocalizations.get('rpt_left_column'),
                AppLocalizations.get('rpt_final_column'),
                AppLocalizations.get('rpt_pain_column'),
                AppLocalizations.get('rpt_recommendation_column'),
              ],
              [
                for (final assessment in assessments)
                  for (final movement in assessment.movements)
                    [
                      date(assessment.createdAt),
                      movement.movement.nameAr,
                      movement.rightScore?.toString() ?? '—',
                      movement.leftScore?.toString() ?? '—',
                      '${movement.finalScore}',
                      movement.pain
                          ? AppLocalizations.get('yes')
                          : AppLocalizations.get('no'),
                      movement.movement.recommendationFor(
                        movement.finalScore,
                        movement.pain,
                      ),
                    ],
              ],
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  // ── Team Performance Report (club_reports_page.dart) ─────────────────────

  Future<Uint8List> generateTeamReportPdf({
    required List<ClubPlayer> players,
    required int totalSessions,
    required int totalAssessments,
  }) async {
    final scored = players.where((p) => p.latestScore != null).toList()
      ..sort((a, b) => (b.latestScore ?? 0).compareTo(a.latestScore ?? 0));

    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.get('rpt_team_performance_report_title'),
                AppLocalizations.get('rpt_team_performance_subtitle'),
                now,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          pw.Row(
            children: [
              _statCard(AppLocalizations.get('rpt_player_count_label'), '${players.length}'),
              _statCard(AppLocalizations.get('rpt_sessions_label'), '$totalSessions'),
              _statCard(AppLocalizations.get('rpt_assessments_label'), '$totalAssessments'),
            ],
          ),
          _sectionTitle(
            AppLocalizations.format('rpt_performance_table_section', {
              'value': scored.length,
            }),
          ),
          _brandedTable(
            [
              '#',
              AppLocalizations.get('rpt_player_column'),
              AppLocalizations.get('position_label'),
              AppLocalizations.get('rpt_score_column'),
              AppLocalizations.get('status_label'),
            ],
            List.generate(scored.length, (i) {
              final p = scored[i];
              return [
                '${i + 1}',
                p.fullName,
                p.position.isEmpty ? '—' : p.position,
                p.latestScore!.toStringAsFixed(0),
                p.status.label,
              ];
            }),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // ── Match Participants Report (match_detail_page.dart) ───────────────────

  Future<Uint8List> generateMatchParticipantsReportPdf({
    required MatchModel match,
    required List<ClubPlayer> players,
    required List<MatchParticipation> participations,
    required List<MatchCard> cards,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();

    String minutesFor(String playerId) {
      final p = participations.where((x) => x.playerId == playerId).firstOrNull;
      if (p != null && p.minutesPlayed > 0) return '${p.minutesPlayed}';
      final fallback = match.playerMinutes[playerId];
      return fallback != null && fallback > 0 ? '$fallback' : '—';
    }

    String statusFor(String playerId) {
      final p = participations.where((x) => x.playerId == playerId).firstOrNull;
      if (p == null || p.played == false) {
        return AppLocalizations.get('match_not_played_label');
      }
      return p.starter
          ? AppLocalizations.get('match_starter_label')
          : AppLocalizations.get('match_substitute_label');
    }

    String cardsFor(String playerId) {
      final playerCards = cards.where((c) => c.playerId == playerId).toList();
      if (playerCards.isEmpty) return '—';
      final yellow = playerCards.where((c) => c.cardType == 'yellow').length;
      final red = playerCards.where((c) => c.cardType == 'red').length;
      final parts = <String>[];
      if (yellow > 0) parts.add('$yellow Y');
      if (red > 0) parts.add('$red R');
      return parts.join('  ');
    }

    final rows = players.map((player) {
      final p = participations.where((x) => x.playerId == player.id).firstOrNull;
      return [
        player.fullName,
        player.position.isEmpty ? '—' : player.position,
        statusFor(player.id),
        minutesFor(player.id),
        '${p?.goals ?? 0}',
        '${p?.assists ?? 0}',
        cardsFor(player.id),
      ];
    }).toList();

    final startersCount = participations.where((p) => p.starter).length;
    final totalGoals = participations.fold<int>(0, (a, p) => a + p.goals);
    final totalAssists = participations.fold<int>(0, (a, p) => a + p.assists);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.get('rpt_match_participants_title'),
                '${AppLocalizations.format('match_vs', {'opponent': match.opponent})} — '
                '${AppLocalizations.get('rpt_match_participants_subtitle')}',
                now,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          pw.Row(
            children: [
              _statCard(AppLocalizations.get('rpt_player_count_label'), '${players.length}'),
              _statCard(AppLocalizations.get('match_starter_label'), '$startersCount'),
              _statCard(AppLocalizations.get('match_goals_label'), '$totalGoals'),
              _statCard(AppLocalizations.get('match_assists_label'), '$totalAssists'),
            ],
          ),
          _sectionTitle(AppLocalizations.get('match_players_title')),
          _brandedTable(
            [
              AppLocalizations.get('rpt_player_column'),
              AppLocalizations.get('position_label'),
              AppLocalizations.get('status_label'),
              AppLocalizations.get('rpt_minutes_column'),
              AppLocalizations.get('match_goals_label'),
              AppLocalizations.get('match_assists_label'),
              AppLocalizations.get('cards_label'),
            ],
            rows,
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // ── Individual Player Report (coach_player_report_screen.dart) ───────────

  Future<Uint8List> generatePlayerReportPdf(CoachPlayerReport report) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    final m = report.bodyMetrics;
    final s = report.summary;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.format('rpt_player_report_title', {
                  'value': report.player.name,
                }),
                '${report.player.position ?? '—'}  ·  ${report.player.teamName ?? '—'}',
                now,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          if (m.latestWeight != null || m.latestHeight != null) ...[
            _sectionTitle(AppLocalizations.get('rpt_body_measurements_section')),
            pw.Row(
              children: [
                if (m.latestWeight != null)
                  _statCard(
                    AppLocalizations.get('rpt_weight_label'),
                    '${m.latestWeight!.toStringAsFixed(1)} kg',
                  ),
                if (m.latestHeight != null)
                  _statCard(
                    AppLocalizations.get('rpt_height_label'),
                    '${m.latestHeight!.toStringAsFixed(0)} cm',
                  ),
                if (m.latestBmi != null)
                  _statCard('BMI', m.latestBmi!.toStringAsFixed(1)),
              ],
            ),
          ],
          _sectionTitle(AppLocalizations.get('rpt_last_30_days_section')),
          pw.Row(
            children: [
              _statCard(
                'Hooper',
                s.averageHooper30d?.toStringAsFixed(1) ?? '—',
              ),
              _statCard('RPE', s.averagePostRpe30d?.toStringAsFixed(1) ?? '—'),
              _statCard(
                AppLocalizations.get('rpt_completion_label'),
                '${s.completionRate30d}%',
              ),
              _statCard(
                AppLocalizations.get('rpt_load_7d_label'),
                '${s.trainingLoad7d}',
              ),
            ],
          ),
          if (report.sessionHistory.isNotEmpty) ...[
            _sectionTitle(
              AppLocalizations.format('rpt_recent_sessions_section', {
                'value': report.sessionHistory.length,
              }),
            ),
            _brandedTable(
              [
                AppLocalizations.get('date_filter_label'),
                AppLocalizations.get('session_label'),
                AppLocalizations.get('duration'),
                AppLocalizations.get('status_label'),
              ],
              report.sessionHistory
                  .map(
                    (sh) => [
                      sh.date,
                      sh.title,
                      '${sh.durationMinutes} ${AppLocalizations.get('minute_unit')}',
                      sh.status,
                    ],
                  )
                  .toList(),
            ),
          ],
          if (report.assessmentHistory.isNotEmpty) ...[
            _sectionTitle(
              AppLocalizations.format('rpt_assessment_history_section', {
                'value': report.assessmentHistory.length,
              }),
            ),
            _brandedTable(
              [
                AppLocalizations.get('date_filter_label'),
                AppLocalizations.get('rpt_test_column'),
                AppLocalizations.get('rpt_total_score_column'),
                AppLocalizations.get('score_stability'),
                AppLocalizations.get('score_symmetry'),
                AppLocalizations.get('rpt_control_column'),
              ],
              report.assessmentHistory
                  .map(
                    (a) => [
                      a.date,
                      a.assessmentType,
                      '${a.overallScore}',
                      '${a.stabilityScore}',
                      '${a.symmetryScore}',
                      '${a.controlScore}',
                    ],
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  // ── Coach Team Report (coach_team_report_screen.dart) ────────────────────

  Future<Uint8List> generateCoachTeamReportPdf(CoachTeamReport report) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    final a = report.teamAverages;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.get('rpt_team_report_title'),
                report.teamName != null && report.teamName!.isNotEmpty
                    ? report.teamName!
                    : AppLocalizations.get('rpt_all_players_label'),
                now,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          pw.Row(
            children: [
              _statCard(AppLocalizations.get('rpt_player_count_label'), '${a.squadSize}'),
              _statCard('Hooper', a.avgHooper?.toStringAsFixed(1) ?? '—'),
              _statCard('RPE', a.avgPostRpe?.toStringAsFixed(1) ?? '—'),
              _statCard(AppLocalizations.get('rpt_completion_label'), '${a.completionRate}%'),
            ],
          ),
          _sectionTitle(
            AppLocalizations.format('rpt_all_players_section', {
              'value': report.players.length,
            }),
          ),
          _brandedTable(
            [
              AppLocalizations.get('rpt_player_column'),
              AppLocalizations.get('position_label'),
              'Hooper',
              'RPE',
              AppLocalizations.get('rpt_completion_label'),
              AppLocalizations.get('rpt_last_assessment_column'),
              AppLocalizations.get('status_label'),
            ],
            report.players
                .map(
                  (p) => [
                    p.name,
                    p.position ?? '—',
                    p.avgHooper?.toStringAsFixed(1) ?? '—',
                    p.avgPostRpe?.toStringAsFixed(1) ?? '—',
                    '${p.completionRate}%',
                    p.lastAssessmentScore?.toString() ?? '—',
                    p.status,
                  ],
                )
                .toList(),
          ),
          if (report.atRiskPlayers.isNotEmpty) ...[
            _sectionTitle(
              AppLocalizations.format('rpt_at_risk_players_section', {
                'value': report.atRiskPlayers.length,
              }),
            ),
            _brandedTable(
              [
                AppLocalizations.get('rpt_player_column'),
                AppLocalizations.get('position_label'),
                AppLocalizations.get('status_label'),
              ],
              report.atRiskPlayers
                  .map((p) => [p.name, p.position ?? '—', p.status])
                  .toList(),
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  // ── Team Training Load Report (team_training_load_report_screen.dart) ────
  // Matches the RPE APR Rwanda Excel layout: player rows × Mon-Sun daily
  // load + Weekly/Mean/SD/Monotony/Strain. Landscape — too many columns for
  // portrait A4. Values come straight from TrainingLoadCalculator via
  // api/club/team-wellness.php; this method only formats them for print.
  Future<Uint8List> generateTrainingLoadReportPdf(
    List<PlayerTrainingLoadRow> rows, {
    ReportMetadata? metadata,
    int? periodDays,
    DateTime? rangeFrom,
    DateTime? rangeTo,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    bool periodIncomplete(PlayerTrainingLoadRow row) =>
        rangeFrom != null && rangeTo != null
        ? isPeriodDataIncomplete(row, rangeFrom, rangeTo)
        : row.completenessStatus == 'INCOMPLETE';
    double? periodCompleteness(PlayerTrainingLoadRow row) =>
        rangeFrom != null && rangeTo != null
        ? computePeriodDataCompleteness(row, rangeFrom, rangeTo)
        : row.dataCompleteness;
    int periodIssueCount(PlayerTrainingLoadRow row, String issuePart) =>
        rangeFrom != null && rangeTo != null
        ? trainingLoadDaysInPeriod(row, rangeFrom, rangeTo)
              .expand((day) => day.dataQualityIssues)
              .where((issue) => issue.contains(issuePart))
              .length
        : issuePart == 'RPE'
        ? row.missingRpeCount
        : row.missingDurationCount;
    List<TrainingLoadSession> selectedSessions(PlayerTrainingLoadRow row) =>
        rangeFrom != null && rangeTo != null
        ? trainingLoadDaysInPeriod(row, rangeFrom, rangeTo)
              .expand((day) => day.sessions)
              .toList()
        : const [];
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.get('training_load_report_title'),
                AppLocalizations.get('training_load_report_subtitle'),
                now,
                metadata,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          pw.Row(
            children: [
              _statCard(AppLocalizations.get('rpt_players_plural_label'), '${rows.length}'),
              _statCard(
                AppLocalizations.get('rpt_period_completion_label'),
                rows.any(periodIncomplete)
                    ? AppLocalizations.get('rpt_incomplete_data')
                    : rows
                          .map(periodCompleteness)
                          .whereType<double>()
                          .isEmpty
                    ? AppLocalizations.get('rpt_na')
                    : '${(rows.map(periodCompleteness).whereType<double>().reduce((a, b) => a + b) / rows.map(periodCompleteness).whereType<double>().length * 100).toStringAsFixed(0)}%',
              ),
              _statCard(
                AppLocalizations.get('missing_rpe'),
                '${rows.fold<int>(0, (sum, row) => sum + periodIssueCount(row, 'RPE'))}',
              ),
              _statCard(
                AppLocalizations.get('missing_duration'),
                '${rows.fold<int>(0, (sum, row) => sum + periodIssueCount(row, 'DURATION'))}',
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            AppLocalizations.get('rpt_acwr_ranges_note'),
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
          // The Excel-style matrix is a fixed Mon-Sun weekly layout (its
          // Monotony/Strain columns are weekly stats by definition) — only
          // meaningful when the report's own period actually is "7 أيام".
          // Showing it for "اليوم"/"28 يوماً"/a custom range made every
          // export look identical and "weekly" no matter what was selected,
          // so skip it entirely otherwise and lead with the period summary.
          if (periodDays == null || periodDays == 7) ...[
            _sectionTitle(AppLocalizations.get('rpt_weekly_record_section')),
            _trainingLoadExcelTable(rows),
            pw.SizedBox(height: 4),
            pw.Text(
              AppLocalizations.get('rpt_weekly_load_note'),
              style: const pw.TextStyle(fontSize: 6.5, color: _muted),
            ),
            pw.NewPage(),
          ],
          // Only 7d/28d already have dedicated columns below — "today" and a
          // A selected period gets its own total from the requested daily
          // range; the ACWR columns remain explicitly 7d/4-week values.
          if (periodDays != null && periodDays != 7 && periodDays != 28) ...[
            _sectionTitle(
              AppLocalizations.format('rpt_period_quality_section', {
                'value': _periodOnlyLabel(periodDays),
              }),
            ),
            _denseTable(
              [
                AppLocalizations.get('rpt_player_column'),
                AppLocalizations.get('rpt_sessions_label'),
                AppLocalizations.get('rpt_minutes_column'),
                AppLocalizations.get('rpt_avg_rpe_column'),
                periodLoadLabel(periodDays),
                AppLocalizations.get('rpt_acute_load_column'),
                AppLocalizations.get('rpt_chronic_load_column'),
                'ACWR',
                AppLocalizations.get('rpt_classification_column'),
                AppLocalizations.get('rpt_completeness_column'),
              ],
              rows
                  .map(
                    (r) {
                      final sessions = selectedSessions(r);
                      final rpes = sessions
                          .map((session) => session.rpe)
                          .whereType<double>()
                          .toList();
                      final averageRpe = rpes.isEmpty
                          ? null
                          : rpes.reduce((a, b) => a + b) / rpes.length;
                      final minutes = sessions.fold<int>(
                        0,
                        (sum, session) =>
                            sum + (session.actualDurationMinutes ?? 0),
                      );
                      return [
                      r.playerName ?? '—',
                      '${sessions.length}',
                      '$minutes',
                      averageRpe?.toStringAsFixed(1) ??
                          AppLocalizations.get('rpt_na'),
                      () {
                        final v = computePeriodLoad(
                          r,
                          periodDays,
                          rangeFrom!,
                          rangeTo!,
                        );
                        return v == null
                            ? AppLocalizations.get('rpt_na')
                            : '${v.toStringAsFixed(0)}'
                                  '${periodIncomplete(r) ? '*' : ''}';
                      }(),
                      r.acuteLoad7d == null
                          ? AppLocalizations.get('rpt_na')
                          : '${r.acuteLoad7d!.toStringAsFixed(0)}'
                                '${periodIncomplete(r) ? '*' : ''}',
                      r.chronicLoadWeeklyAverage == null
                          ? AppLocalizations.get('rpt_na')
                          : '${r.chronicLoadWeeklyAverage!.toStringAsFixed(0)}'
                                '${periodIncomplete(r) ? '*' : ''}',
                      r.acwr?.toStringAsFixed(2) ??
                          AppLocalizations.get('rpt_acwr_requires_28d'),
                      _acwrLabel(r.acwrClassification),
                      periodIncomplete(r)
                          ? AppLocalizations.get('rpt_incomplete_short')
                          : AppLocalizations.get('complete_label'),
                      ];
                    },
                  )
                  .toList(),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.7),
                1: pw.FlexColumnWidth(0.6),
                2: pw.FlexColumnWidth(0.6),
                3: pw.FlexColumnWidth(0.7),
                4: pw.FlexColumnWidth(0.9),
                5: pw.FlexColumnWidth(0.8),
                6: pw.FlexColumnWidth(0.8),
                7: pw.FlexColumnWidth(0.8),
                8: pw.FlexColumnWidth(1.0),
                9: pw.FlexColumnWidth(0.7),
              },
              warningRows: rows
                  .map(periodIncomplete)
                  .toList(),
            ),
          ] else ...[
            _sectionTitle(
              AppLocalizations.format('rpt_period_quality_section', {
                'value': periodDays == 7
                    ? AppLocalizations.get('period_7_days')
                    : AppLocalizations.get('period_28_days'),
              }),
            ),
            _denseTable(
              [
                AppLocalizations.get('rpt_player_column'),
                AppLocalizations.get('rpt_sessions_label'),
                AppLocalizations.get('rpt_minutes_column'),
                AppLocalizations.get('rpt_avg_rpe_column'),
                AppLocalizations.get('rpt_acute_load_column'),
                AppLocalizations.get('rpt_chronic_load_column'),
                AppLocalizations.get('rpt_total_28d_column'),
                'ACWR',
                AppLocalizations.get('rpt_classification_column'),
                AppLocalizations.get('rpt_completeness_column'),
              ],
              rows
                  .map(
                    (r) => [
                      r.playerName ?? '—',
                      '${r.sessionsCount7d}',
                      '${r.totalMinutes7d}',
                      r.averageRpe7d?.toStringAsFixed(1) ??
                          AppLocalizations.get('rpt_na'),
                      r.acuteLoad7d == null
                          ? AppLocalizations.get('rpt_na')
                          : '${r.acuteLoad7d!.toStringAsFixed(0)}'
                                '${periodIncomplete(r) ? '*' : ''}',
                      r.chronicLoadWeeklyAverage == null
                          ? AppLocalizations.get('rpt_na')
                          : '${r.chronicLoadWeeklyAverage!.toStringAsFixed(0)}'
                                '${periodIncomplete(r) ? '*' : ''}',
                      r.load28d == null
                          ? AppLocalizations.get('rpt_na')
                          : '${r.load28d!.toStringAsFixed(0)}'
                                '${periodIncomplete(r) ? '*' : ''}',
                      r.acwr?.toStringAsFixed(2) ??
                          AppLocalizations.get('rpt_acwr_requires_28d'),
                      _acwrLabel(r.acwrClassification),
                      periodIncomplete(r)
                          ? AppLocalizations.get('rpt_incomplete_short')
                          : AppLocalizations.get('complete_label'),
                    ],
                  )
                  .toList(),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.8),
                1: pw.FlexColumnWidth(0.7),
                2: pw.FlexColumnWidth(0.7),
                3: pw.FlexColumnWidth(0.8),
                4: pw.FlexColumnWidth(0.9),
                5: pw.FlexColumnWidth(0.9),
                6: pw.FlexColumnWidth(0.9),
                7: pw.FlexColumnWidth(0.9),
                8: pw.FlexColumnWidth(1.1),
                9: pw.FlexColumnWidth(0.8),
              },
              warningRows: rows
                  .map(periodIncomplete)
                  .toList(),
            ),
          ],
          _sectionTitle(AppLocalizations.get('rpt_player_comparison_charts_section')),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      AppLocalizations.get('rpt_weekly_ce_chart_title'),
                      style: pw.TextStyle(
                        color: _maroon,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    _barChart(
                      rows
                          .take(14)
                          .map(
                            (row) =>
                                MapEntry(row.playerName ?? '—', row.weeklyLoad),
                          )
                          .toList(),
                      height: 92,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Monotony',
                      style: pw.TextStyle(
                        color: _maroon,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    _barChart(
                      rows
                          .take(14)
                          .map(
                            (row) =>
                                MapEntry(row.playerName ?? '—', row.monotony),
                          )
                          .toList(),
                      height: 92,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Strain',
                      style: pw.TextStyle(
                        color: _maroon,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    _barChart(
                      rows
                          .take(14)
                          .map(
                            (row) =>
                                MapEntry(row.playerName ?? '—', row.strain),
                          )
                          .toList(),
                      height: 92,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (metadata?.notes?.isNotEmpty == true) ...[
            _sectionTitle(AppLocalizations.get('rpt_notes_section')),
            pw.Text(
              metadata!.notes!,
              style: const pw.TextStyle(fontSize: 9, color: _ink),
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  String _periodOnlyLabel(int? periodDays) {
    switch (periodDays) {
      case 1:
        return AppLocalizations.get('period_today');
      case 7:
        return AppLocalizations.get('period_7_days');
      case 28:
        return AppLocalizations.get('period_28_days');
      default:
        return AppLocalizations.get('period_custom');
    }
  }

  Future<Uint8List> generateAcwrReportPdf(
    List<PlayerTrainingLoadRow> rows, {
    ReportMetadata? metadata,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    int count(String classification) =>
        rows.where((row) => row.acwrClassification == classification).length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.get('acwr_report_title'),
                AppLocalizations.get('acwr_report_subtitle'),
                now,
                metadata,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          pw.Row(
            children: [
              _acwrPdfSummaryCard(
                AppLocalizations.get('acwr_below_target'),
                count('BELOW_TARGET'),
                _acwrBlue,
              ),
              pw.SizedBox(width: 6),
              _acwrPdfSummaryCard(
                AppLocalizations.get('acwr_in_target'),
                count('IN_TARGET'),
                _acwrGreen,
              ),
              pw.SizedBox(width: 6),
              _acwrPdfSummaryCard(
                AppLocalizations.get('acwr_caution'),
                count('CAUTION'),
                _acwrYellow,
              ),
              pw.SizedBox(width: 6),
              _acwrPdfSummaryCard(
                AppLocalizations.get('acwr_above_target'),
                count('ABOVE_TARGET'),
                _acwrRed,
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          ...rows.map((row) {
            final color = _acwrPdfColor(row.acwrClassification);
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 6),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                children: [
                  pw.Container(width: 4, height: 42, color: color),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 9),
                      child: pw.Text(
                        row.playerName ?? '—',
                        style: pw.TextStyle(
                          color: _ink,
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  _acwrPdfMetric(
                    AppLocalizations.get('acute_load'),
                    row.acuteLoad7d?.toStringAsFixed(0) ?? '—',
                    _ink,
                  ),
                  _acwrPdfMetric(
                    AppLocalizations.get('chronic_load'),
                    row.chronicLoadWeeklyAverage?.toStringAsFixed(0) ?? '—',
                    _ink,
                  ),
                  _acwrPdfMetric(
                    AppLocalizations.get('acwr'),
                    row.acwr?.toStringAsFixed(2) ?? '—',
                    color,
                  ),
                  pw.Container(
                    width: 62,
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      _acwrPdfShortLabel(row.acwrClassification),
                      style: pw.TextStyle(
                        color: color,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
    return pdf.save();
  }

  pw.Widget _acwrPdfSummaryCard(
    String label,
    int value,
    PdfColor color,
  ) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 9),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: color, width: 0.8),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                '$value',
                style: pw.TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(label, style: pw.TextStyle(color: color, fontSize: 7)),
            ],
          ),
        ),
      );

  pw.Widget _acwrPdfMetric(
    String label,
    String value,
    PdfColor color,
  ) =>
      pw.Container(
        width: 70,
        padding: const pw.EdgeInsets.symmetric(vertical: 7),
        child: pw.Column(
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(label, style: const pw.TextStyle(color: _muted, fontSize: 6)),
          ],
        ),
      );

  // Compact portrait companion to the detailed team report. Mirrors the
  // one-page reference layout: one daily CE cell per weekday plus the weekly
  // summary, while preserving P0 data-quality states instead of inventing 0s.
  Future<Uint8List> generateCompactTrainingLoadReportPdf(
    List<PlayerTrainingLoadRow> rows, {
    ReportMetadata? metadata,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    final headers = [
      AppLocalizations.get('rpt_player_column'),
      AppLocalizations.weekdayName(1),
      AppLocalizations.weekdayName(2),
      AppLocalizations.weekdayName(3),
      AppLocalizations.weekdayName(4),
      AppLocalizations.weekdayName(5),
      AppLocalizations.weekdayName(6),
      AppLocalizations.weekdayName(7),
      AppLocalizations.get('rpt_weekly_column'),
      AppLocalizations.get('rpt_mean_column'),
      'ET',
      'Monotony',
      'Strain',
      AppLocalizations.get('status_label'),
    ];
    final tableRows = rows.map((row) {
      final days = _weekDays(row);
      final dailyValues = days.map(_compactDailyLoadText).toList();
      while (dailyValues.length < 7) {
        dailyValues.add('—');
      }
      return [
        row.playerName ?? AppLocalizations.get('rpt_na'),
        ...dailyValues.take(7),
        '${row.weeklyLoad.toStringAsFixed(0)}'
            '${row.completenessStatus == 'INCOMPLETE' ? '*' : ''}',
        MetricFormatter.average(row.dailyMean),
        MetricFormatter.standardDeviation(row.standardDeviation),
        _compactMonotonyText(row),
        _compactStrainText(row),
        row.completenessStatus == 'INCOMPLETE'
            ? AppLocalizations.get('rpt_incomplete_short')
            : row.calculationStatus == 'NO_LOAD'
            ? AppLocalizations.get('rpt_no_load')
            : AppLocalizations.get('complete_label'),
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.get('compact_training_load_title'),
                AppLocalizations.get('compact_training_load_subtitle'),
                now,
                metadata,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          _denseTable(
            headers,
            tableRows,
            columnWidths: const {
              0: pw.FlexColumnWidth(2.3),
              1: pw.FlexColumnWidth(0.62),
              2: pw.FlexColumnWidth(0.62),
              3: pw.FlexColumnWidth(0.62),
              4: pw.FlexColumnWidth(0.62),
              5: pw.FlexColumnWidth(0.62),
              6: pw.FlexColumnWidth(0.62),
              7: pw.FlexColumnWidth(0.62),
              8: pw.FlexColumnWidth(0.82),
              9: pw.FlexColumnWidth(0.82),
              10: pw.FlexColumnWidth(0.72),
              11: pw.FlexColumnWidth(1.0),
              12: pw.FlexColumnWidth(0.9),
              13: pw.FlexColumnWidth(0.85),
            },
            warningRows: rows
                .map((row) => row.completenessStatus == 'INCOMPLETE')
                .toList(),
            fontSize: 5.5,
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            AppLocalizations.get('rpt_sd_definition_note'),
            style: const pw.TextStyle(fontSize: 6.5, color: _muted),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generatePlayerTrainingLoadReportPdf({
    required PlayerTrainingLoadRow row,
    ReportMetadata? metadata,
    int? periodDays,
    DateTime? rangeFrom,
    DateTime? rangeTo,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    final hasSelectedRange = rangeFrom != null && rangeTo != null;
    final periodIncomplete = hasSelectedRange
        ? isPeriodDataIncomplete(row, rangeFrom, rangeTo)
        : row.completenessStatus == 'INCOMPLETE';
    final periodCompleteness = hasSelectedRange
        ? computePeriodDataCompleteness(row, rangeFrom, rangeTo)
        : row.dataCompleteness;
    final visibleDays = hasSelectedRange
        ? trainingLoadDaysInPeriod(row, rangeFrom, rangeTo)
        : row.days28;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.format('player_training_load_title', {
                  'value': row.playerName ?? AppLocalizations.get('player_name'),
                }),
                AppLocalizations.get('player_training_load_subtitle'),
                now,
                metadata,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          pw.Row(
            children: [
              _statCard(
                periodDays == null
                    ? AppLocalizations.get('rpt_period_load_label')
                    : periodLoadLabel(periodDays),
                periodDays == null || rangeFrom == null || rangeTo == null
                    ? AppLocalizations.get('rpt_na')
                    : '${computePeriodLoad(row, periodDays, rangeFrom, rangeTo)?.toStringAsFixed(0) ?? AppLocalizations.get('rpt_na')}'
                          '${periodIncomplete ? AppLocalizations.get('rpt_preliminary_suffix') : ''}',
              ),
              _statCard(
                AppLocalizations.get('rpt_chronic_load_column'),
                row.chronicLoadWeeklyAverage == null
                    ? AppLocalizations.get('rpt_na')
                    : row.chronicLoadWeeklyAverage!.toStringAsFixed(0),
              ),
              _statCard(
                'ACWR',
                row.acwr?.toStringAsFixed(2) ??
                    AppLocalizations.get('rpt_acwr_requires_28d'),
              ),
              _statCard(
                AppLocalizations.get('rpt_period_completion_label'),
                periodIncomplete
                    ? AppLocalizations.get('rpt_incomplete_data')
                    : periodCompleteness == null
                    ? AppLocalizations.get('rpt_na')
                    : '${(periodCompleteness * 100).toStringAsFixed(0)}%',
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              _statCard(
                AppLocalizations.get('rpt_weekly_total_label'),
                '${row.weeklyLoad.toStringAsFixed(0)}'
                    '${row.completenessStatus == 'INCOMPLETE' ? AppLocalizations.get('rpt_preliminary_suffix') : ''}',
              ),
              _statCard(
                AppLocalizations.get('rpt_daily_mean_label'),
                row.dailyMean.toStringAsFixed(2),
              ),
              _statCard(
                AppLocalizations.get('rpt_std_dev_label'),
                row.standardDeviation.toStringAsFixed(2),
              ),
              _statCard('Monotony', _monotonyText(row)),
              _statCard('Strain', _strainText(row)),
            ],
          ),
          _sectionTitle(AppLocalizations.get('rpt_daily_load_section')),
          _barChart(
            visibleDays
                .map(
                  (day) => MapEntry(
                    '${day.date.day}/${day.date.month}',
                    _chartedDailyLoad(day),
                  ),
                )
                .toList(),
            height: 110,
          ),
          _sectionTitle(AppLocalizations.get('rpt_session_details_section')),
          _brandedTable(
            [
              AppLocalizations.get('date_filter_label'),
              AppLocalizations.get('rpt_activity_column'),
              AppLocalizations.get('duration'),
              'RPE',
              'sRPE',
              AppLocalizations.get('data_status_label'),
            ],
            visibleDays
                .expand(
                  (day) => day.sessions.isEmpty
                      ? [
                          [
                            '${day.date.year}-${day.date.month.toString().padLeft(2, '0')}-${day.date.day.toString().padLeft(2, '0')}',
                            _dayStatusLabel(day.participationStatus),
                            AppLocalizations.get('rpt_na'),
                            AppLocalizations.get('rpt_na'),
                            AppLocalizations.get('rpt_na'),
                            _dayStatusLabel(day.participationStatus),
                          ],
                        ]
                      : day.sessions.map(
                          (session) => [
                            '${day.date.year}-${day.date.month.toString().padLeft(2, '0')}-${day.date.day.toString().padLeft(2, '0')}',
                            session.sessionName ??
                                session.sessionType ??
                                AppLocalizations.get('rpt_na'),
                            session.actualDurationMinutes?.toString() ??
                                AppLocalizations.get('rpt_na'),
                            session.rpe?.toStringAsFixed(1) ??
                                AppLocalizations.get('rpt_na'),
                            session.sessionLoad?.toStringAsFixed(0) ??
                                AppLocalizations.get('rpt_na'),
                            isTrainingLoadDayCompleteForPeriod(day)
                                ? _dayStatusLabel(day.participationStatus)
                                : AppLocalizations.get('rpt_incomplete_data'),
                          ],
                        ),
                )
                .toList(),
          ),
          if (metadata?.notes?.isNotEmpty == true) ...[
            _sectionTitle(AppLocalizations.get('rpt_notes_section')),
            pw.Text(
              metadata!.notes!,
              style: const pw.TextStyle(fontSize: 9, color: _ink),
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  // ── Team Wellness Report (team_wellness_screen.dart) ─────────────────────

  Future<Uint8List> generateTeamWellnessReportPdf({
    required TeamWellness wellness,
    required List<PlayerWellnessEntry> players,
    ReportMetadata? metadata,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.get('rpt_hooper_rpe_report_title'),
                AppLocalizations.get('rpt_hooper_rpe_subtitle'),
                now,
                metadata,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          pw.Row(
            children: [
              _statCard(
                AppLocalizations.get('rpt_team_readiness_label'),
                wellness.hasReadinessData
                    ? '${wellness.teamReadinessScore}%'
                    : AppLocalizations.get('rpt_na'),
              ),
              _statCard(
                AppLocalizations.get('rpt_avg_rpe_column'),
                wellness.hasAverageRpeData
                    ? wellness.averageRpe.toStringAsFixed(1)
                    : AppLocalizations.get('rpt_na'),
              ),
              _statCard(
                AppLocalizations.get('rpt_recovery_rate_label'),
                wellness.hasRecoveryData
                    ? '${wellness.recoveryScore}%'
                    : AppLocalizations.get('rpt_na'),
              ),
              _statCard(
                AppLocalizations.get('rpt_needs_attention_label'),
                '${wellness.playersNeedingAttention}',
              ),
            ],
          ),
          _sectionTitle(
            AppLocalizations.format('rpt_players_registered_section', {
              'count': players.length,
              'registered': players.where((p) => p.hooperScore != null).length,
              'unregistered': players.where((p) => p.hooperScore == null).length,
            }),
          ),
          _brandedTable(
            [
              AppLocalizations.get('rpt_player_column'),
              AppLocalizations.get('sleep_quality'),
              AppLocalizations.get('fatigue_label'),
              AppLocalizations.get('muscle_soreness'),
              AppLocalizations.get('stress_label'),
              'Hooper',
              'RPE',
              'sRPE',
              AppLocalizations.get('rpt_submission_time_column'),
              AppLocalizations.get('status_label'),
            ],
            players
                .map(
                  (p) => [
                    p.name,
                    p.sleepQuality?.toStringAsFixed(0) ??
                        AppLocalizations.get('rpt_na'),
                    p.fatigue?.toString() ?? AppLocalizations.get('rpt_na'),
                    p.muscleSoreness?.toStringAsFixed(0) ??
                        AppLocalizations.get('rpt_na'),
                    p.stress?.toStringAsFixed(0) ??
                        AppLocalizations.get('rpt_na'),
                    p.hooperScore?.toString() ?? AppLocalizations.get('rpt_na'),
                    p.lastRpe?.toStringAsFixed(1) ??
                        AppLocalizations.get('rpt_na'),
                    p.lastLoad?.toStringAsFixed(0) ??
                        AppLocalizations.get('rpt_na'),
                    p.submittedAt == null
                        ? AppLocalizations.get('rpt_na')
                        : '${p.submittedAt!.hour.toString().padLeft(2, '0')}:${p.submittedAt!.minute.toString().padLeft(2, '0')}',
                    _wellnessStatusLabel(p.wellnessStatus),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  String _now() {
    final now = DateTime.now();
    return '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _acwrLabel(String value) {
    switch (value) {
      case 'IN_TARGET':
        return AppLocalizations.get('acwr_in_target');
      case 'BELOW_TARGET':
        return AppLocalizations.get('acwr_below_target');
      case 'ABOVE_TARGET':
        return AppLocalizations.get('acwr_above_target');
      case 'CAUTION':
        return AppLocalizations.get('acwr_caution');
      case 'NO_CHRONIC_LOAD':
        return AppLocalizations.get('acwr_no_chronic_load');
      default:
        return AppLocalizations.get('acwr_insufficient_data');
    }
  }

  PdfColor _acwrPdfColor(String classification) {
    switch (classification) {
      case 'BELOW_TARGET':
        return _acwrBlue;
      case 'IN_TARGET':
        return _acwrGreen;
      case 'CAUTION':
        return _acwrYellow;
      case 'ABOVE_TARGET':
        return _acwrRed;
      default:
        return _muted;
    }
  }

  String _acwrPdfShortLabel(String classification) {
    switch (classification) {
      case 'BELOW_TARGET':
        return AppLocalizations.get('acwr_below_target');
      case 'IN_TARGET':
        return AppLocalizations.get('acwr_in_target');
      case 'CAUTION':
        return AppLocalizations.get('acwr_caution');
      case 'ABOVE_TARGET':
        return AppLocalizations.get('acwr_above_target');
      default:
        return AppLocalizations.get('acwr_incomplete');
    }
  }

  String _wellnessStatusLabel(String value) {
    switch (value) {
      case 'normal':
        return AppLocalizations.get('wellness_normal');
      case 'moderate':
        return AppLocalizations.get('wellness_moderate');
      case 'high_risk':
        return AppLocalizations.get('wellness_high_risk');
      default:
        return AppLocalizations.get('wellness_no_data');
    }
  }

  // ── Body Composition — single player report ──────────────────────────────

  Future<Uint8List> generateBodyCompositionReportPdf({
    required String playerName,
    required List<BodyCompositionEntry> history,
    ReportMetadata? metadata,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    // Approval gating removed — a coach-recorded measurement is usable in
    // reports the moment it's saved, no separate approval step.
    final approvedHistory = [...history]
      ..sort((a, b) => b.assessmentDate.compareTo(a.assessmentDate));
    final latest = approvedHistory.isNotEmpty ? approvedHistory.first : null;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.format('rpt_body_comp_report_title', {
                  'value': playerName,
                }),
                AppLocalizations.get('rpt_body_comp_subtitle'),
                now,
                metadata,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          if (latest == null)
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              color: _softBg,
              child: pw.Text(
                AppLocalizations.get('rpt_no_approved_measurement'),
                style: const pw.TextStyle(fontSize: 11, color: _muted),
              ),
            ),
          if (latest != null)
            pw.Row(
              children: [
                _statCard(
                  AppLocalizations.get('rpt_body_fat_pct_label'),
                  latest.bodyFatPercentage != null
                      ? '${latest.bodyFatPercentage!.toStringAsFixed(2)}%'
                      : AppLocalizations.get('rpt_na'),
                ),
                _statCard(
                  AppLocalizations.get('rpt_weight_label'),
                  _decimal(
                    latest.weightKg,
                    suffix: ' ${AppLocalizations.get('unit_kg')}',
                    zeroIsUnavailable: true,
                  ),
                ),
                _statCard(
                  AppLocalizations.get('rpt_height_label'),
                  _decimal(
                    latest.heightCm,
                    digits: 0,
                    suffix: ' ${AppLocalizations.get('unit_cm')}',
                    zeroIsUnavailable: true,
                  ),
                ),
                _statCard(
                  AppLocalizations.get('rpt_fat_mass_label'),
                  latest.fatMassKg != null
                      ? '${latest.fatMassKg!.toStringAsFixed(2)} ${AppLocalizations.get('unit_kg')}'
                      : AppLocalizations.get('rpt_na'),
                ),
              ],
            ),
          if (latest != null) ...[
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                _statCard(
                  AppLocalizations.get('rpt_fat_free_mass_label'),
                  _decimal(
                    latest.fatFreeMassKg,
                    digits: 2,
                    suffix: ' ${AppLocalizations.get('unit_kg')}',
                  ),
                ),
                _statCard('BMI', _decimal(latest.bmi, digits: 1)),
                _statCard(
                  AppLocalizations.get('rpt_measurement_date_label'),
                  latest.assessmentDate,
                ),
                _statCard(
                  AppLocalizations.get('rpt_measurement_status_label'),
                  latest.approvalStatus == 'approved'
                      ? AppLocalizations.get('rpt_approved_status')
                      : AppLocalizations.get('rpt_draft_status'),
                ),
              ],
            ),
            _sectionTitle(AppLocalizations.get('rpt_current_skinfolds_section')),
            _denseTable(
              [
                AppLocalizations.get('rpt_biceps_fold_column'),
                AppLocalizations.get('rpt_triceps_fold_column'),
                AppLocalizations.get('rpt_subscapular_fold_column'),
                AppLocalizations.get('rpt_suprailiac_fold_column'),
                AppLocalizations.get('rpt_skinfold_sum_column'),
                AppLocalizations.get('rpt_body_fat_pct_label'),
              ],
              [
                [
                  _decimal(latest.bicepsMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                  _decimal(latest.tricepsMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                  _decimal(latest.subscapularMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                  _decimal(latest.suprailiacMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                  _decimal(latest.skinfoldSumMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                  _decimal(latest.bodyFatPercentage, digits: 2, suffix: '%'),
                ],
              ],
              columnWidths: const {
                0: pw.FlexColumnWidth(1.2),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.2),
                3: pw.FlexColumnWidth(1.2),
                4: pw.FlexColumnWidth(1.0),
                5: pw.FlexColumnWidth(1.0),
              },
            ),
          ],
          _sectionTitle(AppLocalizations.get('rpt_body_fat_trend_section')),
          _barChart(
            approvedHistory
                .take(12)
                .toList()
                .reversed
                .map(
                  (entry) =>
                      MapEntry(entry.assessmentDate, entry.bodyFatPercentage),
                )
                .toList(),
            digits: 2,
          ),
          _sectionTitle(
            AppLocalizations.format('rpt_measurement_tracking_section', {
              'value': approvedHistory.length,
            }),
          ),
          _denseTable(
            [
              AppLocalizations.get('date_filter_label'),
              AppLocalizations.get('rpt_weight_label'),
              AppLocalizations.get('rpt_body_fat_pct_label'),
              AppLocalizations.get('rpt_fat_mass_label'),
              AppLocalizations.get('rpt_fat_free_mass_label'),
              AppLocalizations.get('rpt_skinfold_sum_column'),
              AppLocalizations.get('status_label'),
            ],
            approvedHistory
                .map(
                  (e) => [
                    e.assessmentDate,
                    _decimal(
                      e.weightKg,
                      suffix: ' ${AppLocalizations.get('unit_kg')}',
                      zeroIsUnavailable: true,
                    ),
                    _decimal(e.bodyFatPercentage, digits: 2, suffix: '%'),
                    _decimal(e.fatMassKg, digits: 2, suffix: ' ${AppLocalizations.get('unit_kg')}'),
                    _decimal(e.fatFreeMassKg, digits: 2, suffix: ' ${AppLocalizations.get('unit_kg')}'),
                    _decimal(e.skinfoldSumMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                    e.approvalStatus == 'approved'
                        ? AppLocalizations.get('rpt_approved_status')
                        : AppLocalizations.get('rpt_draft_status'),
                  ],
                )
                .toList(),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.0),
              1: pw.FlexColumnWidth(0.8),
              2: pw.FlexColumnWidth(0.8),
              3: pw.FlexColumnWidth(0.9),
              4: pw.FlexColumnWidth(1.2),
              5: pw.FlexColumnWidth(0.9),
              6: pw.FlexColumnWidth(0.8),
            },
            warningRows: approvedHistory
                .map(
                  (entry) =>
                      entry.approvalStatus != 'approved' ||
                      entry.calculationStatus.toUpperCase() != 'COMPLETE',
                )
                .toList(),
          ),
          pw.NewPage(),
          _sectionTitle(AppLocalizations.get('rpt_difference_from_previous_section')),
          _denseTable(
            [
              AppLocalizations.get('date_filter_label'),
              AppLocalizations.get('rpt_weight_diff_column'),
              AppLocalizations.get('rpt_body_fat_diff_column'),
              AppLocalizations.get('rpt_fat_mass_diff_column'),
              AppLocalizations.get('rpt_fat_free_mass_diff_column'),
            ],
            approvedHistory.indexed.map((indexed) {
              final entry = indexed.$2;
              final previous = indexed.$1 + 1 < approvedHistory.length
                  ? approvedHistory[indexed.$1 + 1]
                  : null;
              double? delta(double? current, double? old) =>
                  current != null && old != null ? current - old : null;
              return [
                entry.assessmentDate,
                _decimal(
                  delta(entry.weightKg, previous?.weightKg),
                  digits: 2,
                  suffix: ' ${AppLocalizations.get('unit_kg')}',
                ),
                _decimal(
                  delta(entry.bodyFatPercentage, previous?.bodyFatPercentage),
                  digits: 2,
                  suffix: '%',
                ),
                _decimal(
                  delta(entry.fatMassKg, previous?.fatMassKg),
                  digits: 2,
                  suffix: ' ${AppLocalizations.get('unit_kg')}',
                ),
                _decimal(
                  delta(entry.fatFreeMassKg, previous?.fatFreeMassKg),
                  digits: 2,
                  suffix: ' ${AppLocalizations.get('unit_kg')}',
                ),
              ];
            }).toList(),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // ── Body Composition — team overview report ───────────────────────────────

  Future<Uint8List> generateTeamBodyCompositionReportPdf({
    required List<BodyCompositionEntry> entries,
    int excludedPlayersCount = 0,
    ReportMetadata? metadata,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    // Approval gating removed — a coach-recorded measurement is usable in
    // reports the moment it's saved, no separate approval step.
    final approvedHistoryEntries = [...entries]
      ..sort((a, b) => b.assessmentDate.compareTo(a.assessmentDate));
    final approvedHistoryByPlayer = <String, List<BodyCompositionEntry>>{};
    for (final entry in approvedHistoryEntries) {
      final key = entry.linkedPlayerId ?? entry.playerName ?? entry.id;
      approvedHistoryByPlayer.putIfAbsent(key, () => []).add(entry);
    }
    final approvedEntries = approvedHistoryByPlayer.values
        .where((history) => history.isNotEmpty)
        .map((history) => history.first)
        .toList();
    BodyCompositionEntry? previousApproved(BodyCompositionEntry entry) {
      final key = entry.linkedPlayerId ?? entry.playerName ?? entry.id;
      final history = approvedHistoryByPlayer[key] ?? const [];
      return history.length > 1 ? history[1] : null;
    }

    double? approvedDelta(double? current, double? previous) =>
        current != null && previous != null ? current - previous : null;
    String average(
      double? Function(BodyCompositionEntry) pick, {
      int digits = 2,
      String suffix = '',
      bool Function(BodyCompositionEntry)? include,
    }) {
      final values = approvedEntries
          .where(include ?? (_) => true)
          .map(pick)
          .whereType<double>()
          .where((value) => value.isFinite && value > 0)
          .toList();
      if (values.isEmpty) return AppLocalizations.get('rpt_na');
      return '${(values.reduce((a, b) => a + b) / values.length).toStringAsFixed(digits)}$suffix';
    }

    final completeBodyFatEntries = approvedEntries
        .where(_hasCompleteBodyFat)
        .toList();
    final latestMeasurementDate = approvedEntries.isEmpty
        ? AppLocalizations.get('rpt_na')
        : approvedEntries
              .map((entry) => entry.assessmentDate)
              .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.get('rpt_team_body_comp_title'),
                AppLocalizations.get('rpt_team_body_comp_subtitle'),
                now,
                metadata,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          if (approvedEntries.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              color: _softBg,
              child: pw.Text(
                AppLocalizations.get('rpt_no_approved_measurements_period'),
                style: const pw.TextStyle(fontSize: 10, color: _muted),
              ),
            ),
          pw.Row(
            children: [
              _statCard(
                AppLocalizations.get('rpt_players_with_approved_label'),
                '${approvedEntries.length}',
              ),
              _statCard(
                AppLocalizations.get('rpt_used_in_fat_avg_label'),
                '${completeBodyFatEntries.length}',
              ),
              _statCard(
                AppLocalizations.get('rpt_excluded_missing_data_label'),
                '$excludedPlayersCount',
              ),
              _statCard(
                AppLocalizations.get('rpt_last_measurement_date_label'),
                latestMeasurementDate,
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              _statCard(
                AppLocalizations.get('rpt_avg_weight_label'),
                average(
                  (entry) => entry.weightKg,
                  digits: 1,
                  suffix: ' ${AppLocalizations.get('unit_kg')}',
                ),
              ),
              _statCard(
                AppLocalizations.get('rpt_avg_body_fat_label'),
                average(
                  (entry) => entry.bodyFatPercentage,
                  suffix: '%',
                  include: _hasCompleteBodyFat,
                ),
              ),
              _statCard(
                AppLocalizations.get('rpt_avg_fat_mass_label'),
                average(
                  (entry) => entry.fatMassKg,
                  suffix: ' ${AppLocalizations.get('unit_kg')}',
                  include: _hasCompleteBodyFat,
                ),
              ),
              _statCard(
                AppLocalizations.get('rpt_avg_fat_free_mass_label'),
                average(
                  (entry) => entry.fatFreeMassKg,
                  suffix: ' ${AppLocalizations.get('unit_kg')}',
                  include: _hasCompleteBodyFat,
                ),
              ),
            ],
          ),
          _sectionTitle(AppLocalizations.get('rpt_comparison_charts_section')),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      AppLocalizations.get('rpt_current_body_fat_chart_title'),
                      style: pw.TextStyle(
                        color: _maroon,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    _barChart(
                      approvedEntries
                          .take(14)
                          .map(
                            (entry) => MapEntry(
                              entry.playerName ?? '—',
                              _hasCompleteBodyFat(entry)
                                  ? entry.bodyFatPercentage
                                  : null,
                            ),
                          )
                          .toList(),
                      height: 92,
                      digits: 2,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      AppLocalizations.get('rpt_fat_mass_change_chart_title'),
                      style: pw.TextStyle(
                        color: _maroon,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    _barChart(
                      approvedEntries
                          .take(14)
                          .map(
                            (entry) => MapEntry(
                              entry.playerName ?? '—',
                              approvedDelta(
                                entry.fatMassKg,
                                previousApproved(entry)?.fatMassKg,
                              ),
                            ),
                          )
                          .toList(),
                      height: 92,
                      digits: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.NewPage(),
          _sectionTitle(AppLocalizations.get('rpt_skinfolds_body_fat_section')),
          _denseTable(
            [
              '#',
              AppLocalizations.get('rpt_player_column'),
              AppLocalizations.get('rpt_measurement_date_label'),
              AppLocalizations.get('position_label'),
              AppLocalizations.get('rpt_height_label'),
              AppLocalizations.get('rpt_weight_label'),
              AppLocalizations.get('rpt_biceps_short_column'),
              AppLocalizations.get('rpt_triceps_short_column'),
              AppLocalizations.get('rpt_subscapular_short_column'),
              AppLocalizations.get('rpt_suprailiac_short_column'),
              AppLocalizations.get('rpt_skinfold_sum_column'),
              AppLocalizations.get('rpt_body_fat_pct_label'),
              AppLocalizations.get('rpt_fat_mass_label'),
              AppLocalizations.get('rpt_fat_free_mass_label'),
              AppLocalizations.get('status_label'),
            ],
            approvedEntries.indexed
                .map(
                  (indexed) => [
                    '${indexed.$1 + 1}',
                    indexed.$2.playerName ?? AppLocalizations.get('rpt_na'),
                    indexed.$2.assessmentDate,
                    indexed.$2.position ?? AppLocalizations.get('rpt_na'),
                    _decimal(
                      indexed.$2.heightCm,
                      digits: 0,
                      suffix: ' ${AppLocalizations.get('unit_cm')}',
                      zeroIsUnavailable: true,
                    ),
                    _decimal(
                      indexed.$2.weightKg,
                      suffix: ' ${AppLocalizations.get('unit_kg')}',
                      zeroIsUnavailable: true,
                    ),
                    _decimal(indexed.$2.bicepsMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                    _decimal(indexed.$2.tricepsMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                    _decimal(indexed.$2.subscapularMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                    _decimal(indexed.$2.suprailiacMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                    _decimal(indexed.$2.skinfoldSumMm, suffix: ' ${AppLocalizations.get('unit_mm')}'),
                    _decimal(
                      indexed.$2.bodyFatPercentage,
                      digits: 2,
                      suffix: '%',
                    ),
                    _decimal(indexed.$2.fatMassKg, digits: 2, suffix: ' ${AppLocalizations.get('unit_kg')}'),
                    _decimal(
                      indexed.$2.fatFreeMassKg,
                      digits: 2,
                      suffix: ' ${AppLocalizations.get('unit_kg')}',
                    ),
                    indexed.$2.approvalStatus == 'approved'
                        ? AppLocalizations.get('rpt_approved_status')
                        : AppLocalizations.get('rpt_draft_status'),
                  ],
                )
                .toList(),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.4),
              1: pw.FlexColumnWidth(1.7),
              2: pw.FlexColumnWidth(1.0),
              3: pw.FlexColumnWidth(0.7),
              4: pw.FlexColumnWidth(0.7),
              5: pw.FlexColumnWidth(0.8),
              6: pw.FlexColumnWidth(0.7),
              7: pw.FlexColumnWidth(0.7),
              8: pw.FlexColumnWidth(0.8),
              9: pw.FlexColumnWidth(0.8),
              10: pw.FlexColumnWidth(0.9),
              11: pw.FlexColumnWidth(0.8),
              12: pw.FlexColumnWidth(0.9),
              13: pw.FlexColumnWidth(1.0),
              14: pw.FlexColumnWidth(0.8),
            },
            warningRows: approvedEntries
                .map(
                  (entry) =>
                      entry.approvalStatus != 'approved' ||
                      entry.calculationStatus.toUpperCase() != 'COMPLETE' ||
                      entry.goalStatus?.status == 'needs_follow_up' ||
                      entry.goalStatus?.status == 'behind',
                )
                .toList(),
            fontSize: 5.2,
          ),
          _sectionTitle(AppLocalizations.get('rpt_weight_fat_tracking_section')),
          _denseTable(
            [
              AppLocalizations.get('rpt_player_column'),
              AppLocalizations.get('rpt_previous_measurement_column'),
              AppLocalizations.get('rpt_previous_weight_column'),
              AppLocalizations.get('rpt_current_weight_column'),
              AppLocalizations.get('rpt_weight_diff_column'),
              AppLocalizations.get('rpt_previous_fat_pct_column'),
              AppLocalizations.get('rpt_current_fat_pct_column'),
              AppLocalizations.get('rpt_fat_diff_column'),
              AppLocalizations.get('rpt_previous_fat_mass_column'),
              AppLocalizations.get('rpt_current_fat_mass_column'),
              AppLocalizations.get('rpt_fat_mass_diff_column'),
              AppLocalizations.get('rpt_fat_free_diff_column'),
            ],
            approvedEntries.map((entry) {
              final previous = previousApproved(entry);
              final weightDelta = approvedDelta(
                entry.weightKg,
                previous?.weightKg,
              );
              final bodyFatDelta = approvedDelta(
                entry.bodyFatPercentage,
                previous?.bodyFatPercentage,
              );
              final fatMassDelta = approvedDelta(
                entry.fatMassKg,
                previous?.fatMassKg,
              );
              final fatFreeMassDelta = approvedDelta(
                entry.fatFreeMassKg,
                previous?.fatFreeMassKg,
              );
              return [
                entry.playerName ?? '—',
                previous?.assessmentDate ?? AppLocalizations.get('rpt_na'),
                _decimal(
                  previous?.weightKg,
                  suffix: ' ${AppLocalizations.get('unit_kg')}',
                  zeroIsUnavailable: true,
                ),
                _decimal(
                  entry.weightKg,
                  suffix: ' ${AppLocalizations.get('unit_kg')}',
                  zeroIsUnavailable: true,
                ),
                _decimal(weightDelta, digits: 2, suffix: ' ${AppLocalizations.get('unit_kg')}'),
                _decimal(previous?.bodyFatPercentage, digits: 2, suffix: '%'),
                _decimal(entry.bodyFatPercentage, digits: 2, suffix: '%'),
                _decimal(bodyFatDelta, digits: 2, suffix: '%'),
                _decimal(previous?.fatMassKg, digits: 2, suffix: ' ${AppLocalizations.get('unit_kg')}'),
                _decimal(entry.fatMassKg, digits: 2, suffix: ' ${AppLocalizations.get('unit_kg')}'),
                _decimal(fatMassDelta, digits: 2, suffix: ' ${AppLocalizations.get('unit_kg')}'),
                _decimal(fatFreeMassDelta, digits: 2, suffix: ' ${AppLocalizations.get('unit_kg')}'),
              ];
            }).toList(),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.7),
              1: pw.FlexColumnWidth(1.0),
              2: pw.FlexColumnWidth(0.9),
              3: pw.FlexColumnWidth(0.9),
              4: pw.FlexColumnWidth(0.8),
              5: pw.FlexColumnWidth(0.9),
              6: pw.FlexColumnWidth(0.9),
              7: pw.FlexColumnWidth(0.8),
              8: pw.FlexColumnWidth(1.0),
              9: pw.FlexColumnWidth(1.0),
              10: pw.FlexColumnWidth(1.0),
              11: pw.FlexColumnWidth(1.0),
            },
            warningRows: approvedEntries.map((entry) {
              final previous = previousApproved(entry);
              return (approvedDelta(
                            entry.bodyFatPercentage,
                            previous?.bodyFatPercentage,
                          ) ??
                          0) >
                      0 ||
                  (approvedDelta(entry.fatMassKg, previous?.fatMassKg) ?? 0) >
                      0;
            }).toList(),
            fontSize: 5.9,
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // ── Body Composition — two-assessment comparison report ──────────────────

  Future<Uint8List> generateBodyCompositionComparisonPdf({
    required Map<String, dynamic> from,
    required Map<String, dynamic> to,
    required List<BodyCompositionCompareRow> rows,
  }) async {
    final pdf = await _brandedDocument();
    final logo = await _logo();
    final now = _now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        textDirection: getAppLanguage() == 'ar'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        header: (c) => c.pageNumber == 1
            ? _pageHeader(
                logo,
                AppLocalizations.get('rpt_body_comp_comparison_title'),
                '${from['assessment_date']} → ${to['assessment_date']}',
                now,
              )
            : pw.SizedBox(),
        footer: _pageFooter,
        build: (context) => [
          _sectionTitle(AppLocalizations.get('rpt_comparison_table_section')),
          _brandedTable(
            [
              AppLocalizations.get('rpt_indicator_column'),
              AppLocalizations.get('rpt_start_column'),
              AppLocalizations.get('rpt_end_column'),
              AppLocalizations.get('rpt_difference_column'),
              AppLocalizations.get('rpt_pct_change_column'),
            ],
            rows
                .map(
                  (r) => [
                    r.label,
                    r.start?.toStringAsFixed(1) ?? '—',
                    r.end?.toStringAsFixed(1) ?? '—',
                    r.diff != null
                        ? '${r.diff! > 0 ? '+' : ''}${r.diff!.toStringAsFixed(1)}'
                        : '—',
                    r.pctChange != null ? '${r.pctChange}%' : '—',
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // ── Legacy English single-assessment PDF (kept for existing callers) ────

  Future<Uint8List> generatePdfReport(AssessmentResult result) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: _pdfPageMargin,
        build: (context) {
          return pw.Directionality(
            textDirection: getAppLanguage() == 'ar'
                ? pw.TextDirection.rtl
                : pw.TextDirection.ltr,
            child: pw.Container(
              width: double.infinity,
              child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  AppLocalizations.get('assessment_pdf_title'),
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  '${AppLocalizations.get('player_name')}: ${result.playerName}',
                ),
                pw.Text(
                  '${AppLocalizations.get('assessment_choose_test')}: ${result.testType.displayName}',
                ),
                pw.Text(
                  '${AppLocalizations.get('date_filter_label')}: ${result.createdAt.toLocal()}',
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  '${AppLocalizations.get('score')}: ${result.overallScore}',
                  style: const pw.TextStyle(fontSize: 18),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  AppLocalizations.get('assessment_pdf_subscores'),
                  style: const pw.TextStyle(fontSize: 16),
                ),
                pw.Bullet(
                  text: '${AppLocalizations.get('assessment_movement_quality')}: ${result.movementQualityScore}',
                ),
                pw.Bullet(
                  text: '${AppLocalizations.get('assessment_stability')}: ${result.stabilityScore}',
                ),
                pw.Bullet(
                  text: '${AppLocalizations.get('assessment_symmetry')}: ${result.symmetryScore}',
                ),
                pw.Bullet(
                  text: '${AppLocalizations.get('assessment_control')}: ${result.controlScore}',
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  AppLocalizations.get('assessment_pdf_key_metrics'),
                  style: const pw.TextStyle(fontSize: 16),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: result.angleMetrics.entries
                      .map(
                        (entry) => pw.Text(
                          '${entry.key}: ${entry.value.toStringAsFixed(1)}°',
                        ),
                      )
                      .toList(),
                ),
                pw.SizedBox(height: 14),
                pw.Text(
                  AppLocalizations.get('assessment_issues_title'),
                  style: const pw.TextStyle(fontSize: 16),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: result.issues
                      .map((issue) => pw.Text('• $issue'))
                      .toList(),
                ),
                pw.SizedBox(height: 14),
                pw.Text(
                  AppLocalizations.get('assessment_drills_title'),
                  style: const pw.TextStyle(fontSize: 16),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: result.correctionTips
                      .map((tip) => pw.Text('• $tip'))
                      .toList(),
                ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return pdf.save();
  }
}
