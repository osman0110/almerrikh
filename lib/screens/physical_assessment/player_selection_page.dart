import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/assessment_result_model.dart';
import '../../models/player_profile_model.dart';
import '../../services/player_service.dart';
import '../../widgets/common_widgets.dart';
import 'assessment_camera_page.dart';
import 'web_pose_setup_screen.dart'
    if (dart.library.io) 'web_pose_setup_screen_stub.dart';

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
                  final isSignedIn = ApiService.token != null;
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
                                    final args = AssessmentCameraArguments(
                                      player: player,
                                      testType: selectedTest!,
                                    );
                                    if (kIsWeb) {
                                      Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => WebPoseSetupScreen(cameraArgs: args),
                                      ));
                                      return;
                                    }
                                    Navigator.of(context).push(
                                        PageRouteBuilder(
                                          pageBuilder: (_, __, ___) =>
                                              AssessmentCameraPage(
                                                player: args.player,
                                                testType: args.testType,
                                              ),
                                          transitionsBuilder:
                                              (_, anim, __, child) =>
                                                  FadeTransition(
                                                      opacity: anim,
                                                      child: child),
                                          transitionDuration:
                                              const Duration(milliseconds: 200),
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
                                        ? CachedNetworkImageProvider(player.photoUrl!)
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${player.position ?? AppLocalizations.get('unknown_position')} • ${player.team ?? AppLocalizations.get('unknown_team')}',
                                          style: const TextStyle(color: Colors.white70),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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

  // Tests that are not yet fully implemented
  static bool _isComingSoon(AssessmentTestType t) =>
      t == AssessmentTestType.singleLegBalance ||
      t == AssessmentTestType.jumpLanding;

  Widget _buildTestSelector() {
    final tests = AssessmentTestType.values;
    return SizedBox(
      height: 130,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: tests.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final test = tests[index];
          final active = selectedTest == test;
          final comingSoon = _isComingSoon(test);
          return GestureDetector(
            onTap: comingSoon
                ? () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.get('coming_soon_description')),
                        backgroundColor: AppColors.card,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                : () => setState(() => selectedTest = test),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 190,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: comingSoon
                    ? AppColors.card.withOpacity(0.5)
                    : active ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: comingSoon
                      ? AppColors.border.withOpacity(0.4)
                      : active ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          test.displayName,
                          style: TextStyle(
                            color: comingSoon
                                ? Colors.white38
                                : active ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (comingSoon)
                        Container(
                          margin: const EdgeInsetsDirectional.only(start: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            AppLocalizations.get('coming_soon_label'),
                            style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    comingSoon
                        ? AppLocalizations.get('coming_soon_description')
                        : AppLocalizations.get('assessment_test_short_${test.id}'),
                    style: TextStyle(
                      color: comingSoon
                          ? Colors.white24
                          : active ? Colors.black87 : Colors.white70,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
