import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../widgets/common_widgets.dart';

// Maps an AI-generated exercise's stored `assessmentType` to its localization
// key (mirrors _aiAssessmentTypes below). Manual/custom exercises (or
// unrecognized types) fall back to the raw stored `exerciseName`.
const _kAiExerciseLabelKeys = {
  'squat': 'assessment_squat_title',
  'cmj': 'assessment_short_cmj',
  'squat_jump': 'assessment_short_squat_jump',
  'drop_jump': 'assessment_short_drop_jump',
  'single_leg_drop_jump': 'assessment_short_sl_drop_jump',
  'jumpLanding': 'assessment_jl_title',
  'singleLegBalance': 'assessment_slb_title',
};

String _exerciseDisplayLabel(ClubSessionExercise ex) {
  final key = _kAiExerciseLabelKeys[ex.assessmentType];
  return key != null ? AppLocalizations.get(key) : ex.exerciseName;
}

// ─────────────────────────────────────────────────────────────────────────────
// Session Form Page — Create / Edit
// ─────────────────────────────────────────────────────────────────────────────

class SessionFormPage extends StatefulWidget {
  const SessionFormPage({super.key, this.sessionId});
  final String? sessionId;

  @override
  State<SessionFormPage> createState() => _SessionFormPageState();
}

class _SessionFormPageState extends State<SessionFormPage>
    with SingleTickerProviderStateMixin {
  // Basic
  final _name     = TextEditingController();
  final _location = TextEditingController();
  final _notes    = TextEditingController();

  DateTime _date        = DateTime.now();
  TimeOfDay _startTime  = const TimeOfDay(hour: 8, minute: 0);
  int _durationMin      = 90;
  SessionType _type     = SessionType.fitness;
  String _intensity     = 'medium';
  String? _positionFilter;

  // Toggles — surveys default ON; the physical coach relies on this data,
  // so requiring a manual opt-in every time a session is created is friction
  // with no upside.
  bool _wellnessRequired    = true;
  bool _rpeRequired         = true;
  bool _attendanceRequired  = true;

  // Players — default is "everyone", collapsed; expanding (or picking an
  // individual-type session) is the only way to hand-pick specific players.
  Set<String> _selectedPlayerIds = {};
  List<ClubPlayer> _teamPlayers  = [];
  bool _playersExpanded = false;

  // Exercises
  late TabController _exTabCtrl;
  List<ClubSessionExercise> _exercises = [];

  // State
  TrainingSession? _existing;
  bool _loading = false;
  bool _saving  = false;

  bool get _isEdit => widget.sessionId != null;

  List<({String code, String label})> get _positions => [
    (code: 'GK',  label: AppLocalizations.get('pos_gk')),
    (code: 'DEF', label: AppLocalizations.get('pos_def')),
    (code: 'MID', label: AppLocalizations.get('pos_mid')),
    (code: 'FWD', label: AppLocalizations.get('pos_fwd')),
  ];

  @override
  void initState() {
    super.initState();
    _exTabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _notes.dispose();
    _exTabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final teamId = currentTeamId.isNotEmpty ? currentTeamId : null;
      final futures = <Future>[
        ClubService().getPlayers(teamId: teamId),
        if (_isEdit) ClubService().getSession(widget.sessionId!),
        if (_isEdit) ClubService().getSessionExercises(widget.sessionId!),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;

      _teamPlayers = results[0] as List<ClubPlayer>;
      if (!_isEdit) {
        _selectedPlayerIds = _teamPlayers.map((p) => p.id).toSet();
      }

      if (_isEdit && results.length > 1) {
        final session = results[1] as TrainingSession?;
        if (session != null) {
          _existing             = session;
          _name.text            = session.name;
          _location.text        = session.location ?? '';
          _notes.text           = session.notes ?? '';
          _date                 = session.date;
          _type                 = session.type;
          _intensity            = session.intensity;
          _wellnessRequired     = session.wellnessRequired;
          _rpeRequired          = session.rpeRequired;
          _attendanceRequired   = session.attendanceRequired;
          _positionFilter       = session.positionFilter;
          _selectedPlayerIds    = Set.from(session.playerIds);
          final parts = session.startTime.split(':');
          if (parts.length == 2) {
            _startTime = TimeOfDay(
              hour:   int.tryParse(parts[0]) ?? 8,
              minute: int.tryParse(parts[1]) ?? 0,
            );
          }
          _durationMin = session.durationMin;
        }
        if (results.length > 2) {
          _exercises = List.from(results[2] as List<ClubSessionExercise>);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _snack(AppLocalizations.get('session_title_required'));
      return;
    }
    if (_selectedPlayerIds.isEmpty) {
      _snack(AppLocalizations.get('session_min_one_player'));
      return;
    }
    setState(() => _saving = true);
    try {
      final startStr =
          '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
      final session = TrainingSession(
        id:                 widget.sessionId ?? '',
        name:               _name.text.trim(),
        date:               _date,
        teamId:             currentTeamId,
        teamName:           currentTeamName.isNotEmpty ? currentTeamName : null,
        type:               _type,
        startTime:          startStr,
        durationMin:        _durationMin,
        intensity:          _intensity,
        location:           _location.text.trim().isEmpty ? null : _location.text.trim(),
        coachName:          currentUserName.isNotEmpty ? currentUserName : AppLocalizations.get('coach_label'),
        notes:              _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        playerIds:          _selectedPlayerIds.toList(),
        completedPlayerIds: _existing?.completedPlayerIds ?? [],
        assessmentCount:    _existing?.assessmentCount ?? 0,
        createdAt:          _existing?.createdAt ?? DateTime.now(),
        wellnessRequired:   _wellnessRequired,
        rpeRequired:        _rpeRequired,
        attendanceRequired: _attendanceRequired,
        positionFilter:     _positionFilter,
        assessmentTypes: _exercises
            .where((e) => e.isAI && e.assessmentType != null)
            .map((e) => e.assessmentType!)
            .toSet()
            .toList(),
      );

      String? savedId;
      if (_isEdit) {
        final ok = await ClubService().updateSession(session);
        if (ok) savedId = widget.sessionId;
      } else {
        savedId = await ClubService().addSession(session);
      }

      if (!mounted) return;
      if (savedId == null) { _snack(AppLocalizations.get('session_save_failed')); return; }

      if (_exercises.isNotEmpty || _isEdit) {
        await ClubService().saveSessionExercises(savedId, _exercises);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    if (!canManageSessions) return const RoleAccessDeniedPage();
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: GoogleFonts.cairoTextTheme(Theme.of(context).textTheme),
      ),
      child: Scaffold(
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
                    _sectionLabel(AppLocalizations.get('session_basic_info_section'), Icons.info_outline_rounded),
                    _field(AppLocalizations.get('session_name_label'), _name,
                        hint: AppLocalizations.get('session_title_hint')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _datePicker()),
                      const SizedBox(width: 10),
                      Expanded(child: _timePicker()),
                    ]),
                    const SizedBox(height: 12),
                    _durationPicker(),
                    const SizedBox(height: 12),
                    _field(AppLocalizations.get('session_location_label'), _location,
                        hint: AppLocalizations.get('session_location_hint')),
                    const SizedBox(height: 20),

                    _sectionLabel(AppLocalizations.get('session_type_section'), Icons.category_rounded),
                    _typePicker(),
                    const SizedBox(height: 12),
                    _positionPicker(),
                    const SizedBox(height: 12),
                    _intensityPicker(),
                    const SizedBox(height: 20),

                    _sectionLabel(AppLocalizations.get('session_players_label'), Icons.people_rounded),
                    _playersPicker(),
                    const SizedBox(height: 20),

                    _sectionLabel(AppLocalizations.get('session_exercises_section'), Icons.fitness_center_rounded),
                    _exercisesSection(),
                    const SizedBox(height: 20),

                    _sectionLabel(AppLocalizations.get('session_settings_section'), Icons.tune_rounded),
                    _settingsCard(),
                    const SizedBox(height: 20),

                    _sectionLabel(AppLocalizations.get('session_coach_notes_section'), Icons.notes_rounded),
                    _field(AppLocalizations.get('session_notes_label'), _notes,
                        hint: AppLocalizations.get('session_notes_hint'), maxLines: 3),
                  ],
                ),
              ),
            if (!_loading) _bottomBar(),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Row(
        children: [
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
                  ? AppLocalizations.get('session_edit_title')
                  : AppLocalizations.get('session_new_title'),
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w900, fontSize: 18)),
          ),
        ],
      ),
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
                    : Text(AppLocalizations.get('session_save_btn'),
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
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
      ],
    );
  }

  Widget _datePicker() {
    return _tappableField(
      label: AppLocalizations.get('session_date_label'),
      icon: Icons.calendar_today_rounded,
      value: '${_date.day}/${_date.month}/${_date.year}',
      onTap: () async {
        final p = await showDatePicker(
          context: context,
          initialDate: _date,
          firstDate: DateTime.now().subtract(const Duration(days: 180)),
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
    final h = _startTime.hour.toString().padLeft(2, '0');
    final m = _startTime.minute.toString().padLeft(2, '0');
    return _tappableField(
      label: AppLocalizations.get('session_start_time_label'),
      icon: Icons.access_time_rounded,
      value: '$h:$m',
      onTap: () async {
        final p = await showTimePicker(
          context: context,
          initialTime: _startTime,
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(primary: AppColors.primary,
                  onPrimary: AppColors.foreground)),
            child: child!),
        );
        if (p != null) setState(() => _startTime = p);
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

  Widget _durationPicker() {
    const durations = [30, 45, 60, 75, 90, 105, 120, 150];
    final suffix = AppLocalizations.get('session_duration_min_suffix');
    final isCustom = !durations.contains(_durationMin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.get('session_duration_label'), style: const TextStyle(
            color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...durations.map((d) {
                final active = _durationMin == d;
                return GestureDetector(
                  onTap: () => setState(() => _durationMin = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: active ? AppColors.primary : AppColors.border)),
                    child: Center(
                      child: Text('$d$suffix', style: TextStyle(
                          color: active ? AppColors.foreground : AppColors.muted,
                          fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                );
              }),
              GestureDetector(
                onTap: _showCustomDurationDialog,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isCustom ? AppColors.primary : AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isCustom ? AppColors.primary : AppColors.border)),
                  child: Center(
                    child: Text(
                      isCustom
                          ? '$_durationMin$suffix'
                          : AppLocalizations.get('period_custom'),
                      style: TextStyle(
                          color: isCustom ? AppColors.foreground : AppColors.muted,
                          fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomDurationDialog() async {
    final controller = TextEditingController(text: _durationMin.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.get('session_duration_label')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            suffixText: AppLocalizations.get('session_duration_min_suffix'),
            hintText: '1 - 480',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text.trim());
              if (minutes != null && minutes >= 1 && minutes <= 480) {
                Navigator.of(dialogContext).pop(minutes);
              }
            },
            child: Text(AppLocalizations.get('save_btn')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) setState(() => _durationMin = value);
  }

  // Only session types the physical coach actually runs — tactical/technical/
  // goalkeeper/position-specific training and match fixtures belong to other
  // roles/modules and only cluttered this picker.
  List<SessionType> get _sessionTypeOptions => const [
        SessionType.physicalAssessment, SessionType.individual,
        SessionType.strength, SessionType.mobility,
        SessionType.fitness, SessionType.speedAgility,
        SessionType.recovery, SessionType.injuryPrevention, SessionType.rehab,
        SessionType.preMatch, SessionType.postMatch,
      ];

  Widget _typePicker() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _sessionTypeOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          final t = _sessionTypeOptions[i];
          final active = _type == t;
          return GestureDetector(
            onTap: () => setState(() {
              _type = t;
              // Individual sessions need an explicit, deliberate pick —
              // "everyone" as a default doesn't make sense here.
              if (t == SessionType.individual) {
                _playersExpanded = true;
                _selectedPlayerIds = {};
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: active ? AppColors.primary : AppColors.border)),
              alignment: Alignment.center,
              child: Text(t.label, style: TextStyle(
                  color: active ? AppColors.foreground : AppColors.muted,
                  fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          );
        },
      ),
    );
  }

  Widget _positionPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.get('session_position_filter_label'), style: const TextStyle(
            color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7, runSpacing: 7,
          children: [
            GestureDetector(
              onTap: () => setState(() => _positionFilter = null),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _positionFilter == null ? AppColors.primary : AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _positionFilter == null ? AppColors.primary : AppColors.border)),
                child: Text(AppLocalizations.get('category_all'), style: TextStyle(
                    color: _positionFilter == null ? AppColors.foreground : AppColors.muted,
                    fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
            ..._positions.map((p) {
              final active = _positionFilter == p.code;
              return GestureDetector(
                onTap: () => setState(() => _positionFilter = p.code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: active ? AppColors.primary : AppColors.border)),
                  child: Text(p.label, style: TextStyle(
                      color: active ? AppColors.foreground : AppColors.muted,
                      fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _intensityPicker() {
    final levels = [
      ('low',      AppLocalizations.get('intensity_low'),      const Color(0xFF2DBF6C)),
      ('medium',   AppLocalizations.get('intensity_medium'),   const Color(0xFFF2B23B)),
      ('high',     AppLocalizations.get('intensity_high'),     const Color(0xFFF97316)),
      ('recovery', AppLocalizations.get('intensity_recovery'), const Color(0xFF0891B2)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.get('session_intensity_label'), style: const TextStyle(
            color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          children: levels.map((l) {
            final active = _intensity == l.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _intensity = l.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: active ? l.$3.withOpacity(0.15) : AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: active ? l.$3 : AppColors.border, width: active ? 1.5 : 1)),
                  child: Text(l.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: active ? l.$3 : AppColors.muted,
                          fontWeight: FontWeight.w700, fontSize: 11)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _playersPicker() {
    if (_teamPlayers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.muted, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(AppLocalizations.get('session_no_players_hint'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12))),
        ]),
      );
    }

    final displayedPlayers = _positionFilter == null
        ? _teamPlayers
        : _teamPlayers.where((p) {
            final pos = p.position.toUpperCase();
            switch (_positionFilter) {
              case 'GK':  return pos == 'GK' || pos.contains('حارس');
              case 'DEF': return pos == 'CB' || pos == 'LB' || pos == 'RB'
                           || pos == 'DEF' || pos.contains('مدافع');
              case 'MID': return pos == 'CM' || pos == 'DM' || pos == 'AM'
                           || pos == 'MID' || pos.contains('وسط');
              case 'FWD': return pos == 'ST' || pos == 'LW' || pos == 'RW'
                           || pos == 'FWD' || pos.contains('مهاجم');
              default:    return true;
            }
          }).toList();

    // Individual sessions always need an explicit pick; otherwise default to
    // a collapsed "everyone" summary — the full checkbox list only appears
    // once the coach asks to customize it.
    final forceExpanded = _type == SessionType.individual;
    if (!forceExpanded && !_playersExpanded) {
      return GestureDetector(
        onTap: () => setState(() => _playersExpanded = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
          child: Row(children: [
            const Icon(Icons.groups_rounded, color: AppColors.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  AppLocalizations.format('session_players_all_selected',
                      {'count': _selectedPlayerIds.length}),
                  style: const TextStyle(
                      color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
            Text(AppLocalizations.get('session_customize_players'),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
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
                  AppLocalizations.format('session_selected_count',
                      {'count': _selectedPlayerIds.length}),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 10)),
            ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() =>
                _selectedPlayerIds = displayedPlayers.map((p) => p.id).toSet()),
            child: Text(AppLocalizations.get('session_select_all'),
                style: const TextStyle(color: AppColors.primary,
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() => _selectedPlayerIds.clear()),
            child: Text(AppLocalizations.get('session_deselect_all'),
                style: const TextStyle(color: AppColors.muted,
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (!forceExpanded) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() {
              _playersExpanded = false;
              _selectedPlayerIds = displayedPlayers.map((p) => p.id).toSet();
            }),
            child: Text(AppLocalizations.get('session_collapse_players'),
                style: const TextStyle(color: AppColors.muted,
                    fontSize: 11, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
          ),
        ],
        const SizedBox(height: 8),
        ...displayedPlayers.map((p) {
          final sel = _selectedPlayerIds.contains(p.id);
          return GestureDetector(
            onTap: () => setState(() {
              if (sel) _selectedPlayerIds.remove(p.id);
              else _selectedPlayerIds.add(p.id);
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary.withOpacity(0.08) : AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: sel ? AppColors.primary.withOpacity(0.4) : AppColors.border)),
              child: Row(children: [
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sel ? AppColors.primary : AppColors.muted)),
                  child: sel ? const Icon(Icons.check_rounded,
                      color: AppColors.foreground, size: 13) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(p.fullName, style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('#${p.number}  ·  ${p.position}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          );
        }),
      ],
    );
  }

  Widget _exercisesSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          TabBar(
            controller: _exTabCtrl,
            labelColor: AppColors.foreground,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            tabs: [
              Tab(text: AppLocalizations.get('session_ai_tab')),
              Tab(text: AppLocalizations.get('session_manual_tab')),
            ],
          ),
          SizedBox(
            height: 280,
            child: TabBarView(
              controller: _exTabCtrl,
              children: [
                _aiExercisesTab(),
                _manualExercisesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _aiAssessmentTypes = [
    (type: 'squat',             label: 'Squat Assessment',       labelKey: 'assessment_squat_title',       icon: Icons.accessibility_new_rounded),
    (type: 'cmj',               label: 'Countermovement Jump',   labelKey: 'assessment_short_cmj',         icon: Icons.arrow_upward_rounded),
    (type: 'squat_jump',        label: 'Squat Jump',             labelKey: 'assessment_short_squat_jump',  icon: Icons.sports_gymnastics_rounded),
    (type: 'drop_jump',         label: 'Drop Jump Test',         labelKey: 'assessment_short_drop_jump',   icon: Icons.arrow_downward_rounded),
    (type: 'single_leg_drop_jump', label: 'Single Leg Drop Jump', labelKey: 'assessment_short_sl_drop_jump', icon: Icons.directions_run_rounded),
    (type: 'jumpLanding',       label: 'Jump Landing',           labelKey: 'assessment_jl_title',          icon: Icons.arrow_circle_down_rounded),
    (type: 'singleLegBalance',  label: 'Single Leg Balance',     labelKey: 'assessment_slb_title',         icon: Icons.sports_kabaddi_rounded),
  ];

  Widget _aiExercisesTab() {
    final added = _exercises.where((e) => e.isAI).map((e) => e.assessmentType).toSet();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(AppLocalizations.get('session_ai_hint'),
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 10),
        ..._aiAssessmentTypes.map((a) {
          final isAdded = added.contains(a.type);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (isAdded) {
                  _exercises.removeWhere(
                      (e) => e.isAI && e.assessmentType == a.type);
                } else {
                  _exercises.add(ClubSessionExercise(
                    exerciseType:   'ai',
                    exerciseName:   a.label,
                    assessmentType: a.type,
                    sortOrder:      _exercises.length,
                  ));
                }
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isAdded ? AppColors.primary.withOpacity(0.10) : AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isAdded ? AppColors.primary : AppColors.border)),
              child: Row(children: [
                Icon(a.icon,
                    color: isAdded ? AppColors.primary : AppColors.muted,
                    size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(AppLocalizations.get(a.labelKey),
                    style: TextStyle(
                        color: isAdded ? AppColors.foreground : AppColors.muted,
                        fontWeight: FontWeight.w700, fontSize: 12))),
                if (isAdded)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6)),
                    child: Text(AppLocalizations.get('session_exercise_added'),
                        style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w800, fontSize: 10)),
                  )
                else
                  const Icon(Icons.add_circle_outline_rounded,
                      color: AppColors.muted, size: 18),
              ]),
            ),
          );
        }),
      ],
    );
  }

  Widget _manualExercisesTab() {
    final manuals = _exercises.where((e) => !e.isAI).toList();
    return Column(
      children: [
        Expanded(
          child: manuals.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.fitness_center_rounded,
                        color: AppColors.muted, size: 32),
                    const SizedBox(height: 8),
                    Text(AppLocalizations.get('session_no_exercises'),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                )
              : ReorderableListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final item = manuals.removeAt(oldIndex);
                      manuals.insert(newIndex, item);
                      _exercises = [
                        ..._exercises.where((e) => e.isAI),
                        ...manuals,
                      ];
                    });
                  },
                  children: manuals.asMap().entries.map((entry) {
                    final ex = entry.value;
                    return Container(
                      key: ValueKey(ex.hashCode + entry.key),
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        const Icon(Icons.drag_indicator_rounded,
                            color: AppColors.muted, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_exerciseDisplayLabel(ex), style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w700, fontSize: 12)),
                              if (ex.volumeLabel.isNotEmpty)
                                Text(ex.volumeLabel,
                                    style: const TextStyle(
                                        color: AppColors.muted, fontSize: 10)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _exercises.remove(ex)),
                          child: const Icon(Icons.close_rounded,
                              color: AppColors.muted, size: 16),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: GestureDetector(
            onTap: () => _showAddExerciseSheet(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.4))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Text(AppLocalizations.get('session_add_exercise_btn'),
                    style: const TextStyle(color: AppColors.primary,
                        fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddExerciseSheet() {
    final nameCtrl  = TextEditingController();
    final notesCtrl = TextEditingController();
    String category = 'fitness';
    int sets = 3, reps = 10, durationSec = 0, restSec = 60;
    bool useReps = true;

    final categories = [
      ('fitness',    AppLocalizations.get('ex_cat_fitness')),
      ('strength',   AppLocalizations.get('ex_cat_strength')),
      ('speed',      AppLocalizations.get('ex_cat_speed')),
      ('agility',    AppLocalizations.get('ex_cat_agility')),
      ('technical',  AppLocalizations.get('ex_cat_technical')),
      ('recovery',   AppLocalizations.get('ex_cat_recovery')),
      ('warmup',     AppLocalizations.get('ex_cat_warmup')),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(AppLocalizations.get('session_add_manual_title'),
                      style: const TextStyle(color: AppColors.foreground,
                          fontWeight: FontWeight.w900, fontSize: 17))),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.muted, size: 22)),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.get('session_exercise_name_hint'),
                    hintStyle: const TextStyle(color: AppColors.muted),
                    filled: true, fillColor: AppColors.surface2,
                    border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: AppColors.border)),
                    enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: AppColors.border)),
                    focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: categories.map((c) {
                    final active = category == c.$1;
                    return GestureDetector(
                      onTap: () => setModal(() => category = c.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: active ? AppColors.primary : AppColors.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: active ? AppColors.primary : AppColors.border)),
                        child: Text(c.$2, style: TextStyle(
                            color: active ? AppColors.foreground : AppColors.muted,
                            fontWeight: FontWeight.w700, fontSize: 11)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  GestureDetector(
                    onTap: () => setModal(() => useReps = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: useReps ? AppColors.primary : AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: useReps ? AppColors.primary : AppColors.border)),
                      child: Text(AppLocalizations.get('session_sets_reps_toggle'), style: TextStyle(
                          color: useReps ? AppColors.foreground : AppColors.muted,
                          fontWeight: FontWeight.w700, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setModal(() => useReps = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: !useReps ? AppColors.primary : AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: !useReps ? AppColors.primary : AppColors.border)),
                      child: Text(AppLocalizations.get('session_duration_toggle'), style: TextStyle(
                          color: !useReps ? AppColors.foreground : AppColors.muted,
                          fontWeight: FontWeight.w700, fontSize: 11)),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (useReps)
                  Row(children: [
                    Expanded(child: _numField(AppLocalizations.get('session_sets_label'), sets,
                        (v) => setModal(() => sets = v))),
                    const SizedBox(width: 10),
                    Expanded(child: _numField(AppLocalizations.get('session_reps_label'), reps,
                        (v) => setModal(() => reps = v))),
                    const SizedBox(width: 10),
                    Expanded(child: _numField(AppLocalizations.get('session_rest_label'), restSec,
                        (v) => setModal(() => restSec = v))),
                  ])
                else
                  Row(children: [
                    Expanded(child: _numField(AppLocalizations.get('session_duration_sec_label'), durationSec,
                        (v) => setModal(() => durationSec = v))),
                    const SizedBox(width: 10),
                    Expanded(child: _numField(AppLocalizations.get('session_rest_label'), restSec,
                        (v) => setModal(() => restSec = v))),
                  ]),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 13),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.get('session_exercise_notes_hint'),
                    hintStyle: const TextStyle(color: AppColors.muted),
                    filled: true, fillColor: AppColors.surface2,
                    border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: AppColors.border)),
                    enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: AppColors.border)),
                    focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final ex = ClubSessionExercise(
                      exerciseType:    'manual',
                      exerciseName:    nameCtrl.text.trim(),
                      category:        category,
                      sets:            useReps ? sets : null,
                      reps:            useReps ? reps : null,
                      durationSeconds: !useReps ? durationSec : null,
                      restSeconds:     restSec > 0 ? restSec : null,
                      notes:           notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                      sortOrder:       _exercises.length,
                    );
                    setState(() => _exercises.add(ex));
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14)),
                    child: Center(
                      child: Text(AppLocalizations.get('session_add_exercise_confirm'),
                          style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _numField(String label, int value, void Function(int) onChanged) {
    final ctrl = TextEditingController(text: value.toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
            color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.foreground, fontSize: 14,
              fontWeight: FontWeight.w700),
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) onChanged(n);
          },
          decoration: const InputDecoration(
            filled: true, fillColor: AppColors.surface2,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            isDense: true,
          ),
        ),
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
      child: Column(
        children: [
          _toggleRow(
            icon: Icons.self_improvement_rounded,
            label: AppLocalizations.get('session_wellness_label'),
            subtitle: AppLocalizations.get('session_wellness_subtitle'),
            value: _wellnessRequired,
            onChanged: (v) => setState(() => _wellnessRequired = v),
          ),
          const Divider(color: AppColors.border, height: 20),
          _toggleRow(
            icon: Icons.speed_rounded,
            label: AppLocalizations.get('session_rpe_label'),
            subtitle: AppLocalizations.get('session_rpe_subtitle'),
            value: _rpeRequired,
            onChanged: (v) => setState(() => _rpeRequired = v),
          ),
          const Divider(color: AppColors.border, height: 20),
          _toggleRow(
            icon: Icons.how_to_reg_rounded,
            label: AppLocalizations.get('session_attendance_label'),
            subtitle: AppLocalizations.get('session_attendance_subtitle'),
            value: _attendanceRequired,
            onChanged: (v) => setState(() => _attendanceRequired = v),
          ),
        ],
      ),
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
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(
              color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(subtitle, style: const TextStyle(
              color: AppColors.muted, fontSize: 10)),
        ]),
      ),
      Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        activeTrackColor: AppColors.primarySoft,
      ),
    ]);
  }
}
