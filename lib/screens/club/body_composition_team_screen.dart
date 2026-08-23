import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/body_composition_models.dart';
import '../../services/body_composition_service.dart';
import '../../utils/metric_formatter.dart';
import 'body_composition_list_page.dart';

class BodyCompositionTeamScreen extends StatefulWidget {
  const BodyCompositionTeamScreen({super.key});

  @override
  State<BodyCompositionTeamScreen> createState() =>
      _BodyCompositionTeamScreenState();
}

class _BodyCompositionTeamScreenState extends State<BodyCompositionTeamScreen> {
  TeamBodyCompositionSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await BodyCompositionService.getTeamSummary();
    if (mounted)
      setState(() {
        _summary = s;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = getAppLanguage() == 'ar';
    final s = _summary;
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.foreground,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: Text(
            AppLocalizations.get('bc_team_kpi_title'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppColors.muted),
              onPressed: _load,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BodyCompositionListPage()),
          ),
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.list_alt_rounded, color: AppColors.foreground),
          label: Text(
            AppLocalizations.get('bc_list_title'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : s == null
            ? Center(child: Text(AppLocalizations.get('bc_no_history')))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                backgroundColor: AppColors.card,
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.6,
                      children: [
                        _kpiTile(
                          AppLocalizations.get('bc_team_measured_this_month'),
                          '${s.measuredThisMonth}',
                          AppColors.success,
                          Icons.event_available_rounded,
                        ),
                        _kpiTile(
                          AppLocalizations.get('bc_team_overdue'),
                          '${s.overdueCount}',
                          AppColors.destructive,
                          Icons.event_busy_rounded,
                        ),
                        _kpiTile(
                          AppLocalizations.get('bc_team_avg_weight'),
                          MetricFormatter.weight(s.avgWeightKg),
                          AppColors.primary,
                          Icons.scale_outlined,
                        ),
                        _kpiTile(
                          AppLocalizations.get('bc_team_avg_body_fat'),
                          MetricFormatter.bodyFat(s.avgBodyFatPercentage),
                          AppColors.warning,
                          Icons.pie_chart_outline_rounded,
                        ),
                        _kpiTile(
                          AppLocalizations.get('bc_team_avg_fat_mass'),
                          MetricFormatter.fatMass(s.avgFatMassKg),
                          AppColors.warning,
                          Icons.opacity_rounded,
                        ),
                        _kpiTile(
                          AppLocalizations.get('bc_team_avg_lean_mass'),
                          MetricFormatter.fatFreeMass(s.avgFatFreeMassKg),
                          AppColors.success,
                          Icons.fitness_center_rounded,
                        ),
                        _kpiTile(
                          AppLocalizations.get('bc_team_in_goal'),
                          '${s.inGoalCount}',
                          AppColors.success,
                          Icons.flag_outlined,
                        ),
                        _kpiTile(
                          AppLocalizations.get('bc_team_needs_follow_up'),
                          '${s.needsFollowUpCount}',
                          AppColors.destructive,
                          Icons.report_gmailerrorred_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (s.biggestImprovement != null)
                      _changeCard(
                        AppLocalizations.get('bc_team_biggest_improvement'),
                        s.biggestImprovement!,
                        AppColors.success,
                      ),
                    if (s.biggestRegression != null) ...[
                      const SizedBox(height: 10),
                      _changeCard(
                        AppLocalizations.get('bc_team_biggest_regression'),
                        s.biggestRegression!,
                        AppColors.destructive,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _kpiTile(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: AppColors.foreground.withOpacity(0.5),
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _changeCard(String title, Map<String, dynamic> entry, Color color) {
    final name = entry['player_name']?.toString() ?? '—';
    final diff = entry['diff'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.55),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          Text(
            diff != null ? '${diff > 0 ? '+' : ''}$diff%' : '—',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
