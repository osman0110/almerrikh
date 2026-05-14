import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/monitoring_models.dart';
import '../../services/player_monitoring_service.dart';

class MonitoringDashboardScreen extends StatefulWidget {
  const MonitoringDashboardScreen({super.key});

  @override
  State<MonitoringDashboardScreen> createState() => _MonitoringDashboardScreenState();
}

class _MonitoringDashboardScreenState extends State<MonitoringDashboardScreen> {
  MonitoringDashboard? dashboard;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final d = await PlayerMonitoringService.getDashboard();
    setState(() {
      dashboard = d;
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
        title: const Text('Wellness Monitoring'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboard,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : dashboard == null
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
                        onPressed: _loadDashboard,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDashboard,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Readiness Score Card
                        _ReadinessCard(score: dashboard!.readinessScore),
                        const SizedBox(height: 16),

                        // Body Metrics
                        if (dashboard!.bodyMetric != null)
                          _MetricRow(
                            icon: Icons.favorite_rounded,
                            label: 'Body Fat',
                            value: '${dashboard!.bodyMetric!.bodyFatPercent}%',
                            subtitle: dashboard!.bodyMetric!.bmi != null ? 'BMI: ${dashboard!.bodyMetric!.bmi!.toStringAsFixed(1)}' : null,
                          ),

                        // Today Hooper
                        if (dashboard!.todayHooper != null) ...[
                          const SizedBox(height: 12),
                          _MetricRow(
                            icon: Icons.psychology_rounded,
                            label: 'Hooper Index',
                            value: dashboard!.todayHooper!.hooperScore.toString(),
                            valueColor: dashboard!.todayHooper!.status == 'normal'
                                ? AppColors.success
                                : dashboard!.todayHooper!.status == 'moderate'
                                    ? AppColors.warning
                                    : AppColors.destructive,
                          ),
                        ],

                        // Last RPE
                        if (dashboard!.lastRpe != null) ...[
                          const SizedBox(height: 12),
                          _MetricRow(
                            icon: Icons.fitness_center_rounded,
                            label: 'Last Training Load',
                            value: dashboard!.lastRpe!.trainingLoad.toString(),
                          ),
                        ],

                        const SizedBox(height: 16),
                        Divider(color: Colors.white.withOpacity(0.1)),
                        const SizedBox(height: 16),

                        // ACWR & Load Ratio
                        _InfoCard(
                          title: 'Load Ratio (ACWR)',
                          subtitle: 'Acute / Chronic',
                          value: dashboard!.acwr.toStringAsFixed(2),
                          color: dashboard!.acwr > 1.5 ? AppColors.destructive : dashboard!.acwr > 1.3 ? AppColors.warning : AppColors.success,
                        ),

                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _InfoCard(
                                title: 'Acute Load',
                                subtitle: '7 days avg',
                                value: dashboard!.acuteLoad.toStringAsFixed(0),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _InfoCard(
                                title: 'Chronic Load',
                                subtitle: '28 days avg',
                                value: dashboard!.chronicLoad.toStringAsFixed(0),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Alerts
                        if (dashboard!.alerts.isNotEmpty) ...[
                          _SectionHeader('Alerts'),
                          const SizedBox(height: 8),
                          for (final alert in dashboard!.alerts) ...[
                            _AlertBox(alert),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 16),
                        ],

                        // Insights
                        if (dashboard!.insights.isNotEmpty) ...[
                          _SectionHeader('AI Insights'),
                          const SizedBox(height: 8),
                          for (final insight in dashboard!.insights) ...[
                            _InsightBox(insight),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 16),
                        ],

                        // Recommendations
                        if (dashboard!.recommendations.isNotEmpty) ...[
                          _SectionHeader('Recommendations'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final rec in dashboard!.recommendations)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primarySoft,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    rec,
                                    style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Weekly Loads Chart
                        _SectionHeader('Weekly Load'),
                        const SizedBox(height: 12),
                        _WeeklyChart(loads: dashboard!.weeklyLoads),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 70 ? AppColors.success : score >= 40 ? AppColors.warning : AppColors.destructive;
    final progressWidth = (score / 100) * 280;
    final statusText = score >= 70 ? '✅ Ready to go' : score >= 40 ? '⚠️ Monitor closely' : '🛑 High risk';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text('Readiness Score', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
          const SizedBox(height: 12),
          Text('$score/100', style: TextStyle(color: color, fontSize: 48, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(color: color.withOpacity(0.2)),
                  Container(
                    width: progressWidth,
                    color: color,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            statusText,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
  });
  final IconData icon;
  final String label, value;
  final String? subtitle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                if (subtitle != null) Text(subtitle!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Text(value, style: TextStyle(color: valueColor ?? AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.value,
    this.color,
  });
  final String title, subtitle, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color ?? AppColors.primary, fontWeight: FontWeight.w700, fontSize: 20)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
        ],
      ),
    );
  }
}

class _AlertBox extends StatelessWidget {
  const _AlertBox(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.destructive.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.destructive.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_rounded, color: AppColors.destructive, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }
}

class _InsightBox extends StatelessWidget {
  const _InsightBox(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_rounded, color: AppColors.gold, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.loads});
  final List<int> loads;

  @override
  Widget build(BuildContext context) {
    final maxLoad = loads.isEmpty ? 1 : loads.reduce((a, b) => a > b ? a : b).toDouble().clamp(1, double.infinity);
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (int i = 0; i < loads.length; i++)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (loads[i] > 0)
                        Tooltip(
                          message: loads[i].toString(),
                          child: Container(
                            width: 18,
                            height: (loads[i] / maxLoad) * 80,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        )
                      else
                        Container(width: 18, height: 0),
                      const SizedBox(height: 4),
                      Text(days[i], style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
