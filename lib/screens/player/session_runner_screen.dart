import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/session_models.dart';

class SessionRunnerScreen extends StatefulWidget {
  const SessionRunnerScreen({super.key, required this.session});
  final PlayerSessionData session;

  @override
  State<SessionRunnerScreen> createState() => _SessionRunnerScreenState();
}

class _SessionRunnerScreenState extends State<SessionRunnerScreen> {
  bool _starting   = true;
  bool _startError = false;
  String? _startErrMsg;
  final Set<int> _done = {};
  int _hoooperScore = 0;
  int _preRpe       = 0;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  Future<void> _startSession() async {
    setState(() { _starting = true; _startError = false; });
    final res = await ApiService.startSession(widget.session.id);
    if (!mounted) return;
    if (res.containsKey('error')) {
      final code = res['code'] as String?;
      if (code == 'wellness_required') {
        // Should not reach here normally, but handle gracefully
        Navigator.of(context).pushReplacementNamed(
          '/player/session/pre-check',
          arguments: widget.session,
        );
        return;
      }
      setState(() {
        _starting    = false;
        _startError  = true;
        _startErrMsg = res['error'] as String?;
      });
      return;
    }
    setState(() => _starting = false);
  }

  void _toggleDone(int index) {
    setState(() {
      if (_done.contains(index)) _done.remove(index);
      else _done.add(index);
    });
  }

  void _finishSession() {
    Navigator.of(context).pushReplacementNamed(
      '/player/session/post-feedback',
      arguments: {
        'session_id':       widget.session.id,
        'session_title':    widget.session.title,
        'duration_minutes': widget.session.durationMinutes,
        if (_hoooperScore > 0) 'hooper_score': _hoooperScore,
        if (_preRpe > 0) 'pre_rpe': _preRpe,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_starting) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(AppLocalizations.get('session_starting'),
                style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.60), fontSize: 14)),
          ]),
        ),
      );
    }

    if (_startError) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.destructive, size: 48),
              const SizedBox(height: 16),
              Text(
                _startErrMsg ?? AppLocalizations.get('session_start_failed'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.foreground, fontSize: 15),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _startSession,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.foreground,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(AppLocalizations.get('retry_btn'),
                    style: const TextStyle(color: AppColors.foreground)),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppLocalizations.get('back_btn'),
                    style:
                        TextStyle(color: AppColors.foreground.withOpacity(0.45))),
              ),
            ]),
          ),
        ),
      );
    }

    final exercises = widget.session.exercises;
    final doneCount = _done.length;
    final total     = exercises.isEmpty ? 1 : exercises.length;
    final progress  = exercises.isEmpty ? 1.0 : doneCount / total;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.foreground.withOpacity(0.70), size: 18),
          onPressed: () => _confirmExit(context),
        ),
        title: Text(widget.session.title,
            style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 17),
            overflow: TextOverflow.ellipsis),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${widget.session.durationMinutes} ${AppLocalizations.get('min_suffix')}',
                style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.45), fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          // Progress bar
          _ProgressBar(progress: progress, done: doneCount, total: exercises.length),

          Expanded(
            child: exercises.isEmpty
                ? _EmptyExercises(onFinish: _finishSession)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: exercises.length,
                    itemBuilder: (ctx, i) => _ExerciseCard(
                      exercise: exercises[i],
                      index: i,
                      isDone: _done.contains(i),
                      onToggle: () => _toggleDone(i),
                    ),
                  ),
          ),

          // Finish button
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border(
                top: BorderSide(color: AppColors.border),
              ),
            ),
            child: Column(children: [
              if (exercises.isNotEmpty && doneCount < exercises.length)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    AppLocalizations.format('session_done_progress', {
                      'done': doneCount,
                      'total': exercises.length,
                    }),
                    style: TextStyle(
                        color: AppColors.foreground.withOpacity(0.40), fontSize: 12),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _finishSession,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(AppLocalizations.get('session_finish'),
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  void _confirmExit(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.get('session_leave_title'),
            style: const TextStyle(
                color: AppColors.foreground, fontWeight: FontWeight.w800)),
        content: Text(AppLocalizations.get('session_leave_message'),
            style: TextStyle(color: AppColors.foreground.withOpacity(0.55))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.get('session_keep_training'),
                style: const TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
              Navigator.of(context).pop();
            },
            child: Text(AppLocalizations.get('session_leave'),
                style: TextStyle(color: AppColors.foreground.withOpacity(0.45))),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.done,
    required this.total,
  });
  final double progress;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(AppLocalizations.get('progress_label'),
                style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.50), fontSize: 12)),
            Text(
                total > 0
                    ? '$done / $total'
                    : AppLocalizations.get('session_no_exercises'),
                style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.50), fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.foreground.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary),
              minHeight: 5,
            ),
          ),
        ]),
      );
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.index,
    required this.isDone,
    required this.onToggle,
  });
  final SessionExercise exercise;
  final int index;
  final bool isDone;
  final VoidCallback onToggle;

  Color get _intensityColor {
    switch (exercise.intensity) {
      case 'high':   return AppColors.destructive;
      case 'medium': return AppColors.warning;
      default:       return AppColors.success;
    }
  }

  String get _intensityLabel {
    switch (exercise.intensity.toLowerCase()) {
      case 'high':
        return AppLocalizations.get('intensity_high');
      case 'medium':
        return AppLocalizations.get('intensity_medium');
      case 'recovery':
        return AppLocalizations.get('intensity_recovery');
      case 'low':
      case 'light':
        return AppLocalizations.get('intensity_light');
      default:
        return exercise.intensity;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDone
            ? AppColors.primary.withOpacity(0.07)
            : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? AppColors.primary.withOpacity(0.35)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(children: [
              // Index circle
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isDone
                      ? AppColors.primary.withOpacity(0.20)
                      : AppColors.foreground.withOpacity(0.07),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check_rounded,
                          color: AppColors.primary, size: 16)
                      : Text('${index + 1}',
                          style: TextStyle(
                              color: AppColors.foreground.withOpacity(0.50),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(exercise.exerciseName,
                    style: TextStyle(
                        color: isDone
                            ? AppColors.foreground.withOpacity(0.55)
                            : AppColors.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        decoration: isDone
                            ? TextDecoration.lineThrough
                            : null)),
              ),
              // Intensity badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _intensityColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_intensityLabel,
                    style: TextStyle(
                        color: _intensityColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),

          // Volume / duration
          if (exercise.volumeLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 6, 14, 0),
              child: Text(exercise.volumeLabel,
                  style: TextStyle(
                      color: AppColors.primary.withOpacity(0.80),
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
            ),

          // Instructions
          if (exercise.instructions != null &&
              exercise.instructions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 6, 14, 0),
              child: Text(exercise.instructions!,
                  style: TextStyle(
                      color: AppColors.foreground.withOpacity(0.45), fontSize: 13)),
            ),

          // Pose detection placeholder
          if (exercise.requiresPoseDetection)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.warning.withOpacity(0.30)),
                ),
                child: Row(children: [
                  Icon(Icons.camera_alt_outlined,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.get('session_ai_assessment_hint'),
                      style: TextStyle(
                          color: AppColors.warning.withOpacity(0.85),
                          fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ),

          // Done button
          Padding(
            padding: const EdgeInsets.all(14),
            child: GestureDetector(
              onTap: onToggle,
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: isDone
                      ? AppColors.primary.withOpacity(0.15)
                      : AppColors.foreground.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDone
                        ? AppColors.primary.withOpacity(0.40)
                        : AppColors.border,
                  ),
                ),
                child: Center(
                  child: Text(
                      isDone
                          ? AppLocalizations.get('exercise_done')
                          : AppLocalizations.get('exercise_mark_done'),
                      style: TextStyle(
                        color: isDone
                            ? AppColors.primary
                            : AppColors.foreground.withOpacity(0.50),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyExercises extends StatelessWidget {
  const _EmptyExercises({required this.onFinish});
  final VoidCallback onFinish;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.fitness_center_rounded,
              color: AppColors.foreground.withOpacity(0.15), size: 48),
          const SizedBox(height: 12),
          Text(AppLocalizations.get('session_no_exercises_detail'),
              style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.40), fontSize: 14)),
          const SizedBox(height: 6),
          Text(AppLocalizations.get('session_finish_hint'),
              style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.25), fontSize: 12)),
        ]),
      );
}
