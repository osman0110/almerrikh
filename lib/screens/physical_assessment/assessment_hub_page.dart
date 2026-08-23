import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/assessment_result_model.dart';
import '../../models/player_profile_model.dart';
import '../../services/player_service.dart';
import '../../utils/app_logger.dart';
import '../../widgets/common_widgets.dart';
import 'assessment_camera_page.dart';
import 'web_pose_setup_screen.dart'
    if (dart.library.io) 'web_pose_setup_screen_stub.dart';

class AssessmentHubPage extends StatefulWidget {
  const AssessmentHubPage({super.key});

  @override
  State<AssessmentHubPage> createState() => _AssessmentHubPageState();
}

class _AssessmentHubPageState extends State<AssessmentHubPage> {
  @override
  Widget build(BuildContext context) {
    // Player role: pushed as a sub-screen from the Training hub tab —
    // plain Scaffold with a back button, matching the pattern below.
    if (currentUserRole == UserRole.player) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text(AppLocalizations.get('assessment_hub_title')),
        ),
        body: ApiService.token == null
            ? _SignInPrompt()
            : _PlayerRoleHub(),
      );
    }

    if (ApiService.token != null &&
        currentUserId != null &&
        currentUserRole == UserRole.club &&
        !canRunAssessments) {
      return const RoleAccessDeniedPage();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(AppLocalizations.get('assessment_hub_title')),
      ),
      body: Builder(
        builder: (context) {
          if (ApiService.token == null) {
            return _SignInPrompt();
          }

          // Club/coach role: show full players list
          return StreamBuilder<List<PlayerProfile>>(
            stream: PlayerService.instance.streamPlayers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2),
                );
              }
              final players = snapshot.data ?? const [];
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xff150A12), Color(0xff0A0810), Color(0xff100812)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.get('assessment_hub_title'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          AppLocalizations.get('assessment_hub_subtitle'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 22),
                        PrimaryButton(
                          label: AppLocalizations.get('assessment_start'),
                          onTap: () => Navigator.of(context).pushNamed(
                            '/physical-assessment/select',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.get('assessment_players_title'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (players.isEmpty)
                          _EmptyCard(
                            label: AppLocalizations.get('assessment_no_players'),
                            actionLabel: AppLocalizations.get('assessment_add_player'),
                            onAction: () => Navigator.of(context).pushNamed(
                              '/physical-assessment/new-player',
                            ),
                          )
                        else ...[
                          for (final player in players) _PlayerCard(player: player),
                          const SizedBox(height: 12),
                          Text(
                            AppLocalizations.get('assessment_tips_title'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.get('assessment_tips_body'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.get('assessment_auth_required'),
              style: const TextStyle(color: AppColors.muted, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: AppLocalizations.get('sign_in_btn'),
              onTap: () => Navigator.of(context).pushNamed('/auth'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.player});

  final PlayerProfile player;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).pushNamed(
                '/physical-assessment/history',
                arguments: player,
              );
            },
            icon: const Icon(Icons.history_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

// ── Player-role hub: shows only the player's own profile ─────────────────────
class _PlayerRoleHub extends StatefulWidget {
  @override
  State<_PlayerRoleHub> createState() => _PlayerRoleHubState();
}

class _PlayerRoleHubState extends State<_PlayerRoleHub> {
  PlayerProfile? _profile;
  bool _loading = true;
  AssessmentTestType? _selectedTest;

  // MVP tests only
  static const _tests = [
    AssessmentTestType.squat,
    AssessmentTestType.singleLegBalance,
    AssessmentTestType.jumpLanding,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getMyPlayerProfile();
      final pMap = data['player'] as Map<String, dynamic>?;
      if (pMap != null && mounted) {
        final id = pMap['id']?.toString() ?? '';
        setState(() {
          _profile = PlayerProfile.fromMap(id, pMap);
          _loading = false;
        });
        return;
      }
      // Fallback: create profile from user data
      final uMap = data['user'] as Map<String, dynamic>?;
      if (uMap != null && mounted) {
        setState(() {
          _profile = PlayerProfile(
            id: uMap['id']?.toString() ?? '',
            name: uMap['name'] as String? ?? AppLocalizations.get('nav_my_profile'),
          );
          _loading = false;
        });
        return;
      }
    } catch (e) {
      AppLogger.e('AssessmentHub', 'Failed to load player profile', e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        // Header
        Text(
          AppLocalizations.get('assessment_hub_title'),
          style: const TextStyle(
            color: AppColors.foreground, fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.get('assessment_hub_subtitle'),
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        if (_profile == null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(AppLocalizations.get('error_generic'),
                      style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    _load();
                  },
                  child: Text(AppLocalizations.get('retry')),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Test selector
        Text(
          AppLocalizations.get('assessment_choose_test'),
          style: const TextStyle(
            color: AppColors.foreground, fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        for (final t in _tests) ...[
          GestureDetector(
            onTap: () => setState(() => _selectedTest = t),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _selectedTest == t
                    ? AppColors.primary.withOpacity(0.15)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedTest == t
                      ? AppColors.primary
                      : AppColors.border,
                  width: _selectedTest == t ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sports_score_rounded,
                    color: _selectedTest == t ? AppColors.primary : AppColors.muted,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.displayName,
                      style: TextStyle(
                        color: _selectedTest == t
                            ? AppColors.primary
                            : AppColors.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (_selectedTest == t)
                    Icon(Icons.check_circle_rounded,
                        color: AppColors.primary, size: 18),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Start button
        ElevatedButton.icon(
          onPressed: (_selectedTest == null || _profile == null)
              ? null
              : () {
                  final args = AssessmentCameraArguments(
                    player: _profile!,
                    testType: _selectedTest!,
                  );
                  if (kIsWeb) {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => WebPoseSetupScreen(cameraArgs: args),
                    ));
                  } else {
                    Navigator.of(context).push(PageRouteBuilder(
                      pageBuilder: (_, __, ___) => AssessmentCameraPage(
                        player: args.player,
                        testType: args.testType,
                      ),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                      transitionDuration: const Duration(milliseconds: 200),
                    ));
                  }
                },
          icon: const Icon(Icons.videocam_rounded),
          label: Text(_selectedTest == null
              ? AppLocalizations.get('assessment_choose_test')
              : AppLocalizations.get('assessment_start')),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.label,
    required this.actionLabel,
    required this.onAction,
  });

  final String label;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: actionLabel, onTap: onAction),
        ],
      ),
    );
  }
}
