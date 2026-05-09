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
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            _summaryCard(),
            const SizedBox(height: 16),
            _metricsCard(),
            const SizedBox(height: 16),
            _sectionCard(
              title: AppLocalizations.get('assessment_issues_title'),
              items: widget.result.issues,
              emptyText: AppLocalizations.get('assessment_no_issues'),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: AppLocalizations.get('assessment_tips_title'),
              items: widget.result.correctionTips,
              emptyText: AppLocalizations.get('assessment_no_tips'),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: AppLocalizations.get('assessment_drills_title'),
              items: widget.result.recommendedDrills,
              emptyText: AppLocalizations.get('assessment_no_drills'),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: _saved
                  ? AppLocalizations.get('assessment_saved')
                  : AppLocalizations.get('assessment_save_result'),
              onTap: _saved || _saving ? () {} : () => _saveAgain(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.result.testType.displayName,
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.result.playerName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${widget.result.overallScore}/100',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _scorePill(AppLocalizations.get('assessment_movement_quality'), widget.result.movementQualityScore),
              _scorePill(AppLocalizations.get('assessment_symmetry'), widget.result.symmetryScore),
              _scorePill(AppLocalizations.get('assessment_stability'), widget.result.stabilityScore),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.get('assessment_metric_breakdown'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 14),
          for (final entry in widget.result.angleMetrics.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(entry.key, style: const TextStyle(color: Colors.white70)),
                  ),
                  Text('${entry.value.toStringAsFixed(0)}°', style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required List<String> items, required String emptyText}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(emptyText, style: const TextStyle(color: Colors.white70))
          else
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item, style: const TextStyle(color: Colors.white70))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _scorePill(String label, int score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text('$score', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
