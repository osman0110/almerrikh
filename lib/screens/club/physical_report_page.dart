import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/physical_report_models.dart';
import '../../services/physical_report_service.dart';
import '../../widgets/common_widgets.dart';
import 'club_dashboard.dart';
import 'club_widgets.dart';

class ManagementPhysicalReportPage extends StatelessWidget {
  const ManagementPhysicalReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!canViewManagementReport) return const RoleAccessDeniedPage();
    return const _PhysicalReportView(editable: false);
  }
}

class PhysicalReadinessManagementPage extends StatelessWidget {
  const PhysicalReadinessManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isCoachRole) return const RoleAccessDeniedPage();
    return const _PhysicalReportView(editable: true);
  }
}

class _PhysicalReportView extends StatefulWidget {
  const _PhysicalReportView({required this.editable});

  final bool editable;

  @override
  State<_PhysicalReportView> createState() => _PhysicalReportViewState();
}

class _PhysicalReportViewState extends State<_PhysicalReportView> {
  final _service = const PhysicalReportService();
  final Set<String> _updatingPlayers = {};
  PhysicalReportData? _data;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    final data = await _service.getReport();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _error = data == null;
    });
  }

  Future<void> _setReadiness(PhysicalReportPlayer player, bool isReady) async {
    setState(() => _updatingPlayers.add(player.id));
    final saved = await _service.updateReadiness(
      playerId: player.id,
      isReady: isReady,
    );
    if (!mounted) return;

    if (saved && _data != null) {
      final players = _data!.players
          .map(
            (item) =>
                item.id == player.id ? item.copyWith(isReady: isReady) : item,
          )
          .toList();
      final readyPlayers = players.where((item) => item.isReady).length;
      _data = PhysicalReportData(
        summary: PhysicalReportSummary(
          totalPlayers: players.length,
          readyPlayers: readyPlayers,
          notReadyPlayers: players.length - readyPlayers,
          averageBodyFat: _data!.summary.averageBodyFat,
          totalSessions: _data!.summary.totalSessions,
        ),
        players: players,
      );
    }

    setState(() => _updatingPlayers.remove(player.id));
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.get('physical_status_update_failed')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.editable
        ? AppLocalizations.get('physical_readiness_manage_title')
        : AppLocalizations.get('physical_report_title');

    return ClubShell(
      currentIndex: widget.editable ? 0 : 4,
      child: Column(
        children: [
          ClubAppHeader(
            title: title,
            subtitle: widget.editable
                ? AppLocalizations.get('physical_readiness_manage_subtitle')
                : AppLocalizations.get('physical_report_subtitle'),
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
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.foreground,
                  size: 18,
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error || _data == null) {
      return ClubEmptyState(
        icon: Icons.cloud_off_rounded,
        title: AppLocalizations.get('reports_load_error'),
        ctaLabel: AppLocalizations.get('try_again'),
        onCta: _load,
      );
    }
    if (_data!.players.isEmpty) {
      return ClubEmptyState(
        icon: Icons.groups_outlined,
        title: AppLocalizations.get('no_players_yet'),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _SummaryRow(summary: _data!.summary),
          const SizedBox(height: 12),
          _InfoBanner(editable: widget.editable),
          const SizedBox(height: 18),
          ClubSectionLabel(AppLocalizations.get('players_title')),
          ..._data!.players.map(
            (player) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PlayerPhysicalCard(
                player: player,
                editable: widget.editable,
                updating: _updatingPlayers.contains(player.id),
                onChanged: (value) => _setReadiness(player, value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final PhysicalReportSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: AppLocalizations.get('physical_report_ready_players'),
            value: '${summary.readyPlayers}',
            color: AppColors.success,
            icon: Icons.check_circle_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            label: AppLocalizations.get('physical_report_not_ready_players'),
            value: '${summary.notReadyPlayers}',
            color: AppColors.destructive,
            icon: Icons.pause_circle_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            label: AppLocalizations.get('physical_sessions_short'),
            value: '${summary.totalSessions}',
            color: AppColors.primary,
            icon: Icons.event_available_rounded,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.editable});

  final bool editable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              AppLocalizations.get(
                editable
                    ? 'physical_readiness_default_note'
                    : 'physical_report_admin_note',
              ),
              style: const TextStyle(
                color: AppColors.foreground,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerPhysicalCard extends StatelessWidget {
  const _PlayerPhysicalCard({
    required this.player,
    required this.editable,
    required this.updating,
    required this.onChanged,
  });

  final PhysicalReportPlayer player;
  final bool editable;
  final bool updating;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final statusColor = player.isReady
        ? AppColors.success
        : AppColors.destructive;
    final statusLabel = AppLocalizations.get(
      player.isReady ? 'physical_status_ready' : 'physical_status_not_ready',
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: statusColor.withOpacity(0.22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        player.position,
                        player.teamName,
                      ].where((value) => value.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (editable) ...[
                const SizedBox(width: 6),
                updating
                    ? const SizedBox(
                        width: 34,
                        height: 34,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : Switch.adaptive(
                        value: player.isReady,
                        activeColor: AppColors.success,
                        onChanged: onChanged,
                      ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 11),
          Row(
            children: [
              _Metric(
                label: AppLocalizations.get('physical_body_fat_short'),
                value: player.bodyFatPercentage == null
                    ? '—'
                    : '${player.bodyFatPercentage!.toStringAsFixed(1)}%',
              ),
              _Metric(
                label: AppLocalizations.get('physical_sessions_short'),
                value: '${player.sessionsCount}',
              ),
              _Metric(
                label: AppLocalizations.get('physical_weekly_load_short'),
                value: '${player.load7d}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}
