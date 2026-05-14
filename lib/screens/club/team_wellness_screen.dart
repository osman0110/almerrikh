import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/monitoring_models.dart';
import '../../services/player_monitoring_service.dart';

class TeamWellnessScreen extends StatefulWidget {
  const TeamWellnessScreen({super.key});

  @override
  State<TeamWellnessScreen> createState() => _TeamWellnessScreenState();
}

class _TeamWellnessScreenState extends State<TeamWellnessScreen> {
  TeamWellness? wellness;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await PlayerMonitoringService.getTeamWellness();
    setState(() {
      wellness = w;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Team Wellness'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : wellness == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.white.withOpacity(0.3), size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Team Readiness
                        _KpiCard(
                          label: 'Team Readiness',
                          value: '${wellness!.teamReadinessScore}%',
                          icon: Icons.people_rounded,
                          valueColor: wellness!.teamReadinessScore >= 70
                              ? AppColors.success
                              : wellness!.teamReadinessScore >= 40
                                  ? AppColors.warning
                                  : AppColors.destructive,
                        ),
                        const SizedBox(height: 12),

                        // Injury Risk
                        _KpiCard(
                          label: 'Players at Injury Risk',
                          value: wellness!.injuryRiskCount.toString(),
                          icon: Icons.warning_rounded,
                          valueColor: wellness!.injuryRiskCount > 0 ? AppColors.destructive : AppColors.success,
                        ),
                        const SizedBox(height: 12),

                        // Average RPE
                        _KpiCard(
                          label: 'Average RPE',
                          value: wellness!.averageRpe.toStringAsFixed(1),
                          icon: Icons.fitness_center_rounded,
                        ),
                        const SizedBox(height: 12),

                        // Weekly Load
                        _KpiCard(
                          label: 'Weekly Load',
                          value: wellness!.weeklyLoad.toString(),
                          icon: Icons.trending_up_rounded,
                        ),
                        const SizedBox(height: 12),

                        // Recovery Score
                        _KpiCard(
                          label: 'Recovery Score',
                          value: '${wellness!.recoveryScore}%',
                          icon: Icons.restore_rounded,
                          valueColor: wellness!.recoveryScore >= 70
                              ? AppColors.success
                              : wellness!.recoveryScore >= 40
                                  ? AppColors.warning
                                  : AppColors.destructive,
                        ),
                        const SizedBox(height: 12),

                        // Check-in Status
                        _KpiCard(
                          label: 'Checked In Today',
                          value: '${wellness!.totalCheckedIn}',
                          icon: Icons.check_circle_rounded,
                        ),
                        const SizedBox(height: 24),

                        // Players Needing Attention
                        if (wellness!.playersNeedingAttention > 0) ...[
                          Text(
                            'Players Needing Attention',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.destructive.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.destructive.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_rounded, color: AppColors.destructive, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${wellness!.playersNeedingAttention} player(s) showing high wellness risk',
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Summary
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Summary',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _SummaryRow(
                                'Total Checked In',
                                wellness!.totalCheckedIn.toString(),
                              ),
                              const SizedBox(height: 8),
                              _SummaryRow(
                                'Avg Training Load',
                                (wellness!.weeklyLoad ~/ 7).toString(),
                              ),
                              const SizedBox(height: 8),
                              _SummaryRow(
                                'Injury Risk',
                                '${wellness!.injuryRiskCount} player(s)',
                                color: wellness!.injuryRiskCount > 0 ? AppColors.destructive : AppColors.success,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });
  final String label, value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.primary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
