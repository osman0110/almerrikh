import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/player_profile_model.dart';
import '../../models/assessment_result_model.dart';
import 'assessment_camera_page.dart';
import '../../services/firebase_service.dart';
import '../../services/player_service.dart';
import '../../widgets/common_widgets.dart';

class PlayerSelectionPage extends StatefulWidget {
  const PlayerSelectionPage({super.key});

  @override
  State<PlayerSelectionPage> createState() => _PlayerSelectionPageState();
}

class _PlayerSelectionPageState extends State<PlayerSelectionPage> {
  AssessmentTestType? selectedTest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(AppLocalizations.get('assessment_select_title')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Text(
                AppLocalizations.get('assessment_select_subtitle'),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            _buildTestSelector(),
            Expanded(
              child: Builder(
                builder: (context) {
                  final isSignedIn = FirebaseService().uid != null;
                  if (!isSignedIn) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppLocalizations.get('assessment_auth_required'),
                            style: const TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          PrimaryButton(
                            label: AppLocalizations.get('sign_in_btn'),
                            onTap: () => Navigator.of(context).pushNamed('/auth'),
                          ),
                        ],
                      ),
                    );
                  }
                  return StreamBuilder<List<PlayerProfile>>(
                    stream: PlayerService.instance.streamPlayers(),
                    builder: (context, snapshot) {
                      final players = snapshot.data ?? const [];
                      if (players.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                AppLocalizations.get('assessment_no_players'),
                                style: const TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 18),
                              PrimaryButton(
                                label: AppLocalizations.get('assessment_add_player'),
                                onTap: () => Navigator.of(context).pushNamed(
                                  '/physical-assessment/new-player',
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        itemCount: players.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final player = players[index];
                          return GestureDetector(
                            onTap: selectedTest == null
                                ? null
                                : () {
                                    Navigator.of(context).pushNamed(
                                      '/physical-assessment/camera',
                                      arguments: AssessmentCameraArguments(
                                        player: player,
                                        testType: selectedTest!,
                                      ),
                                    );
                                  },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: AppColors.surface2,
                                    backgroundImage: player.photoUrl != null
                                        ? NetworkImage(player.photoUrl!)
                                        : null,
                                    child: player.photoUrl == null
                                        ? Text(player.name.isNotEmpty ? player.name[0] : '?')
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          player.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${player.position ?? AppLocalizations.get('unknown_position')} • ${player.team ?? AppLocalizations.get('unknown_team')}',
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selectedTest != null)
                                    const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: PrimaryButton(
          label: selectedTest == null
              ? AppLocalizations.get('assessment_choose_test')
              : AppLocalizations.get('assessment_choose_player'),
          onTap: () {
            if (selectedTest == null) {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppColors.card,
                  title: Text(AppLocalizations.get('assessment_choose_test')),
                  content: Text(AppLocalizations.get('assessment_select_test_hint')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(AppLocalizations.get('back_btn')),
                    ),
                  ],
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildTestSelector() {
    final tests = AssessmentTestType.values;
    return SizedBox(
      height: 120,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: tests.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final test = tests[index];
          final active = selectedTest == test;
          return GestureDetector(
            onTap: () => setState(() => selectedTest = test),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 180,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? AppColors.primary : AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    test.displayName,
                    style: TextStyle(
                      color: active ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.get('assessment_test_short_${test.id}'),
                    style: TextStyle(
                      color: active ? Colors.black87 : Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
