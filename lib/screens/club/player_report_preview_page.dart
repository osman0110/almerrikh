import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/coach_summary_helper.dart';
import '../../services/readiness_helper.dart';
import '../../services/risk_flags_helper.dart';
import '../../services/smart_recommendation_service.dart';
import '../../services/weekly_plan_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Player Report Preview Page
// Generates a structured, human-readable coach report for a player.
// Rules-based — no external AI API.
// ─────────────────────────────────────────────────────────────────────────────

class PlayerReportPreviewPage extends StatelessWidget {
  const PlayerReportPreviewPage({
    super.key,
    required this.player,
    required this.readiness,
    required this.flags,
    required this.recommendations,
    required this.weeklyPlan,
    required this.summary,
    this.latestAssessmentType,
    this.latestAssessmentScore,
    this.trend,
  });

  final ClubPlayer player;
  final ReadinessResult readiness;
  final List<RiskFlag> flags;
  final List<String> recommendations;
  final List<String> weeklyPlan;
  final CoachSummary summary;
  final String? latestAssessmentType;
  final double? latestAssessmentScore;
  final String? trend;

  String _buildTextReport() {
    final buf = StringBuffer();
    final date = AppLocalizations.formatDate(DateTime.now(), withYear: true);
    buf.writeln('═══════════════════════════════');
    buf.writeln(AppLocalizations.get('report_preview_title').toUpperCase());
    buf.writeln(AppLocalizations.format('report_generated_on', {'date': date}));
    buf.writeln('═══════════════════════════════');
    buf.writeln();
    buf.writeln('${player.fullName}  •  #${player.number}');
    buf.writeln('${player.position}  •  ${player.teamName ?? ""}');
    buf.writeln();

    buf.writeln('─── ${AppLocalizations.get("report_section_readiness")} ───');
    buf.writeln('${readiness.statusLabel}  (${readiness.score}/100)');
    buf.writeln(readiness.recommendation);
    buf.writeln();

    if (flags.isNotEmpty) {
      buf.writeln('─── ${AppLocalizations.get("report_section_flags")} ───');
      for (final f in flags.take(3)) {
        buf.writeln('• ${f.title}: ${f.reason}');
      }
      buf.writeln();
    }

    if (latestAssessmentScore != null) {
      buf.writeln('─── ${AppLocalizations.get("report_section_assessment")} ───');
      buf.writeln(
          '${latestAssessmentType ?? "Assessment"}: ${latestAssessmentScore!.toStringAsFixed(0)}/100');
      buf.writeln();
    }

    if (trend != null) {
      buf.writeln('─── ${AppLocalizations.get("report_section_trend")} ───');
      buf.writeln(AppLocalizations.get('trend_$trend'));
      buf.writeln();
    }

    buf.writeln('─── ${AppLocalizations.get("report_section_recommendations")} ───');
    for (final r in recommendations) {
      buf.writeln('• $r');
    }
    buf.writeln();

    buf.writeln('─── ${AppLocalizations.get("report_section_weekly")} ───');
    for (final w in weeklyPlan) {
      buf.writeln('• $w');
    }
    buf.writeln();
    buf.writeln('═══════════════════════════════');

    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final date = AppLocalizations.formatDate(DateTime.now(), withYear: true);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.foreground, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.get('report_preview_title'),
          style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 16),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _buildTextReport()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(AppLocalizations.get('report_copied')),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ));
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
            label: Text(AppLocalizations.get('copy_report_btn'),
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // ── Header card ──────────────────────────────────────────────────
          _ReportCard(
            color: AppColors.maroon,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  '#${player.number}  •  ${player.position}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75), fontSize: 13),
                ),
                if (player.teamName != null && player.teamName!.isNotEmpty)
                  Text(player.teamName!,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.55), fontSize: 11)),
                const SizedBox(height: 10),
                Text(
                  AppLocalizations.format('report_generated_on', {'date': date}),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Readiness ────────────────────────────────────────────────────
          _SectionTitle(AppLocalizations.get('report_section_readiness')),
          _ReportCard(
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: readiness.color.withOpacity(0.12),
                  border:
                      Border.all(color: readiness.color.withOpacity(0.45), width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${readiness.score}',
                  style: TextStyle(
                      color: readiness.color,
                      fontWeight: FontWeight.w900,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(readiness.statusLabel,
                        style: TextStyle(
                            color: readiness.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(readiness.recommendation,
                        style: const TextStyle(
                            color: AppColors.textSoft, fontSize: 12)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Flags ────────────────────────────────────────────────────────
          if (flags.isNotEmpty) ...[
            _SectionTitle(AppLocalizations.get('report_section_flags')),
            _ReportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: flags.take(3).map((f) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: f.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.title,
                                style: TextStyle(
                                    color: f.color,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                            Text(f.reason,
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                    ]),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Latest Assessment ─────────────────────────────────────────────
          if (latestAssessmentScore != null) ...[
            _SectionTitle(AppLocalizations.get('report_section_assessment')),
            _ReportCard(
              child: Row(children: [
                const Icon(Icons.sports_score_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      latestAssessmentType != null
                          ? _assessmentLabel(latestAssessmentType!)
                          : 'Assessment',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                    Text(
                      '${latestAssessmentScore!.toStringAsFixed(0)} / 100',
                      style: TextStyle(
                          color: latestAssessmentScore! >= 75
                              ? AppColors.success
                              : latestAssessmentScore! >= 55
                                  ? AppColors.warning
                                  : AppColors.destructive,
                          fontWeight: FontWeight.w900,
                          fontSize: 18),
                    ),
                  ]),
                ),
                if (trend != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _trendColor(trend!).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_trendIcon(trend!),
                          color: _trendColor(trend!), size: 12),
                      const SizedBox(width: 4),
                      Text(AppLocalizations.get('trend_$trend'),
                          style: TextStyle(
                              color: _trendColor(trend!),
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // ── Recommendations ───────────────────────────────────────────────
          _SectionTitle(AppLocalizations.get('report_section_recommendations')),
          _ReportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: recommendations.map((r) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          color: AppColors.primary, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r,
                            style: const TextStyle(
                                color: AppColors.textSoft, fontSize: 12.5)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // ── Weekly Plan ────────────────────────────────────────────────────
          _SectionTitle(AppLocalizations.get('report_section_weekly')),
          _ReportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: weeklyPlan.asMap().entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.maroon.withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Text('${e.key + 1}',
                            style: const TextStyle(
                                color: AppColors.maroon,
                                fontSize: 9,
                                fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(e.value,
                            style: const TextStyle(
                                color: AppColors.textSoft, fontSize: 12.5)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _assessmentLabel(String type) {
    switch (type) {
      case 'squat':            return 'Squat Assessment';
      case 'jumpLanding':      return 'Jump Landing Assessment';
      case 'singleLegBalance': return 'Single Leg Balance';
      default:                 return 'Assessment';
    }
  }

  Color _trendColor(String t) {
    if (t == 'improving') return AppColors.success;
    if (t == 'declining') return AppColors.destructive;
    return AppColors.muted;
  }

  IconData _trendIcon(String t) {
    if (t == 'improving') return Icons.trending_up_rounded;
    if (t == 'declining') return Icons.trending_down_rounded;
    return Icons.trending_flat_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: open report preview with pre-computed data
// ─────────────────────────────────────────────────────────────────────────────

void openPlayerReport({
  required BuildContext context,
  required ClubPlayer player,
  required List history, // List<PlayerAssessment>
  required Map<String, dynamic>? wellnessData,
}) {
  final latest = history.isNotEmpty ? history.first : null;
  final latestScore = latest?.overallScore as double?;
  final latestType = latest?.type?.name as String?;
  final latestMovement = latest?.movementQualityScore as double?;
  final latestStability = latest?.stabilityScore as double?;

  String? trend;
  if (history.length >= 3) {
    final diff =
        (history[0].overallScore as double) - (history[2].overallScore as double);
    if (diff > 5)       trend = 'improving';
    else if (diff < -5) trend = 'declining';
    else                trend = 'stable';
  }

  final hooper = wellnessData?['hooper_score'] as int?;
  final rpe    = wellnessData?['last_rpe'] as int?;

  final readiness = ReadinessHelper.calculate(
    hooperScore:           hooper,
    lastRpe:               rpe,
    latestAssessmentScore: latestScore,
    trendDirection:        trend,
  );

  final flags = RiskFlagsHelper.evaluate(
    hooperScore:          hooper,
    lastRpe:              rpe,
    latestAssessmentScore: latestScore,
    latestAssessmentType:  latest?.type,
    stabilityScore:        latestStability,
    movementScore:         latestMovement,
    trend:                 trend,
    lastAssessmentDate:    latest?.date as DateTime?,
  );

  final recs = SmartRecommendationService.generate(
    readiness:             readiness,
    flags:                 flags,
    hooperScore:           hooper,
    lastRpe:               rpe,
    latestAssessmentScore: latestScore,
    latestAssessmentType:  latestType,
    trend:                 trend,
  );

  final weeklyPlan = WeeklyPlanHelper.suggest(readiness.status);

  final coachSummary = CoachSummaryHelper.build(
    readiness:       readiness,
    flags:           flags,
    recommendations: recs,
    movementScore:   latestMovement,
    stabilityScore:  latestStability,
    symmetryScore:   latest?.symmetryScore as double?,
    trend:           trend,
    hooperScore:     hooper,
    lastRpe:         rpe,
  );

  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PlayerReportPreviewPage(
      player:                player,
      readiness:             readiness,
      flags:                 flags,
      recommendations:       recs,
      weeklyPlan:            weeklyPlan,
      summary:               coachSummary,
      latestAssessmentType:  latestType,
      latestAssessmentScore: latestScore,
      trend:                 trend,
    ),
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}
