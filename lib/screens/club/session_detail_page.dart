import 'dart:async';
import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/assessment_result_model.dart';
import '../../models/club_models.dart';
import '../../models/player_profile_model.dart';
import '../../services/club_service.dart';
import '../../utils/app_logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../physical_assessment/assessment_camera_page.dart';
import '../physical_assessment/web_pose_setup_screen.dart'
    if (dart.library.io) '../physical_assessment/web_pose_setup_screen_stub.dart';
import 'session_form_page.dart';
import 'session_queue_page.dart';
import 'coach_evaluation_sheet.dart';
import 'club_player_profile_page.dart';
import 'injury_case_screen.dart';
import '../../shared/responsive.dart';

// Maps an AI-generated exercise's stored `assessmentType` (English, snake/camel
// case per _aiAssessmentTypes in session_form_page.dart) to its localization key.
// Manual/custom exercises (or unrecognized types) fall back to the raw stored
// `exerciseName` so existing data keeps displaying.
const _kAiExerciseLabelKeys = {
  'squat': 'assessment_squat_title',
  'cmj': 'assessment_short_cmj',
  'squat_jump': 'assessment_short_squat_jump',
  'drop_jump': 'assessment_short_drop_jump',
  'single_leg_drop_jump': 'assessment_short_sl_drop_jump',
  'jumpLanding': 'assessment_jl_title',
  'singleLegBalance': 'assessment_slb_title',
};

String exerciseDisplayLabel(ClubSessionExercise ex) {
  final key = _kAiExerciseLabelKeys[ex.assessmentType];
  return key != null ? AppLocalizations.get(key) : ex.exerciseName;
}

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  TrainingSession? _session;
  List<ClubPlayer> _players = [];
  List<ClubSessionExercise> _exercises = [];
  List<CoachEvaluation> _evaluations = [];
  Map<String, String> _attendance = {};
  Map<String, Map<String, dynamic>> _playerClocks = {};
  bool _loading = true;
  bool _loadError = false;
  bool _clockBusy = false;
  DateTime _clockSnapshotAt = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_session?.clockRunning == true ||
          _playerClocks.values.any((clock) => clock['running'] == true))) {
        setState(() {});
      }
    });
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int _liveSeconds(int storedSeconds, bool running) => storedSeconds +
      (running ? DateTime.now().difference(_clockSnapshotAt).inSeconds : 0);

  String _formatClock(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final secs = safe % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final session = await ClubService().getSession(widget.sessionId);
      if (session == null) { if (mounted) setState(() => _loading = false); return; }
      if (mounted) setState(() => _session = session);

      final futures = <Future>[
        ...session.playerIds.map((pid) => ClubService().getPlayer(pid)),
        ClubService().getSessionExercises(widget.sessionId),
        ClubService().getEvaluations(sessionId: widget.sessionId),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;

      _players = results
          .sublist(0, session.playerIds.length)
          .whereType<ClubPlayer>()
          .toList();
      _exercises   = results[session.playerIds.length] as List<ClubSessionExercise>;
      _evaluations = results[session.playerIds.length + 1] as List<CoachEvaluation>;
      _playerClocks = await ClubService().getSessionPlayerClocks(widget.sessionId);
      _clockSnapshotAt = DateTime.now();

      if (session.attendanceRequired) {
        _attendance = await ClubService().getSessionAttendance(widget.sessionId);
      }
    } catch (e) {
      AppLogger.e('SessionDetail', 'Failed to load session ${widget.sessionId}', e);
      if (mounted && _session == null) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setAttendance(String playerId, String status) async {
    final previous = _attendance[playerId];
    setState(() => _attendance = {..._attendance, playerId: status});
    final ok = await ClubService().setSessionAttendance(widget.sessionId, {playerId: status});
    if (!ok && mounted) {
      setState(() => _attendance = {..._attendance, playerId: previous ?? 'pending'});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('attendance_save_failed'))),
      );
    }
  }

  Future<void> _runSessionClock(String operation, {String? playerId}) async {
    if (_clockBusy) return;
    setState(() => _clockBusy = true);
    final error = await ClubService().controlSessionClock(
        widget.sessionId, operation, playerId: playerId);
    if (error == null && mounted) {
      // Apply the clock change locally instead of re-fetching the whole
      // session (which flashed the entire page to a spinner on every
      // start/stop tap). First freeze every clock's elapsed time to its
      // live value at this instant — they all share `_clockSnapshotAt` as
      // their timing baseline, so moving that baseline requires freezing
      // every running clock, not just the one being toggled.
      setState(() {
        final now = DateTime.now();
        final s = _session!;
        s.elapsedSeconds = _liveSeconds(s.elapsedSeconds, s.clockRunning);
        final frozenClocks = <String, Map<String, dynamic>>{};
        _playerClocks.forEach((pid, clock) {
          final running = clock['running'] == true;
          final elapsed = _liveSeconds(clock['elapsed_seconds'] as int? ?? 0, running);
          frozenClocks[pid] = {...clock, 'elapsed_seconds': elapsed};
        });
        _clockSnapshotAt = now;

        if (playerId == null) {
          s.clockRunning = operation == 'start_session';
          if (operation == 'finish_session') s.status = 'completed';
        } else {
          final clock = frozenClocks[playerId] ?? {'elapsed_seconds': 0, 'running': false};
          frozenClocks[playerId] = {
            ...clock,
            'running': operation == 'start_player',
          };
        }
        _playerClocks = frozenClocks;
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error!)));
    }
    if (mounted) setState(() => _clockBusy = false);
  }

  Future<void> _startBatchAssessment() async {
    final s = _session!;
    final allowedTypes = _getAllowedAssessmentTypes(s);

    debugPrint('[SessionDetail._startBatchAssessment] allowedTypes: $allowedTypes');

    if (allowedTypes.isEmpty) {
      if (!mounted) return;
      _showNoTestSnackBar();
      return;
    }

    final pending = _players.where((p) => !s.completedPlayerIds.contains(p.id)).toList();
    if (pending.isEmpty) return;

    AssessmentTestType? testType;

    if (allowedTypes.length == 1) {
      testType = allowedTypes.first;
    } else {
      testType = await showModalBottomSheet<AssessmentTestType>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _TestTypePicker(allowedTypes: allowedTypes),
      );
    }

    debugPrint('[SessionDetail._startBatchAssessment] selected testType: $testType');

    if (testType == null || !mounted) return;

    debugPrint('[SessionDetail._startBatchAssessment] navigating to SessionQueuePage → $testType');
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SessionQueuePage(
        sessionId: widget.sessionId,
        players: _players,
        assessmentType: testType!,
      ),
    ));
    _load();
  }

  /// Converts a raw string from the API/backend to [AssessmentTestType].
  /// Handles snake_case, camelCase, and legacy aliases without throwing.
  AssessmentTestType? _parseAssessmentTestType(String? value) {
    if (value == null || value.isEmpty) return null;
    switch (value.toLowerCase().replaceAll('_', '').replaceAll(' ', '')) {
      case 'squat':
      case 'squatanalysis':
        return AssessmentTestType.squat;
      case 'singlelegbalance':
      case 'singlelegstability':
        return AssessmentTestType.singleLegBalance;
      case 'jumplanding':
      case 'landingcontrol':
        return AssessmentTestType.jumpLanding;
      case 'countermovementjump':
      case 'cmj':
        return AssessmentTestType.countermovementJump;
      case 'squatjump':
      case 'sj':
        return AssessmentTestType.squatJump;
      case 'dropjump':
      case 'dj':
        return AssessmentTestType.dropJump;
      case 'singlelegdropjump':
      case 'sldj':
        return AssessmentTestType.singleLegDropJump;
      default:
        // Try exact enum name match as final fallback
        return AssessmentTestType.values
            .where((t) => t.name.toLowerCase() == value.toLowerCase())
            .firstOrNull;
    }
  }

  /// Builds the list of allowed test types for a session.
  /// Reads assessmentTypes (new field) first, falls back to assessmentType (legacy).
  List<AssessmentTestType> _getAllowedAssessmentTypes(TrainingSession session) {
    final types = <AssessmentTestType>[];
    for (final raw in session.assessmentTypes) {
      final t = _parseAssessmentTestType(raw);
      if (t != null && !types.contains(t)) types.add(t);
    }
    if (types.isEmpty && session.assessmentType != null) {
      final t = _parseAssessmentTestType(session.assessmentType);
      if (t != null) types.add(t);
    }
    return types;
  }

  /// Shows a SnackBar when no test is configured for the session.
  void _showNoTestSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.get('no_test_selected_for_session')),
        backgroundColor: AppColors.risk,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startTest(ClubPlayer p) async {
    final session = _session!;
    final allowedTypes = _getAllowedAssessmentTypes(session);

    debugPrint('[SessionDetail._startTest] assessmentTypes: ${session.assessmentTypes}');
    debugPrint('[SessionDetail._startTest] assessmentType (legacy): ${session.assessmentType}');
    debugPrint('[SessionDetail._startTest] allowedTypes: $allowedTypes');

    AssessmentTestType? testType;

    if (allowedTypes.isEmpty) {
      if (!mounted) return;
      _showNoTestSnackBar();
      return;
    } else if (allowedTypes.length == 1) {
      testType = allowedTypes.first;
    } else {
      testType = await showModalBottomSheet<AssessmentTestType>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _TestTypePicker(allowedTypes: allowedTypes),
      );
    }

    debugPrint('[SessionDetail._startTest] selected testType: $testType');

    if (testType == null || !mounted) return;

    final profile = PlayerProfile(
      id: p.id,
      name: p.fullName,
      heightCm: p.height?.toInt(),
      weightKg: p.weight?.toInt(),
      dominantFoot: p.dominantFoot,
      position: p.position,
      team: p.teamName,
    );

    if (!mounted) return;
    final args = AssessmentCameraArguments(
      player: profile,
      testType: testType,
      sessionId: widget.sessionId,
    );
    if (kIsWeb) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebPoseSetupScreen(cameraArgs: args),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AssessmentCameraPage(
          player: args.player,
          testType: args.testType,
          sessionId: args.sessionId,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                ),
              )
            else if (_loadError && _session == null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.muted, size: 40),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.get('error_generic'),
                          style: const TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(AppLocalizations.get('retry')),
                      ),
                    ],
                  ),
                ),
              )
            else if (_session == null)
              Expanded(
                child: Center(
                  child: Text(AppLocalizations.get('session_not_found'),
                      style: const TextStyle(color: AppColors.muted)),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.card,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _buildInfoCard(),
                      if (canControlActivityClock) ...[
                        const SizedBox(height: 16),
                        _buildActivityClockCard(),
                      ],
                      const SizedBox(height: 16),
                      _buildProgressCard(),
                      const SizedBox(height: 16),
                      _buildAssessmentSummary(),
                      if (_exercises.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildExercisesCard(),
                      ],
                      const SizedBox(height: 16),
                      _buildPlayersSection(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.arrow_back_rounded, color: AppColors.foreground, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _session?.name ?? AppLocalizations.get('session_label'),
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 18),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_session != null && canManageSessions)
            GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SessionFormPage(sessionId: widget.sessionId),
                ));
                _load();
              },
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final s = _session!;
    final statusColor = s.status == 'completed'
        ? AppColors.success
        : s.status == 'cancelled'
            ? AppColors.destructive
            : s.status == 'active'
                ? AppColors.success
                : AppColors.warning;

    final attendedCount = _attendance.values
        .where((v) => v == 'present' || v == 'late')
        .length;
    final showAttendance = s.attendanceRequired &&
        s.playerIds.isNotEmpty && _attendance.isNotEmpty;
    final attendancePct = s.playerIds.isEmpty
        ? 0
        : (attendedCount / s.playerIds.length * 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border(left: BorderSide(color: AppColors.maroon, width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _pillBadge(
            icon: Icons.category_rounded,
            label: s.type.label,
            color: AppColors.maroon,
            bg: AppColors.primarySoft,
          ),
          const Spacer(),
          Container(
            height: 19,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(s.statusLabel, style: TextStyle(
                  color: statusColor, fontWeight: FontWeight.w700, fontSize: 9.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text(s.name, style: const TextStyle(
            color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 18)),
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _infoRow(Icons.calendar_today_rounded, AppLocalizations.formatFullDate(s.date)),
            const SizedBox(height: 11),
            _infoRow(Icons.access_time_rounded, s.startTime, ltr: true),
            if (s.location != null && s.location!.isNotEmpty) ...[
              const SizedBox(height: 11),
              _infoRow(Icons.location_on_rounded, s.location!),
            ],
            if (s.teamName != null) ...[
              const SizedBox(height: 11),
              _infoRow(Icons.group_rounded, s.teamName!),
            ],
            const SizedBox(height: 11),
            _infoRow(Icons.people_rounded,
                AppLocalizations.format('match_players_count', {'count': s.playerIds.length})),
          ]),
        ),
        if (showAttendance) ...[
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(AppLocalizations.get('attendance_rate_label'), style: const TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 11)),
                const Spacer(),
                Text('$attendedCount/${s.playerIds.length}', style: const TextStyle(
                    color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              Stack(children: [
                Container(height: 5, decoration: BoxDecoration(
                    color: AppColors.surface2, borderRadius: BorderRadius.circular(99))),
                FractionallySizedBox(
                  widthFactor: (attendancePct / 100).clamp(0.0, 1.0),
                  child: Container(height: 5, decoration: BoxDecoration(
                      color: AppColors.maroon, borderRadius: BorderRadius.circular(99))),
                ),
              ]),
            ]),
          ),
        ],
        if (s.notes != null && s.notes!.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border))),
            child: Text(s.notes!,
                style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5, height: 1.6)),
          ),
        ],
      ]),
    );
  }

  Widget _pillBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text, {bool ltr = false}) {
    return Row(children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
            color: AppColors.background, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.muted, size: 13),
      ),
      const SizedBox(width: 9),
      Expanded(child: Text(text,
          textDirection: ltr ? TextDirection.ltr : null,
          style: const TextStyle(
              color: AppColors.foreground, fontWeight: FontWeight.w600, fontSize: 12.5))),
    ]);
  }

  Widget _buildActivityClockCard() {
    final session = _session!;
    final running = session.clockRunning;
    final elapsed = _liveSeconds(session.elapsedSeconds, running);
    final hasStarted = session.elapsedSeconds > 0 || running;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: running
            ? Border.all(color: AppColors.success.withOpacity(0.45))
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.timer_rounded,
              color: running ? AppColors.success : AppColors.primary, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Text(AppLocalizations.get('activity_clock_title'),
              style: const TextStyle(color: AppColors.foreground,
                  fontWeight: FontWeight.w800, fontSize: 14))),
          Text(_formatClock(elapsed),
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: AppColors.foreground,
                  fontWeight: FontWeight.w900, fontSize: 22,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _clockBusy || (!running && hasStarted)
                ? null
                : () => _runSessionClock(
                    running ? 'finish_session' : 'start_session'),
            icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(AppLocalizations.get(running
                ? 'activity_finish_session'
                : 'activity_start_session')),
            style: ElevatedButton.styleFrom(
              backgroundColor: running ? AppColors.destructive : AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }


  Widget _buildProgressCard() {
    final s = _session!;
    final pct = s.playerIds.isEmpty ? 0.0
        : s.completedPlayerIds.length / s.playerIds.length;
    final pctInt = (pct * 100).round();
    final color = pctInt == 100 ? AppColors.success : AppColors.primary;
    final batchAllowedTypes = _getAllowedAssessmentTypes(s);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(AppLocalizations.get('progress_label').toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 0.8)),
              const Spacer(),
              Text('$pctInt%',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 18)),
            ],
          ),
          const SizedBox(height: 10),
          Stack(children: [
            Container(height: 6,
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(99))),
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(height: 6,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(99))),
            ),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(AppLocalizations.format('players_assessed_of',
                  {'done': s.completedPlayerIds.length, 'total': s.playerIds.length}),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const Spacer(),
              if (pctInt == 100)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 14),
                    const SizedBox(width: 4),
                    Text(AppLocalizations.get('session_completed_label'), style: const TextStyle(
                        color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 11)),
                  ],
                ),
            ],
          ),
          if (canRunAssessments && batchAllowedTypes.isNotEmpty && pctInt < 100) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _startBatchAssessment,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.queue_rounded, color: AppColors.foreground, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    batchAllowedTypes.length == 1
                        ? '${AppLocalizations.get('batch_assessment_btn')} · ${batchAllowedTypes.first.displayName}'
                        : AppLocalizations.get('batch_assessment_btn'),
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssessmentSummary() {
    final s = _session!;
    final completedPlayers = _players
        .where((p) => s.completedPlayerIds.contains(p.id))
        .toList();

    if (completedPlayers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(children: [
          const Icon(Icons.sports_score_rounded,
              color: AppColors.muted, size: 18),
          const SizedBox(width: 10),
          Text(AppLocalizations.get('no_assessments_yet'),
              style: const TextStyle(
                  color: AppColors.muted, fontSize: 12)),
        ]),
      );
    }

    final withScores = completedPlayers
        .where((p) => p.latestScore != null)
        .toList();
    final avgScore = withScores.isEmpty
        ? null
        : withScores
                .map((p) => p.latestScore!)
                .reduce((a, b) => a + b) /
            withScores.length;
    final needFollowup =
        withScores.where((p) => p.latestScore! < 60).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.analytics_rounded,
                color: AppColors.primary, size: 15),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.get('session_summary_coach_note').toUpperCase(),
              style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _SummaryStatBox(
                value: AppLocalizations.format('session_assessed_count',
                    {'n': completedPlayers.length}),
                label: '',
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
              ),
            ),
            if (avgScore != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryStatBox(
                  value: '${avgScore.round()}/100',
                  label: AppLocalizations.get('session_avg_score'),
                  icon: Icons.sports_score_rounded,
                  color: avgScore >= 70
                      ? AppColors.success
                      : avgScore >= 55
                          ? AppColors.warning
                          : AppColors.destructive,
                ),
              ),
            ],
            if (needFollowup > 0) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryStatBox(
                  value: '$needFollowup',
                  label: AppLocalizations.get('session_needs_followup'),
                  icon: Icons.flag_rounded,
                  color: AppColors.destructive,
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _buildExercisesCard() {
    final aiExercises     = _exercises.where((e) => e.isAI).toList();
    final manualExercises = _exercises.where((e) => !e.isAI).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.fitness_center_rounded,
                color: AppColors.maroon, size: 16),
            const SizedBox(width: 8),
            Text(AppLocalizations.format('exercises_title', {'count': _exercises.length}),
                style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ]),
          if (aiExercises.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(AppLocalizations.get('ai_assessments_label'),
                style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...aiExercises.map((ex) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                      color: AppColors.maroon, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(exerciseDisplayLabel(ex), style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('AI', style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 9)),
                ),
              ]),
            )),
          ],
          if (manualExercises.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(AppLocalizations.get('manual_exercises_label'),
                style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...manualExercises.map((ex) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                      color: AppColors.muted, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(exerciseDisplayLabel(ex), style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 12))),
                if (ex.volumeLabel.isNotEmpty)
                  Text(ex.volumeLabel,
                      style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11)),
              ]),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayersSection() {
    final s = _session!;
    if (_players.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(AppLocalizations.get('no_players_session'),
              style: const TextStyle(
                  color: AppColors.muted)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(AppLocalizations.get('session_players_label').toUpperCase(),
              style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 0.8)),
        ),
        ..._players.map((p) {
          final done  = s.completedPlayerIds.contains(p.id);
          final eval  = _evaluations.where((e) => e.playerId == p.id).firstOrNull;
          final avg   = eval?.average;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: done
                  ? Border.all(color: AppColors.success.withOpacity(0.20))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () async {
                    if (isDoctorRole) {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => InjuryCaseScreen(
                          playerId: p.id,
                          playerName: p.fullName,
                        ),
                      ));
                      return;
                    }
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ClubPlayerProfilePage(
                        playerId: p.id,
                        sessionId: widget.sessionId,
                      ),
                    ));
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: done ? AppColors.success.withOpacity(0.10) : AppColors.surface2,
                          border: Border.all(
                              color: done ? AppColors.success.withOpacity(0.40) : AppColors.border,
                              width: 0.8)),
                        child: Center(child: Text(p.initials,
                            style: TextStyle(
                                color: done ? AppColors.success : AppColors.muted,
                                fontWeight: FontWeight.w700,
                                fontSize: 12))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.fullName, style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('#${p.number}  ·  ${p.position}',
                              style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      )),
                      // Assessment button
                      if (done)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.success.withOpacity(0.25), width: 0.8)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.check_rounded,
                                color: AppColors.success, size: 13),
                            const SizedBox(width: 4),
                            Text(AppLocalizations.get('done_label'),
                                style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11)),
                          ]),
                        )
                      else
                        GestureDetector(
                          onTap: () => _startTest(p),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [BoxShadow(
                                  color: AppColors.primary.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))]),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.videocam_rounded,
                                  color: AppColors.foreground, size: 14),
                              const SizedBox(width: 5),
                              Text(AppLocalizations.get('start_btn'),
                                  style: const TextStyle(
                                      color: AppColors.foreground,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
                // Coach evaluation row
                const SizedBox(height: 10),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final result = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppColors.card,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24))),
                      builder: (_) => CoachEvaluationSheet(
                        player: p,
                        sessionId: widget.sessionId,
                        existing: eval,
                      ),
                    );
                    if (result == true) _load();
                  },
                  child: Row(children: [
                    Icon(Icons.star_outline_rounded,
                        color: avg != null ? AppColors.primary : AppColors.muted, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      avg != null
                          ? AppLocalizations.format('coach_rating_value', {'score': avg.toStringAsFixed(1)})
                          : AppLocalizations.get('add_coach_rating'),
                      style: TextStyle(
                          color: avg != null ? AppColors.primary : AppColors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 11)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.muted, size: 16),
                  ]),
                ),
                if (s.attendanceRequired) ...[
                  const SizedBox(height: 10),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 8),
                  _AttendanceRow(
                    status: _attendance[p.id] ?? 'pending',
                    onChanged: (status) => _setAttendance(p.id, status),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.status, required this.onChanged});
  final String status;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('present', Icons.check_circle_outline_rounded, AppColors.success),
    ('late', Icons.schedule_rounded, AppColors.warning),
    ('absent', Icons.cancel_outlined, AppColors.destructive),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _options.map((opt) {
        final (value, icon, color) = opt;
        final selected = status == value;
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? color.withOpacity(0.14) : AppColors.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: selected ? color.withOpacity(0.4) : AppColors.border,
                    width: 0.8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: selected ? color : AppColors.muted, size: 14),
                const SizedBox(width: 4),
                Text(AppLocalizations.get('attendance_$value'),
                    style: TextStyle(
                        color: selected ? color : AppColors.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 11)),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Type Picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TestTypePicker extends StatelessWidget {
  const _TestTypePicker({required this.allowedTypes});

  final List<AssessmentTestType> allowedTypes;


  static (String, IconData, Color) _infoFor(AssessmentTestType t) {
    switch (t) {
      case AssessmentTestType.squat:
        return (AppLocalizations.get('assessment_test_short_squat'), Icons.accessibility_new_rounded, AppColors.maroon);
      case AssessmentTestType.singleLegBalance:
        return (AppLocalizations.get('assessment_test_short_singleLegBalance'), Icons.sports_gymnastics_rounded, AppColors.success);
      case AssessmentTestType.jumpLanding:
        return (AppLocalizations.get('assessment_test_short_jumpLanding'), Icons.arrow_downward_rounded, AppColors.risk);
      case AssessmentTestType.countermovementJump:
        return (AppLocalizations.get('assessment_short_cmj'), Icons.arrow_upward_rounded, AppColors.gold);
      case AssessmentTestType.squatJump:
        return (AppLocalizations.get('assessment_short_squat_jump'), Icons.sports_gymnastics_rounded, AppColors.primary);
      case AssessmentTestType.dropJump:
        return (AppLocalizations.get('assessment_short_drop_jump'), Icons.arrow_downward_rounded, AppColors.warning);
      case AssessmentTestType.singleLegDropJump:
        return (AppLocalizations.get('assessment_short_sl_drop_jump'), Icons.directions_run_rounded, AppColors.playerAccent);
    }
  }

  static (String label, Color color)? _statusBadge(AssessmentTestStatus status) {
    switch (status) {
      case AssessmentTestStatus.complete:       return null; // no badge needed
      case AssessmentTestStatus.partial:        return (AppLocalizations.get('test_status_partial'), AppColors.warning);
      case AssessmentTestStatus.demoOnly:       return (AppLocalizations.get('test_status_demo'), AppColors.muted);
      case AssessmentTestStatus.notImplemented: return (AppLocalizations.get('test_status_not_implemented'), AppColors.risk);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tests = allowedTypes.map((t) {
      final info = _infoFor(t);
      return (t, info.$1, info.$2, info.$3);
    }).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: Responsive.bottomSheetMaxHeight(context)),
      child: SingleChildScrollView(
        child: Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(AppLocalizations.get('select_test'),
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 17)),
          const SizedBox(height: 14),
          for (final t in tests) ...[
            Builder(builder: (ctx) {
              final badge = _statusBadge(t.$1.testStatus);
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(t.$1),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: t.$4.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.$4.withOpacity(0.25), width: 0.8),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                          color: t.$4.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(11)),
                      child: Icon(t.$3, color: t.$4, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.$2,
                              style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                          if (badge != null) ...[
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: badge.$2.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: badge.$2.withOpacity(0.3), width: 0.7),
                              ),
                              child: Text(badge.$1,
                                  style: TextStyle(
                                      color: badge.$2,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: t.$4.withOpacity(0.6), size: 18),
                  ]),
                ),
              );
            }),
          ],
        ],
      ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session Summary Stat Box
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryStatBox extends StatelessWidget {
  const _SummaryStatBox({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final String value, label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      height: 1.1)),
              if (label.isNotEmpty)
                Text(label,
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 9),
                    maxLines: 1),
            ],
          ),
        ),
      ]),
    );
  }
}
