import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/assessment_result_model.dart';
import '../../models/club_models.dart';
import '../../models/player_profile_model.dart';
import '../../services/club_service.dart';
import '../physical_assessment/assessment_camera_page.dart';
import '../physical_assessment/web_pose_setup_screen.dart'
    if (dart.library.io) '../physical_assessment/web_pose_setup_screen_stub.dart';

class SessionQueuePage extends StatefulWidget {
  const SessionQueuePage({
    super.key,
    required this.sessionId,
    required this.players,
    required this.assessmentType,
  });

  final String sessionId;
  final List<ClubPlayer> players;
  final AssessmentTestType assessmentType;

  @override
  State<SessionQueuePage> createState() => _SessionQueuePageState();
}

class _SessionQueuePageState extends State<SessionQueuePage> {
  late List<ClubPlayer> _allPlayers;
  Set<String> _completedIds = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _allPlayers = List.from(widget.players);
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await ClubService().getSession(widget.sessionId);
    if (session != null && mounted) {
      setState(() => _completedIds = Set.from(session.completedPlayerIds));
    }
  }

  List<ClubPlayer> get _pending =>
      _allPlayers.where((p) => !_completedIds.contains(p.id)).toList();

  List<ClubPlayer> get _done =>
      _allPlayers.where((p) => _completedIds.contains(p.id)).toList();

  Future<void> _startPlayer(ClubPlayer p) async {
    final profile = PlayerProfile(
      id: p.id,
      name: p.fullName,
      heightCm: p.height?.toInt(),
      weightKg: p.weight?.toInt(),
      dominantFoot: p.dominantFoot,
      position: p.position,
      team: p.teamName,
    );

    setState(() => _loading = true);
    final args = AssessmentCameraArguments(
      player: profile,
      testType: widget.assessmentType,
      sessionId: widget.sessionId,
    );
    if (kIsWeb) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebPoseSetupScreen(cameraArgs: args),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AssessmentCameraPage(
          player: args.player,
          testType: args.testType,
          sessionId: args.sessionId,
          onNextPlayer: () => Navigator.of(context).pop(),
        ),
      ));
    }
    await _loadSession();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final done = _done;
    final total = _allPlayers.length;
    final pct = total == 0 ? 0.0 : done.length / total;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(done.length, total),
            _buildProgressBar(pct, done.length, total),
            Expanded(
              child: pending.isEmpty
                  ? _buildAllDone(done.length)
                  : _buildQueue(pending, done),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int done, int total) {
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
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface2, shape: BoxShape.circle,
                border: Border.all(color: AppColors.border)),
              child: const Icon(Icons.arrow_back_rounded, color: AppColors.foreground, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.assessmentType.displayName,
                    style: const TextStyle(
                        color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 16)),
                Text(AppLocalizations.format('queue_mode_status', {'done': done, 'total': total}),
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.coachAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.coachAccent.withOpacity(0.30)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.queue_rounded, color: AppColors.coachAccent, size: 14),
              const SizedBox(width: 5),
              Text(AppLocalizations.format('remaining_count', {'count': _pending.length}),
                  style: const TextStyle(
                      color: AppColors.coachAccent, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(double pct, int done, int total) {
    final color = pct == 1.0 ? AppColors.success : AppColors.coachAccent;
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        children: [
          Stack(children: [
            Container(height: 5,
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(99))),
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(height: 5,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(99))),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildQueue(List<ClubPlayer> pending, List<ClubPlayer> done) {
    final current = pending.first;
    final next = pending.length > 1 ? pending[1] : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        // Current player card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.coachAccent.withOpacity(0.15),
                AppColors.coachAccent.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.coachAccent.withOpacity(0.35), width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.coachAccent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(AppLocalizations.get('current_turn_label'),
                    style: const TextStyle(
                        color: AppColors.coachAccent,
                        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 20),
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.coachAccent.withOpacity(0.18),
                  border: Border.all(color: AppColors.coachAccent.withOpacity(0.5), width: 2),
                ),
                child: Center(
                  child: Text(current.initials,
                      style: const TextStyle(
                          color: AppColors.coachAccent,
                          fontWeight: FontWeight.w900, fontSize: 26)),
                ),
              ),
              const SizedBox(height: 14),
              Text(current.fullName,
                  style: const TextStyle(
                      color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 22),
                  textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('#${current.number}  ·  ${current.position}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _loading ? null : () => _startPlayer(current),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.coachAccent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.coachAccent.withOpacity(0.35),
                          blurRadius: 16, offset: const Offset(0, 5))
                    ],
                  ),
                  child: _loading
                      ? const Center(child: SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.foreground)))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.videocam_rounded, color: AppColors.foreground, size: 20),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.get('start_assessment_btn'),
                              style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                        ]),
                ),
              ),
            ],
          ),
        ),

        // Next player preview
        if (next != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface2,
                  border: Border.all(color: AppColors.border),
                ),
                child: Center(
                  child: Text(next.initials,
                      style: const TextStyle(
                          color: AppColors.muted, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLocalizations.get('next_player_label'), style: const TextStyle(
                      color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)),
                  Text(next.fullName, style: const TextStyle(
                      color: AppColors.textSoft, fontWeight: FontWeight.w700, fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (pending.length > 2)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(AppLocalizations.format('after_them_count', {'count': pending.length - 2}),
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ),
            ]),
          ),
        ],

        // Completed players
        if (done.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(width: 3, height: 12,
                  decoration: BoxDecoration(
                      color: AppColors.success, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 7),
              Text(AppLocalizations.format('completed_section', {'count': done.length}),
                  style: const TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 11)),
            ]),
          ),
          ...done.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.18)),
            ),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success.withOpacity(0.12),
                ),
                child: const Icon(Icons.check_rounded, color: AppColors.success, size: 15),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(p.fullName,
                  style: const TextStyle(
                      color: AppColors.textSoft, fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('#${p.number}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          )),
        ],
      ],
    );
  }

  Widget _buildAllDone(int count) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withOpacity(0.12),
                border: Border.all(color: AppColors.success.withOpacity(0.4), width: 2),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 46),
            ),
            const SizedBox(height: 20),
            Text(AppLocalizations.get('all_done_title'),
                style: const TextStyle(
                    color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 24)),
            const SizedBox(height: 8),
            Text(AppLocalizations.format('players_assessed_success', {'count': count}),
                style: const TextStyle(color: AppColors.muted, fontSize: 14)),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.coachAccent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.coachAccent.withOpacity(0.3),
                        blurRadius: 12, offset: const Offset(0, 4))
                  ],
                ),
                child: Text(AppLocalizations.get('back_to_session'),
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
