import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/assessment_result_model.dart';
import '../../services/assessment_storage_service.dart';
import '../../widgets/common_widgets.dart';

class AssessmentResultPage extends StatefulWidget {
  const AssessmentResultPage({super.key, required this.result});

  final AssessmentResult result;

  @override
  State<AssessmentResultPage> createState() => _AssessmentResultPageState();
}

class _AssessmentResultPageState extends State<AssessmentResultPage> {
  bool _saving = false;
  bool _saved = false;

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
        child: Stack(
          children: [
            // DEBUG LABEL - REMOVE IN PRODUCTION
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PREMIUM RESULT PAGE ACTIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                // Hero score section
                _buildHeroScore(),
                const SizedBox(height: 20),
                // Three metric bars
                _buildMetricBars(),
                const SizedBox(height: 20),
                // Angle metrics table
                _buildAngleMetricsTable(),
                const SizedBox(height: 20),
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
                PrimaryButton(
                  label: _saved ? 'Saved ✓' : 'Save Assessment',
                  onTap: _saved || _saving ? () {} : () => _saveAgain(),
                ),
                if (kDebugMode && widget.result.debugData.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildDebugPanel(),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroScore() {
    final grade = widget.result.overallScore >= 85
        ? 'Excellent'
        : widget.result.overallScore >= 75
            ? 'Good'
            : widget.result.overallScore >= 65
                ? 'Fair'
                : 'Needs Work';

    final gradeColor = widget.result.overallScore >= 85
        ? AppColors.primary
        : widget.result.overallScore >= 75
            ? Colors.amber
            : Colors.red;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            widget.result.playerName,
            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
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
                        color: Colors.white,
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
            style: const TextStyle(color: Colors.white70, fontSize: 12),
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
          _metricBar('Movement Quality', widget.result.movementQualityScore),
          const SizedBox(height: 16),
          _metricBar('Stability', widget.result.stabilityScore),
          const SizedBox(height: 16),
          _metricBar('Symmetry', widget.result.symmetryScore),
        ],
      ),
    );
  }

  Widget _metricBar(String label, int score) {
    final color = score >= 85 ? AppColors.primary : score >= 75 ? Colors.amber : Colors.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text('$score', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        RoundedProgress(value: score / 100, dark: false),
      ],
    );
  }

  Widget _buildAngleMetricsTable() {
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
          const Text(
            'Joint Angles',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          ...widget.result.angleMetrics.entries.map((entry) {
            final value = entry.value;
            Color dotColor = Colors.white;
            if (entry.key.contains('Trunk')) {
              dotColor = value > 20 ? Colors.red : Colors.white;
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(entry.key, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                  Text('${value.toStringAsFixed(0)}°', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
        const Text(
          'Detected Issues',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
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
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
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
        const Text(
          'Recommendations',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
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
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
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
    setState(() {
      _saving = true;
    });
    await AssessmentStorageService.instance.saveAssessment(widget.result);
    setState(() {
      _saving = false;
      _saved = true;
    });
  }
}
