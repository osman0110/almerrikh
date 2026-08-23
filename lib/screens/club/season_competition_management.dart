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
import 'match_list_page.dart';

class SeasonCompetitionManagementPage extends StatefulWidget {
  const SeasonCompetitionManagementPage({super.key});

  @override
  State<SeasonCompetitionManagementPage> createState() =>
      _SeasonCompetitionManagementPageState();
}

class _SeasonCompetitionManagementPageState
    extends State<SeasonCompetitionManagementPage> {
  List<ClubSeason> _seasons = [];
  List<ClubCompetition> _competitions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ClubService().getSeasons(),
      ClubService().getCompetitions(),
    ]);
    if (!mounted) return;
    setState(() {
      _seasons = results[0] as List<ClubSeason>;
      _competitions = results[1] as List<ClubCompetition>;
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
            title: AppLocalizations.get('competition_management_title'),
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
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.card,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        _SectionHeader(
                          title: AppLocalizations.get('seasons_title'),
                          onAdd: () => _openSeasonSheet(),
                        ),
                        const SizedBox(height: 10),
                        if (_seasons.isEmpty)
                          ClubEmptyState(
                            icon: Icons.calendar_month_rounded,
                            title: AppLocalizations.get('no_seasons_yet'),
                          )
                        else
                          ..._seasons.map((s) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _SeasonCard(
                                  season: s,
                                  onEdit: () => _openSeasonSheet(season: s),
                                  onDelete: () => _deleteSeason(s),
                                  onActivate: () => _activateSeason(s),
                                ),
                              )),
                        const SizedBox(height: 24),
                        _SectionHeader(
                          title: AppLocalizations.get('competitions_title'),
                          onAdd: () => _openCompetitionSheet(),
                        ),
                        const SizedBox(height: 10),
                        if (_competitions.isEmpty)
                          ClubEmptyState(
                            icon: Icons.emoji_events_rounded,
                            title: AppLocalizations.get('no_competitions_yet'),
                          )
                        else
                          ..._competitions.map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _CompetitionCard(
                                  competition: c,
                                  onEdit: () => _openCompetitionSheet(competition: c),
                                  onDelete: () => _deleteCompetition(c),
                                ),
                              )),
                        const SizedBox(height: 24),
                        _ScheduleManagementCard(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MatchListPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _activateSeason(ClubSeason season) async {
    await ClubService().activateSeason(season.id);
    _load();
  }

  Future<void> _deleteSeason(ClubSeason season) async {
    if (season.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('cannot_delete_active_season'))),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClubConfirmDialog(
        title: AppLocalizations.get('delete_season_title'),
        body: AppLocalizations.format('delete_season_msg', {'name': season.name}),
      ),
    );
    if (ok == true) {
      await ClubService().deleteSeason(season.id);
      _load();
    }
  }

  Future<void> _deleteCompetition(ClubCompetition competition) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClubConfirmDialog(
        title: AppLocalizations.get('delete_competition_title'),
        body: AppLocalizations.format(
            'delete_competition_msg', {'name': competition.name}),
      ),
    );
    if (ok == true) {
      await ClubService().deleteCompetition(competition.id);
      _load();
    }
  }

  Future<void> _openSeasonSheet({ClubSeason? season}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SeasonEditSheet(season: season),
    );
    if (saved == true) _load();
  }

  Future<void> _openCompetitionSheet({ClubCompetition? competition}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CompetitionEditSheet(competition: competition, seasons: _seasons),
    );
    if (saved == true) _load();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onAdd});
  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title.toUpperCase(),
            style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.8)),
        const Spacer(),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded, color: AppColors.foreground, size: 15),
              const SizedBox(width: 4),
              Text(AppLocalizations.get('add'),
                  style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ]),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule management — entry point into the existing match list/fixtures
// screen, scoped as part of competition management.
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleManagementCard extends StatelessWidget {
  const _ScheduleManagementCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(ClubUiTokens.cardRadius),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.calendar_view_week_rounded,
                  color: AppColors.primary, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.get('competition_schedule_title'),
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(AppLocalizations.get('competition_schedule_subtitle'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: AppColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Season card
// ─────────────────────────────────────────────────────────────────────────────

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    required this.season,
    required this.onEdit,
    required this.onDelete,
    required this.onActivate,
  });
  final ClubSeason season;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onActivate;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Color get _statusColor {
    switch (season.status) {
      case 'active':
        return AppColors.success;
      case 'archived':
        return AppColors.muted;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(ClubUiTokens.cardRadius),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(season.name,
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  ClubStatusBadge(
                      label: AppLocalizations.get('season_status_${season.status}'),
                      color: _statusColor),
                  const SizedBox(width: 8),
                  Text('${_fmt(season.startsOn)} → ${_fmt(season.endsOn)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ]),
              ],
            ),
          ),
          if (!season.isActive)
            GestureDetector(
              onTap: onActivate,
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Text(AppLocalizations.get('activate_season_btn'),
                    style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted, size: 18),
            color: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(AppLocalizations.get('edit_btn'),
                    style: const TextStyle(color: AppColors.foreground)),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(AppLocalizations.get('delete'),
                    style: const TextStyle(color: AppColors.destructive)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Competition card
// ─────────────────────────────────────────────────────────────────────────────

class _CompetitionCard extends StatelessWidget {
  const _CompetitionCard({
    required this.competition,
    required this.onEdit,
    required this.onDelete,
  });
  final ClubCompetition competition;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color get _statusColor {
    switch (competition.competitionStatus) {
      case 'ongoing':
        return AppColors.success;
      case 'completed':
        return AppColors.muted;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(ClubUiTokens.cardRadius),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(competition.name,
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  ClubStatusBadge(
                      label: AppLocalizations.get('competition_type_${competition.type}'),
                      color: AppColors.primary),
                  const SizedBox(width: 6),
                  ClubStatusBadge(
                      label: AppLocalizations.get(
                          'competition_status_${competition.competitionStatus}'),
                      color: _statusColor),
                  if (competition.seasonName != null) ...[
                    const SizedBox(width: 8),
                    Text(competition.seasonName!,
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ],
                ]),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted, size: 18),
            color: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(AppLocalizations.get('edit_btn'),
                    style: const TextStyle(color: AppColors.foreground)),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(AppLocalizations.get('delete'),
                    style: const TextStyle(color: AppColors.destructive)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Season add/edit sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SeasonEditSheet extends StatefulWidget {
  const _SeasonEditSheet({this.season});
  final ClubSeason? season;

  @override
  State<_SeasonEditSheet> createState() => _SeasonEditSheetState();
}

class _SeasonEditSheetState extends State<_SeasonEditSheet> {
  final _name = TextEditingController();
  DateTime? _startsOn;
  DateTime? _endsOn;
  bool _saving = false;

  bool get _isEdit => widget.season != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final s = widget.season!;
      _name.text = s.name;
      _startsOn = s.startsOn;
      _endsOn = s.endsOn;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startsOn : _endsOn) ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => isStart ? _startsOn = picked : _endsOn = picked);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _startsOn == null || _endsOn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('season_dates_required'))),
      );
      return;
    }
    setState(() => _saving = true);
    final season = ClubSeason(
      id: widget.season?.id ?? 0,
      name: _name.text.trim(),
      startsOn: _startsOn!,
      endsOn: _endsOn!,
      status: widget.season?.status ?? 'draft',
    );
    final ok = await ClubService().saveSeason(season);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(ok);
  }

  String _fmt(DateTime? d) => d == null
      ? '—'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEdit
                ? AppLocalizations.get('edit_season')
                : AppLocalizations.get('add_season'),
            style: const TextStyle(
                color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: ClubUiTokens.spacingLg),
          ClubFormField(
            controller: _name,
            label: AppLocalizations.get('season_name_label'),
            hint: AppLocalizations.get('season_name_hint'),
          ),
          const SizedBox(height: ClubUiTokens.spacingLg),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _pickDate(isStart: true),
                child: _DateBox(
                    label: AppLocalizations.get('starts_on_label'),
                    value: _fmt(_startsOn)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _pickDate(isStart: false),
                child: _DateBox(
                    label: AppLocalizations.get('ends_on_label'),
                    value: _fmt(_endsOn)),
              ),
            ),
          ]),
          const SizedBox(height: ClubUiTokens.spacingLg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ClubUiTokens.buttonRadius)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: AppColors.foreground, strokeWidth: 2))
                  : Text(AppLocalizations.get('save_btn'),
                      style: const TextStyle(
                          color: AppColors.foreground, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Row(children: [
            Expanded(
              child: Text(value,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
            ),
            const Icon(Icons.calendar_today_rounded, color: AppColors.muted, size: 14),
          ]),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Competition add/edit sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CompetitionEditSheet extends StatefulWidget {
  const _CompetitionEditSheet({this.competition, required this.seasons});
  final ClubCompetition? competition;
  final List<ClubSeason> seasons;

  @override
  State<_CompetitionEditSheet> createState() => _CompetitionEditSheetState();
}

class _CompetitionEditSheetState extends State<_CompetitionEditSheet> {
  final _name = TextEditingController();
  final _yellowThreshold = TextEditingController(text: '3');
  final _suspensionMatches = TextEditingController(text: '1');
  final _directRedMatches = TextEditingController(text: '2');
  final _twoYellowsMatches = TextEditingController(text: '1');
  final _stagesCount = TextEditingController(text: '1');
  final _winPoints = TextEditingController(text: '3');
  final _drawPoints = TextEditingController(text: '1');
  final _lossPoints = TextEditingController(text: '0');
  String _type = 'league';
  int? _seasonId;
  bool _resetYellowCycle = true;
  bool _carryCards = true;
  bool _carrySuspensions = false;
  bool _allowAdminOverride = true;
  String _formatType = 'league';
  String _tieBreakRule = 'goal_difference';
  String _competitionStatus = 'upcoming';
  bool _saving = false;

  bool get _isEdit => widget.competition != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final c = widget.competition!;
      _name.text = c.name;
      _type = c.type;
      _seasonId = c.seasonId;
      _yellowThreshold.text = '${c.yellowCardThreshold}';
      _suspensionMatches.text = '${c.suspensionMatches}';
      _directRedMatches.text = '${c.directRedSuspensionMatches}';
      _twoYellowsMatches.text = '${c.twoYellowsSuspensionMatches}';
      _resetYellowCycle = c.resetYellowCycle;
      _carryCards = c.carryCardsBetweenStages;
      _carrySuspensions = c.carrySuspensionsForward;
      _allowAdminOverride = c.allowAdminOverride;
      _formatType = c.formatType;
      _stagesCount.text = '${c.stagesCount}';
      _winPoints.text = '${c.winPoints}';
      _drawPoints.text = '${c.drawPoints}';
      _lossPoints.text = '${c.lossPoints}';
      _tieBreakRule = c.tieBreakRule;
      _competitionStatus = c.competitionStatus;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _yellowThreshold.dispose();
    _suspensionMatches.dispose();
    _directRedMatches.dispose();
    _twoYellowsMatches.dispose();
    _stagesCount.dispose();
    _winPoints.dispose();
    _drawPoints.dispose();
    _lossPoints.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('team_name_required'))),
      );
      return;
    }
    setState(() => _saving = true);
    final competition = ClubCompetition(
      id: widget.competition?.id ?? 0,
      name: _name.text.trim(),
      type: _type,
      seasonId: _seasonId,
      yellowCardThreshold: int.tryParse(_yellowThreshold.text) ?? 3,
      suspensionMatches: int.tryParse(_suspensionMatches.text) ?? 1,
      resetYellowCycle: _resetYellowCycle,
      carryCardsBetweenStages: _carryCards,
      carrySuspensionsForward: _carrySuspensions,
      directRedSuspensionMatches: int.tryParse(_directRedMatches.text) ?? 2,
      twoYellowsSuspensionMatches: int.tryParse(_twoYellowsMatches.text) ?? 1,
      allowAdminOverride: _allowAdminOverride,
      formatType: _formatType,
      stagesCount: int.tryParse(_stagesCount.text) ?? 1,
      winPoints: int.tryParse(_winPoints.text) ?? 3,
      drawPoints: int.tryParse(_drawPoints.text) ?? 1,
      lossPoints: int.tryParse(_lossPoints.text) ?? 0,
      tieBreakRule: _tieBreakRule,
      competitionStatus: _competitionStatus,
    );
    final ok = await ClubService().saveCompetition(competition);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final seasonItems = <int?>[null, ...widget.seasons.map((s) => s.id)];
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEdit
                ? AppLocalizations.get('edit_competition')
                : AppLocalizations.get('add_competition'),
            style: const TextStyle(
                color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: ClubUiTokens.spacingLg),
          ClubFormField(
            controller: _name,
            label: AppLocalizations.get('competition_name_label'),
            hint: AppLocalizations.get('competition_name_hint'),
          ),
          const SizedBox(height: ClubUiTokens.spacingLg),
          ClubDropdownField<String>(
            label: AppLocalizations.get('competition_type_label'),
            value: _type,
            items: const ['league', 'cup', 'friendly'],
            labelOf: (t) => AppLocalizations.get('competition_type_$t'),
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: ClubUiTokens.spacingLg),
          ClubDropdownField<int?>(
            label: AppLocalizations.get('linked_season_label'),
            value: _seasonId,
            items: seasonItems,
            labelOf: (id) => id == null
                ? AppLocalizations.get('no_linked_season')
                : widget.seasons.firstWhere((s) => s.id == id).name,
            onChanged: (v) => setState(() => _seasonId = v),
          ),
          const SizedBox(height: ClubUiTokens.spacingLg),
          const Divider(color: AppColors.border),
          const SizedBox(height: ClubUiTokens.spacingMd),
          Text(AppLocalizations.get('competition_format_section_title'), style: const TextStyle(
              color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: ClubUiTokens.spacingMd),
          ClubDropdownField<String>(
            label: AppLocalizations.get('competition_format_label'),
            value: _formatType,
            items: const ['league', 'knockout', 'groups', 'friendly'],
            labelOf: (t) => AppLocalizations.get('competition_format_$t'),
            onChanged: (v) => setState(() => _formatType = v!),
          ),
          const SizedBox(height: ClubUiTokens.spacingMd),
          Row(children: [
            Expanded(
                child: _disciplineNumber(
                    _stagesCount, AppLocalizations.get('competition_stages_count_label'))),
            const SizedBox(width: 10),
            Expanded(
              child: ClubDropdownField<String>(
                label: AppLocalizations.get('competition_status_label'),
                value: _competitionStatus,
                items: const ['upcoming', 'ongoing', 'completed'],
                labelOf: (s) => AppLocalizations.get('competition_status_$s'),
                onChanged: (v) => setState(() => _competitionStatus = v!),
              ),
            ),
          ]),
          const SizedBox(height: ClubUiTokens.spacingMd),
          Row(children: [
            Expanded(
                child: _disciplineNumber(
                    _winPoints, AppLocalizations.get('competition_win_points_label'))),
            const SizedBox(width: 10),
            Expanded(
                child: _disciplineNumber(
                    _drawPoints, AppLocalizations.get('competition_draw_points_label'))),
            const SizedBox(width: 10),
            Expanded(
                child: _disciplineNumber(
                    _lossPoints, AppLocalizations.get('competition_loss_points_label'))),
          ]),
          const SizedBox(height: ClubUiTokens.spacingMd),
          ClubDropdownField<String>(
            label: AppLocalizations.get('competition_tie_break_label'),
            value: _tieBreakRule,
            items: const ['goal_difference', 'head_to_head', 'goals_scored'],
            labelOf: (t) => AppLocalizations.get('competition_tie_break_$t'),
            onChanged: (v) => setState(() => _tieBreakRule = v!),
          ),
          const SizedBox(height: ClubUiTokens.spacingLg),
          const Divider(color: AppColors.border),
          const SizedBox(height: ClubUiTokens.spacingMd),
          const Text('قواعد البطاقات والإيقافات', style: TextStyle(
              color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: ClubUiTokens.spacingMd),
          Row(children: [
            Expanded(child: _disciplineNumber(_yellowThreshold, 'البطاقات الصفراء للإيقاف')),
            const SizedBox(width: 10),
            Expanded(child: _disciplineNumber(_suspensionMatches, 'مباريات الإيقاف')),
          ]),
          Row(children: [
            Expanded(child: _disciplineNumber(_directRedMatches, 'إيقاف الحمراء المباشرة')),
            const SizedBox(width: 10),
            Expanded(child: _disciplineNumber(_twoYellowsMatches, 'إيقاف بطاقتين صفراوين')),
          ]),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero, title: const Text('تصفير دورة الإنذارات بعد تنفيذ الإيقاف'),
            value: _resetYellowCycle, onChanged: (v) => setState(() => _resetYellowCycle = v)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero, title: const Text('ترحيل البطاقات بين مراحل البطولة'),
            value: _carryCards, onChanged: (v) => setState(() => _carryCards = v)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero, title: const Text('ترحيل الإيقافات للبطولة التالية'),
            value: _carrySuspensions, onChanged: (v) => setState(() => _carrySuspensions = v)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero, title: const Text('السماح بتعديل مدة الإيقاف إدارياً'),
            value: _allowAdminOverride, onChanged: (v) => setState(() => _allowAdminOverride = v)),
          const SizedBox(height: ClubUiTokens.spacingLg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ClubUiTokens.buttonRadius)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: AppColors.foreground, strokeWidth: 2))
                  : Text(AppLocalizations.get('save_btn'),
                      style: const TextStyle(
                          color: AppColors.foreground, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _disciplineNumber(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
  );
}
