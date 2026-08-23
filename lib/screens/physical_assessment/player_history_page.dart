import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/assessment_result_model.dart';
import '../../models/player_profile_model.dart';
import '../../services/assessment_storage_service.dart';

class PlayerHistoryPage extends StatelessWidget {
  const PlayerHistoryPage({super.key, required this.player});

  final PlayerProfile player;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('${player.name} • ${AppLocalizations.get('assessment_history_title')}'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<AssessmentResult>>(
          stream: AssessmentStorageService.instance.streamAssessments(player.id),
          builder: (context, snapshot) {
            final results = snapshot.data;
            if (results == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (results.isEmpty) {
              return Center(
                child: Text(
                  AppLocalizations.get('assessment_history_empty'),
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              itemCount: results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _HistoryCard(result: results[index]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.result});

  final AssessmentResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.testType.displayName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${result.overallScore}/100',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            result.createdAt.toLocal().toString().split('.').first,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _ValueLabel(label: AppLocalizations.get('assessment_symmetry'), value: '${result.symmetryScore}%')),
              Expanded(child: _ValueLabel(label: AppLocalizations.get('assessment_stability'), value: '${result.stabilityScore}%')),
              Expanded(child: _ValueLabel(label: AppLocalizations.get('assessment_quality'), value: '${result.qualityScore}%')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueLabel extends StatelessWidget {
  const _ValueLabel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
