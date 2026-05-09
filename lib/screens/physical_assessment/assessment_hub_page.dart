import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/player_profile_model.dart';
import '../../services/firebase_service.dart';
import '../../services/player_service.dart';
import '../../widgets/common_widgets.dart';

class AssessmentHubPage extends StatefulWidget {
  const AssessmentHubPage({super.key});

  @override
  State<AssessmentHubPage> createState() => _AssessmentHubPageState();
}

class _AssessmentHubPageState extends State<AssessmentHubPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(AppLocalizations.get('assessment_hub_title')),
      ),
      body: Builder(
        builder: (context) {
          final isSignedIn = FirebaseService().uid != null;
          if (!isSignedIn) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AppLocalizations.get('assessment_auth_required'),
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
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
          return StreamBuilder<List<PlayerProfile>>(
            stream: PlayerService.instance.streamPlayers(),
            builder: (context, snapshot) {
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
            backgroundImage:
                player.photoUrl != null ? NetworkImage(player.photoUrl!) : null,
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
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
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
