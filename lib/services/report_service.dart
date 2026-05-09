import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/assessment_result_model.dart';

class ReportService {
  ReportService._internal();
  static final ReportService instance = ReportService._internal();

  Future<Uint8List> generatePdfReport(AssessmentResult result) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('AI Physical Assessment Report',
                    style: pw.TextStyle(
                        fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Text('Player: ${result.playerName}'),
                pw.Text('Test: ${result.testType.displayName}'),
                pw.Text('Date: ${result.createdAt.toLocal()}'),
                pw.SizedBox(height: 18),
                pw.Text('Overall Score: ${result.overallScore}',
                    style: const pw.TextStyle(fontSize: 18)),
                pw.SizedBox(height: 12),
                pw.Text('Sub-scores', style: const pw.TextStyle(fontSize: 16)),
                pw.Bullet(text: 'Movement Quality: ${result.movementQualityScore}'),
                pw.Bullet(text: 'Stability: ${result.stabilityScore}'),
                pw.Bullet(text: 'Symmetry: ${result.symmetryScore}'),
                pw.Bullet(text: 'Control: ${result.controlScore}'),
                pw.SizedBox(height: 12),
                pw.Text('Key metrics', style: const pw.TextStyle(fontSize: 16)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: result.angleMetrics.entries
                      .map((entry) => pw.Text('${entry.key}: ${entry.value.toStringAsFixed(1)}°'))
                      .toList(),
                ),
                pw.SizedBox(height: 14),
                pw.Text('Issues', style: const pw.TextStyle(fontSize: 16)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: result.issues.map((issue) => pw.Text('• $issue')).toList(),
                ),
                pw.SizedBox(height: 14),
                pw.Text('Correction Tips', style: const pw.TextStyle(fontSize: 16)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: result.correctionTips.map((tip) => pw.Text('• $tip')).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
    return pdf.save();
  }
}
