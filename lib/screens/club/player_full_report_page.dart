import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../services/club_service.dart';

/// Aggregated player report — profile, readiness, training attendance, match
/// stats, assessment scores, and a coach-safe medical summary (status/counts
/// only). Opened from club_player_profile_page.dart.
class PlayerFullReportPage extends StatefulWidget {
  const PlayerFullReportPage({super.key, required this.playerId, required this.playerName});
  final String playerId;
  final String playerName;

  @override
  State<PlayerFullReportPage> createState() => _PlayerFullReportPageState();
}

class _PlayerFullReportPageState extends State<PlayerFullReportPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ClubService().getPlayerFullReport(widget.playerId);
    if (!mounted) return;
    setState(() {
      _data = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2))
                  : _data == null
                      ? Center(child: Text(AppLocalizations.get('error_generic'),
                          style: const TextStyle(color: AppColors.muted)))
                      : RefreshIndicator(
                          color: AppColors.primary,
                          backgroundColor: AppColors.card,
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                            children: [
                              _buildReadinessCard(),
                              const SizedBox(height: 16),
                              _buildTrainingLoadCard(),
                              const SizedBox(height: 16),
                              _buildTrainingCard(),
                              const SizedBox(height: 16),
                              _buildMatchesCard(),
                              const SizedBox(height: 16),
                              _buildAssessmentsCard(),
                              const SizedBox(height: 16),
                              _buildMedicalCard(),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: AppColors.surface2, shape: BoxShape.circle,
                border: Border.all(color: AppColors.border)),
            child: const Icon(Icons.arrow_back_rounded,
                color: AppColors.foreground, size: 18),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text('${AppLocalizations.get('player_full_report_title')} — ${widget.playerName}',
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w900, fontSize: 16),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
            color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _statTile(String value, String label, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600),
            maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildReadinessCard() {
    final readiness = _data!['readiness'] as Map?;
    return _sectionCard(
      title: AppLocalizations.get('team_status_today'),
      child: readiness == null
          ? Text(AppLocalizations.get('status_missing_readiness'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12))
          : Row(children: [
              Expanded(child: _statTile('${readiness['hooper_score']}', 'Hooper', AppColors.primary)),
              Expanded(child: _statTile('${readiness['fatigue']}', AppLocalizations.get('kpi_fatigue'), AppColors.warning)),
              Expanded(child: _statTile('${readiness['sleep_quality']}', AppLocalizations.get('sleep_quality'), AppColors.success)),
            ]),
    );
  }

  Widget _buildTrainingCard() {
    final t = (_data!['training_30d'] as Map?)?.cast<String, dynamic>() ?? {};
    return _sectionCard(
      title: '${AppLocalizations.get('last_30_days_label')}',
      child: Row(children: [
        Expanded(child: _statTile('${t['present'] ?? 0}', AppLocalizations.get('present_players'), AppColors.success)),
        Expanded(child: _statTile('${t['late'] ?? 0}', AppLocalizations.get('attendance_late'), AppColors.warning)),
        Expanded(child: _statTile('${t['absent'] ?? 0}', AppLocalizations.get('attendance_absent'), AppColors.destructive)),
      ]),
    );
  }

  Widget _buildTrainingLoadCard() {
    final load =
        (_data!['training_load'] as Map?)?.cast<String, dynamic>() ?? {};
    final acute = (load['acute_load_7d'] as num?)?.toDouble();
    final chronic =
        (load['chronic_load_weekly_average'] as num?)?.toDouble();
    final acwr = (load['acwr'] as num?)?.toDouble();
    final classification =
        load['classification']?.toString() ?? 'INSUFFICIENT_DATA';
    final statusColor = _acwrColor(classification);

    return _sectionCard(
      title: 'مراقبة الحمل التدريبي',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statTile(
                  _loadValue(acute),
                  'الحمل الحاد\n7 أيام',
                  AppColors.primary,
                ),
              ),
              Expanded(
                child: _statTile(
                  _loadValue(chronic),
                  'الحمل المزمن\nمتوسط 4 أسابيع',
                  AppColors.parentAccent,
                ),
              ),
              Expanded(
                child: _statTile(
                  acwr?.toStringAsFixed(2) ?? '—',
                  'ACWR',
                  statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withOpacity(0.35)),
            ),
            child: Text(
              _acwrLabel(classification),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _loadValue(double? value) =>
      value == null ? '—' : value.toStringAsFixed(0);

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
        return 'حمل ضعيف — أقل من 0.8';
      case 'IN_TARGET':
        return 'المنطقة المثالية والآمنة — من 0.8 إلى 1.3';
      case 'CAUTION':
        return 'منطقة تنبيه وإجهاد متوسط — أكبر من 1.3 إلى 1.5';
      case 'ABOVE_TARGET':
        return 'خطر إجهاد مفرط — أكبر من 1.5';
      case 'NO_CHRONIC_LOAD':
        return 'لا يوجد حمل مزمن كافٍ للحساب';
      default:
        return 'يتطلب حساب ACWR نافذة تاريخية مكتملة';
    }
  }

  Widget _buildMatchesCard() {
    final m = (_data!['matches_90d'] as Map?)?.cast<String, dynamic>() ?? {};
    return _sectionCard(
      title: AppLocalizations.get('matches_90d_label'),
      child: Column(children: [
        Row(children: [
          Expanded(child: _statTile('${m['appearances'] ?? 0}', AppLocalizations.get('appearances_label'), AppColors.foreground)),
          Expanded(child: _statTile('${m['starts'] ?? 0}', AppLocalizations.get('starts_label'), AppColors.foreground)),
          Expanded(child: _statTile('${m['minutes'] ?? 0}', AppLocalizations.get('total_minutes_label'), AppColors.foreground)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _statTile('${m['goals'] ?? 0}', AppLocalizations.get('match_goals_label'), AppColors.primary)),
          Expanded(child: _statTile('${m['assists'] ?? 0}', AppLocalizations.get('match_assists_label'), AppColors.primary)),
          Expanded(child: _statTile('${m['yellow_cards'] ?? 0} / ${m['red_cards'] ?? 0}', AppLocalizations.get('total_cards_label'), AppColors.warning)),
        ]),
      ]),
    );
  }

  Widget _buildAssessmentsCard() {
    final a = (_data!['assessments'] as Map?)?.cast<String, dynamic>() ?? {};
    final latest = a['latest_score'];
    return _sectionCard(
      title: AppLocalizations.get('assessments_label'),
      child: latest == null
          ? Text(AppLocalizations.get('no_players_yet'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12))
          : Row(children: [
              Expanded(child: _statTile('${latest.toStringAsFixed(0)}', AppLocalizations.get('assessments_label'), AppColors.primary)),
              Expanded(child: _statTile('${a['movement_score'] ?? '—'}', 'Movement', AppColors.foreground)),
              Expanded(child: _statTile('${a['stability_score'] ?? '—'}', 'Stability', AppColors.foreground)),
              Expanded(child: _statTile('${a['symmetry_score'] ?? '—'}', 'Symmetry', AppColors.foreground)),
            ]),
    );
  }

  Widget _buildMedicalCard() {
    final med = (_data!['medical'] as Map?)?.cast<String, dynamic>() ?? {};
    return _sectionCard(
      title: AppLocalizations.get('open_injury_cases_label'),
      child: Row(children: [
        Expanded(child: _statTile('${med['open_injury_cases'] ?? 0}', AppLocalizations.get('open_injury_cases_label'), AppColors.destructive)),
        Expanded(child: _statTile('${med['physio_sessions_30d'] ?? 0}', AppLocalizations.get('physio_sessions_today_label'), AppColors.primary)),
      ]),
    );
  }
}
