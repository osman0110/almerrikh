import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/session_models.dart';

class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({super.key, required this.completion});
  final SessionCompletionData completion;

  @override
  Widget build(BuildContext context) {
    final rec = _recommendation(completion);
    final color = completion.recommendationColor;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Completion hero ────────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.success.withOpacity(0.40),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: AppColors.success,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppLocalizations.get('session_completed_title'),
                            style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            completion.sessionTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.foreground.withOpacity(0.45),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Recommendation banner ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withOpacity(0.30)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            completion.painReported
                                ? Icons.medical_services_outlined
                                : completion.postRpe >= 8
                                ? Icons.warning_amber_rounded
                                : Icons.thumb_up_rounded,
                            color: color,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              rec,
                              style: TextStyle(
                                color: color.withOpacity(0.90),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Stats grid ────────────────────────────────────────
                    _SectionTitle(
                      AppLocalizations.get('session_stats_title'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: AppLocalizations.get('training_load'),
                            value: '${completion.trainingLoad}',
                            unit: 'CE',
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            label: AppLocalizations.get(
                              'session_duration_label',
                            ),
                            value: '${completion.durationMinutes}',
                            unit: 'min',
                            color: const Color(0xff8B5CF6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: AppLocalizations.get('post_rpe_label'),
                            value: '${completion.postRpe}',
                            unit: '/ 10',
                            color: _rpeColor(completion.postRpe),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (completion.preRpe != null)
                          Expanded(
                            child: _StatCard(
                              label: AppLocalizations.get('pre_rpe_label'),
                              value: '${completion.preRpe}',
                              unit: '/ 10',
                              color: AppColors.foreground.withOpacity(0.45),
                            ),
                          )
                        else
                          const Expanded(child: SizedBox()),
                      ],
                    ),

                    // ── Hooper section ────────────────────────────────────
                    if (completion.hoooperScore != null) ...[
                      const SizedBox(height: 20),
                      _SectionTitle(AppLocalizations.get('readiness_label')),
                      const SizedBox(height: 12),
                      _HooperRow(score: completion.hoooperScore!),
                    ],

                    // ── Other details ─────────────────────────────────────
                    const SizedBox(height: 20),
                    _SectionTitle(
                      AppLocalizations.get('session_feedback_title'),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _DetailRow(
                            label: AppLocalizations.get(
                              'session_difficulty_label',
                            ),
                            value: _difficultyLabel(completion.difficulty),
                            color: _difficultyColor(completion.difficulty),
                          ),
                          const Divider(color: Color(0xff1A1928), height: 16),
                          _DetailRow(
                            label: AppLocalizations.get('mood_after_label'),
                            value: completion.moodAfter != null
                                ? '${'⭐' * (completion.moodAfter ?? 0)}'
                                : '—',
                            color: const Color(0xffF59E0B),
                          ),
                          const Divider(color: Color(0xff1A1928), height: 16),
                          _DetailRow(
                            label: AppLocalizations.get('pain_reported_short'),
                            value: completion.painReported
                                ? AppLocalizations.get('yes')
                                : AppLocalizations.get('no'),
                            color: completion.painReported
                                ? AppColors.destructive
                                : AppColors.success,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Back button ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/player', (_) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    AppLocalizations.get('back_to_dashboard'),
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _rpeColor(int rpe) {
    if (rpe >= 8) return AppColors.destructive;
    if (rpe >= 6) return AppColors.warning;
    return AppColors.success;
  }

  static String _difficultyLabel(String? d) {
    final map = {
      'easy': AppLocalizations.get('difficulty_easy_label'),
      'good': AppLocalizations.get('difficulty_good_label'),
      'hard': AppLocalizations.get('difficulty_hard_label'),
      'too_hard': AppLocalizations.get('difficulty_too_hard_label'),
    };
    return map[d] ?? '—';
  }

  static String _recommendation(SessionCompletionData value) {
    if (value.hoooperScore != null && value.hoooperScore! >= 17) {
      return AppLocalizations.get('session_rec_recovery');
    }
    if (value.painReported) {
      return AppLocalizations.get('session_rec_pain');
    }
    if (value.postRpe >= 8) {
      return AppLocalizations.get('session_rec_high_effort');
    }
    return AppLocalizations.get('session_rec_success');
  }

  static Color _difficultyColor(String? d) {
    switch (d) {
      case 'easy':
        return AppColors.success;
      case 'good':
        return AppColors.primary;
      case 'hard':
        return AppColors.warning;
      case 'too_hard':
        return AppColors.destructive;
      default:
        return AppColors.foreground.withOpacity(0.54);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.foreground,
      fontWeight: FontWeight.w800,
      fontSize: 14,
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });
  final String label, value, unit;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.foreground.withOpacity(0.45),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: TextStyle(color: color.withOpacity(0.60), fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );
}

class _HooperRow extends StatelessWidget {
  const _HooperRow({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (score <= 10) {
      color = AppColors.success;
      label = AppLocalizations.get('readiness_good_label');
    } else if (score <= 16) {
      color = AppColors.warning;
      label = AppLocalizations.get('readiness_moderate_label');
    } else {
      color = AppColors.destructive;
      label = AppLocalizations.get('readiness_high_label');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$score',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.get('hooper_index'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                label,
                style: TextStyle(color: color.withOpacity(0.75), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          color: AppColors.foreground.withOpacity(0.45),
          fontSize: 13,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ],
  );
}
