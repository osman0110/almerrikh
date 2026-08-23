import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../widgets/common_widgets.dart';
import 'club_dashboard.dart';
import 'club_widgets.dart';

class TeamManagementReportScreen extends StatefulWidget {
  const TeamManagementReportScreen({super.key});

  @override
  State<TeamManagementReportScreen> createState() =>
      _TeamManagementReportScreenState();
}

class _TeamManagementReportScreenState extends State<TeamManagementReportScreen> {
  List<PlayerManagementReportRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await ClubService().getManagementReport();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!canViewManagementReport) return const RoleAccessDeniedPage();
    return ClubShell(
      currentIndex: 0,
      child: Column(
        children: [
          ClubAppHeader(
            title: AppLocalizations.get('report_tile_management_title'),
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
                : _rows.isEmpty
                    ? ClubEmptyState(
                        icon: Icons.assignment_turned_in_rounded,
                        title: AppLocalizations.get('no_players_yet'),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.card,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ManagementReportRow(row: _rows[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ManagementReportRow extends StatelessWidget {
  const _ManagementReportRow({required this.row});
  final PlayerManagementReportRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.name,
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
          const SizedBox(height: 10),
          Row(children: [
            _Stat(
                icon: Icons.timer_rounded,
                label: AppLocalizations.get('management_report_minutes'),
                value: '${row.minutes}'),
            const SizedBox(width: 14),
            _Stat(
                icon: Icons.check_circle_outline_rounded,
                label: AppLocalizations.get('attendance_present'),
                value: '${row.present}',
                color: AppColors.success),
            const SizedBox(width: 14),
            _Stat(
                icon: Icons.schedule_rounded,
                label: AppLocalizations.get('attendance_late'),
                value: '${row.late}',
                color: AppColors.warning),
            const SizedBox(width: 14),
            _Stat(
                icon: Icons.cancel_outlined,
                label: AppLocalizations.get('attendance_absent'),
                value: '${row.absent}',
                color: AppColors.destructive),
          ]),
          if (row.yellowCards > 0 || row.redCards > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (row.yellowCards > 0)
                _CardBadge(color: const Color(0xFFE5A315), count: row.yellowCards),
              if (row.yellowCards > 0 && row.redCards > 0) const SizedBox(width: 6),
              if (row.redCards > 0)
                _CardBadge(color: AppColors.destructive, count: row.redCards),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.muted,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color == AppColors.muted ? AppColors.foreground : color,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ],
      ),
    );
  }
}

class _CardBadge extends StatelessWidget {
  const _CardBadge({required this.color, required this.count});
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.square_rounded, size: 11, color: color),
        const SizedBox(width: 4),
        Text('x$count',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }
}
