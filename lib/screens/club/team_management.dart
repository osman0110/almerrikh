import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import 'club_dashboard.dart';

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
    return ClubShell(
      currentIndex: 0,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 16, 20, 16),
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
            ),
            child: Row(
              children: [
                GestureDetector(
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
                        color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Team Management',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
                GestureDetector(
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
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withOpacity(0.30),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('Add',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _teams.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.groups_rounded,
                                  color: AppColors.primary, size: 36),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No Teams Yet',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Create your first team to get started',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 24),
                            GestureDetector(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const AddEditTeamPage()),
                                );
                                _load();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 28, vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.30),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'Create Team',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                            return GestureDetector(
                              onTap: () => Navigator.of(context).pushNamed(
                                  '/club/players',
                                  arguments: {'teamId': team.id}),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.border),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.05),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: AppColors.primarySoft,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                                color: AppColors.primary
                                                    .withOpacity(0.30),
                                                width: 1.5),
                                          ),
                                          child: const Icon(
                                              Icons.shield_rounded,
                                              color: AppColors.primary,
                                              size: 26),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                team.name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary
                                                          .withOpacity(0.12),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(8),
                                                      border: Border.all(
                                                          color: AppColors
                                                              .primary
                                                              .withOpacity(
                                                                  0.25)),
                                                    ),
                                                    child: Text(
                                                      team.category.label,
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.primary,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.gold
                                                          .withOpacity(0.12),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(8),
                                                      border: Border.all(
                                                          color: AppColors
                                                              .gold
                                                              .withOpacity(
                                                                  0.25)),
                                                    ),
                                                    child: Text(
                                                      team.season,
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.gold,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          color: AppColors.card,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            side: const BorderSide(
                                                color: AppColors.border),
                                          ),
                                          onSelected: (v) {
                                            if (v == 'edit') {
                                              Navigator.of(context)
                                                  .push(MaterialPageRoute(
                                                builder: (_) =>
                                                    AddEditTeamPage(team: team),
                                              ))
                                                  .then((_) => _load());
                                            }
                                            if (v == 'delete') {
                                              _showDeleteConfirm(team);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(children: [
                                                Icon(Icons.edit_rounded,
                                                    color: AppColors.primary,
                                                    size: 18),
                                                SizedBox(width: 10),
                                                Text('Edit',
                                                    style: TextStyle(
                                                        color: Colors.white)),
                                              ]),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(children: [
                                                Icon(Icons.delete_rounded,
                                                    color: AppColors.destructive,
                                                    size: 18),
                                                SizedBox(width: 10),
                                                Text('Delete',
                                                    style: TextStyle(
                                                        color: AppColors
                                                            .destructive)),
                                              ]),
                                            ),
                                          ],
                                          child: const Icon(
                                              Icons.more_vert_rounded,
                                              color: AppColors.muted,
                                              size: 22),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    const Divider(
                                        color: AppColors.border, height: 1),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(Icons.people_rounded,
                                                      size: 12,
                                                      color: AppColors.muted),
                                                  const SizedBox(width: 4),
                                                  Text('Players',
                                                      style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  0.40),
                                                          fontSize: 10)),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${team.playerCount}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(Icons.person_rounded,
                                                      size: 12,
                                                      color: AppColors.muted),
                                                  const SizedBox(width: 4),
                                                  Text('Coach',
                                                      style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  0.40),
                                                          fontSize: 10)),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                team.coachName.isNotEmpty
                                                    ? team.coachName
                                                    : '—',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .fitness_center_rounded,
                                                      size: 12,
                                                      color: AppColors.muted),
                                                  const SizedBox(width: 4),
                                                  Text('Physical Coach',
                                                      style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  0.40),
                                                          fontSize: 10)),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                team.physicalCoachName
                                                        .isNotEmpty
                                                    ? team.physicalCoachName
                                                    : '—',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(ClubTeam team) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete Team',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text('Are you sure you want to delete "${team.name}"?',
            style: TextStyle(color: Colors.white.withOpacity(0.65))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.55))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await ClubService().deleteTeam(team.id);
              _load();
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: AppColors.destructive,
                    fontWeight: FontWeight.w800)),
          ),
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
          .showSnackBar(const SnackBar(content: Text('Team name is required')));
      return;
    }
    setState(() => _saving = true);
    if (_isEdit) {
      final t = widget.team!;
      t.name = _name.text.trim();
      t.category = _category;
      t.coachName = _coach.text.trim();
      t.physicalCoachName = _physCoach.text.trim();
      t.season = _season.text.trim();
      t.notes = _notes.text.trim();
      await ClubService().updateTeam(t);
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
      await ClubService().addTeam(team);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                color: AppColors.card,
                border:
                    Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                        _isEdit ? 'Edit Team' : 'New Team',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18)),
                  ),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.primary.withOpacity(0.30),
                              blurRadius: 12,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Team Name',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Al Merrikh First Team',
                          hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.30),
                              fontSize: 14),
                          filled: true,
                          fillColor: AppColors.surface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.primary, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Category',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButton<TeamCategory>(
                          value: _category,
                          isExpanded: true,
                          dropdownColor: AppColors.card,
                          underline: const SizedBox(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          items: TeamCategory.values
                              .map((e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e.label),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _category = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Season',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _season,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '2024/2025',
                          hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.30),
                              fontSize: 14),
                          filled: true,
                          fillColor: AppColors.surface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.primary, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Head Coach',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _coach,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Coach name',
                          hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.30),
                              fontSize: 14),
                          filled: true,
                          fillColor: AppColors.surface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.primary, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Physical Coach',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _physCoach,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Physical coach name',
                          hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.30),
                              fontSize: 14),
                          filled: true,
                          fillColor: AppColors.surface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.primary, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notes',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notes,
                        maxLines: 3,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Optional notes',
                          hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.30),
                              fontSize: 14),
                          filled: true,
                          fillColor: AppColors.surface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.primary, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                      ),
                    ],
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
