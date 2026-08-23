import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/monitoring_models.dart';
import '../../models/training_load_models.dart';
import '../../services/player_monitoring_service.dart';
import '../../utils/metric_formatter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Training Load & RPE Section — calendar-week sRPE / Monotony / Strain
// (TrainingLoadCalculator is the single source of truth — see
// api/player/training-load/TrainingLoadCalculator.php; this widget only
// displays the numbers, it never recomputes them).
//
// Shared across every screen that shows a player profile / report:
//  - club_player_detail_page.dart (main roster player profile)
//  - club_player_profile_page.dart (assessment risk dashboard / session detail)
//  - coach/coach_player_report_screen.dart (coach's player report)
// ─────────────────────────────────────────────────────────────────────────────

class TrainingLoadSection extends StatefulWidget {
  const TrainingLoadSection({
    super.key,
    required this.playerId,
    this.compact = false,
  });
  final String playerId;
  final bool compact;

  @override
  State<TrainingLoadSection> createState() => _TrainingLoadSectionState();
}

class _TrainingLoadSectionState extends State<TrainingLoadSection>
    with AutomaticKeepAliveClientMixin {
  TrainingLoadWeekSummary? _report;
  PlayerTrainingLoadRow? _rollingReport;
  bool _loading = true;
  bool _expanded = false;

  @override
  bool get wantKeepAlive => true;

  static const _dayNameKeys = {
    'Monday': 'day_mon',
    'Tuesday': 'day_tue',
    'Wednesday': 'day_wed',
    'Thursday': 'day_thu',
    'Friday': 'day_fri',
    'Saturday': 'day_sat',
    'Sunday': 'day_sun',
  };

  String _dayName(String dayName) {
    final key = _dayNameKeys[dayName];
    return key != null ? AppLocalizations.get(key) : dayName;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      ApiService.getPlayerTrainingLoadWeekly(playerId: widget.playerId),
      if (widget.compact) PlayerMonitoringService.getTeamWellness(),
    ]);
    final report = results[0] as TrainingLoadWeekSummary?;
    PlayerTrainingLoadRow? rollingReport;
    if (widget.compact && results.length > 1) {
      final wellness = results[1] as TeamWellness?;
      if (wellness != null) {
        for (final row in wellness.playersTrainingLoad) {
          if (row.playerId == widget.playerId) {
            rollingReport = row;
            break;
          }
        }
      }
    }
    if (mounted)
      setState(() {
        _report = report;
        _rollingReport = rollingReport;
        _loading = false;
      });
  }

  Future<void> _editRpe(TrainingLoadSession session) async {
    if (session.sessionId == null) return;
    var selectedRpe = (session.rpe ?? 0).round().clamp(0, 10);
    final durationController = TextEditingController(
      text: session.actualDurationMinutes?.toString() ?? '',
    );
    final reasonController = TextEditingController();
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppLocalizations.get('tls_approve_rpe_title'),
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLocalizations.get('tls_approve_rpe_subtitle'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text(
                  'RPE: $selectedRpe',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Slider(
                  value: selectedRpe.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '$selectedRpe',
                  activeColor: AppColors.primary,
                  onChanged: saving
                      ? null
                      : (value) => setSheetState(
                            () => selectedRpe = value.round(),
                          ),
                ),
                TextField(
                  controller: durationController,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.foreground),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.get('tls_actual_duration_label'),
                    labelStyle: const TextStyle(color: AppColors.muted),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonController,
                  enabled: !saving,
                  maxLength: 500,
                  style: const TextStyle(color: AppColors.foreground),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.get('tls_override_reason_label'),
                    labelStyle: const TextStyle(color: AppColors.muted),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final duration =
                              int.tryParse(durationController.text.trim());
                          final reason = reasonController.text.trim();
                          if (duration == null ||
                              duration < 1 ||
                              duration > 480 ||
                              reason.isEmpty) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.get('tls_invalid_input_msg'),
                                ),
                              ),
                            );
                            return;
                          }
                          setSheetState(() => saving = true);
                          final result =
                              await PlayerMonitoringService.saveRpe(
                            rpeScore: selectedRpe,
                            durationMinutes: duration,
                            actualDurationMinutes: duration,
                            sessionId: session.sessionId,
                            playerId: widget.playerId,
                            reason: reason,
                          );
                          if (!sheetContext.mounted) return;
                          if (result['success'] == true) {
                            Navigator.of(sheetContext).pop();
                            await _load();
                            return;
                          }
                          setSheetState(() => saving = false);
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                result['message']?.toString() ??
                                    result['error']?.toString() ??
                                    AppLocalizations.get('tls_save_failed_msg'),
                              ),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(AppLocalizations.get('tls_confirm_btn')),
                ),
              ],
            ),
        ),
      ),
    );

    durationController.dispose();
    reasonController.dispose();
  }

  Color _dayColor(String status) {
    switch (status) {
      case 'COMPLETE':
        return AppColors.success;
      case 'REST':
        return AppColors.muted;
      case 'MISSING_RPE':
      case 'MISSING_DURATION':
        return AppColors.warning;
      case 'ABSENT':
        return AppColors.destructive;
      case 'UNAVAILABLE':
        return AppColors.destructive;
      case 'MATCH_NO_RPE':
      case 'MATCH_MISSING_RPE':
        return AppColors.risk;
      case 'SCHEDULED_SESSION_MISSING_RECORD':
      case 'UNKNOWN_DAY_STATUS':
      case 'HISTORICAL_STATUS_UNKNOWN':
        return AppColors.muted;
      default:
        return AppColors.border;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'COMPLETE':
        return AppLocalizations.get('tls_status_complete');
      case 'REST':
        return AppLocalizations.get('tls_status_rest');
      case 'MISSING_RPE':
        return AppLocalizations.get('tls_status_missing_rpe');
      case 'MISSING_DURATION':
        return AppLocalizations.get('tls_status_missing_duration');
      case 'ABSENT':
        return AppLocalizations.get('attendance_absent');
      case 'UNAVAILABLE':
        return AppLocalizations.get('roster_status_inactive');
      case 'MATCH_NO_RPE':
      case 'MATCH_MISSING_RPE':
        return AppLocalizations.get('tls_status_match_no_rpe');
      case 'SCHEDULED_SESSION_MISSING_RECORD':
        return AppLocalizations.get('tls_status_scheduled_no_record');
      case 'UNKNOWN_DAY_STATUS':
        return AppLocalizations.get('tls_status_unknown_day');
      case 'HISTORICAL_STATUS_UNKNOWN':
        return AppLocalizations.get('tls_status_unknown_historical');
      default:
        return AppLocalizations.get('tls_status_no_record');
    }
  }

  String _monotonyValue(TrainingLoadWeekSummary report) {
    if (report.isIncomplete) return MetricFormatter.incompleteData;
    if (report.isConstantLoad) return AppLocalizations.get('tls_cannot_calculate');
    if (report.isNoLoad) return MetricFormatter.insufficientData;
    return MetricFormatter.monotony(report.monotony);
  }

  String _strainValue(TrainingLoadWeekSummary report) {
    if (report.isIncomplete) return MetricFormatter.incompleteData;
    if (report.isConstantLoad) return AppLocalizations.get('tls_cannot_calculate');
    if (report.isNoLoad) return MetricFormatter.insufficientData;
    return MetricFormatter.strain(report.strain);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Container(
        height: widget.compact ? 48 : 60,
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

    final r = _report;
    if (widget.compact) {
      return _buildCompactSummary(r, _rollingReport);
    }
    if (r == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.bar_chart_rounded, color: AppColors.muted, size: 16),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.get('tls_no_data_yet'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final maxLoad = r.days.fold<double>(
      0,
      (a, d) => d.dailyLoad > a ? d.dailyLoad : a,
    );
    final pw = r.previousWeek;

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
                Icons.fitness_center_rounded,
                color: AppColors.primary,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.get('tls_week_summary'),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Text(
                '${r.weekStart} → ${r.weekEnd}',
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (r.isNoLoad)
            _statusBanner(AppLocalizations.get('tls_no_load_this_week'), AppColors.muted)
          else if (r.isConstantLoad)
            _statusBanner(
              AppLocalizations.get('tls_constant_load_msg'),
              AppColors.warning,
            )
          else if (r.isIncomplete)
            _statusBanner(
              AppLocalizations.get('tls_incomplete_report_msg'),
              AppColors.warning,
            ),
          if (r.isNoLoad || r.isConstantLoad || r.isIncomplete)
            const SizedBox(height: 10),

          // KPI grid
          Row(
            children: [
              Expanded(
                child: _miniCard(
                  AppLocalizations.get('weekly_load'),
                  '${MetricFormatter.loadValue(r.weeklyLoad)}${r.isIncomplete ? '*' : ''}',
                  'CE',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniCard(
                  AppLocalizations.get('tls_daily_average'),
                  MetricFormatter.average(r.dailyMean),
                  'CE',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _miniCard(
                  AppLocalizations.get('tls_standard_deviation'),
                  MetricFormatter.standardDeviation(r.standardDeviation),
                  'CE',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _miniCard('Monotony', _monotonyValue(r), '')),
              const SizedBox(width: 8),
              Expanded(child: _miniCard('Strain', _strainValue(r), '')),
            ],
          ),

          if (pw != null) ...[const SizedBox(height: 10), _previousWeekRow(pw)],

          const SizedBox(height: 14),
          Text(
            AppLocalizations.get('tls_daily_load_chart_title'),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: r.days.map((d) {
                final h = maxLoad > 0 ? (d.dailyLoad / maxLoad) * 64 : 0.0;
                final barColor = _dayColor(d.participationStatus);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          d.dailyLoad > 0
                              ? MetricFormatter.loadValue(d.dailyLoad)
                              : '',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: d.dailyLoad > 0 && h < 4 ? 4 : h,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dayName(d.dayName),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppLocalizations.get(_expanded ? 'tls_hide_details' : 'tls_show_details'),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
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
          if (_expanded) ...[
            const SizedBox(height: 8),
            ...r.days.map(_dayDetailTile),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactSummary(
    TrainingLoadWeekSummary? weekly,
    PlayerTrainingLoadRow? rolling,
  ) {
    final classification =
        rolling?.acwrClassification ?? 'INSUFFICIENT_DATA';
    final color = _acwrColor(classification);
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
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.fitness_center_rounded,
                  color: AppColors.primary,
                  size: 13,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.get('tls_compact_title'),
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 5, height: 5,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _acwrLabel(classification),
                    style: TextStyle(
                      color: color,
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
                rolling?.acwr?.toStringAsFixed(2) ?? '—',
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              const SizedBox(width: 4),
              const Text('ACWR',
                  style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _compactMetric(
                  AppLocalizations.get('weekly_load'),
                  weekly == null
                      ? '—'
                      : MetricFormatter.loadValue(weekly.weeklyLoad),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _compactMetric(
                  AppLocalizations.get('physical_weekly_load_short'),
                  rolling?.load7d == null
                      ? '—'
                      : MetricFormatter.loadValue(rolling!.load7d!),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _compactMetric(
                  AppLocalizations.get('tls_average_rpe'),
                  rolling?.averageRpe7d?.toStringAsFixed(1) ?? '—',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compactMetric(String label, String value) => Container(
    height: 24,
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(999),
    ),
    alignment: Alignment.center,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.foreground,
            fontWeight: FontWeight.w600,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 8.5),
          ),
        ),
      ],
    ),
  );

  Color _acwrColor(String classification) {
    switch (classification) {
      case 'BELOW_TARGET':
        return AppColors.parentAccent;
      case 'IN_TARGET':
        return AppColors.success;
      case 'CAUTION':
        return AppColors.warning;
      case 'ABOVE_TARGET':
        return AppColors.destructive;
      default:
        return AppColors.muted;
    }
  }

  String _acwrLabel(String classification) {
    switch (classification) {
      case 'BELOW_TARGET':
        return AppLocalizations.get('tls_acwr_below');
      case 'IN_TARGET':
        return AppLocalizations.get('tls_acwr_in_target');
      case 'CAUTION':
        return AppLocalizations.get('tls_acwr_caution');
      case 'ABOVE_TARGET':
        return AppLocalizations.get('tls_acwr_above');
      default:
        return AppLocalizations.get('tls_acwr_insufficient');
    }
  }

  Widget _statusBanner(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline_rounded, color: color, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 10.5)),
        ),
      ],
    ),
  );

  Widget _previousWeekRow(TrainingLoadPreviousWeek pw) {
    final change = pw.changePercent;
    final up = change != null && change > 0;
    final color = change == null
        ? AppColors.muted
        : (up ? AppColors.destructive : AppColors.success);
    return Row(
      children: [
        const Icon(Icons.history_rounded, color: AppColors.muted, size: 13),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            AppLocalizations.format('tls_compare_previous_week', {'value': MetricFormatter.load(pw.weeklyLoad)}),
            style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
          ),
        ),
        Text(
          change != null
              ? '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}%'
              : '—',
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _dayDetailTile(TrainingLoadDay d) {
    final color = _dayColor(d.participationStatus);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                _dayName(d.dayName),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                d.date.toIso8601String().split('T').first,
                style: const TextStyle(color: AppColors.muted, fontSize: 9),
              ),
              const Spacer(),
              Text(
                _statusLabel(d.participationStatus),
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (d.sessionsCount > 0) ...[
            const SizedBox(height: 6),
            ...d.sessions.map(
              (s) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s.sessionName ?? s.sessionType ?? AppLocalizations.get('tls_session_fallback')} — '
                        'RPE ${MetricFormatter.rpe(s.rpe)} × '
                        '${MetricFormatter.duration(s.actualDurationMinutes)} = '
                        '${MetricFormatter.load(s.sessionLoad)}'
                        '${s.recordStatus == 'edited' ? AppLocalizations.get('tls_edited_suffix') : ''}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    if (s.sessionId != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: AppLocalizations.get('tls_edit_rpe_tooltip'),
                        onPressed: () => _editRpe(s),
                        icon: const Icon(
                          Icons.edit_rounded,
                          color: AppColors.primary,
                          size: 17,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniCard(String label, String value, String unit) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
        ),
        const SizedBox(height: 3),
        Text(
          unit.isEmpty ? value : '$value $unit',
          style: const TextStyle(
            color: AppColors.foreground,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}
