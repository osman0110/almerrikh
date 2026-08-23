import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../models/ai_plan_models.dart';

class AIPlanPreviewScreen extends StatefulWidget {
  const AIPlanPreviewScreen({
    super.key,
    required this.planId,
    required this.planTitle,
  });
  final String planId;
  final String planTitle;

  @override
  State<AIPlanPreviewScreen> createState() => _AIPlanPreviewScreenState();
}

class _AIPlanPreviewScreenState extends State<AIPlanPreviewScreen> {
  AIPlanDetail? _plan;
  bool _loading = true;
  bool _error   = false;
  int  _tab     = 0; // active week tab

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = false; });
    final plan = await ApiService.getPlayerPlanDetail(widget.planId);
    if (!mounted) return;
    setState(() {
      _plan    = plan;
      _loading = false;
      _error   = plan == null;
    });
  }

  void _startSession(AIPlanSession s) async {
    // Fetch session detail to get exercises, then navigate to the existing flow
    final detail = await ApiService.getSessionDetail(s.id);
    if (!mounted) return;
    if (detail == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not load session details.'),
        backgroundColor: AppColors.destructive,
      ));
      return;
    }

    if (detail.needsPreCheck) {
      Navigator.of(context).pushNamed('/player/session/pre-check', arguments: detail);
    } else {
      Navigator.of(context).pushNamed('/player/session/run', arguments: detail);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.foreground.withOpacity(0.70), size: 18),
          onPressed: () =>
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/player', (_) => false),
        ),
        title: Text(widget.planTitle,
            style: const TextStyle(
                color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16),
            overflow: TextOverflow.ellipsis),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: AppColors.foreground.withOpacity(0.70), size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _error || _plan == null
                ? _ErrorState(onRetry: _load)
                : _PlanBody(
                    plan:         _plan!,
                    activeTab:    _tab,
                    onTabChanged: (t) => setState(() => _tab = t),
                    onStartSession: _startSession,
                  ),
      ),
    );
  }
}

// ── Plan body ─────────────────────────────────────────────────────────────────

class _PlanBody extends StatelessWidget {
  const _PlanBody({
    required this.plan,
    required this.activeTab,
    required this.onTabChanged,
    required this.onStartSession,
  });
  final AIPlanDetail plan;
  final int activeTab;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<AIPlanSession> onStartSession;

  @override
  Widget build(BuildContext context) {
    final p = plan.plan;
    return Column(children: [
      // ── Header card ────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.primary.withOpacity(0.20)),
          ),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(p.title,
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${p.numWeeks ?? plan.weeks.length} weeks  ·  '
                  '${plan.totalSessions} sessions  ·  '
                  '${p.goal}',
                  style: TextStyle(
                      color: AppColors.foreground.withOpacity(0.45), fontSize: 12),
                ),
              ]),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${p.completedCount}/${plan.totalSessions}',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 18)),
                Text('done',
                    style: TextStyle(
                        color: AppColors.foreground.withOpacity(0.35), fontSize: 10)),
              ],
            ),
          ]),
        ),
      ),

      // ── Week tabs ──────────────────────────────────────────────────────
      if (plan.weeks.length > 1) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: plan.weeks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final week = plan.weeks[i];
              final active = i == activeTab;
              return GestureDetector(
                onTap: () => onTabChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                  ),
                  child: Row(children: [
                    Text('Week ${week.week}',
                        style: TextStyle(
                          color: active
                              ? AppColors.foreground
                              : AppColors.foreground.withOpacity(0.55),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        )),
                    if (week.isComplete) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle_rounded,
                          size: 13,
                          color: active
                              ? AppColors.foreground
                              : AppColors.success),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      ],
      const SizedBox(height: 12),

      // ── Sessions list ──────────────────────────────────────────────────
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          children: [
            if (activeTab < plan.weeks.length)
              ..._buildWeekSessions(plan.weeks[activeTab], context),

            // Recovery & progression notes
            if (p.recoveryNotes?.isNotEmpty == true ||
                p.progressionRules?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              if (p.recoveryNotes?.isNotEmpty == true)
                _NoteCard(
                  icon: Icons.self_improvement_rounded,
                  label: 'Recovery',
                  text: p.recoveryNotes!,
                  color: AppColors.success,
                ),
              if (p.progressionRules?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _NoteCard(
                  icon: Icons.trending_up_rounded,
                  label: 'Progression',
                  text: p.progressionRules!,
                  color: AppColors.primary,
                ),
              ],
            ],
          ],
        ),
      ),
    ]);
  }

  List<Widget> _buildWeekSessions(AIPlanWeek week, BuildContext context) =>
      week.sessions.asMap().entries.map((entry) {
        final s = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SessionCard(
            session:     s,
            onStart:     () => onStartSession(s),
          ),
        );
      }).toList();
}

// ── Session card ──────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onStart});
  final AIPlanSession session;
  final VoidCallback onStart;

  Color get _intensityColor {
    switch (session.intensity) {
      case 'high':   return AppColors.destructive;
      case 'medium': return AppColors.warning;
      default:       return AppColors.success;
    }
  }

  String get _btnLabel {
    if (session.isCompleted) return 'Completed ✓';
    if (session.isStarted)   return 'Continue';
    if (session.isMissed)    return 'Missed';
    return 'Start Session';
  }

  Color get _btnColor {
    if (session.isCompleted) return AppColors.success;
    if (session.isMissed)    return Colors.grey;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: session.isCompleted
              ? AppColors.primary.withOpacity(0.07)
              : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: session.isCompleted
                ? AppColors.primary.withOpacity(0.25)
                : AppColors.border,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(children: [
              Expanded(
                child: Text(session.title,
                    style: TextStyle(
                        color: session.isCompleted
                            ? AppColors.foreground.withOpacity(0.55)
                            : AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ),
              // Intensity dot
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                    color: _intensityColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(session.intensity,
                  style: TextStyle(
                      color: _intensityColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded,
                  size: 12, color: AppColors.foreground.withOpacity(0.35)),
              const SizedBox(width: 4),
              Text(session.sessionDate,
                  style: TextStyle(
                      color: AppColors.foreground.withOpacity(0.45), fontSize: 12)),
              const SizedBox(width: 10),
              Icon(Icons.timer_outlined,
                  size: 12, color: AppColors.foreground.withOpacity(0.35)),
              const SizedBox(width: 4),
              Text('${session.durationMinutes}min',
                  style: TextStyle(
                      color: AppColors.foreground.withOpacity(0.45), fontSize: 12)),
              const SizedBox(width: 10),
              Icon(Icons.sports_rounded,
                  size: 12, color: AppColors.foreground.withOpacity(0.35)),
              const SizedBox(width: 4),
              Text(session.objectiveLabel,
                  style: TextStyle(
                      color: AppColors.foreground.withOpacity(0.45), fontSize: 12)),
            ]),
          ),
          if (session.exerciseCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Text('${session.exerciseCount} exercises',
                  style: TextStyle(
                      color: AppColors.foreground.withOpacity(0.30), fontSize: 11)),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                onPressed: session.isCompleted || session.isMissed
                    ? null
                    : onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _btnColor,
                  disabledBackgroundColor: _btnColor.withOpacity(0.20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: Text(_btnLabel,
                    style: TextStyle(
                      color: session.isCompleted || session.isMissed
                          ? _btnColor.withOpacity(0.60)
                          : AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
              ),
            ),
          ),
        ]),
      );
}

// ── Note card ─────────────────────────────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String label, text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.20)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          Text(text,
              style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.55), fontSize: 13)),
        ]),
      );
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.destructive, size: 48),
            const SizedBox(height: 16),
            const Text('Could not load plan',
                style: TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 17)),
            const SizedBox(height: 8),
            Text('Check your connection and try again.',
                style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.45), fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.foreground,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Retry',
                  style: TextStyle(color: AppColors.foreground)),
            ),
          ]),
        ),
      );
}
