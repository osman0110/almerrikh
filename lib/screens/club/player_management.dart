import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import 'club_dashboard.dart';

class PlayerManagementPage extends StatefulWidget {
  const PlayerManagementPage({super.key, this.filterTeamId});
  final String? filterTeamId;

  @override
  State<PlayerManagementPage> createState() => _PlayerManagementPageState();
}

class _PlayerManagementPageState extends State<PlayerManagementPage> {
  List<ClubPlayer> _all = [];
  List<ClubTeam> _teams = [];
  bool _playersLoading = false;
  String _query = '';
  PlayerStatus? _statusFilter;
  String? _teamFilter;

  @override
  void initState() {
    super.initState();
    _teamFilter = widget.filterTeamId;
    // Load players asynchronously - don't block UI
    _loadPlayersAsync();
  }

  Future<void> _loadPlayersAsync() async {
    // Load without blocking - UI renders immediately
    setState(() => _playersLoading = true);
    try {
      final start = DateTime.now();
      final results = await Future.wait([
        ClubService().getPlayers(teamId: widget.filterTeamId),
        ClubService().getTeams(),
      ]);
      if (!mounted) return;
      setState(() {
        _all = results[0] as List<ClubPlayer>;
        _teams = results[1] as List<ClubTeam>;
        _playersLoading = false;
      });
      final ms = DateTime.now().difference(start).inMilliseconds;
      debugPrint('[PlayerManagement] Loaded ${_all.length} players in ${ms}ms');
    } catch (e) {
      if (mounted) setState(() => _playersLoading = false);
      debugPrint('[PlayerManagement] Load error: $e');
    }
  }

  Future<void> _load() async {
    // Manual refresh
    await _loadPlayersAsync();
  }

  List<ClubPlayer> get _filtered {
    return _all.where((p) {
      final matchQ = _query.isEmpty ||
          p.fullName.toLowerCase().contains(_query.toLowerCase()) ||
          p.number.contains(_query) ||
          p.position.toLowerCase().contains(_query.toLowerCase());
      final matchS = _statusFilter == null || p.status == _statusFilter;
      final matchT = _teamFilter == null || p.teamId == _teamFilter;
      return matchQ && matchS && matchT;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ClubShell(
      currentIndex: 1,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 16, 20, 12),
            decoration: const BoxDecoration(
              color: AppColors.card,
              border:
                  Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_rounded,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Players  (${_all.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        if (_teams.isEmpty && _playersLoading) {
                          await _loadPlayersAsync();
                        }
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AddEditPlayerPage(teams: _teams),
                          ),
                        );
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    AppColors.primary.withOpacity(0.30),
                                blurRadius: 12,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded,
                                color: Colors.white, size: 18),
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
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by name, number, position…',
                    hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.30), fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.muted),
                    filled: true,
                    fillColor: AppColors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 1.2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              children: [null, ...PlayerStatus.values].map((s) {
                final active = _statusFilter == s;
                final label = s == null ? 'All' : s.label;
                return GestureDetector(
                  onTap: () => setState(() => _statusFilter = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: active ? Colors.white : AppColors.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _playersLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary))
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                color: AppColors.primarySoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person_add_rounded,
                                  color: AppColors.primary, size: 34),
                            ),
                            const SizedBox(height: 16),
                            const Text('No Players Found',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18)),
                            const SizedBox(height: 6),
                            Text(
                              _query.isNotEmpty
                                  ? 'Try a different search term'
                                  : 'Add your first player',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.50),
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.card,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final p = _filtered[i];
                            final sc = p.latestScore;
                            final statusColor = _getStatusColor(p.status);
                            return GestureDetector(
                              onTap: () async {
                                await Navigator.of(context)
                                    .pushNamed('/club/players/${p.id}');
                                _load();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(18),
                                  border:
                                      Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.primarySoft,
                                        border: Border.all(
                                            color: AppColors.primary
                                                .withOpacity(0.35),
                                            width: 1.5),
                                      ),
                                      child: Center(
                                        child: Text(
                                          p.initials,
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  p.fullName,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 14),
                                                ),
                                              ),
                                              Text(
                                                '#${p.number}',
                                                style: const TextStyle(
                                                  color: AppColors.gold,
                                                  fontWeight:
                                                      FontWeight.w900,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${p.position}  ·  ${p.teamName ?? "No team"}',
                                            style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.45),
                                                fontSize: 12),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 8,
                                                    vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: statusColor
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8),
                                                  border: Border.all(
                                                      color: statusColor
                                                          .withOpacity(
                                                              0.25)),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                        width: 6,
                                                        height: 6,
                                                        decoration:
                                                            BoxDecoration(
                                                                color:
                                                                    statusColor,
                                                                shape: BoxShape
                                                                    .circle)),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      p.status.label,
                                                      style: TextStyle(
                                                          color: statusColor,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 10),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Spacer(),
                                              if (sc != null)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: _getScoreColor(sc)
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Text(
                                                    '${sc.toStringAsFixed(0)} pts',
                                                    style: TextStyle(
                                                      color:
                                                          _getScoreColor(sc),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Column(
                                      children: [
                                        GestureDetector(
                                          onTap: () async {
                                            await Navigator.of(context)
                                                .push(MaterialPageRoute(
                                              builder: (_) =>
                                                  AddEditPlayerPage(
                                                player: p,
                                                teams: _teams,
                                              ),
                                            ));
                                            _load();
                                          },
                                          child: Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: AppColors.primarySoft,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                                Icons.edit_rounded,
                                                color: AppColors.primary,
                                                size: 16),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        GestureDetector(
                                          onTap: () => _delete(p),
                                          child: Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: AppColors.destructive
                                                  .withOpacity(0.10),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                                Icons.delete_rounded,
                                                color:
                                                    AppColors.destructive,
                                                size: 16),
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

  Color _getStatusColor(PlayerStatus s) {
    switch (s) {
      case PlayerStatus.active:
        return AppColors.success;
      case PlayerStatus.injured:
        return AppColors.destructive;
      case PlayerStatus.recovering:
        return AppColors.warning;
      case PlayerStatus.inactive:
        return AppColors.muted;
    }
  }

  Color _getScoreColor(double s) {
    if (s >= 80) return AppColors.success;
    if (s >= 60) return AppColors.warning;
    return AppColors.destructive;
  }

  Future<void> _delete(ClubPlayer p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete Player',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text('Remove "${p.fullName}" from the system?',
            style: TextStyle(color: Colors.white.withOpacity(0.65))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete',
                style: TextStyle(
                    color: AppColors.destructive,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ClubService().deletePlayer(p.id, p.teamId);
      _load();
    }
  }
}

class AddEditPlayerPage extends StatefulWidget {
  const AddEditPlayerPage({super.key, this.player, required this.teams});
  final ClubPlayer? player;
  final List<ClubTeam> teams;

  @override
  State<AddEditPlayerPage> createState() => _AddEditPlayerPageState();
}

class _AddEditPlayerPageState extends State<AddEditPlayerPage> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _position = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _natl = TextEditingController();
  final _injNotes = TextEditingController();
  final _physNotes = TextEditingController();
  final _medNotes = TextEditingController();

  PlayerStatus _status = PlayerStatus.active;
  String _foot = 'right';
  DateTime? _dob;
  String? _teamId;
  bool _saving = false;

  static const _positions = [
    'Goalkeeper',
    'Centre-Back',
    'Right-Back',
    'Left-Back',
    'Defensive Mid',
    'Central Mid',
    'Attacking Mid',
    'Right Wing',
    'Left Wing',
    'Striker',
  ];

  bool get _isEdit => widget.player != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = widget.player!;
      _name.text = p.fullName;
      _number.text = p.number;
      _position.text = p.position;
      _height.text = p.height?.toString() ?? '';
      _weight.text = p.weight?.toString() ?? '';
      _natl.text = p.nationality;
      _injNotes.text = p.injuryNotes ?? '';
      _physNotes.text = p.physicalNotes ?? '';
      _medNotes.text = p.medicalNotes ?? '';
      _status = p.status;
      _foot = p.dominantFoot;
      _dob = p.dateOfBirth;
      _teamId = p.teamId;
    } else if (widget.teams.isNotEmpty) {
      _teamId = widget.teams.first.id;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _number,
      _position,
      _height,
      _weight,
      _natl,
      _injNotes,
      _physNotes,
      _medNotes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _snack('Player name is required');
      return;
    }
    if (_teamId == null) {
      _snack('Please select a team');
      return;
    }

    setState(() => _saving = true);

    final teamName = widget.teams
        .where((t) => t.id == _teamId)
        .map((t) => t.name)
        .firstOrNull;

    try {
      if (_isEdit) {
        final p = widget.player!;
        p.fullName = _name.text.trim();
        p.number = _number.text.trim();
        p.position = _position.text.trim();
        p.height = double.tryParse(_height.text);
        p.weight = double.tryParse(_weight.text);
        p.nationality = _natl.text.trim();
        p.injuryNotes = _injNotes.text.trim();
        p.physicalNotes = _physNotes.text.trim();
        p.medicalNotes = _medNotes.text.trim();
        p.status = _status;
        p.dominantFoot = _foot;
        p.dateOfBirth = _dob;
        p.teamId = _teamId!;
        p.teamName = teamName;
        final updated = await ClubService().updatePlayer(p);
        if (!mounted) return;
        if (updated) {
          _snack('Player updated successfully');
          Navigator.of(context).pop();
        } else {
          _snack('Failed to update player');
        }
      } else {
        final player = ClubPlayer(
          id: '',
          fullName: _name.text.trim(),
          number: _number.text.trim(),
          position: _position.text.trim(),
          dateOfBirth: _dob,
          height: double.tryParse(_height.text),
          weight: double.tryParse(_weight.text),
          dominantFoot: _foot,
          teamId: _teamId!,
          teamName: teamName,
          nationality: _natl.text.trim(),
          injuryNotes: _injNotes.text.trim(),
          physicalNotes: _physNotes.text.trim(),
          medicalNotes: _medNotes.text.trim(),
          status: _status,
          createdAt: DateTime.now(),
        );
        final playerId = await ClubService().addPlayer(player);
        if (!mounted) return;
        if (playerId != null) {
          _snack('Player added successfully');
          Navigator.of(context).pop();
        } else {
          _snack('Failed to add player');
        }
      }
    } catch (e) {
      debugPrint('[AddPlayer] Caught error: $e');
      if (!mounted) return;
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.8)),
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
                    child: Text(_isEdit ? 'Edit Player' : 'New Player',
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(children: [
                      Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          )),
                      const SizedBox(width: 8),
                      const Text('Basic Information',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ]),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Full Name',
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
                          hintText: 'Player full name',
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
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Jersey #',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.65),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _number,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '10',
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
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dob ?? DateTime(2000),
                            firstDate: DateTime(1970),
                            lastDate: DateTime.now(),
                            builder: (ctx, child) => Theme(
                              data: Theme.of(ctx).copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: AppColors.primary,
                                  surface: AppColors.card,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) setState(() => _dob = picked);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Date of Birth',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.65),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                            const SizedBox(height: 8),
                            Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(children: [
                                const Icon(Icons.cake_rounded,
                                    color: AppColors.muted, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  _dob == null
                                      ? 'Pick date'
                                      : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                                  style: TextStyle(
                                    color: _dob == null
                                        ? Colors.white.withOpacity(0.30)
                                        : Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Position',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _positions.map((pos) {
                          final active = _position.text == pos;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _position.text = pos),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.surface2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: active
                                        ? AppColors.primary
                                        : AppColors.border),
                              ),
                              child: Text(
                                pos,
                                style: TextStyle(
                                  color: active
                                      ? Colors.white
                                      : AppColors.muted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nationality',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _natl,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Sudan',
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
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(children: [
                      Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          )),
                      const SizedBox(width: 8),
                      const Text('Physical Data',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ]),
                  ),
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Height (cm)',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.65),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _height,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '182',
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
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Weight (kg)',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.65),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _weight,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '75',
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
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dominant Foot',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      Row(
                        children: ['right', 'left', 'both'].map((f) {
                          final active = _foot == f;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _foot = f),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(right: 8),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: active
                                      ? AppColors.primary
                                      : AppColors.surface2,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: active
                                          ? AppColors.primary
                                          : AppColors.border),
                                ),
                                child: Text(
                                  f[0].toUpperCase() + f.substring(1),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color:
                                        active ? Colors.white : AppColors.muted,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(children: [
                      Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          )),
                      const SizedBox(width: 8),
                      const Text('Assignment',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ]),
                  ),
                  if (widget.teams.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.warning.withOpacity(0.30)),
                      ),
                      child: const Text(
                        'No teams found. Create a team first.',
                        style: TextStyle(
                            color: AppColors.warning, fontSize: 13),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Team',
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
                          child: DropdownButton<String>(
                            value: _teamId ?? widget.teams.first.id,
                            isExpanded: true,
                            dropdownColor: AppColors.card,
                            underline: const SizedBox(),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            items: widget.teams
                                .map((t) => DropdownMenuItem(
                                      value: t.id,
                                      child: Text(t.name),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _teamId = v),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status',
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
                        child: DropdownButton<PlayerStatus>(
                          value: _status,
                          isExpanded: true,
                          dropdownColor: AppColors.card,
                          underline: const SizedBox(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          items: PlayerStatus.values
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s.label),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _status = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(children: [
                      Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          )),
                      const SizedBox(width: 8),
                      const Text('Medical & Physical Notes',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ]),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Injury Notes',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _injNotes,
                        maxLines: 3,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Current or past injuries',
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
                  const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Physical Notes',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _physNotes,
                        maxLines: 3,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Coach observations',
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
                  const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Medical Restrictions',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _medNotes,
                        maxLines: 3,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Any medical limitations',
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
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
