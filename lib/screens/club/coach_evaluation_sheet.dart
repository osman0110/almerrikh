import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';

/// Bottom sheet for coach to evaluate a player in a session or match.
class CoachEvaluationSheet extends StatefulWidget {
  const CoachEvaluationSheet({
    super.key,
    required this.player,
    this.sessionId,
    this.matchId,
    this.existing,
  }) : assert(sessionId != null || matchId != null,
            'sessionId or matchId is required');

  final ClubPlayer player;
  final String? sessionId;
  final String? matchId;
  final CoachEvaluation? existing;

  @override
  State<CoachEvaluationSheet> createState() => _CoachEvaluationSheetState();
}

class _CoachEvaluationSheetState extends State<CoachEvaluationSheet> {
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  late Map<String, int?> _scores;

  static List<(String, String, IconData)> _metrics() => [
    ('fitnessLevel', AppLocalizations.get('eval_fitness'),  Icons.directions_run_rounded),
    ('effort',       AppLocalizations.get('eval_effort'),   Icons.local_fire_department_rounded),
    ('speed',        AppLocalizations.get('eval_speed'),    Icons.bolt_rounded),
    ('strength',     AppLocalizations.get('eval_strength'), Icons.fitness_center_rounded),
    ('agility',      AppLocalizations.get('eval_agility'),  Icons.loop_rounded),
    ('endurance',    AppLocalizations.get('eval_endurance'),Icons.timer_rounded),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _scores = {
      'fitnessLevel': e?.fitnessLevel,
      'effort':       e?.effort,
      'speed':        e?.speed,
      'strength':     e?.strength,
      'agility':      e?.agility,
      'endurance':    e?.endurance,
    };
    _notesCtrl.text = e?.notes ?? '';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final eval = CoachEvaluation(
        sessionId:    widget.sessionId,
        matchId:      widget.matchId,
        playerId:     widget.player.id,
        fitnessLevel: _scores['fitnessLevel'],
        effort:       _scores['effort'],
        speed:        _scores['speed'],
        strength:     _scores['strength'],
        agility:      _scores['agility'],
        endurance:    _scores['endurance'],
        notes:        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      final ok = await ClubService().saveEvaluation(eval);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.get('save_failed'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${AppLocalizations.get("error")}: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  double? get _average {
    final vals = _scores.values.whereType<int>().toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                      color: AppColors.surface2, shape: BoxShape.circle),
                  child: Center(child: Text(widget.player.initials,
                      style: const TextStyle(color: AppColors.foreground,
                          fontWeight: FontWeight.w900, fontSize: 15))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.format('eval_player_title', {'name': widget.player.fullName}),
                        style: const TextStyle(color: AppColors.foreground,
                            fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('#${widget.player.number}  ·  ${widget.player.position}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                )),
                if (_average != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.4))),
                    child: Text(_average!.toStringAsFixed(1),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 17)),
                  ),
              ]),
              const SizedBox(height: 20),

              // Score sliders
              ..._metrics().map((m) {
                final score = _scores[m.$1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(m.$3, color: AppColors.muted, size: 15),
                        const SizedBox(width: 6),
                        Expanded(child: Text(m.$2, style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w700, fontSize: 13))),
                        Text(score?.toString() ?? '—',
                            style: TextStyle(
                                color: score != null
                                    ? AppColors.primary
                                    : AppColors.muted,
                                fontWeight: FontWeight.w900, fontSize: 14)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: List.generate(10, (i) {
                        final val = i + 1;
                        final active = score == val;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _scores[m.$1] = val),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              height: 30,
                              margin: const EdgeInsets.symmetric(horizontal: 1.5),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.primary
                                    : (score != null && val <= score)
                                        ? AppColors.primarySoft
                                        : AppColors.surface2,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: active
                                        ? AppColors.primary
                                        : AppColors.border),
                              ),
                              child: Center(
                                child: Text('$val',
                                    style: TextStyle(
                                        color: active
                                            ? AppColors.foreground
                                            : AppColors.muted,
                                        fontWeight: active
                                            ? FontWeight.w900
                                            : FontWeight.w500,
                                        fontSize: 10)),
                              ),
                            ),
                          ),
                        );
                      })),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(AppLocalizations.get('poor'), style: const TextStyle(color: AppColors.muted, fontSize: 9)),
                          Text(AppLocalizations.get('excellent'), style: const TextStyle(color: AppColors.muted, fontSize: 9)),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              // Notes
              const SizedBox(height: 4),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                style: const TextStyle(color: AppColors.foreground, fontSize: 13),
                decoration: InputDecoration(
                  hintText: AppLocalizations.get('coach_notes_hint'),
                  hintStyle: TextStyle(color: AppColors.muted),
                  filled: true, fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Save button
              GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14)),
                  child: Center(
                    child: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.foreground))
                        : Text(AppLocalizations.get('save_evaluation'),
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
    );
  }
}
