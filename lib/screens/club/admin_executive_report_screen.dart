import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../services/club_service.dart';
import '../../widgets/common_widgets.dart';
import 'club_dashboard.dart';
import 'club_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Team Executive Report — admin/owner only. Shows the final, approved status
// the club's coaches already decided (ready / needs monitoring / high load),
// never raw Hooper/RPE/daily-measurement detail. Combines three read-only
// endpoints: admin-dashboard.php (readiness composite counts, medical/physio
// counts), admin-dashboard-details.php (minutes/goals/cards rollup), and
// admin-executive-report.php (match record, standings, attendance rate,
// admin-decision alerts) — none of them touch the physical-coach/doctor/
// physio operational data itself.
// ─────────────────────────────────────────────────────────────────────────────

class AdminExecutiveReportScreen extends StatefulWidget {
  const AdminExecutiveReportScreen({super.key});

  @override
  State<AdminExecutiveReportScreen> createState() =>
      _AdminExecutiveReportScreenState();
}

class _AdminExecutiveReportScreenState
    extends State<AdminExecutiveReportScreen> {
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _details;
  Map<String, dynamic>? _executive;
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
    final results = await Future.wait([
      ClubService().getAdminDashboard(),
      ClubService().getAdminDashboardDetails(
        from: _fmt(_rangeFrom),
        to: _fmt(_rangeTo),
      ),
      ClubService().getAdminExecutiveReport(
        from: _fmt(_rangeFrom),
        to: _fmt(_rangeTo),
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _dashboard = results[0];
      _details = results[1];
      _executive = results[2];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!isOrgAdmin) return const RoleAccessDeniedPage();
    return ClubShell(
      currentIndex: 0,
      child: Column(
        children: [
          ClubAppHeader(
            title: AppLocalizations.get('admin_executive_report_title'),
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
                : _dashboard == null && _executive == null
                    ? ClubEmptyState(
                        icon: Icons.bar_chart_rounded,
                        title: AppLocalizations.get('error_load_failed'),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.card,
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          children: [
                            Text(
                              '${_fmt(_rangeFrom)} — ${_fmt(_rangeTo)}',
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 11),
                            ),
                            const SizedBox(height: 16),
                            _buildReadinessSection(),
                            const SizedBox(height: 20),
                            _buildRecordSection(),
                            const SizedBox(height: 20),
                            _buildStandingsSection(),
                            const SizedBox(height: 20),
                            _buildParticipationSection(),
                            const SizedBox(height: 20),
                            _buildAlertsSection(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label,
        style: const TextStyle(
            color: AppColors.foreground,
            fontWeight: FontWeight.w900,
            fontSize: 15)),
  );

  Widget _buildReadinessSection() {
    final counts =
        (_dashboard?['composite_counts'] as Map?)?.cast<String, dynamic>() ?? {};
    int c(String k) => (counts[k] as num?)?.toInt() ?? 0;
    final ready = c('ready') + c('ready_with_note');
    final needsMonitoring = c('high_strain');
    final unavailable = c('injured') + c('rehab');
    final noData = c('incomplete_data');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(AppLocalizations.get('admin_readiness_section')),
        Row(children: [
          _MetricTile(
              value: '$ready',
              label: AppLocalizations.get('admin_readiness_ready'),
              color: AppColors.success),
          const SizedBox(width: 8),
          _MetricTile(
              value: '$needsMonitoring',
              label: AppLocalizations.get('admin_readiness_monitor'),
              color: AppColors.warning),
          const SizedBox(width: 8),
          _MetricTile(
              value: '$unavailable',
              label: AppLocalizations.get('admin_readiness_unavailable'),
              color: AppColors.destructive),
          const SizedBox(width: 8),
          _MetricTile(
              value: '$noData',
              label: AppLocalizations.get('admin_readiness_no_data'),
              color: AppColors.muted),
        ]),
      ],
    );
  }

  Widget _buildRecordSection() {
    final record = (_executive?['record'] as Map?)?.cast<String, dynamic>();
    if (record == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(AppLocalizations.get('admin_record_section')),
        Row(children: [
          _MetricTile(
              value: '${record['won']}',
              label: AppLocalizations.get('admin_record_won'),
              color: AppColors.success),
          const SizedBox(width: 8),
          _MetricTile(
              value: '${record['drawn']}',
              label: AppLocalizations.get('admin_record_drawn'),
              color: AppColors.warning),
          const SizedBox(width: 8),
          _MetricTile(
              value: '${record['lost']}',
              label: AppLocalizations.get('admin_record_lost'),
              color: AppColors.destructive),
          const SizedBox(width: 8),
          _MetricTile(
              value: '${record['played']}',
              label: AppLocalizations.get('admin_record_played'),
              color: AppColors.muted),
        ]),
      ],
    );
  }

  Widget _buildStandingsSection() {
    final standings =
        (_executive?['standings'] as List?)?.cast<Map>() ?? const [];
    if (standings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(AppLocalizations.get('admin_standings_section')),
        ...standings.map((row) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Row(children: [
                Expanded(
                  child: Text('${row['competition_name']}',
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
                Text(
                  AppLocalizations.format(
                      'admin_standings_position', {'position': '${row['position']}'}),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13),
                ),
                const SizedBox(width: 10),
                Text('${row['points']} ${AppLocalizations.get('admin_points_short')}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            )),
      ],
    );
  }

  Widget _buildParticipationSection() {
    final totals = (_details?['totals'] as Map?)?.cast<String, dynamic>();
    final attendance =
        (_executive?['attendance'] as Map?)?.cast<String, dynamic>();
    final attendanceRate = _executive?['attendance_rate'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(AppLocalizations.get('admin_participation_section')),
        Row(children: [
          _MetricTile(
              value: '${totals?['total_minutes'] ?? '-'}',
              label: AppLocalizations.get('admin_total_minutes'),
              color: AppColors.primary),
          const SizedBox(width: 8),
          _MetricTile(
              value: attendanceRate != null ? '$attendanceRate%' : '-',
              label: AppLocalizations.get('admin_attendance_rate'),
              color: AppColors.success),
          const SizedBox(width: 8),
          _MetricTile(
              value: '${totals?['yellow_cards'] ?? 0}',
              label: AppLocalizations.get('admin_yellow_cards'),
              color: AppColors.warning),
          const SizedBox(width: 8),
          _MetricTile(
              value: '${totals?['red_cards'] ?? 0}',
              label: AppLocalizations.get('admin_red_cards'),
              color: AppColors.destructive),
        ]),
        if (attendance != null) ...[
          const SizedBox(height: 8),
          Text(
            '${AppLocalizations.get('attendance_present')}: ${attendance['present']} · '
            '${AppLocalizations.get('attendance_late')}: ${attendance['late']} · '
            '${AppLocalizations.get('attendance_absent')}: ${attendance['absent']}',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildAlertsSection() {
    final alerts = (_executive?['alerts'] as List?)?.cast<Map>() ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(AppLocalizations.get('admin_alerts_section')),
        if (alerts.isEmpty)
          Text(AppLocalizations.get('admin_alerts_none'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12))
        else
          ...alerts.map((a) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${a['label']}',
                        style: const TextStyle(
                            color: AppColors.foreground, fontSize: 12.5)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${a['count']}',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ),
                ]),
              )),
      ],
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
