import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../models/club_models.dart';
import '../../models/player_profile_model.dart';
import '../../models/assessment_result_model.dart';
import '../../services/club_service.dart';
import '../../screens/physical_assessment/assessment_camera_page.dart';
import 'club_widgets.dart';
import 'player_management.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Club Player Profile Page
// ─────────────────────────────────────────────────────────────────────────────

class ClubPlayerProfilePage extends StatefulWidget {
  const ClubPlayerProfilePage({super.key, required this.playerId});
  final String playerId;

  @override
  State<ClubPlayerProfilePage> createState() => _ClubPlayerProfilePageState();
}

class _ClubPlayerProfilePageState extends State<ClubPlayerProfilePage> {
  ClubPlayer? _player;
  List<PlayerAssessment> _history = [];
  List<CoachNote> _notes = [];
  List<ClubTeam> _teams = [];
  bool _loading = true;
  bool _addingNote = false;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final start = DateTime.now();
    setState(() => _loading = true);
    try {
      final player = await ClubService().getPlayer(widget.playerId);
      if (!mounted) return;

      // Update UI with player first - show skeleton
      setState(() => _player = player);

      if (player != null) {
        // Load history, notes, and teams in parallel
        final results = await Future.wait([
          ClubService().getAssessmentsForPlayer(player.id),
          ClubService().getNotesForPlayer(player.id),
          ClubService().getTeams(),
        ]);
        if (!mounted) return;
        setState(() {
          _history = results[0] as List<PlayerAssessment>;
          _notes = results[1] as List<CoachNote>;
          _teams = results[2] as List<ClubTeam>;
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }

      final ms = DateTime.now().difference(start).inMilliseconds;
      debugPrint('[PlayerProfile] Loaded in ${ms}ms');
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      debugPrint('[PlayerProfile] Load error: $e');
    }
  }

  Future<void> _addNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty || _player == null) return;
    setState(() => _addingNote = true);
    await ClubService().addNote(CoachNote(
      id: '',
      playerId: _player!.id,
      authorName: 'Coach',
      text: text,
      date: DateTime.now(),
    ));
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
              const Icon(Icons.person_off_rounded,
                  color: AppColors.muted, size: 48),
              const SizedBox(height: 12),
              const Text('Player not found',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
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
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    _buildPlayerCard(),
                    const SizedBox(height: 20),
                    if (_player!.latestScore != null) ...[
                      _buildScores(),
                      const SizedBox(height: 20),
                    ],
                    _buildAssessmentAction(),
                    const SizedBox(height: 20),
                    if (_history.isNotEmpty) ...[
                      ClubSectionLabel('Assessment History (${_history.length})'),
                      ..._history.map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AssessmentCard(assessment: a),
                          )),
                      const SizedBox(height: 10),
                    ],
                    ClubSectionLabel('Coach Notes'),
                    _buildNoteInput(),
                    const SizedBox(height: 10),
                    if (_notes.isEmpty)
                      _emptyNotes()
                    else
                      ..._notes.map((n) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _NoteCard(note: n),
                          )),
                    if (_player!.physicalNotes != null &&
                        _player!.physicalNotes!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ClubSectionLabel('Physical Notes'),
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
          20, MediaQuery.of(context).padding.top > 0 ? 16 : 16, 20, 14),
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
              child: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _player!.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                Text(
                  '#${_player!.number}  ·  ${_player!.position}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    AddEditPlayerPage(player: _player!, teams: _teams),
              ));
              _load();
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppColors.primary.withOpacity(0.35)),
              ),
              child: const Icon(Icons.edit_rounded,
                  color: AppColors.primary, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Player Card ─────────────────────────────────────────────────────────────

  Widget _buildPlayerCard() {
    final p = _player!;
    final statusColor = _statusColor(p.status);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff1A0A10), Color(0xff0E0810)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.20)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primarySoft,
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.45), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.20),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    p.initials,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.fullName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        // Jersey number badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.gold.withOpacity(0.30)),
                          ),
                          child: Text(
                            '#${p.number}',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.position,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.55), fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: statusColor.withOpacity(0.30)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: statusColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            p.status.label,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          // Bio stats row
          Row(
            children: [
              _BioStat(
                  label: 'Age',
                  value: p.age > 0 ? '${p.age} yr' : '—'),
              _BioStatDivider(),
              _BioStat(
                  label: 'Height',
                  value: p.height != null
                      ? '${p.height!.toStringAsFixed(0)} cm'
                      : '—'),
              _BioStatDivider(),
              _BioStat(
                  label: 'Weight',
                  value: p.weight != null
                      ? '${p.weight!.toStringAsFixed(0)} kg'
                      : '—'),
              _BioStatDivider(),
              _BioStat(
                  label: 'Foot',
                  value: _capitalize(p.dominantFoot)),
            ],
          ),
          if (p.teamName != null && p.teamName!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.groups_rounded,
                    color: AppColors.muted, size: 14),
                const SizedBox(width: 6),
                Text(
                  p.teamName!,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55), fontSize: 12),
                ),
                if (p.nationality.isNotEmpty) ...[
                  Text('  ·  ',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.25),
                          fontSize: 12)),
                  Text(
                    p.nationality,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.55), fontSize: 12),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Scores ──────────────────────────────────────────────────────────────────

  Widget _buildScores() {
    final p = _player!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClubSectionLabel('Performance Scores'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            ClubScoreRing(
              score: p.movementScore ?? 0,
              size: 72,
              label: 'Movement',
            ),
            ClubScoreRing(
              score: p.stabilityScore ?? 0,
              size: 72,
              label: 'Stability',
            ),
            ClubScoreRing(
              score: p.symmetryScore ?? 0,
              size: 72,
              label: 'Symmetry',
            ),
            ClubScoreRing(
              score: p.latestScore ?? 0,
              size: 72,
              label: 'Overall',
            ),
          ],
        ),
      ],
    );
  }

  // ── Assessment Action ────────────────────────────────────────────────────────

  Widget _buildAssessmentAction() {
    final latest = _history.isNotEmpty ? _history.first : null;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.sports_score_rounded,
                        color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Latest Assessment',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          latest != null
                              ? '${_testLabel(latest.type)}  ·  ${_formatDate(latest.date)}'
                              : 'No assessments yet',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.45), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (latest != null)
                    _ScoreBadge(score: latest.overallScore),
                ],
              ),
              if (latest != null && latest.detectedIssues.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 10),
                ...latest.detectedIssues.take(2).map(
                      (issue) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: AppColors.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                issue,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.70),
                                  fontSize: 12,
                                ),
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
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () => _startAssessment(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_rounded, color: Colors.black, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Start AI Assessment',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _startAssessment() async {
    if (_player == null) return;
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
        testType: AssessmentTestType.squat,
      ),
    );
    if (result != null) {
      _load();
    }
  }

  // ── Note Input ───────────────────────────────────────────────────────────────

  Widget _buildNoteInput() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _noteCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Add a coach note…',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.30), fontSize: 13),
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
                color: _addingNote
                    ? AppColors.primarySoft
                    : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: _addingNote
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 16),
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
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.notes_rounded, color: AppColors.muted, size: 18),
          const SizedBox(width: 10),
          Text(
            'No coach notes yet',
            style:
                TextStyle(color: Colors.white.withOpacity(0.40), fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Color _statusColor(PlayerStatus s) {
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

  String _testLabel(AssessmentType t) {
    switch (t) {
      case AssessmentType.squat:
        return 'Squat';
      case AssessmentType.singleLegBalance:
        return 'Single Leg Balance';
      case AssessmentType.jumpLanding:
        return 'Jump Landing';
      case AssessmentType.lunge:
        return 'Lunge';
      case AssessmentType.custom:
        return 'Custom';
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// Assessment Card
// ─────────────────────────────────────────────────────────────────────────────

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.assessment});
  final PlayerAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(assessment.date),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.40), fontSize: 11),
                ),
                if (assessment.sessionName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    assessment.sessionName,
                    style: TextStyle(
                        color: AppColors.primary.withOpacity(0.70),
                        fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          // Mini score bars
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _ScoreBadge(score: assessment.overallScore),
              const SizedBox(height: 4),
              Row(
                children: [
                  _MiniBar(
                      value: assessment.movementQualityScore / 100,
                      color: AppColors.primary),
                  const SizedBox(width: 3),
                  _MiniBar(
                      value: assessment.stabilityScore / 100,
                      color: AppColors.gold),
                  const SizedBox(width: 3),
                  _MiniBar(
                      value: assessment.symmetryScore / 100,
                      color: const Color(0xff7B68EE)),
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

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
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
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded,
                  color: AppColors.primary, size: 14),
              const SizedBox(width: 6),
              Text(
                note.authorName,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(note.date),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note.text,
            style: TextStyle(
                color: Colors.white.withOpacity(0.80), fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
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
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style:
            TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13, height: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _BioStat extends StatelessWidget {
  const _BioStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.40), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _BioStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
        width: 1, height: 28, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 4));
  }
}

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
