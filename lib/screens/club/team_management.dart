import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../shared/club_ui_tokens.dart';
import '../../widgets/common_widgets.dart';
import 'club_dashboard.dart';
import 'club_widgets.dart';

class TeamManagementPage extends StatefulWidget {
  const TeamManagementPage({super.key});

  @override
  State<TeamManagementPage> createState() => _TeamManagementPageState();
}

class _TeamManagementPageState extends State<TeamManagementPage> {
  List<ClubTeam> _teams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final teams = await ClubService().getTeams();
    if (!mounted) return;
    setState(() {
      _teams = teams;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!canManageTeams) return const RoleAccessDeniedPage();
    return ClubShell(
      currentIndex: 0,
      child: Column(
        children: [
          ClubAppHeader(
            title: AppLocalizations.get('team_management'),
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.foreground, size: 18),
              ),
            ),
            trailing: GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddEditTeamPage()),
                );
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(ClubUiTokens.buttonRadius - 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, color: AppColors.foreground, size: 18),
                    const SizedBox(width: 6),
                    Text(AppLocalizations.get('add'),
                        style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _teams.isEmpty
                    ? ClubEmptyState(
                        icon: Icons.groups_rounded,
                        title: AppLocalizations.get('no_teams_yet'),
                        description: AppLocalizations.get('create_first_team_hint'),
                        ctaLabel: AppLocalizations.get('create_team'),
                        onCta: () async {
                          await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AddEditTeamPage()));
                          _load();
                        },
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.card,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          itemCount: _teams.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final team = _teams[i];
                            return _TeamCard(
                              team: team,
                              onTap: () {
                                currentTeamId = team.id;
                                currentTeamName = team.name;
                                Navigator.of(context).pushNamed(
                                    '/club/players',
                                    arguments: {'teamId': team.id});
                              },
                              onEdit: () => Navigator.of(context)
                                  .push(MaterialPageRoute(
                                      builder: (_) => AddEditTeamPage(team: team)))
                                  .then((_) => _load()),
                              onDelete: () => _showDeleteConfirm(team),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirm(ClubTeam team) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClubConfirmDialog(
        title: AppLocalizations.get('delete_team_title'),
        body: AppLocalizations.format('delete_team_msg', {'name': team.name}),
      ),
    );
    if (ok == true) {
      final deleted = await ClubService().deleteTeam(team.id);
      if (!mounted) return;
      if (deleted) {
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.get('error_generic'))),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team Card
// ─────────────────────────────────────────────────────────────────────────────

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });
  final ClubTeam team;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(ClubUiTokens.cardRadius),
          border: Border.all(color: AppColors.border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ClubUiTokens.cardRadius - 0.8),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 34, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.shield_rounded,
                          color: AppColors.maroon, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.name,
                            style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(children: [
                            ClubStatusBadge(
                                label: team.category.label, color: AppColors.maroon),
                            const SizedBox(width: 6),
                            ClubStatusBadge(label: team.season, color: AppColors.primary),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            _TeamStat(
                                icon: Icons.people_rounded,
                                label: AppLocalizations.get('players_title'),
                                value: '${team.playerCount}'),
                            const SizedBox(width: 16),
                            _TeamStat(
                                icon: Icons.person_rounded,
                                label: AppLocalizations.get('coach_label'),
                                value: team.coachName.isNotEmpty
                                    ? team.coachName
                                    : '—'),
                            const SizedBox(width: 16),
                            _TeamStat(
                                icon: Icons.fitness_center_rounded,
                                label: AppLocalizations.get('physical_coach_label'),
                                value: team.physicalCoachName.isNotEmpty
                                    ? team.physicalCoachName
                                    : '—'),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded,
                      color: AppColors.muted, size: 18),
                  color: AppColors.card,
                  elevation: 4,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      height: 42,
                      child: Row(children: [
                        const Icon(Icons.edit_rounded,
                            color: AppColors.primary, size: 16),
                        const SizedBox(width: 10),
                        Text(AppLocalizations.get('edit_btn'),
                            style: const TextStyle(color: AppColors.foreground)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      height: 42,
                      child: Row(children: [
                        const Icon(Icons.delete_rounded,
                            color: AppColors.destructive, size: 16),
                        const SizedBox(width: 10),
                        Text(AppLocalizations.get('delete'),
                            style: const TextStyle(color: AppColors.destructive)),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamStat extends StatelessWidget {
  const _TeamStat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 11, color: AppColors.muted),
            const SizedBox(width: 3),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class AddEditTeamPage extends StatefulWidget {
  const AddEditTeamPage({super.key, this.team});
  final ClubTeam? team;

  @override
  State<AddEditTeamPage> createState() => _AddEditTeamPageState();
}

class _AddEditTeamPageState extends State<AddEditTeamPage> {
  final _name = TextEditingController();
  final _coach = TextEditingController();
  final _physCoach = TextEditingController();
  final _season = TextEditingController();
  final _notes = TextEditingController();
  TeamCategory _category = TeamCategory.firstTeam;
  bool _saving = false;

  bool get _isEdit => widget.team != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final t = widget.team!;
      _name.text = t.name;
      _coach.text = t.coachName;
      _physCoach.text = t.physicalCoachName;
      _season.text = t.season;
      _notes.text = t.notes ?? '';
      _category = t.category;
    } else {
      _season.text = '2024/2025';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _coach.dispose();
    _physCoach.dispose();
    _season.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.get('team_name_required'))));
      return;
    }
    setState(() => _saving = true);
    bool saved;
    if (_isEdit) {
      final t = widget.team!;
      final updatedTeam = ClubTeam(
        id: t.id,
        name: _name.text.trim(),
        category: _category,
        coachName: _coach.text.trim(),
        physicalCoachName: _physCoach.text.trim(),
        season: _season.text.trim(),
        logoUrl: t.logoUrl,
        notes: _notes.text.trim(),
        playerIds: List<String>.from(t.playerIds),
        createdAt: t.createdAt,
      );
      saved = await ClubService().updateTeam(updatedTeam);
    } else {
      final team = ClubTeam(
        id: '',
        name: _name.text.trim(),
        category: _category,
        coachName: _coach.text.trim(),
        physicalCoachName: _physCoach.text.trim(),
        season: _season.text.trim(),
        notes: _notes.text.trim(),
        createdAt: DateTime.now(),
      );
      saved = await ClubService().addTeam(team) != null;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('save_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            ClubFormHeader(
              title: _isEdit
                  ? AppLocalizations.get('edit_team')
                  : AppLocalizations.get('new_team'),
              onBack: () => Navigator.of(context).pop(),
              onSave: _saving ? null : _save,
              saving: _saving,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(ClubUiTokens.pageHorizontalPadding),
                children: [
                  ClubFormField(
                    controller: _name,
                    label: AppLocalizations.get('team_name_label'),
                    hint: AppLocalizations.get('team_name_example'),
                  ),
                  const SizedBox(height: ClubUiTokens.spacingLg),
                  ClubDropdownField<TeamCategory>(
                    label: AppLocalizations.get('category_label'),
                    value: _category,
                    items: TeamCategory.values,
                    labelOf: (e) => e.label,
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                  const SizedBox(height: ClubUiTokens.spacingLg),
                  ClubFormField(
                    controller: _season,
                    label: AppLocalizations.get('season_label'),
                    hint: '2024/2025',
                  ),
                  const SizedBox(height: ClubUiTokens.spacingLg),
                  ClubFormField(
                    controller: _coach,
                    label: AppLocalizations.get('head_coach_label'),
                    hint: AppLocalizations.get('coach_name_hint'),
                  ),
                  const SizedBox(height: ClubUiTokens.spacingLg),
                  ClubFormField(
                    controller: _physCoach,
                    label: AppLocalizations.get('physical_coach_label'),
                    hint: AppLocalizations.get('physical_coach_hint'),
                  ),
                  const SizedBox(height: ClubUiTokens.spacingLg),
                  ClubFormField(
                    controller: _notes,
                    label: AppLocalizations.get('session_notes_label'),
                    hint: AppLocalizations.get('optional_hint'),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
