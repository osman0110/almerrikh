import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../services/club_service.dart';
import '../../widgets/common_widgets.dart';
import 'club_dashboard.dart';
import 'club_widgets.dart';
import 'competition_stats_section.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Comprehensive Admin Player Report — admin/owner only, non-clinical. Bio,
// composite readiness status, attendance, matches/minutes, discipline, a
// coach-safe injury/physio summary (status and counts, never diagnosis), a
// previous-period comparison, and per-competition performance (reusing the
// existing [CompetitionStatsSection] rather than duplicating that query).
// Admin cannot add/edit anything from this screen — view and export only.
// ─────────────────────────────────────────────────────────────────────────────

class AdminPlayerReportScreen extends StatefulWidget {
  const AdminPlayerReportScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });
  final String playerId;
  final String playerName;

  @override
  State<AdminPlayerReportScreen> createState() =>
      _AdminPlayerReportScreenState();
}

class _AdminPlayerReportScreenState extends State<AdminPlayerReportScreen> {
  Map<String, dynamic>? _report;
  bool _loading = true;
  late DateTime _rangeFrom;
  late DateTime _rangeTo;

  @override
  void initState() {
    super.initState();
    _rangeTo = DateTime.now();
    _rangeFrom = _rangeTo.subtract(const Duration(days: 29));
    _load();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final report = await ClubService().getAdminPlayerReport(
      widget.playerId,
      from: _fmt(_rangeFrom),
      to: _fmt(_rangeTo),
    );
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  String _readinessLabel(String? status) {
    switch (status) {
      case 'ready':
        return AppLocalizations.get('admin_readiness_ready');
      case 'ready_with_note':
        return AppLocalizations.get('admin_readiness_ready_note');
      case 'high_strain':
        return AppLocalizations.get('admin_readiness_monitor');
      case 'injured':
      case 'rehab':
        return AppLocalizations.get('admin_readiness_unavailable');
      default:
        return AppLocalizations.get('admin_readiness_no_data');
    }
  }

  Color _readinessColor(String? status) {
    switch (status) {
      case 'ready':
        return AppColors.success;
      case 'ready_with_note':
      case 'high_strain':
        return AppColors.warning;
      case 'injured':
      case 'rehab':
        return AppColors.destructive;
      default:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isOrgAdmin) return const RoleAccessDeniedPage();
    final current = (_report?['current'] as Map?)?.cast<String, dynamic>();
    final previous = (_report?['previous'] as Map?)?.cast<String, dynamic>();
    final currentAttendance =
        (current?['attendance'] as Map?)?.cast<String, dynamic>();
    final currentMatches = (current?['matches'] as Map?)?.cast<String, dynamic>();
    final previousMatches =
        (previous?['matches'] as Map?)?.cast<String, dynamic>();
    final discipline = (_report?['discipline'] as Map?)?.cast<String, dynamic>();
    final medical = (_report?['medical'] as Map?)?.cast<String, dynamic>();

    return ClubShell(
      currentIndex: 0,
      child: Column(
        children: [
          ClubAppHeader(
            title: widget.playerName,
            subtitle: AppLocalizations.get('admin_player_report_entry'),
            leading: GestureDetector(
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
                    color: AppColors.foreground, size: 18),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _report == null
                    ? ClubEmptyState(
                        icon: Icons.assessment_rounded,
                        title: AppLocalizations.get('error_load_failed'),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.card,
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _readinessColor(
                                          _report?['readiness_status'] as String?)
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _readinessLabel(
                                      _report?['readiness_status'] as String?),
                                  style: TextStyle(
                                    color: _readinessColor(
                                        _report?['readiness_status'] as String?),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text('${_fmt(_rangeFrom)} — ${_fmt(_rangeTo)}',
                                  style: const TextStyle(
                                      color: AppColors.muted, fontSize: 11)),
                            ]),
                            const SizedBox(height: 16),
                            ClubSectionLabel(AppLocalizations.get('attendance_label')),
                            const SizedBox(height: 8),
                            Row(children: [
                              _MetricTile(
                                  value: '${currentAttendance?['present'] ?? 0}',
                                  label: AppLocalizations.get('attendance_present'),
                                  color: AppColors.success),
                              const SizedBox(width: 8),
                              _MetricTile(
                                  value: '${currentAttendance?['late'] ?? 0}',
                                  label: AppLocalizations.get('attendance_late'),
                                  color: AppColors.warning),
                              const SizedBox(width: 8),
                              _MetricTile(
                                  value: '${currentAttendance?['absent'] ?? 0}',
                                  label: AppLocalizations.get('attendance_absent'),
                                  color: AppColors.destructive),
                            ]),
                            const SizedBox(height: 20),
                            ClubSectionLabel(AppLocalizations.get('match_players_section')),
                            const SizedBox(height: 8),
                            Row(children: [
                              _MetricTile(
                                  value: '${currentMatches?['appearances'] ?? 0}',
                                  label: AppLocalizations.get('management_report_minutes'),
                                  color: AppColors.primary),
                              const SizedBox(width: 8),
                              _MetricTile(
                                  value: '${currentMatches?['minutes'] ?? 0}',
                                  label: AppLocalizations.get('duration_minutes'),
                                  color: AppColors.primary),
                              const SizedBox(width: 8),
                              _MetricTile(
                                  value: '${currentMatches?['goals'] ?? 0}',
                                  label: AppLocalizations.get('match_goals_label'),
                                  color: AppColors.success),
                              const SizedBox(width: 8),
                              _MetricTile(
                                  value: '${currentMatches?['assists'] ?? 0}',
                                  label: AppLocalizations.get('match_assists_label'),
                                  color: AppColors.success),
                            ]),
                            if (previousMatches != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                AppLocalizations.format('admin_previous_period', {
                                  'minutes': '${previousMatches['minutes'] ?? 0}',
                                }),
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 11),
                              ),
                            ],
                            const SizedBox(height: 20),
                            ClubSectionLabel(AppLocalizations.get('discipline_card_title')),
                            const SizedBox(height: 8),
                            Row(children: [
                              _MetricTile(
                                  value: '${currentMatches?['yellow_cards'] ?? 0}',
                                  label: AppLocalizations.get('yellow_card_label'),
                                  color: AppColors.warning),
                              const SizedBox(width: 8),
                              _MetricTile(
                                  value: '${currentMatches?['red_cards'] ?? 0}',
                                  label: AppLocalizations.get('red_card_label'),
                                  color: AppColors.destructive),
                              const SizedBox(width: 8),
                              _MetricTile(
                                  value: '${discipline?['active_suspensions'] ?? 0}',
                                  label: AppLocalizations.get('discipline_status_suspended'),
                                  color: AppColors.destructive),
                            ]),
                            const SizedBox(height: 20),
                            ClubSectionLabel(AppLocalizations.get('admin_medical_summary_section')),
                            const SizedBox(height: 8),
                            Row(children: [
                              _MetricTile(
                                  value: '${medical?['open_injury_cases'] ?? 0}',
                                  label: AppLocalizations.get('admin_open_injury_cases'),
                                  color: AppColors.destructive),
                              const SizedBox(width: 8),
                              _MetricTile(
                                  value: '${medical?['physio_sessions'] ?? 0}',
                                  label: AppLocalizations.get('admin_physio_sessions_count'),
                                  color: AppColors.primary),
                            ]),
                            if (medical?['expected_return_date'] != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                AppLocalizations.format('admin_expected_return', {
                                  'date': '${medical?['expected_return_date']}',
                                }),
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 11),
                              ),
                            ],
                            const SizedBox(height: 20),
                            ClubSectionLabel(AppLocalizations.get('competitions_title')),
                            CompetitionStatsSection(playerId: widget.playerId),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 9.5)),
          ],
        ),
      ),
    );
  }
}
