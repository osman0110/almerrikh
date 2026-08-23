import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../utils/app_logger.dart';
import '../../utils/metric_formatter.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../shared/club_status_color.dart';
import '../../shared/responsive.dart';
import '../../models/player_profile_model.dart';
import '../../models/assessment_result_model.dart';
import '../../services/club_service.dart';
import '../../services/assessment_storage_service.dart';
import '../../services/player_monitoring_service.dart';
import '../../services/body_composition_service.dart';
import '../../models/body_composition_models.dart';
import '../../services/report_service.dart';
import '../player/body_composition_entry_screen.dart';
import 'body_composition_compare_page.dart';
import '../../services/readiness_helper.dart';
import '../../services/risk_flags_helper.dart';
import 'injury_case_screen.dart';
import 'admin_player_report_screen.dart';
import 'physio_session_screen.dart';
import 'nutrition_screen.dart';
import 'individual_program_page.dart';
import '../../services/score_interpreter.dart';
import '../../services/smart_recommendation_service.dart';
import '../../services/coach_summary_helper.dart';
import '../../screens/physical_assessment/assessment_camera_page.dart';
import 'add_edit_player_page.dart';
import '../coach/coach_assessment_report_screen.dart';
import 'fms_summary_section.dart';
import 'club_widgets.dart';
import 'competition_stats_section.dart';
import 'player_report_preview_page.dart';
import 'training_load_section.dart';

int? _nullableJsonInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

// Maps an AI-generated exercise's stored `assessmentType` to its localization
// key (mirrors _aiAssessmentTypes in session_form_page.dart). Manual/custom
// exercises (or unrecognized types) fall back to the raw stored `exerciseName`.
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
// Club Player Profile Page
// ─────────────────────────────────────────────────────────────────────────────

class ClubPlayerProfilePage extends StatefulWidget {
  const ClubPlayerProfilePage({
    super.key,
    required this.playerId,
    this.sessionId,
  });
  final String playerId;
  final String? sessionId;

  @override
  State<ClubPlayerProfilePage> createState() => _ClubPlayerProfilePageState();
}

class _ClubPlayerProfilePageState extends State<ClubPlayerProfilePage> {
  ClubPlayer? _player;
  List<PlayerAssessment> _history = [];
  List<CoachNote> _notes = [];
  List<ClubSessionExercise> _sessionExercises = [];
  List<Map<String, dynamic>> _injuryCases = [];
  List<Map<String, dynamic>> _physioSessions = [];
  List<Map<String, dynamic>> _nutritionPlans = [];
  List<Map<String, dynamic>> _statusHistory = [];
  bool _loading = true;
  bool _loadInProgress = false;
  bool _addingNote = false;
  int _contentGeneration = 0;
  final _noteCtrl = TextEditingController();

  bool get _canViewAssessmentDetails =>
      canRunAssessments || isAnalystRole || isTacticalCoachRole;

  bool get _canViewCompetitionStats => true;

  @override
  void initState() {
    super.initState();
    _load(showFullLoader: true);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    bool showFullLoader = false,
    bool refreshChildren = false,
  }) async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    final start = DateTime.now();
    if (showFullLoader && _player == null) {
      setState(() => _loading = true);
    }
    try {
      final player = await ClubService().getPlayer(widget.playerId);
      if (!mounted) return;

      if (player != null) {
        final results = await Future.wait([
          ClubService().getAssessmentsForPlayer(player.id),
          ClubService().getNotesForPlayer(player.id),
          widget.sessionId != null
              ? ClubService().getSessionExercises(widget.sessionId!)
              : Future.value(<ClubSessionExercise>[]),
          // Live status badges for the specialty entry cards below — only
          // fetched for roles that can actually see that card.
          canManageInjuryCases
              ? ApiService.getInjuryCases(player.id)
              : Future.value(<Map<String, dynamic>>[]),
          canManagePhysioSessions
              ? ApiService.getPhysioSessions(player.id)
              : Future.value(<Map<String, dynamic>>[]),
          // getNutritionPlans rethrows on failure (nutrition_screen.dart
          // needs that to show a real error state) — this badge is purely
          // decorative, so swallow locally rather than let it break the
          // whole batch load above.
          canManageNutrition
              ? ApiService.getNutritionPlans(
                  player.id,
                ).catchError((_) => <Map<String, dynamic>>[])
              : Future.value(<Map<String, dynamic>>[]),
          ApiService.getPlayerStatusHistory(player.id),
        ]);

        if (!mounted) return;
        setState(() {
          _player = player;
          _history = results[0] as List<PlayerAssessment>;
          _notes = results[1] as List<CoachNote>;
          _sessionExercises = results[2] as List<ClubSessionExercise>;
          _injuryCases = results[3] as List<Map<String, dynamic>>;
          _physioSessions = results[4] as List<Map<String, dynamic>>;
          _nutritionPlans = results[5] as List<Map<String, dynamic>>;
          _statusHistory = results[6] as List<Map<String, dynamic>>;
          if (refreshChildren) _contentGeneration++;
          _loading = false;
        });
      } else {
        if (mounted)
          setState(() {
            _loading = false;
          });
      }

      final ms = DateTime.now().difference(start).inMilliseconds;
      AppLogger.i('PlayerProfile', 'Loaded in ${ms}ms');
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      AppLogger.e('PlayerProfile', 'Load failed', e);
    } finally {
      _loadInProgress = false;
    }
  }

  Future<void> _refresh() =>
      _load(refreshChildren: true);

  Future<void> _addNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty || _player == null) return;
    setState(() => _addingNote = true);
    await ClubService().addNote(
      CoachNote(
        id: '',
        playerId: _player!.id,
        authorName: currentUserName,
        text: text,
        date: DateTime.now(),
      ),
    );
    _noteCtrl.clear();
    await _load();
    if (mounted) setState(() => _addingNote = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (_player == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_off_rounded,
                color: AppColors.muted,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.get('player_not_found'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppLocalizations.get('back_btn')),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.card,
                triggerMode: RefreshIndicatorTriggerMode.onEdge,
                notificationPredicate: (notification) =>
                    notification.depth == 0,
                onRefresh: _refresh,
                child: ListView(
                  physics: const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    _buildPlayerCard(),
                    const SizedBox(height: 14),
                    ClubSectionLabel(
                      AppLocalizations.get('physical_report_title'),
                    ),
                    const SizedBox(height: 8),
                    if (_canViewAssessmentDetails) ...[
                      _buildAssessmentAction(),
                      const SizedBox(height: 8),
                    ],
                    if (isCoachRole) ...[
                      TrainingLoadSection(
                        key: ValueKey('training-load-$_contentGeneration'),
                        playerId: widget.playerId,
                        compact: true,
                      ),
                      const SizedBox(height: 8),
                      _BodyCompositionSection(
                        key: ValueKey('body-composition-$_contentGeneration'),
                        playerId: widget.playerId,
                        playerName: _player!.fullName,
                      ),
                      const SizedBox(height: 8),
                      FmsSummarySection(
                        key: ValueKey('fms-$_contentGeneration'),
                        playerId: widget.playerId,
                        playerName: _player!.fullName,
                        compact: true,
                      ),
                    ],
                    if (_canViewAssessmentDetails) ...[
                      const SizedBox(height: 10),
                      _buildAssessmentButtons(),
                    ],
                    if (_sessionExercises.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildSessionExercises(),
                    ],
                    const SizedBox(height: 14),
                    ClubSectionLabel(
                      AppLocalizations.get('monitoring_title'),
                    ),
                    const SizedBox(height: 8),
                    _ReadinessAndFlagsSection(
                      key: ValueKey('readiness-$_contentGeneration'),
                      player: _player!,
                    ),
                    if (_statusHistory.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildStatusHistorySection(),
                    ],
                    if (isOrgAdmin) ...[
                      const SizedBox(height: 10),
                      _buildAdminReportEntry(),
                    ],
                    if (canManageInjuryCases) ...[
                      const SizedBox(height: 10),
                      _buildInjuryFileEntry(),
                    ],
                    if (canManagePhysioSessions) ...[
                      const SizedBox(height: 10),
                      _buildPhysioSessionsEntry(),
                    ],
                    if (canManageNutrition) ...[
                      const SizedBox(height: 10),
                      _buildNutritionEntry(),
                    ],
                    if (canManagePlayers) ...[
                      const SizedBox(height: 10),
                      _buildIndividualProgramsEntry(),
                    ],
                    const SizedBox(height: 20),
                    if (_canViewCompetitionStats) ...[
                      ClubSectionLabel(
                        AppLocalizations.get('competitions_title'),
                      ),
                      CompetitionStatsSection(playerId: widget.playerId),
                      const SizedBox(height: 20),
                    ],
                    ClubSectionLabel(AppLocalizations.get('coach_notes_label')),
                    if (canManagePlayers) _buildNoteInput(),
                    const SizedBox(height: 10),
                    if (_notes.isEmpty)
                      _emptyNotes()
                    else
                      ..._notes.map(
                        (n) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _NoteCard(note: n),
                        ),
                      ),
                    if (_player!.physicalNotes != null &&
                        _player!.physicalNotes!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ClubSectionLabel(
                        AppLocalizations.get('physical_notes_label'),
                      ),
                      _PhysicalNotesCard(text: _player!.physicalNotes!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top > 0 ? 16 : 16,
        16,
        14,
      ),
      color: AppColors.background,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.foreground,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppLocalizations.get('player_file_title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          if (canManagePlayers)
            GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddEditPlayerPage(player: _player!),
                  ),
                );
                _load();
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  color: AppColors.foreground,
                  size: 15,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Live status for the specialty entry cards ────────────────────────────────

  bool get _hasOpenInjuryCase => _injuryCases.any(
    (c) =>
        !['graduated', 'closed'].contains((c['case_status'] ?? '').toString()),
  );

  Map<String, dynamic>? get _nextScheduledPhysioSession {
    final now = DateTime.now();
    final scheduled =
        _physioSessions
            .where((s) => (s['status'] ?? '').toString() == 'scheduled')
            .toList()
          ..sort(
            (a, b) => (a['scheduled_at'] ?? '').toString().compareTo(
              (b['scheduled_at'] ?? '').toString(),
            ),
          );
    for (final s in scheduled) {
      final dt = DateTime.tryParse((s['scheduled_at'] ?? '').toString());
      if (dt != null && !dt.isBefore(now)) return s;
    }
    return null;
  }

  String _formatWhen(DateTime dt) {
    final now = DateTime.now();
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow =
        dt.year == tomorrow.year &&
        dt.month == tomorrow.month &&
        dt.day == tomorrow.day;
    if (sameDay) return '${AppLocalizations.get('today_label')} $time';
    if (isTomorrow) return '${AppLocalizations.get('tomorrow_label')} $time';
    return '${AppLocalizations.formatDate(dt)} $time';
  }

  // ── Injury File entry (doctor / physiotherapist / admin only) ────────────────

  Widget _buildAdminReportEntry() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AdminPlayerReportScreen(
            playerId: widget.playerId,
            playerName: _player!.fullName,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.assessment_rounded,
              color: AppColors.primary,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppLocalizations.get('admin_player_report_entry'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_left_rounded,
              color: AppColors.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInjuryFileEntry() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InjuryCaseScreen(
            playerId: widget.playerId,
            playerName: _player!.fullName,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.medical_information_rounded,
              color: AppColors.destructive,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.get('injury_file'),
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (_hasOpenInjuryCase)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.destructive,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            AppLocalizations.get('injury_case_open_badge'),
                            style: const TextStyle(
                              color: AppColors.destructive,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ── Physiotherapy & Massage entry (doctor / physio / massage / admin only) ───

  Widget _buildPhysioSessionsEntry() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhysioSessionScreen(
            playerId: widget.playerId,
            playerName: _player!.fullName,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.spa_rounded, color: AppColors.risk, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.get('physio_sessions_title'),
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final next = _nextScheduledPhysioSession;
                      if (next == null) return const SizedBox.shrink();
                      final dt = DateTime.tryParse(
                        (next['scheduled_at'] ?? '').toString(),
                      );
                      if (dt == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatWhen(dt),
                          style: const TextStyle(
                            color: AppColors.risk,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ── Nutrition entry (doctor / nutritionist / admin only) ─────────────────────

  Widget _buildNutritionEntry() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NutritionScreen(
            playerId: widget.playerId,
            playerName: _player!.fullName,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.restaurant_menu_rounded,
              color: AppColors.warning,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.get('nutrition_title'),
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (_nutritionPlans.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        AppLocalizations.format(
                          'nutrition_active_plans_badge',
                          {'count': _nutritionPlans.length},
                        ),
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ── Individual programs entry (coach / performance manager / admin) ──────────

  Widget _buildIndividualProgramsEntry() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IndividualProgramPage(
            playerId: widget.playerId,
            playerName: _player!.fullName,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.fitness_center_rounded,
              color: AppColors.coachAccent,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.get('individual_programs_title'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(
              Icons.north_east_rounded,
              color: AppColors.muted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ── Status History ───────────────────────────────────────────────────────────

  Widget _buildStatusHistorySection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                color: AppColors.muted,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.get('status_history_label'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._statusHistory.take(5).map((h) {
            final oldStatus = h['old_status'] as String?;
            final newStatus = PlayerStatusExt.fromString(
              (h['new_status'] ?? 'active').toString(),
            );
            final newColor = clubStatusColor(newStatus);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: newColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      oldStatus != null
                          ? '${PlayerStatusExt.fromString(oldStatus).localizedLabel} ← ${newStatus.localizedLabel}'
                          : newStatus.localizedLabel,
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${h['changed_at'] ?? ''}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Player Card ─────────────────────────────────────────────────────────────

  Widget _buildPlayerCard() {
    final p = _player!;
    final statusColor = clubStatusColor(p.status);
    final hasPhoto = p.profileImageUrl?.isNotEmpty ?? false;

    final infoBlock = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '#${p.number} ',
                style: const TextStyle(
                  color: AppColors.onDarkMuted,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              TextSpan(
                text: p.fullName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 3),
        Text(
          [
            if (p.teamName?.isNotEmpty == true) p.teamName!,
            if (p.position.isNotEmpty) p.position,
          ].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.onDarkMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                p.status.localizedLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _compactPlayerMeta(
                label: AppLocalizations.get('bio_age'),
                value: p.age > 0 ? '${p.age}' : '—',
              ),
              _statDivider(),
              _compactPlayerMeta(
                label: AppLocalizations.get('bio_weight'),
                value: MetricFormatter.weight(p.weight),
              ),
              _statDivider(),
              _compactPlayerMeta(
                label: AppLocalizations.get('bio_height'),
                value: MetricFormatter.height(p.height),
              ),
              _statDivider(),
              _compactPlayerMeta(
                label: AppLocalizations.get('bio_foot'),
                value: _capitalize(p.dominantFoot),
              ),
            ],
          ),
        ),
      ],
    );

    final cardDecoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [statusColor, const Color(0xFF2A0008)],
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: statusColor.withOpacity(0.25),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );

    if (!hasPhoto) {
      // No photo: simple gradient card, initials avatar on top, text centered.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: cardDecoration,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.6),
                    radius: 0.9,
                    colors: [
                      Colors.white.withOpacity(0.12),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                _buildCompactPlayerAvatar(p),
                const SizedBox(height: 12),
                infoBlock,
              ],
            ),
          ],
        ),
      );
    }

    // Has a photo: the photo defines the card's height via AspectRatio (a
    // bounded, deterministic size — required so the Stack below can size
    // itself; a Stack made only of Positioned children with no bounded
    // height crashes with a 'size.isFinite' assertion inside a ListView).
    // The face is what matters, so the image is top-aligned and the info
    // sits at the bottom over a dark scrim, keeping the top clear.
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration,
      child: AspectRatio(
        aspectRatio: 4 / 3.4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              p.profileImageUrl!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.35, 1.0],
                  colors: [
                    Colors.transparent,
                    const Color(0xFF2A0008).withOpacity(0.92),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: infoBlock,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: Colors.white.withOpacity(0.25),
      );

  Widget _buildCompactPlayerAvatar(ClubPlayer p) {
    const size = 72.0;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.10),
          border: Border.all(color: AppColors.gold.withOpacity(0.65), width: 2.5),
        ),
        child: ClipOval(
          child: (p.profileImageUrl?.isNotEmpty ?? false)
              ? Image.network(
                  p.profileImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _compactAvatarPlaceholder(p),
                )
              : _compactAvatarPlaceholder(p),
        ),
      ),
    );
  }

  Widget _compactAvatarPlaceholder(ClubPlayer p) {
    return Center(
      child: Text(
        p.initials,
        style: const TextStyle(
          color: AppColors.gold,
          fontWeight: FontWeight.w900,
          fontSize: 26,
        ),
      ),
    );
  }

  Widget _compactPlayerMeta({required String label, required String value}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 8,
          ),
        ),
      ],
    );
  }

  // ── Score Trend Chart ────────────────────────────────────────────────────────

  // ignore: unused_element
  Widget _buildScoreTrend() {
    // Sort ascending by date, take last 8
    final sorted = (_history.toList()..sort((a, b) => a.date.compareTo(b.date)))
        .take(8)
        .toList();

    final spots = sorted
        .asMap()
        .entries
        .map(
          (e) => FlSpot(e.key.toDouble(), e.value.overallScore.clamp(0, 100)),
        )
        .toList();

    final minY =
        (sorted.map((a) => a.overallScore).reduce((a, b) => a < b ? a : b) - 10)
            .clamp(0, 100)
            .toDouble();
    final maxY =
        (sorted.map((a) => a.overallScore).reduce((a, b) => a > b ? a : b) + 10)
            .clamp(0, 100)
            .toDouble();
    final last = sorted.last.overallScore;
    final first = sorted.first.overallScore;
    final trending = last > first + 2
        ? 'improving'
        : last < first - 2
        ? 'declining'
        : 'stable';
    final trendColor = trending == 'improving'
        ? AppColors.success
        : trending == 'declining'
        ? AppColors.destructive
        : AppColors.warning;
    final trendIcon = trending == 'improving'
        ? Icons.trending_up_rounded
        : trending == 'declining'
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;
    final trendLabel = trending == 'improving'
        ? AppLocalizations.get('trend_improving')
        : trending == 'declining'
        ? AppLocalizations.get('trend_declining')
        : AppLocalizations.get('trend_stable');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClubSectionLabel(AppLocalizations.get('performance_trend_title')),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppLocalizations.get('trend_chart_label'),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: trendColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: trendColor.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(trendIcon, color: trendColor, size: 12),
                        const SizedBox(width: 3),
                        Text(
                          trendLabel,
                          style: TextStyle(
                            color: trendColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 90,
                child: LineChart(
                  LineChartData(
                    minY: minY,
                    maxY: maxY,
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.35,
                        color: AppColors.coachAccent,
                        barWidth: 2.5,
                        isStrokeCapRound: true,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, pct, bar, idx) =>
                              FlDotCirclePainter(
                                radius: idx == spots.length - 1 ? 4 : 2.5,
                                color: idx == spots.length - 1
                                    ? AppColors.coachAccent
                                    : AppColors.coachAccent.withOpacity(0.55),
                                strokeWidth: 0,
                                strokeColor: Colors.transparent,
                              ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.coachAccent.withOpacity(0.18),
                              AppColors.coachAccent.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 20,
                          getTitlesWidget: (v, m) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= sorted.length)
                              return const SizedBox.shrink();
                            final d = sorted[idx].date;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${d.day}/${d.month}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 8.5,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, m) => Text(
                            '${v.toInt()}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 8.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) =>
                          FlLine(color: AppColors.surface2, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      enabled: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => AppColors.foreground,
                        tooltipRoundedRadius: 8,
                        getTooltipItems: (spots) => spots
                            .map(
                              (s) => LineTooltipItem(
                                '${s.y.toInt()} ${AppLocalizations.get("pts_label")}',
                                const TextStyle(
                                  color: AppColors.coachAccent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            )
                            .toList(),
                      ),
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

  // ── Session Exercises ──────────────────────────────────────────────────────

  Widget _buildSessionExercises() {
    final aiExercises = _sessionExercises.where((e) => e.isAI).toList();
    final manualExercises = _sessionExercises.where((e) => !e.isAI).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClubSectionLabel(
          AppLocalizations.format('exercises_title', {
            'count': _sessionExercises.length,
          }),
        ),
        Container(
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
              if (aiExercises.isNotEmpty) ...[
                Text(
                  AppLocalizations.get('ai_assessments_label'),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ...aiExercises.map(
                  (ex) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.maroon,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _exerciseDisplayLabel(ex),
                          style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'AI',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (manualExercises.isNotEmpty) ...[
                if (aiExercises.isNotEmpty) const SizedBox(height: 12),
                Text(
                  AppLocalizations.get('manual_exercises_label'),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ...manualExercises.map(
                  (ex) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.muted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _exerciseDisplayLabel(ex),
                            style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (ex.volumeLabel.isNotEmpty)
                          Text(
                            ex.volumeLabel,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Assessment Action ────────────────────────────────────────────────────────

  Widget _buildAssessmentAction() {
    final latest = _history.isNotEmpty ? _history.first : null;
    final hasScore = latest != null;
    final score = latest?.effectiveScore ?? 0;
    final rating = score >= 85
        ? AppLocalizations.get('score_excellent')
        : score >= 75
            ? AppLocalizations.get('score_very_good')
            : score >= 60
                ? AppLocalizations.get('score_good')
                : AppLocalizations.get('score_needs_improvement');

    final badgeColor = !hasScore
        ? AppColors.muted
        : score >= 75
            ? AppColors.success
            : score >= 60
                ? AppColors.warning
                : AppColors.destructive;
    final badgeLabel = hasScore ? rating : AppLocalizations.get('no_data_label');

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: AppColors.maroon.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.insights_rounded,
                  color: AppColors.maroon,
                  size: 13,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.get('perf_assessment_title'),
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 5, height: 5,
                    decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    badgeLabel,
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 9,
                    ),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hasScore ? '${score.round()}' : '—',
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (hasScore) ...[
                const SizedBox(width: 4),
                const Text('/ 100 نقطة',
                    style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w500)),
              ],
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    hasScore
                        ? AppLocalizations.formatDate(latest.date, withYear: true)
                        : AppLocalizations.get('perf_assessment_empty'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w600, fontSize: 9.5),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    AppLocalizations.format('assessment_count_label', {'count': _history.length}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 9),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssessmentButtons() {
    final hasScore = _history.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _assessmentPrimaryButton(
          AppLocalizations.get('start_camera_assessment_btn'),
          Icons.videocam_rounded,
          _startAssessment,
        ),
        const SizedBox(height: 8),
        _assessmentSecondaryButton(
          hasScore
              ? AppLocalizations.get('view_report_btn')
              : AppLocalizations.get('add_manual_assessment_btn'),
          hasScore ? Icons.description_outlined : Icons.edit_note_rounded,
          hasScore ? _openAssessmentDetails : _addManualAssessment,
        ),
      ],
    );
  }

  Widget _assessmentPrimaryButton(
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) => SizedBox(
        height: 44,
        child: FilledButton.icon(
          onPressed: canRunAssessments ? onPressed : null,
          icon: Icon(icon, size: 17),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: const Color(0xFF3A2A08),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      );

  Widget _assessmentSecondaryButton(
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) => SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          onPressed: canRunAssessments ? onPressed : null,
          icon: Icon(icon, size: 16),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.foreground,
            side: const BorderSide(color: AppColors.border, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      );

  // ignore: unused_element
  Widget _scoreChip(String label, double? value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Column(
      children: [
        Text(
          value == null ? '—' : '${value.round()}%',
          style: const TextStyle(
            color: AppColors.foreground,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
        ),
      ],
    ),
  );

  Future<void> _openAssessmentDetails() async {
    if (_player == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CoachAssessmentReportScreen(
          playerId: widget.playerId,
          playerName: _player!.fullName,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _startAssessment() async {
    if (_player == null) return;
    final testType = await showModalBottomSheet<AssessmentTestType>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: Responsive.bottomSheetMaxHeight(ctx),
        ),
        child: SingleChildScrollView(child: _AssessmentTypePicker()),
      ),
    );
    if (testType == null || !mounted) return;
    final result = await Navigator.of(context).pushNamed(
      '/physical-assessment/camera',
      arguments: AssessmentCameraArguments(
        player: PlayerProfile(
          id: _player!.id,
          name: _player!.fullName,
          heightCm: _player!.height?.toInt(),
          weightKg: _player!.weight?.toInt(),
          position: _player!.position,
        ),
        testType: testType,
      ),
    );
    if (result != null) {
      _load();
    }
  }

  Future<void> _addManualAssessment() async {
    if (_player == null || !mounted) return;
    final controller = TextEditingController();
    final score = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.get('add_manual_assessment_btn')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: AppLocalizations.get('manual_assessment_score_out_of_100'),
            hintText: AppLocalizations.get('manual_assessment_score_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value >= 0 && value <= 100) {
                Navigator.of(dialogContext).pop(value);
              }
            },
            child: Text(AppLocalizations.get('save_btn')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (score == null || !mounted || _player == null) return;

    final result = AssessmentResult(
      id: '${_player!.id}_manual_${DateTime.now().millisecondsSinceEpoch}',
      playerId: _player!.id,
      playerName: _player!.fullName,
      testType: AssessmentTestType.squat,
      overallScore: score,
      movementQualityScore: score,
      stabilityScore: score,
      symmetryScore: score,
      controlScore: score,
      qualityScore: 100,
      angleMetrics: const {},
      issues: const [],
      correctionTips: const [],
      recommendedDrills: const [],
      createdAt: DateTime.now(),
    );
    await AssessmentStorageService.instance.saveAssessment(result);
    if (mounted) _load();
  }

  // ── Performance Trends Section ───────────────────────────────────────────────

  // ignore: unused_element
  Widget _buildPerformanceTrendsSection() {
    if (_history.length < 2) return const SizedBox.shrink();

    final Map<AssessmentType, List<PlayerAssessment>> grouped = {};
    for (final a in _history) {
      grouped.putIfAbsent(a.type, () => []).add(a);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClubSectionLabel(AppLocalizations.get('perf_trends_title')),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: grouped.entries.map((entry) {
              final type = entry.key;
              final records = (entry.value.toList()
                ..sort((a, b) => b.date.compareTo(a.date)));
              final last = records.first.overallScore;
              final best = records
                  .map((r) => r.overallScore)
                  .reduce((a, b) => a > b ? a : b);
              final take5 = records.take(5).toList();
              final avg5 =
                  take5.map((r) => r.overallScore).reduce((a, b) => a + b) /
                  take5.length;

              // Trend only meaningful with ≥ 2 records of the same type
              String? trend;
              if (records.length >= 3) {
                final diff = records[0].overallScore - records[2].overallScore;
                if (diff > 5)
                  trend = 'improving';
                else if (diff < -5)
                  trend = 'declining';
                else
                  trend = 'stable';
              } else if (records.length == 2) {
                final diff = records[0].overallScore - records[1].overallScore;
                if (diff > 5)
                  trend = 'improving';
                else if (diff < -5)
                  trend = 'declining';
                else
                  trend = 'stable';
              }

              final trendColor = trend == 'improving'
                  ? AppColors.success
                  : trend == 'declining'
                  ? AppColors.destructive
                  : AppColors.muted;
              final trendIcon = trend == 'improving'
                  ? Icons.trending_up_rounded
                  : trend == 'declining'
                  ? Icons.trending_down_rounded
                  : Icons.trending_flat_rounded;
              final trendLabel = trend == 'improving'
                  ? AppLocalizations.get('trend_improving')
                  : trend == 'declining'
                  ? AppLocalizations.get('trend_declining')
                  : trend == 'stable'
                  ? AppLocalizations.get('trend_stable')
                  : '';

              final scoreColor = last >= 75
                  ? AppColors.success
                  : last >= 55
                  ? AppColors.warning
                  : AppColors.destructive;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            type.label,
                            style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (trend != null) ...[
                          Icon(trendIcon, color: trendColor, size: 13),
                          const SizedBox(width: 3),
                          Text(
                            trendLabel,
                            style: TextStyle(
                              color: trendColor,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _TrendStatChip(
                          label: AppLocalizations.get('trend_last_score'),
                          value: last.round().toString(),
                          color: scoreColor,
                        ),
                        const SizedBox(width: 6),
                        _TrendStatChip(
                          label: AppLocalizations.get('trend_best_score'),
                          value: best.round().toString(),
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        _TrendStatChip(
                          label: AppLocalizations.get('trend_avg_5'),
                          value: avg5.round().toString(),
                          color: AppColors.muted,
                        ),
                        const Spacer(),
                        Text(
                          '${records.length} ${AppLocalizations.get('sessions_title').toLowerCase()}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                    if (records.length >= 2) ...[
                      const SizedBox(height: 8),
                      _buildMiniTrendChart(records, trendColor),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// Small per-exercise sparkline — the stat chips above already give
  /// last/best/avg-5 as numbers; this is the missing visual trend line for
  /// that specific [AssessmentType], distinct from the overall combined
  /// score chart in [_buildScoreTrend].
  Widget _buildMiniTrendChart(List<PlayerAssessment> records, Color lineColor) {
    // records arrive newest-first; chart wants oldest-first, last 8.
    final ascending = records.reversed.toList();
    final windowed = ascending.length > 8
        ? ascending.sublist(ascending.length - 8)
        : ascending;

    final spots = windowed
        .asMap()
        .entries
        .map(
          (e) => FlSpot(e.key.toDouble(), e.value.overallScore.clamp(0, 100)),
        )
        .toList();
    final scores = windowed.map((r) => r.overallScore).toList();
    final minY = (scores.reduce((a, b) => a < b ? a : b) - 8)
        .clamp(0, 100)
        .toDouble();
    final maxY = (scores.reduce((a, b) => a > b ? a : b) + 8)
        .clamp(0, 100)
        .toDouble();

    return SizedBox(
      height: 44,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: lineColor,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                  radius: idx == spots.length - 1 ? 3 : 2,
                  color: idx == spots.length - 1
                      ? lineColor
                      : lineColor.withOpacity(0.5),
                  strokeWidth: 0,
                  strokeColor: Colors.transparent,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withOpacity(0.14),
                    lineColor.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
        ),
      ),
    );
  }

  // ── Note Input ───────────────────────────────────────────────────────────────

  Widget _buildNoteInput() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _noteCtrl,
              style: const TextStyle(color: AppColors.foreground, fontSize: 13),
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                hintText: AppLocalizations.get('add_coach_note'),
                hintStyle: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _addingNote ? null : _addNote,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _addingNote ? AppColors.primarySoft : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: _addingNote
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        color: AppColors.foreground,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: AppColors.foreground,
                      size: 16,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyNotes() {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.notes_rounded, color: AppColors.muted, size: 18),
          const SizedBox(width: 10),
          Text(
            AppLocalizations.get('no_coach_notes_yet'),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Assessment Type Breakdown ─────────────────────────────────────────────

  // ignore: unused_element
  Widget _buildTypeBreakdown(List<PlayerAssessment> history) {
    // Group by type → latest score + trend
    final Map<AssessmentType, List<PlayerAssessment>> grouped = {};
    for (final a in history) {
      grouped.putIfAbsent(a.type, () => []).add(a);
    }

    final typeColors = {
      AssessmentType.squat: AppColors.primary,
      AssessmentType.countermovementJump: const Color(0xffF59E0B),
      AssessmentType.squatJump: const Color(0xffEF4444),
      AssessmentType.dropJump: AppColors.risk,
      AssessmentType.singleLegDropJump: AppColors.risk,
      AssessmentType.singleLegBalance: AppColors.coachAccent,
      AssessmentType.jumpLanding: AppColors.risk,
    };
    final typeIcons = {
      AssessmentType.squat: Icons.accessibility_new_rounded,
      AssessmentType.countermovementJump: Icons.arrow_upward_rounded,
      AssessmentType.squatJump: Icons.trending_up_rounded,
      AssessmentType.dropJump: Icons.south_rounded,
      AssessmentType.singleLegDropJump: Icons.directions_run_rounded,
      AssessmentType.singleLegBalance: Icons.sports_gymnastics_rounded,
      AssessmentType.jumpLanding: Icons.arrow_downward_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.get('by_test_type_label'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          ...grouped.entries.map((entry) {
            final type = entry.key;
            final records = entry.value
              ..sort((a, b) => b.date.compareTo(a.date));
            final latest = records.first;
            final color = typeColors[type] ?? AppColors.muted;
            final icon = typeIcons[type] ?? Icons.sports_score_rounded;

            // Trend: compare latest vs previous of same type
            IconData trendIcon = Icons.trending_flat_rounded;
            Color trendColor = AppColors.warning;
            if (records.length >= 2) {
              final diff = latest.overallScore - records[1].overallScore;
              if (diff >= 5) {
                trendIcon = Icons.trending_up_rounded;
                trendColor = AppColors.success;
              } else if (diff <= -5) {
                trendIcon = Icons.trending_down_rounded;
                trendColor = AppColors.destructive;
              }
            }

            final scoreColor = latest.overallScore >= 75
                ? AppColors.success
                : latest.overallScore >= 55
                ? AppColors.warning
                : AppColors.destructive;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 14),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.label,
                          style: const TextStyle(
                            color: AppColors.foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${records.length} ${AppLocalizations.get('sessions_title').toLowerCase()}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Mini score sparkline (last 4)
                  Row(
                    children: records.take(4).toList().reversed.map((r) {
                      final h = (r.overallScore / 100).clamp(0.2, 1.0);
                      final c = r.overallScore >= 75
                          ? AppColors.success
                          : r.overallScore >= 55
                          ? AppColors.warning
                          : AppColors.destructive;
                      return Container(
                        width: 4,
                        height: 20 * h,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: c.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${latest.overallScore.round()}',
                    style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(trendIcon, color: trendColor, size: 14),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  // ignore: unused_element
  String _testLabel(AssessmentType t) => t.label;

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// Assessment Type Picker (bottom sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _AssessmentTypePicker extends StatelessWidget {
  const _AssessmentTypePicker();

  static const _tests = <(AssessmentTestType, String, String, IconData, Color)>[
    (
      AssessmentTestType.squat,
      'assessment_squat_title',
      'assessment_test_short_squat',
      Icons.accessibility_new_rounded,
      AppColors.maroon,
    ),
    (
      AssessmentTestType.countermovementJump,
      'assessment_short_cmj',
      'assessment_test_short_countermovementJump',
      Icons.arrow_upward_rounded,
      AppColors.gold,
    ),
    (
      AssessmentTestType.dropJump,
      'assessment_short_drop_jump',
      'assessment_test_short_dropJump',
      Icons.arrow_downward_rounded,
      AppColors.warning,
    ),
    (
      AssessmentTestType.singleLegDropJump,
      'assessment_sldj_title',
      'assessment_test_short_singleLegDropJump',
      Icons.directions_run_rounded,
      AppColors.playerAccent,
    ),
    (
      AssessmentTestType.squatJump,
      'assessment_short_squat_jump',
      'assessment_test_short_squatJump',
      Icons.sports_gymnastics_rounded,
      AppColors.primary,
    ),
    (
      AssessmentTestType.singleLegBalance,
      'assessment_slb_title',
      'assessment_test_short_singleLegBalance',
      Icons.sports_kabaddi_rounded,
      AppColors.success,
    ),
    (
      AssessmentTestType.jumpLanding,
      'assessment_jl_title',
      'assessment_test_short_jumpLanding',
      Icons.sports_score_rounded,
      AppColors.risk,
    ),
  ];

  static (String, Color)? _badge(AssessmentTestStatus s) {
    switch (s) {
      case AssessmentTestStatus.complete:
        return null;
      case AssessmentTestStatus.partial:
        return (AppLocalizations.get('test_status_partial'), AppColors.warning);
      case AssessmentTestStatus.demoOnly:
        return (AppLocalizations.get('test_status_demo'), AppColors.muted);
      case AssessmentTestStatus.notImplemented:
        return (AppLocalizations.get('test_status_not_implemented'), AppColors.risk);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            AppLocalizations.get('select_test'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 14),
          for (final t in _tests)
            Builder(
              builder: (_) {
                final badge = _badge(t.$1.testStatus);
                return GestureDetector(
                  onTap: () => Navigator.of(context).pop(t.$1),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: t.$5.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.$5.withOpacity(0.22)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: t.$5.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(t.$4, color: t.$5, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.get(t.$2),
                                style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppLocalizations.get(t.$3),
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                              if (badge != null) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badge.$2.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: badge.$2.withOpacity(0.3),
                                      width: 0.7,
                                    ),
                                  ),
                                  child: Text(
                                    badge.$1,
                                    style: TextStyle(
                                      color: badge.$2,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: t.$5.withOpacity(0.6),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Assessment Card
// ─────────────────────────────────────────────────────────────────────────────

// ignore: unused_element
class _AssessmentCard extends StatelessWidget {
  // ignore: unused_element_parameter
  const _AssessmentCard({required this.assessment, this.onOverridden});
  final PlayerAssessment assessment;
  final VoidCallback? onOverridden;

  Future<void> _openOverrideDialog(BuildContext context) async {
    final scoreCtrl = TextEditingController(
      text: assessment.effectiveScore.round().toString(),
    );
    final reasonCtrl = TextEditingController(
      text: assessment.overrideReason ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          AppLocalizations.get('edit_score_manually_title'),
          style: const TextStyle(color: AppColors.foreground),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.get('new_score_label'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: scoreCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.foreground),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.get('override_reason_label'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              style: const TextStyle(color: AppColors.foreground),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: AppLocalizations.get('override_reason_hint'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.get('save_btn')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newScore = int.tryParse(scoreCtrl.text);
    final reason = reasonCtrl.text.trim();
    if (newScore == null || newScore < 0 || newScore > 100 || reason.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.get('override_reason_validation_error'),
            ),
          ),
        );
      }
      return;
    }

    final ok = await ClubService().overrideAssessmentScore(
      assessmentId: assessment.id,
      overrideScore: newScore,
      reason: reason,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'تم تحديث النتيجة' : 'فشل تحديث النتيجة')),
      );
    }
    if (ok) onOverridden?.call();
  }

  @override
  Widget build(BuildContext context) {
    final interp = ScoreInterpreter.interpret(
      type: assessment.type,
      score: assessment.effectiveScore,
      movementQuality: assessment.movementQualityScore,
      stability: assessment.stabilityScore,
      symmetry: assessment.symmetryScore,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Type icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _typeIcon(assessment.type),
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assessment.type.label,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.formatDate(assessment.date, withYear: true),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                // ScoreInterpreter: type-specific headline
                const SizedBox(height: 2),
                Text(
                  interp.headline,
                  style: const TextStyle(
                    color: AppColors.textSoft,
                    fontSize: 10.5,
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (assessment.sessionName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    assessment.sessionName,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Mini score bars
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: canRunAssessments
                    ? () => _openOverrideDialog(context)
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (assessment.overrideScore != null) ...[
                      Tooltip(
                        message:
                            'معدّل يدويًا: ${assessment.overrideReason ?? ''}',
                        child: const Icon(
                          Icons.edit_note_rounded,
                          size: 14,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(width: 3),
                    ],
                    _ScoreBadge(score: assessment.effectiveScore),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _MiniBar(
                    value: assessment.movementQualityScore / 100,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 3),
                  _MiniBar(
                    value: assessment.stabilityScore / 100,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 3),
                  _MiniBar(
                    value: assessment.symmetryScore / 100,
                    color: AppColors.risk,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(AssessmentType t) {
    switch (t) {
      case AssessmentType.squat:
        return Icons.airline_seat_legroom_extra_rounded;
      case AssessmentType.singleLegBalance:
        return Icons.accessibility_new_rounded;
      case AssessmentType.jumpLanding:
        return Icons.moving_rounded;
      default:
        return Icons.sports_score_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Note Card
// ─────────────────────────────────────────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final CoachNote note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_rounded,
                color: AppColors.primary,
                size: 14,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  note.authorName,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.formatDate(note.date, withYear: true),
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note.text,
            style: const TextStyle(color: AppColors.textSoft, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Physical Notes Card
// ─────────────────────────────────────────────────────────────────────────────

class _PhysicalNotesCard extends StatelessWidget {
  const _PhysicalNotesCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSoft,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.destructive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(
        score.toStringAsFixed(0),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 20,
        height: 4,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: color.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wellness Summary Section — empty state until player logs Hooper/RPE
// ─────────────────────────────────────────────────────────────────────────────

class _WellnessSummarySection extends StatefulWidget {
  const _WellnessSummarySection({required this.playerId});
  final String playerId;

  @override
  State<_WellnessSummarySection> createState() =>
      _WellnessSummarySectionState();
}

class _WellnessSummarySectionState extends State<_WellnessSummarySection> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await PlayerMonitoringService.getPlayerWellnessSnapshot(
      widget.playerId,
    ).catchError((_) => null);
    if (mounted)
      setState(() {
        _data = d;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.success,
          ),
        ),
      );
    }

    final d = _data;
    final hs = d?['hooper_score'] as int?;
    // last_rpe deliberately not shown here — TrainingLoadSection right below
    // already shows RPE per day/session with full context.

    Color hColor = AppColors.muted;
    String hLabel = AppLocalizations.get('no_wellness_today');
    if (hs != null) {
      if (hs >= 17) {
        hColor = AppColors.destructive;
        hLabel = AppLocalizations.get('flag_high_fatigue');
      } else if (hs >= 13) {
        hColor = AppColors.warning;
        hLabel = AppLocalizations.get('flag_moderate_fatigue');
      } else {
        hColor = AppColors.success;
        hLabel = AppLocalizations.get('wellness_ready');
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                color: AppColors.success,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.get('daily_health_title'),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _CoachEntrySheet(playerId: widget.playerId),
                  );
                  _load();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.primary,
                    size: 17,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/club/wellness'),
                child: Text(
                  AppLocalizations.get('team_link_label'),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _WellnessMiniCard(
            label: 'Hooper',
            value: hs != null ? '$hs/28' : '—',
            sub: hLabel,
            color: hColor,
            icon: Icons.monitor_heart_rounded,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body Composition Section — latest values + 5 independent trend charts
// (weight/body-fat%/fat-mass/fat-free-mass/skinfold-sum) + tap-to-detail
// history list. Mirrors _WellnessSummarySection's load/setState pattern.
// ─────────────────────────────────────────────────────────────────────────────

class _BodyCompositionSection extends StatefulWidget {
  const _BodyCompositionSection({
    super.key,
    required this.playerId,
    required this.playerName,
  });
  final String playerId;
  final String playerName;

  @override
  State<_BodyCompositionSection> createState() =>
      _BodyCompositionSectionState();
}

class _BodyCompositionSectionState extends State<_BodyCompositionSection>
    with AutomaticKeepAliveClientMixin {
  List<BodyCompositionEntry> _history = [];
  BodyCompositionGoalStatus? _goalStatus;
  bool _loading = true;
  bool _expanded = false;
  bool _compareMode = false;
  final Set<String> _selectedForCompare = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      BodyCompositionService.getHistory(
        playerId: widget.playerId,
        limit: 20,
      ),
      BodyCompositionService.getGoal(playerId: widget.playerId),
    ]);
    final h = results[0] as List<BodyCompositionEntry>;
    final goalRes = results[1] as Map<String, dynamic>;
    final statusJson = goalRes['status'] as Map<String, dynamic>?;
    if (mounted) {
      setState(() {
        _history = h;
        _goalStatus = statusJson != null
            ? BodyCompositionGoalStatus.fromJson(statusJson)
            : null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.success,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.monitor_weight_rounded,
                  color: AppColors.warning,
                  size: 13,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _history.isNotEmpty
                      ? '${AppLocalizations.get('bc_title_short')} ${MetricFormatter.bodyFat(_history.first.bodyFatPercentage)}'
                      : AppLocalizations.get('body_composition_title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _history.isNotEmpty
                        ? AppColors.foreground
                        : AppColors.muted,
                    fontSize: _history.isNotEmpty ? 16 : 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_history.isEmpty)
            Text(
              AppLocalizations.get('bc_no_history'),
              style: TextStyle(
                color: AppColors.foreground.withOpacity(0.45),
                fontSize: 12.5,
              ),
            )
          else ...[
            _buildLatestRow(_history.first),
            if (_goalStatus != null) ...[
              const SizedBox(height: 10),
              _buildGoalChip(_goalStatus!),
            ],
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _expanded
                          ? AppLocalizations.get('close')
                          : AppLocalizations.get('view_details_btn'),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.primary,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              _buildMiniChart(
                AppLocalizations.get('bc_chart_body_fat'),
                (e) => e.bodyFatPercentage,
                AppColors.destructive,
                digits: 2,
              ),
              const SizedBox(height: 14),
              _buildMiniChart(
                AppLocalizations.get('bc_chart_weight'),
                (e) => e.weightKg,
                AppColors.primary,
              ),
              const SizedBox(height: 14),
              _buildMiniChart(
                AppLocalizations.get('bc_chart_fat_mass'),
                (e) => e.fatMassKg,
                AppColors.warning,
                digits: 2,
              ),
              const SizedBox(height: 14),
              _buildMiniChart(
                AppLocalizations.get('bc_chart_lean_mass'),
                (e) => e.fatFreeMassKg,
                AppColors.success,
                digits: 2,
              ),
              const SizedBox(height: 14),
              _buildMiniChart(
                AppLocalizations.get('bc_chart_skinfold_sum'),
                (e) => e.skinfoldSumMm,
                AppColors.coachAccent,
              ),
              const SizedBox(height: 16),
              if (_compareMode) ...[
                Text(
                  AppLocalizations.get('bc_compare_pick_two'),
                  style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              ..._history.take(5).map(
                (e) => _HistoryRow(
                  entry: e,
                  compareMode: _compareMode,
                  selected: _selectedForCompare.contains(e.id),
                  onSelect: () => setState(() {
                    if (_selectedForCompare.contains(e.id)) {
                      _selectedForCompare.remove(e.id);
                    } else {
                      if (_selectedForCompare.length >= 2) {
                        _selectedForCompare.remove(_selectedForCompare.first);
                      }
                      _selectedForCompare.add(e.id);
                    }
                  }),
                ),
              ),
              if (_compareMode && _selectedForCompare.length == 2) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final picked = _history
                          .where((e) => _selectedForCompare.contains(e.id))
                          .toList()
                        ..sort((a, b) => a.assessmentDate.compareTo(b.assessmentDate));
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BodyCompositionComparePage(
                            fromId: picked[0].id,
                            toId: picked[1].id,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.foreground,
                    ),
                    icon: const Icon(Icons.compare_arrows_rounded, size: 17),
                    label: Text(AppLocalizations.get('bc_action_compare')),
                  ),
                ),
              ],
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (canManageBodyComposition) ...[
                _bcActionButton(
                  icon: Icons.add_circle_outline_rounded,
                  label: AppLocalizations.get('bc_action_add'),
                  onTap: () async {
                    final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            BodyCompositionEntryScreen(playerId: widget.playerId),
                      ),
                    );
                    if (saved == true) _load();
                  },
                ),
                const SizedBox(width: 8),
              ],
              _bcActionButton(
                icon: Icons.flag_outlined,
                label: AppLocalizations.get('bc_action_goal'),
                onTap: () async {
                  final saved = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _GoalEditSheet(playerId: widget.playerId),
                  );
                  if (saved == true) _load();
                },
              ),
            ],
          ),
          if (_history.length >= 2 || _history.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (_history.length >= 2)
                  _bcActionButton(
                    icon: Icons.compare_arrows_rounded,
                    label: AppLocalizations.get('bc_action_compare'),
                    active: _compareMode,
                    onTap: () => setState(() {
                      _compareMode = !_compareMode;
                      _selectedForCompare.clear();
                      if (_compareMode) _expanded = true;
                    }),
                  ),
                if (_history.length >= 2 && _history.isNotEmpty)
                  const SizedBox(width: 8),
                if (_history.isNotEmpty)
                  _bcActionButton(
                    icon: Icons.print_outlined,
                    label: AppLocalizations.get('bc_action_print'),
                    onTap: () => Printing.layoutPdf(
                      onLayout: (format) =>
                          ReportService.instance.generateBodyCompositionReportPdf(
                            playerName: widget.playerName,
                            history: _history,
                            metadata: ReportMetadata(
                              team: 'الفريق',
                              season: 'الموسم النشط',
                              period:
                                  '${_history.last.assessmentDate} — ${_history.first.assessmentDate}',
                              issuedBy: currentUserName,
                            ),
                          ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bcActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final color = active ? AppColors.destructive : AppColors.foreground;
    return Expanded(
      child: SizedBox(
        height: 34,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 14, color: active ? AppColors.destructive : AppColors.muted),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: active ? AppColors.destructive.withOpacity(0.4) : AppColors.border, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _buildLatestRow(BodyCompositionEntry e) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _compactBodyMetric(
              AppLocalizations.get('bc_body_fat_percentage'),
              MetricFormatter.bodyFat(e.bodyFatPercentage),
              AppColors.destructive,
            ),
          ),
          Expanded(
            child: _compactBodyMetric(
              AppLocalizations.get('bc_weight_kg'),
              MetricFormatter.weight(e.weightKg),
              AppColors.primary,
            ),
          ),
          Expanded(
            child: _compactBodyMetric(
              AppLocalizations.get('bc_bmi'),
              MetricFormatter.bmi(e.bmi),
              AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactBodyMetric(String label, String value, Color color) => Column(
    children: [
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted, fontSize: 8.5),
      ),
    ],
  );

  Widget _buildGoalChip(BodyCompositionGoalStatus status) {
    final color = status.status == 'achieved' || status.status == 'on_track'
        ? AppColors.success
        : status.status == 'needs_follow_up'
        ? AppColors.warning
        : AppColors.destructive;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, color: color, size: 13),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${AppLocalizations.get('bc_vs_goal')}: ${AppLocalizations.get('bc_goal_status_${status.status}')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (status.daysRemaining != null) ...[
            const SizedBox(width: 6),
            Text(
              AppLocalizations.format('bc_goal_days_remaining', {
                'days': status.daysRemaining!,
              }),
              style: TextStyle(color: color.withOpacity(0.7), fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniChart(
    String label,
    double? Function(BodyCompositionEntry) selector,
    Color color, {
    int digits = 1,
  }) {
    final sorted = _history.reversed
        .toList(); // chronological order for the chart
    final spots = <FlSpot>[];
    for (var i = 0; i < sorted.length; i++) {
      final v = selector(sorted[i]);
      if (v != null) spots.add(FlSpot(i.toDouble(), v));
    }
    if (spots.length < 2) return const SizedBox.shrink();

    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b) * 0.95;
    final maxY = values.reduce((a, b) => a > b ? a : b) * 1.05;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.foreground.withOpacity(0.55),
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 70,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: color,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                      radius: idx == spots.length - 1 ? 4 : 2.5,
                      color: idx == spots.length - 1
                          ? color
                          : color.withOpacity(0.55),
                      strokeWidth: 0,
                      strokeColor: Colors.transparent,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [color.withOpacity(0.16), color.withOpacity(0.0)],
                    ),
                  ),
                ),
              ],
              titlesData: const FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: AppColors.surface2, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.foreground,
                  tooltipRoundedRadius: 8,
                  getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                    final idx = s.x.toInt();
                    final date = (idx >= 0 && idx < sorted.length)
                        ? sorted[idx].assessmentDate
                        : '';
                    return LineTooltipItem(
                      '${s.y.toStringAsFixed(digits)}\n$date',
                      TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    this.compareMode = false,
    this.selected = false,
    this.onSelect,
  });
  final BodyCompositionEntry entry;
  final bool compareMode;
  final bool selected;
  final VoidCallback? onSelect;

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.assessmentDate,
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _detailLine(
              AppLocalizations.get('bc_weight_kg'),
              MetricFormatter.weight(entry.weightKg),
              entry.delta?.weightKg,
            ),
            _detailLine(
              AppLocalizations.get('bc_body_fat_percentage'),
              MetricFormatter.bodyFat(entry.bodyFatPercentage),
              entry.delta?.bodyFatPercentage,
              deltaDigits: 2,
            ),
            _detailLine(
              AppLocalizations.get('bc_fat_mass_kg'),
              MetricFormatter.fatMass(entry.fatMassKg),
              entry.delta?.fatMassKg,
              deltaDigits: 2,
            ),
            _detailLine(
              AppLocalizations.get('bc_fat_free_mass_kg'),
              MetricFormatter.fatFreeMass(entry.fatFreeMassKg),
              entry.delta?.fatFreeMassKg,
              deltaDigits: 2,
            ),
            _detailLine(
              AppLocalizations.get('bc_skinfold_sum'),
              MetricFormatter.skinfold(entry.skinfoldSumMm),
              entry.delta?.skinfoldSumMm,
            ),
            if (entry.assessedBy != null) ...[
              const SizedBox(height: 8),
              Text(
                '${AppLocalizations.get('bc_assessed_by')}: ${entry.assessedBy}',
                style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.55),
                  fontSize: 12.5,
                ),
              ),
            ],
            if (entry.notes != null && entry.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${AppLocalizations.get('bc_notes')}: ${entry.notes}',
                style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.55),
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  Widget _detailLine(
    String label,
    String value,
    double? delta, {
    int deltaDigits = 1,
  }) {
    final deltaText = delta == null
        ? ''
        : (delta > 0
              ? ' (+${delta.toStringAsFixed(deltaDigits)})'
              : ' (${delta.toStringAsFixed(deltaDigits)})');
    final deltaColor = delta == null
        ? AppColors.muted
        : (delta > 0 ? AppColors.warning : AppColors.success);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.foreground.withOpacity(0.55),
              fontSize: 12.5,
            ),
          ),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (delta != null)
                Text(
                  deltaText,
                  style: TextStyle(
                    color: deltaColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: compareMode ? onSelect : () => _showDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (compareMode) ...[
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: Checkbox(
                        value: selected,
                        activeColor: AppColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (_) => onSelect?.call(),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      entry.assessmentDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.foreground.withOpacity(0.7),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  MetricFormatter.bodyFat(entry.bodyFatPercentage),
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.foreground.withOpacity(0.35),
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Goal Edit Sheet — set/update the single active body-composition goal for
// a player (upserted server-side, see goals/save.php).
// ─────────────────────────────────────────────────────────────────────────────

class _GoalEditSheet extends StatefulWidget {
  const _GoalEditSheet({required this.playerId});
  final String playerId;

  @override
  State<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends State<_GoalEditSheet> {
  final _targetWeightCtrl = TextEditingController();
  final _targetBodyFatCtrl = TextEditingController();
  final _minAcceptableCtrl = TextEditingController();
  final _maxAcceptableCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _targetDate;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BodyCompositionService.getGoal(playerId: widget.playerId);
    final goal = res['goal'] as Map<String, dynamic>?;
    if (goal != null) {
      _targetWeightCtrl.text = goal['target_weight_kg']?.toString() ?? '';
      _targetBodyFatCtrl.text =
          goal['target_body_fat_percentage']?.toString() ?? '';
      _minAcceptableCtrl.text =
          goal['min_acceptable_body_fat']?.toString() ?? '';
      _maxAcceptableCtrl.text =
          goal['max_acceptable_body_fat']?.toString() ?? '';
      _notesCtrl.text = goal['notes']?.toString() ?? '';
      if (goal['target_date'] != null)
        _targetDate = DateTime.tryParse(goal['target_date'].toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _targetWeightCtrl.dispose();
    _targetBodyFatCtrl.dispose();
    _minAcceptableCtrl.dispose();
    _maxAcceptableCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await BodyCompositionService.saveGoal(
      playerId: widget.playerId,
      targetWeightKg: double.tryParse(_targetWeightCtrl.text),
      targetBodyFatPercentage: double.tryParse(_targetBodyFatCtrl.text),
      minAcceptableBodyFat: double.tryParse(_minAcceptableCtrl.text),
      maxAcceptableBodyFat: double.tryParse(_maxAcceptableCtrl.text),
      targetDate: _targetDate?.toIso8601String().substring(0, 10),
      notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(res['success'] == true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.get('bc_goal_title'),
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sheetField(
                      _targetWeightCtrl,
                      AppLocalizations.get('bc_goal_target_weight'),
                    ),
                    const SizedBox(height: 10),
                    _sheetField(
                      _targetBodyFatCtrl,
                      AppLocalizations.get('bc_goal_target_body_fat'),
                    ),
                    const SizedBox(height: 10),
                    _sheetField(
                      _minAcceptableCtrl,
                      AppLocalizations.get('bc_goal_min_acceptable'),
                    ),
                    const SizedBox(height: 10),
                    _sheetField(
                      _maxAcceptableCtrl,
                      AppLocalizations.get('bc_goal_max_acceptable'),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _targetDate ??
                              DateTime.now().add(const Duration(days: 60)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 730),
                          ),
                        );
                        if (picked != null)
                          setState(() => _targetDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _targetDate != null
                                  ? _targetDate!.toIso8601String().substring(
                                      0,
                                      10,
                                    )
                                  : AppLocalizations.get('bc_goal_target_date'),
                            ),
                            const Icon(
                              Icons.calendar_today_rounded,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _sheetField(
                      _notesCtrl,
                      AppLocalizations.get('bc_notes'),
                      isNumeric: false,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.foreground,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(AppLocalizations.get('bc_goal_save')),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _sheetField(
    TextEditingController ctrl,
    String label, {
    bool isNumeric = true,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: isNumeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coach Entry Sheet — lets the coach record body metrics / RPE / Hooper on
// behalf of a roster player who may have no login account of their own.
// ─────────────────────────────────────────────────────────────────────────────

class _CoachEntrySheet extends StatefulWidget {
  const _CoachEntrySheet({required this.playerId});
  final String playerId;

  @override
  State<_CoachEntrySheet> createState() => _CoachEntrySheetState();
}

class _CoachEntrySheetState extends State<_CoachEntrySheet> {
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '60');
  int _rpe = 5;
  int _sleepQ = 4, _fatigue = 4, _stress = 4, _soreness = 4;
  bool _savingBody = false, _savingRpe = false, _savingHooper = false;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _fatCtrl.dispose();
    _waistCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _saveBody() async {
    final w = double.tryParse(_weightCtrl.text);
    final h = double.tryParse(_heightCtrl.text);
    final f = double.tryParse(_fatCtrl.text);
    if (w == null || h == null || f == null) {
      _snack(AppLocalizations.get('enter_weight_height_bodyfat'));
      return;
    }
    setState(() => _savingBody = true);
    final res = await PlayerMonitoringService.saveBodyMetrics(
      weightKg: w,
      heightCm: h,
      bodyFatPercent: f,
      waistCm: double.tryParse(_waistCtrl.text),
      playerId: widget.playerId,
    );
    if (!mounted) return;
    setState(() => _savingBody = false);
    _snack(
      res['success'] == true
          ? AppLocalizations.get('body_metrics_saved')
          : (res['error']?.toString() ?? AppLocalizations.get('error_generic')),
    );
  }

  Future<void> _saveRpe() async {
    final duration = int.tryParse(_durationCtrl.text);
    if (duration == null || duration < 1) {
      _snack(AppLocalizations.get('enter_exercise_duration_minutes'));
      return;
    }
    setState(() => _savingRpe = true);
    final res = await PlayerMonitoringService.saveRpe(
      rpeScore: _rpe,
      durationMinutes: duration,
      playerId: widget.playerId,
    );
    if (!mounted) return;
    setState(() => _savingRpe = false);
    _snack(
      res['success'] == true
          ? AppLocalizations.get('rpe_saved')
          : (res['error']?.toString() ?? AppLocalizations.get('error_generic')),
    );
  }

  Future<void> _saveHooper() async {
    setState(() => _savingHooper = true);
    final res = await PlayerMonitoringService.saveHooper(
      sleepQuality: _sleepQ,
      fatigue: _fatigue,
      stress: _stress,
      muscleSoreness: _soreness,
      playerId: widget.playerId,
    );
    if (!mounted) return;
    setState(() => _savingHooper = false);
    _snack(
      res['success'] == true
          ? AppLocalizations.get('hooper_saved')
          : (res['error']?.toString() ?? AppLocalizations.get('error_generic')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            28 + MediaQuery.of(context).viewInsets.bottom,
          ),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.get('record_player_data_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              AppLocalizations.get('record_on_behalf_note'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 20),

            _sectionTitle(AppLocalizations.get('body_metrics_section_title')),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _weightCtrl,
                    AppLocalizations.get('weight_kg_field_label'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(
                    _heightCtrl,
                    AppLocalizations.get('height_cm_field_label'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _fatCtrl,
                    AppLocalizations.get('body_fat_percent_field_label'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(
                    _waistCtrl,
                    AppLocalizations.get('waist_optional_field_label'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _saveButton(
              AppLocalizations.get('save_body_metrics_btn'),
              _savingBody,
              _saveBody,
            ),

            const SizedBox(height: 24),
            _sectionTitle(AppLocalizations.get('rpe_section_title')),
            _slider(
              AppLocalizations.get('intensity_label'),
              _rpe,
              0,
              10,
              (v) => setState(() => _rpe = v),
            ),
            const SizedBox(height: 8),
            _field(
              _durationCtrl,
              AppLocalizations.get('exercise_duration_minutes_field_label'),
            ),
            const SizedBox(height: 10),
            _saveButton(
              AppLocalizations.get('save_rpe_btn'),
              _savingRpe,
              _saveRpe,
            ),

            const SizedBox(height: 24),
            _sectionTitle(AppLocalizations.get('hooper_section_title')),
            _slider(
              AppLocalizations.get('sleep_quality_label'),
              _sleepQ,
              1,
              7,
              (v) => setState(() => _sleepQ = v),
            ),
            _slider(
              AppLocalizations.get('fatigue_label'),
              _fatigue,
              1,
              7,
              (v) => setState(() => _fatigue = v),
            ),
            _slider(
              AppLocalizations.get('stress_label'),
              _stress,
              1,
              7,
              (v) => setState(() => _stress = v),
            ),
            _slider(
              AppLocalizations.get('muscle_soreness_label'),
              _soreness,
              1,
              7,
              (v) => setState(() => _soreness = v),
            ),
            const SizedBox(height: 10),
            _saveButton(
              AppLocalizations.get('save_hooper_btn'),
              _savingHooper,
              _saveHooper,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      t,
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _field(TextEditingController ctrl, String hint) => TextField(
    controller: ctrl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _slider(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              activeColor: AppColors.primary,
              label: '$value',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 22,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveButton(String label, bool saving, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton(
        onPressed: saving ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _WellnessMiniCard extends StatelessWidget {
  const _WellnessMiniCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });
  final String label, value, sub;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 9),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ShowMoreButton extends StatelessWidget {
  const _ShowMoreButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        child: Text(
          '+ $count تقييم آخر',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trend Stat Chip
// ─────────────────────────────────────────────────────────────────────────────

class _TrendStatChip extends StatelessWidget {
  const _TrendStatChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 8.5),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coach Summary Card — Phase 3 AI-style synthesis card
// ─────────────────────────────────────────────────────────────────────────────

class _CoachSummaryCard extends StatefulWidget {
  const _CoachSummaryCard({
    required this.player,
    required this.history,
    required this.playerId,
  });
  final ClubPlayer player;
  final List<PlayerAssessment> history;
  final String playerId;

  @override
  State<_CoachSummaryCard> createState() => _CoachSummaryCardState();
}

class _CoachSummaryCardState extends State<_CoachSummaryCard> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAndCompute();
  }

  Future<void> _loadAndCompute() async {
    final d = await PlayerMonitoringService.getPlayerWellnessSnapshot(
      widget.playerId,
    ).catchError((_) => null);
    if (mounted)
      setState(() {
        _data = d;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    final d = _data;
    final hooper = d?['hooper_score'] as int?;
    final rpe = d?['last_rpe'] as int?;
    final latest = widget.history.isNotEmpty ? widget.history.first : null;
    final latestScore = latest?.overallScore;

    String? trend;
    if (widget.history.length >= 3) {
      final diff =
          widget.history[0].overallScore - widget.history[2].overallScore;
      if (diff > 5)
        trend = 'improving';
      else if (diff < -5)
        trend = 'declining';
      else
        trend = 'stable';
    }

    final readiness = ReadinessHelper.calculate(
      hooperScore: hooper,
      lastRpe: rpe,
      latestAssessmentScore: latestScore,
      trendDirection: trend,
    );

    final flags = RiskFlagsHelper.evaluate(
      hooperScore: hooper,
      lastRpe: rpe,
      latestAssessmentScore: latestScore,
      latestAssessmentType: latest?.type,
      stabilityScore: latest?.stabilityScore,
      movementScore: latest?.movementQualityScore,
      trend: trend,
      lastAssessmentDate: latest?.date,
    );

    final recs = SmartRecommendationService.generate(
      readiness: readiness,
      flags: flags,
      hooperScore: hooper,
      lastRpe: rpe,
      latestAssessmentScore: latestScore,
      latestAssessmentType: latest?.type.name,
      trend: trend,
    );

    final summary = CoachSummaryHelper.build(
      readiness: readiness,
      flags: flags,
      recommendations: recs,
      movementScore: widget.player.movementScore,
      stabilityScore: widget.player.stabilityScore,
      symmetryScore: widget.player.symmetryScore,
      trend: trend,
      hooperScore: hooper,
      lastRpe: rpe,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: title + AI badge + Report button
        Row(
          children: [
            const Icon(
              Icons.psychology_rounded,
              color: AppColors.primary,
              size: 15,
            ),
            const SizedBox(width: 5),
            Text(
              AppLocalizations.get('coach_summary_title').toUpperCase(),
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => openPlayerReport(
                context: context,
                player: widget.player,
                history: widget.history,
                wellnessData: d,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.maroon.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.maroon.withOpacity(0.20)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 11,
                      color: AppColors.maroon,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.get('view_report_btn'),
                      style: const TextStyle(
                        color: AppColors.maroon,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Main summary card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: summary.statusColor.withOpacity(0.20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status badge + score
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: summary.statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: summary.statusColor.withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: summary.statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          summary.statusLabel,
                          style: TextStyle(
                            color: summary.statusColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    summary.statusReason,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 10),

              // Main recommendation
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppColors.primary,
                    size: 14,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      summary.mainRecommendation,
                      style: const TextStyle(
                        color: AppColors.textSoft,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Chips row: strength | flag | next check
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _SummaryChip(
                    icon: Icons.star_outline_rounded,
                    label: summary.strength,
                    color: AppColors.success,
                  ),
                  if (summary.topFlag != null)
                    _SummaryChip(
                      icon: Icons.flag_outlined,
                      label: summary.topFlag!,
                      color: AppColors.warning,
                    ),
                  _SummaryChip(
                    icon: Icons.schedule_rounded,
                    label: summary.nextCheck,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.85),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Readiness + Risk Flags Section
// ─────────────────────────────────────────────────────────────────────────────

class _ReadinessAndFlagsSection extends StatefulWidget {
  const _ReadinessAndFlagsSection({
    super.key,
    required this.player,
  });
  final ClubPlayer player;

  @override
  State<_ReadinessAndFlagsSection> createState() =>
      _ReadinessAndFlagsSectionState();
}

class _ReadinessAndFlagsSectionState extends State<_ReadinessAndFlagsSection>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _decision;
  bool _loading = true;
  bool _expanded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final results = await Future.wait<Object?>([
      PlayerMonitoringService.getPlayerWellnessSnapshot(
        widget.player.id,
      ).catchError((_) => null),
      ApiService.getDailyReadiness(date),
    ]);
    final d = results[0] as Map<String, dynamic>?;
    final readinessResponse = results[1] as Map<String, dynamic>;
    Map<String, dynamic>? decision;
    final players = readinessResponse['players'] as List?;
    if (players != null) {
      for (final item in players) {
        if (item is! Map ||
            item['player_id']?.toString() != widget.player.id) {
          continue;
        }
        final rawDecision = item['decision'];
        if (rawDecision is Map) {
          decision = Map<String, dynamic>.from(rawDecision);
        }
        break;
      }
    }
    if (mounted)
      setState(() {
        _data = d;
        _decision = decision;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Container(
        height: 72,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    final d = _data;
    final hooper = _nullableJsonInt(d?['hooper_score']);
    final rpe = _nullableJsonInt(d?['last_rpe']);

    final readiness = ReadinessHelper.calculate(
      hooperScore: hooper,
      lastRpe: rpe,
      latestAssessmentScore: null,
      trendDirection: null,
    );

    final flags = RiskFlagsHelper.evaluate(
      hooperScore: hooper,
      lastRpe: rpe,
      latestAssessmentScore: null,
      latestAssessmentType: null,
      stabilityScore: null,
      movementScore: null,
      trend: null,
      lastAssessmentDate: null,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReadinessCard(
            readiness,
            hooper: hooper,
            rpe: rpe,
            alertsCount: flags.length,
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  color: AppColors.warning,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.get('risk_flags_title'),
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (flags.isEmpty)
              Text(
                AppLocalizations.get('risk_flags_empty'),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                ),
              )
            else
              ...flags
                  .take(3)
                  .map(
                    (flag) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FlagCard(flag: flag),
                    ),
                  ),
            const SizedBox(height: 8),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 10),
            _buildDailyHealth(_data),
          ],
        ],
      ),
    );
  }

  Widget _buildReadinessCard(
    ReadinessResult readiness, {
    required int? hooper,
    required int? rpe,
    required int alertsCount,
  }) {
    final player = widget.player;
    final allowedDuration = _decision?['allowed_duration_minutes'];
    final restrictions = _decision?['restrictions']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: readiness.color.withOpacity(0.10),
                  border: Border.all(
                    color: readiness.color.withOpacity(0.40),
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${readiness.score}',
                  style: TextStyle(
                    color: readiness.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppLocalizations.get('readiness_card_title'),
                          style: const TextStyle(
                            color: AppColors.foreground,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          readiness.statusLabel,
                          style: TextStyle(
                            color: readiness.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      readiness.recommendation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'H ${hooper ?? '—'} · RPE ${rpe ?? '—'}',
                    style: const TextStyle(
                      color: AppColors.textSoft,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${AppLocalizations.get('risk_flags_title')}: $alertsCount',
                    style: TextStyle(
                      color: alertsCount > 0
                          ? AppColors.warning
                          : AppColors.success,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.muted,
                size: 18,
              ),
            ],
          ),
        ),
        if (_expanded &&
            (allowedDuration != null ||
              restrictions?.isNotEmpty == true ||
              (canViewMedicalNotes &&
                  player.injuryNotes?.isNotEmpty == true) ||
              player.expectedReturnDate != null ||
              player.unavailableReason?.isNotEmpty == true)) ...[
            const SizedBox(height: 10),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 8),
            if (allowedDuration != null)
              Text(
                '${AppLocalizations.get('allowed_duration_minutes')}: '
                '$allowedDuration',
                style: const TextStyle(
                  color: AppColors.textSoft,
                  fontSize: 11,
                ),
              ),
            if (restrictions?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  '${AppLocalizations.get('restrictions')}: $restrictions',
                  style: const TextStyle(
                    color: AppColors.textSoft,
                    fontSize: 11,
                  ),
                ),
              ),
            if (canViewMedicalNotes &&
                player.injuryNotes?.isNotEmpty == true)
              Padding(
                padding: EdgeInsets.only(
                  top: allowedDuration != null ||
                          restrictions?.isNotEmpty == true
                      ? 5
                      : 0,
                ),
                child: Text(
                  player.injuryNotes!,
                  style: const TextStyle(
                    color: AppColors.textSoft,
                    fontSize: 11,
                  ),
                ),
              ),
            if (player.expectedReturnDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  '${AppLocalizations.get('expected_return_label')}: '
                  '${player.expectedReturnDate!.day}/${player.expectedReturnDate!.month}/${player.expectedReturnDate!.year}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                  ),
                ),
              ),
            if (player.unavailableReason?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  '${AppLocalizations.get('absence_reason_label')}: '
                  '${player.unavailableReason}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                  ),
                ),
              ),
          ],
        ],
      );
  }

  Widget _buildDailyHealth(Map<String, dynamic>? data) {
    final hooper = _nullableJsonInt(data?['hooper_score']);
    Color color = AppColors.muted;
    String label = AppLocalizations.get('no_wellness_today');
    if (hooper != null) {
      if (hooper >= 17) {
        color = AppColors.destructive;
        label = AppLocalizations.get('flag_high_fatigue');
      } else if (hooper >= 13) {
        color = AppColors.warning;
        label = AppLocalizations.get('flag_moderate_fatigue');
      } else {
        color = AppColors.success;
        label = AppLocalizations.get('wellness_ready');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.favorite_rounded,
              color: AppColors.success,
              size: 15,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                AppLocalizations.get('daily_health_title'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: AppLocalizations.get('add'),
              onPressed: () async {
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) =>
                      _CoachEntrySheet(playerId: widget.player.id),
                );
                await _load();
              },
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/club/wellness'),
              child: Text(
                AppLocalizations.get('team_link_label'),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Icon(Icons.monitor_heart_rounded, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              hooper != null ? '$hooper/28' : '—',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSoft,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Risk Flag Card
// ─────────────────────────────────────────────────────────────────────────────

class _FlagCard extends StatelessWidget {
  const _FlagCard({required this.flag});
  final RiskFlag flag;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: flag.color.withOpacity(0.04),
          border: Border(left: BorderSide(color: flag.color, width: 3)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: flag.color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(flag.icon, color: flag.color, size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          flag.title,
                          style: TextStyle(
                            color: flag.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: flag.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          flag.priorityLabel,
                          style: TextStyle(
                            color: flag.color,
                            fontWeight: FontWeight.w900,
                            fontSize: 8.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    flag.reason,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    flag.recommendation,
                    style: const TextStyle(
                      color: AppColors.textSoft,
                      fontSize: 11,
                    ),
                    maxLines: 2,
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
