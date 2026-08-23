import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../utils/app_logger.dart';
import '../../widgets/common_widgets.dart';

class MatchFormPage extends StatefulWidget {
  const MatchFormPage({super.key, this.matchId});
  final String? matchId;

  @override
  State<MatchFormPage> createState() => _MatchFormPageState();
}

class _MatchFormPageState extends State<MatchFormPage> {
  final _opponent  = TextEditingController();
  final _location  = TextEditingController();
  final _notes     = TextEditingController();
  final _roundLabel = TextEditingController();
  final _groupName  = TextEditingController();

  DateTime _date   = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _time  = const TimeOfDay(hour: 16, minute: 0);
  String _status   = 'scheduled';
  String? _stage;

  bool _wellnessRequired = false;
  bool _rpeRequired      = false;

  Set<String> _selectedPlayerIds = {};
  List<ClubPlayer> _players = [];
  List<ClubCompetition> _competitions = [];
  int? _competitionId;
  final Map<String, TextEditingController> _minutesControllers = {};

  bool _loading = false;
  bool _saving  = false;
  MatchModel? _existing;

  bool get _isEdit => widget.matchId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _opponent.dispose();
    _location.dispose();
    _notes.dispose();
    _roundLabel.dispose();
    _groupName.dispose();
    for (final c in _minutesControllers.values) { c.dispose(); }
    super.dispose();
  }

  TextEditingController _minutesController(String playerId) {
    return _minutesControllers.putIfAbsent(
      playerId,
      () => TextEditingController(
          text: (_existing?.playerMinutes[playerId] ?? 0) > 0
              ? _existing!.playerMinutes[playerId].toString()
              : ''),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final teamId = currentTeamId.isNotEmpty ? currentTeamId : null;
      final results = await Future.wait([
        ClubService().getPlayers(teamId: teamId),
        ClubService().getCompetitions(),
      ]);
      if (mounted) {
        final uniqueCompetitions = <int, ClubCompetition>{
          for (final competition
              in results[1] as List<ClubCompetition>)
            competition.id: competition,
        };
        setState(() {
          _players = results[0] as List<ClubPlayer>;
          _competitions = uniqueCompetitions.values.toList();
          // New match: default to the whole squad selected — the coach
          // deselects anyone not involved rather than picking each player.
          if (!_isEdit) {
            _selectedPlayerIds = _players.map((p) => p.id).toSet();
          }
        });
      }

      if (_isEdit) {
        final match = await ClubService().getMatch(widget.matchId!);
        if (!mounted) return;
        if (match != null) {
          _existing           = match;
          _opponent.text      = match.opponent;
          _location.text      = match.location ?? '';
          _notes.text         = match.notes ?? '';
          _date               = match.matchDate;
          _status             = match.status;
          _wellnessRequired   = match.wellnessRequired;
          _rpeRequired        = match.rpeRequired;
          _stage              = match.stage;
          _roundLabel.text    = match.roundLabel ?? '';
          _groupName.text     = match.groupName ?? '';
          _selectedPlayerIds  = Set.from(match.playerIds);
          final matchCompetitionId = match.competitionId;
          _competitionId = _competitions.any(
            (competition) => competition.id == matchCompetitionId,
          )
              ? matchCompetitionId
              : null;
          final parts = match.matchTime.split(':');
          if (parts.length == 2) {
            _time = TimeOfDay(
              hour:   int.tryParse(parts[0]) ?? 16,
              minute: int.tryParse(parts[1]) ?? 0,
            );
          }
        }
      }
    } catch (e) {
      AppLogger.e('MatchForm', 'Failed to load match form data', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.get('error_generic')),
          action: SnackBarAction(
            label: AppLocalizations.get('retry'),
            onPressed: _load,
          ),
        ));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_opponent.text.trim().isEmpty) {
      _snack(AppLocalizations.get('match_opponent_required'));
      return;
    }
    if (_competitionId == null) {
      _snack(AppLocalizations.get('match_competition_required'));
      return;
    }
    setState(() => _saving = true);
    try {
      final timeStr =
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
      final playerMinutes = <String, int>{
        for (final pid in _selectedPlayerIds)
          if (int.tryParse(_minutesControllers[pid]?.text.trim() ?? '') != null)
            pid: int.parse(_minutesControllers[pid]!.text.trim()),
      };
      final match = MatchModel(
        id:               widget.matchId ?? '',
        opponent:         _opponent.text.trim(),
        matchDate:        _date,
        matchTime:        timeStr,
        location:         _location.text.trim().isEmpty ? null : _location.text.trim(),
        status:           _status,
        playerIds:        _selectedPlayerIds.toList(),
        playerMinutes:    playerMinutes,
        competitionId:    _competitionId,
        wellnessRequired: _wellnessRequired,
        rpeRequired:      _rpeRequired,
        notes:            _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        createdAt:        _existing?.createdAt ?? DateTime.now(),
        stage:            _stage,
        roundLabel:       _roundLabel.text.trim().isEmpty ? null : _roundLabel.text.trim(),
        groupName:        _groupName.text.trim().isEmpty ? null : _groupName.text.trim(),
        ourScore:         _existing?.ourScore,
        opponentScore:    _existing?.opponentScore,
      );
      final id = await ClubService().saveMatch(match);
      if (!mounted) return;
      if (id != null) {
        Navigator.of(context).pop(true);
      } else {
        _snack(AppLocalizations.get('match_save_failed'));
      }
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final canAccessForm =
        widget.matchId == null ? canCreateMatches : canManageMatches;
    if (!canAccessForm) return const RoleAccessDeniedPage();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2)),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  children: [
                    _sectionLabel(AppLocalizations.get('match_info_section'), Icons.sports_soccer_rounded),
                    _field(AppLocalizations.get('match_opponent_label'), _opponent,
                        hint: AppLocalizations.get('match_opponent_hint')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _datePicker()),
                      const SizedBox(width: 10),
                      Expanded(child: _timePicker()),
                    ]),
                    const SizedBox(height: 12),
                    _field(AppLocalizations.get('match_location_label'), _location,
                        hint: AppLocalizations.get('match_optional')),
                    const SizedBox(height: 12),
                    _statusPicker(),
                    const SizedBox(height: 12),
                    _competitionPicker(),
                    const SizedBox(height: 12),
                    _stagePicker(),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _field(AppLocalizations.get('match_round_label'), _roundLabel,
                              hint: AppLocalizations.get('match_optional'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _field(AppLocalizations.get('match_group_label'), _groupName,
                              hint: AppLocalizations.get('match_optional'))),
                    ]),
                    const SizedBox(height: 20),

                    _sectionLabel(AppLocalizations.get('match_players_section'), Icons.people_rounded),
                    _playersPicker(),
                    const SizedBox(height: 20),

                    _sectionLabel(AppLocalizations.get('match_survey_section'), Icons.poll_rounded),
                    _settingsCard(),
                    const SizedBox(height: 20),

                    _sectionLabel(AppLocalizations.get('match_notes_section'), Icons.notes_rounded),
                    _field(AppLocalizations.get('match_notes_section'), _notes,
                        hint: AppLocalizations.get('match_notes_hint'), maxLines: 3),
                  ],
                ),
              ),
            if (!_loading) _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8))),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: AppColors.surface2, shape: BoxShape.circle,
                border: Border.all(color: AppColors.border)),
            child: const Icon(Icons.close_rounded,
                color: AppColors.foreground, size: 18),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
              _isEdit
                  ? AppLocalizations.get('match_edit_title')
                  : AppLocalizations.get('match_new_title'),
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w900, fontSize: 18)),
        ),
      ]),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(top: BorderSide(color: AppColors.border, width: 0.8)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20, offset: const Offset(0, -6))],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _saving ? null : () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(999)),
                alignment: Alignment.center,
                child: Text(AppLocalizations.get('cancel'),
                    style: const TextStyle(color: AppColors.foreground,
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.maroon,
                  borderRadius: BorderRadius.circular(999)),
                alignment: Alignment.center,
                child: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.get('match_save_btn'),
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: AppColors.primary, size: 16),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(
            color: AppColors.foreground,
            fontWeight: FontWeight.w800, fontSize: 14)),
      ]),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
            color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(color: AppColors.foreground, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
            filled: true, fillColor: AppColors.surface2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
      ],
    );
  }

  Widget _datePicker() {
    return _tappableField(
      label: AppLocalizations.get('match_date_label'),
      icon: Icons.calendar_today_rounded,
      value: '${_date.day}/${_date.month}/${_date.year}',
      onTap: () async {
        final p = await showDatePicker(
          context: context,
          initialDate: _date,
          firstDate: DateTime.now().subtract(const Duration(days: 30)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(primary: AppColors.primary,
                  onPrimary: AppColors.foreground)),
            child: child!),
        );
        if (p != null) setState(() => _date = p);
      },
    );
  }

  Widget _timePicker() {
    final h = _time.hour.toString().padLeft(2, '0');
    final m = _time.minute.toString().padLeft(2, '0');
    return _tappableField(
      label: AppLocalizations.get('match_kickoff_label'),
      icon: Icons.access_time_rounded,
      value: '$h:$m',
      onTap: () async {
        final p = await showTimePicker(
          context: context,
          initialTime: _time,
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(primary: AppColors.primary,
                  onPrimary: AppColors.foreground)),
            child: child!),
        );
        if (p != null) setState(() => _time = p);
      },
    );
  }

  Widget _tappableField({
    required String label,
    required IconData icon,
    required String value,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
            color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 46, padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Icon(icon, color: AppColors.muted, size: 17),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(
                  color: AppColors.foreground, fontSize: 14)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _statusPicker() {
    final statuses = [
      ('scheduled', AppLocalizations.get('match_status_scheduled'), const Color(0xFFF2B23B)),
      ('completed', AppLocalizations.get('match_status_completed'), const Color(0xFF2DBF6C)),
      ('cancelled', AppLocalizations.get('match_status_cancelled'), const Color(0xFFFF4D2E)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.get('match_status_label'), style: const TextStyle(
            color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          children: statuses.map((s) {
            final active = _status == s.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _status = s.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: active ? s.$3.withOpacity(0.12) : AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: active ? s.$3 : AppColors.border,
                        width: active ? 1.5 : 1)),
                  child: Text(s.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: active ? s.$3 : AppColors.muted,
                          fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _competitionPicker() {
    final selectedCompetitionId = _competitions.any(
      (competition) => competition.id == _competitionId,
    )
        ? _competitionId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${AppLocalizations.get('competitions_title')} *', style: const TextStyle(
            color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _competitionId == null ? AppColors.destructive.withOpacity(0.4) : AppColors.border)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: selectedCompetitionId,
              isExpanded: true,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.foreground, fontSize: 14),
              hint: Text(AppLocalizations.get('select_competition_hint'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 14)),
              items: _competitions
                  .map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _competitionId = v),
            ),
          ),
        ),
        if (_competitions.isEmpty) ...[
          const SizedBox(height: 6),
          Text(AppLocalizations.get('no_competitions_hint'),
              style: const TextStyle(color: AppColors.destructive, fontSize: 11)),
        ],
      ],
    );
  }

  Widget _stagePicker() {
    const stages = ['group', 'quarterfinal', 'semifinal', 'final', 'round'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.get('match_stage_label'), style: const TextStyle(
            color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _stage,
              isExpanded: true,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.foreground, fontSize: 14),
              hint: Text(AppLocalizations.get('match_stage_none'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 14)),
              items: [
                DropdownMenuItem<String?>(
                    value: null, child: Text(AppLocalizations.get('match_stage_none'))),
                ...stages.map((s) => DropdownMenuItem<String?>(
                    value: s, child: Text(AppLocalizations.get('match_stage_$s')))),
              ],
              onChanged: (v) => setState(() => _stage = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _playersPicker() {
    if (_players.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.muted, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(AppLocalizations.get('match_no_players_hint'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12))),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          if (_selectedPlayerIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(999)),
              child: Text(
                  AppLocalizations.format('match_selected_count',
                      {'count': _selectedPlayerIds.length}),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700, fontSize: 10)),
            ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() =>
                _selectedPlayerIds = _players.map((p) => p.id).toSet()),
            child: Text(AppLocalizations.get('match_select_all'),
                style: const TextStyle(color: AppColors.primary,
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() => _selectedPlayerIds.clear()),
            child: Text(AppLocalizations.get('match_deselect_all'),
                style: const TextStyle(color: AppColors.muted,
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        ..._players.map((p) {
          final sel = _selectedPlayerIds.contains(p.id);
          final showMinutes = sel && _status == 'completed';
          return Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary.withOpacity(0.08) : AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: sel ? AppColors.primary.withOpacity(0.4) : AppColors.border)),
            child: Row(children: [
              GestureDetector(
                onTap: () => setState(() {
                  if (sel) _selectedPlayerIds.remove(p.id);
                  else _selectedPlayerIds.add(p.id);
                }),
                child: Row(children: [
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: sel ? AppColors.primary : AppColors.muted)),
                    child: sel
                        ? const Icon(Icons.check_rounded,
                            color: AppColors.foreground, size: 13)
                        : null,
                  ),
                  const SizedBox(width: 12),
                ]),
              ),
              Expanded(
                child: Text(
                  p.nickname?.trim().isNotEmpty == true
                      ? '${p.fullName} (${p.nickname})'
                      : p.fullName,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (showMinutes) ...[
                SizedBox(
                  width: 56,
                  height: 34,
                  child: TextField(
                    controller: _minutesController(p.id),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.foreground, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: AppLocalizations.get('match_minutes_hint'),
                      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 10),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                Text('#${p.number}  ·  ${p.position}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          );
        }),
      ],
    );
  }

  Widget _settingsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border)),
      child: Column(children: [
        _toggleRow(
          icon: Icons.self_improvement_rounded,
          label: AppLocalizations.get('match_wellness_label'),
          subtitle: AppLocalizations.get('match_wellness_subtitle'),
          value: _wellnessRequired,
          onChanged: (v) => setState(() => _wellnessRequired = v),
        ),
        const Divider(color: AppColors.border, height: 20),
        _toggleRow(
          icon: Icons.speed_rounded,
          label: AppLocalizations.get('match_rpe_label'),
          subtitle: AppLocalizations.get('match_rpe_subtitle'),
          value: _rpeRequired,
          onChanged: (v) => setState(() => _rpeRequired = v),
        ),
      ]),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(children: [
      Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: AppColors.muted, size: 16),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(
              color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ],
      )),
      Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        activeTrackColor: AppColors.primarySoft,
      ),
    ]);
  }
}
