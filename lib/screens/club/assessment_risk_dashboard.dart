import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import 'club_player_profile_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class PlayerAssessmentSummary {
  const PlayerAssessmentSummary({
    required this.id,
    required this.name,
    required this.position,
    required this.team,
    required this.riskLevel,
    required this.riskFlags,
    required this.assessments,
    this.latestDate,
  });

  final String id;
  final String name;
  final String? position;
  final String? team;
  final String riskLevel; // 'high' | 'medium' | 'low' | 'none'
  final List<String> riskFlags;
  final Map<String, TypeAssessmentSummary> assessments;
  final String? latestDate;

  factory PlayerAssessmentSummary.fromMap(Map<String, dynamic> m) {
    final rawA = m['assessments'] as Map<String, dynamic>? ?? {};
    final assessments = <String, TypeAssessmentSummary>{};
    rawA.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        assessments[k] = TypeAssessmentSummary.fromMap(v);
      }
    });
    return PlayerAssessmentSummary(
      id:          m['id'] as String? ?? '',
      name:        m['name'] as String? ?? '',
      position:    m['position'] as String?,
      team:        m['team'] as String?,
      riskLevel:   m['risk_level'] as String? ?? 'none',
      riskFlags:   List<String>.from(m['risk_flags'] as List? ?? []),
      assessments: assessments,
      latestDate:  m['latest_date'] as String?,
    );
  }
}

class TypeAssessmentSummary {
  const TypeAssessmentSummary({
    required this.score,
    required this.date,
    required this.trend,
  });
  final int score;
  final String? date;
  final String trend; // 'improving'|'declining'|'stable'|'no_data'

  factory TypeAssessmentSummary.fromMap(Map<String, dynamic> m) =>
      TypeAssessmentSummary(
        score: (m['score'] as num?)?.toInt() ?? 0,
        date:  m['date'] as String?,
        trend: m['trend'] as String? ?? 'no_data',
      );
}

class AssessmentSummaryData {
  const AssessmentSummaryData({
    required this.players,
    required this.totalPlayers,
    required this.assessedThisWeek,
    required this.highRiskCount,
    required this.mediumRiskCount,
    required this.avgByType,
  });

  final List<PlayerAssessmentSummary> players;
  final int totalPlayers;
  final int assessedThisWeek;
  final int highRiskCount;
  final int mediumRiskCount;
  final Map<String, double> avgByType;

  factory AssessmentSummaryData.fromMap(Map<String, dynamic> m) {
    final rawP = m['players'] as List? ?? [];
    final rawS = m['summary'] as Map<String, dynamic>? ?? {};
    final rawA = rawS['avg_by_type'] as Map<String, dynamic>? ?? {};
    return AssessmentSummaryData(
      players:          rawP.map((p) => PlayerAssessmentSummary.fromMap(p as Map<String, dynamic>)).toList(),
      totalPlayers:     (rawS['total_players'] as num?)?.toInt() ?? 0,
      assessedThisWeek: (rawS['assessed_this_week'] as num?)?.toInt() ?? 0,
      highRiskCount:    (rawS['high_risk_count'] as num?)?.toInt() ?? 0,
      mediumRiskCount:  (rawS['medium_risk_count'] as num?)?.toInt() ?? 0,
      avgByType:        rawA.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Assessment Risk Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class AssessmentRiskDashboard extends StatefulWidget {
  const AssessmentRiskDashboard({super.key});

  @override
  State<AssessmentRiskDashboard> createState() => _AssessmentRiskDashboardState();
}

class _AssessmentRiskDashboardState extends State<AssessmentRiskDashboard> {
  AssessmentSummaryData? _data;
  bool _loading = true;
  String _filter = 'all'; // 'all' | 'high' | 'medium'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await ApiService.getAssessmentSummary();
      if (mounted && raw.isNotEmpty) {
        setState(() => _data = AssessmentSummaryData.fromMap(raw));
      }
    } catch (e) {
      AppLogger.e('RiskDashboard', 'Load failed', e);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<PlayerAssessmentSummary> get _filtered {
    final all = _data?.players ?? [];
    if (_filter == 'all') return all;
    return all.where((p) => p.riskLevel == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(child: Center(
                child: CircularProgressIndicator(color: AppColors.primary)))
            else if (_data == null)
              Expanded(child: _buildEmpty())
            else ...[
              _buildKpiRow(),
              _buildFilterRow(),
              Expanded(child: _buildPlayerList()),
            ],
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface2, shape: BoxShape.circle,
                border: Border.all(color: AppColors.border)),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.foreground, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.get('risk_dashboard_title'),
                    style: const TextStyle(color: AppColors.foreground,
                        fontWeight: FontWeight.w900, fontSize: 16)),
                Text(AppLocalizations.get('risk_dashboard_subtitle'),
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _load,
            child: const Icon(Icons.refresh_rounded,
                color: AppColors.muted, size: 20),
          ),
        ],
      ),
    );
  }

  // ── KPI Row ────────────────────────────────────────────────────────────────

  Widget _buildKpiRow() {
    final d = _data!;
    final assessedPct = d.totalPlayers > 0
        ? (d.assessedThisWeek / d.totalPlayers * 100).round()
        : 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          _kpi('${d.highRiskCount}',   AppLocalizations.get('high_risk'),               AppColors.destructive),
          const SizedBox(width: 8),
          _kpi('${d.mediumRiskCount}', AppLocalizations.get('medium_risk_label'),        AppColors.warning),
          const SizedBox(width: 8),
          _kpi('$assessedPct%',        AppLocalizations.get('assessed_this_week_kpi'),   AppColors.primary),
          const SizedBox(width: 8),
          _kpi('${d.totalPlayers}',    AppLocalizations.get('nav_players'),               AppColors.muted),
        ],
      ),
    );
  }

  Widget _kpi(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(color: color, fontSize: 20,
                    fontWeight: FontWeight.w900, height: 1.1)),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted,
                    fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Filter Row ─────────────────────────────────────────────────────────────

  Widget _buildFilterRow() {
    final filters = [
      ('all',    AppLocalizations.get('filter_all_players')),
      ('high',   AppLocalizations.get('high_risk')),
      ('medium', AppLocalizations.get('medium_risk_label')),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: filters.map((f) {
          final active = _filter == f.$1;
          return GestureDetector(
            onTap: () => setState(() => _filter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsetsDirectional.only(end: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: active ? AppColors.primary : AppColors.border),
              ),
              child: Text(f.$2,
                  style: TextStyle(
                      color: active ? Colors.black : AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Player List ────────────────────────────────────────────────────────────

  Widget _buildPlayerList() {
    final players = _filtered;
    if (players.isEmpty) {
      return Center(
        child: Text(
          _filter == 'all'
              ? AppLocalizations.get('no_players_assessed')
              : AppLocalizations.get('no_filter_risk_players'),
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: players.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _PlayerRiskCard(
          player: players[i],
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ClubPlayerProfilePage(playerId: players[i].id),
            ));
            _load();
          },
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.assessment_outlined,
              color: AppColors.muted, size: 48),
          const SizedBox(height: 12),
          Text(AppLocalizations.get('no_assessment_data'),
              style: const TextStyle(color: AppColors.foreground, fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(AppLocalizations.get('run_assessments_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(AppLocalizations.get('try_again')),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Player Risk Card
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerRiskCard extends StatelessWidget {
  const _PlayerRiskCard({required this.player, required this.onTap});
  final PlayerAssessmentSummary player;
  final VoidCallback onTap;

  static const _riskColors = {
    'high':   AppColors.destructive,
    'medium': AppColors.warning,
    'low':    AppColors.success,
    'none':   AppColors.muted,
  };

  static String _riskLevelLabel(String level) {
    switch (level) {
      case 'high':   return AppLocalizations.get('high_risk');
      case 'medium': return AppLocalizations.get('medium_risk_label');
      case 'low':    return AppLocalizations.get('player_status_ready');
      default:       return level;
    }
  }

  static Map<String, String> get _flagLabels => {
    'knee_valgus':       AppLocalizations.get('risk_flag_knee_valgus'),
    'mild_valgus':       AppLocalizations.get('risk_flag_mild_valgus'),
    'high_asymmetry':    AppLocalizations.get('risk_flag_high_asymmetry'),
    'asymmetry':         AppLocalizations.get('risk_flag_asymmetry'),
    'poor_landing':      AppLocalizations.get('risk_flag_poor_landing'),
    'poor_squat':        AppLocalizations.get('risk_flag_poor_squat'),
    'poor_jump_power':   AppLocalizations.get('risk_flag_poor_jump_power'),
  };

  @override
  Widget build(BuildContext context) {
    final riskColor = _riskColors[player.riskLevel] ?? AppColors.muted;
    final initials  = player.name.isNotEmpty ? player.name[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: riskColor.withOpacity(
              player.riskLevel == 'none' ? 0.15 : 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: riskColor.withOpacity(0.15),
                  child: Text(initials,
                      style: TextStyle(color: riskColor,
                          fontWeight: FontWeight.w900, fontSize: 14)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(player.name,
                          style: const TextStyle(color: AppColors.foreground,
                              fontWeight: FontWeight.w800, fontSize: 14)),
                      Text(
                        '${player.position ?? '—'}  ·  ${player.team ?? '—'}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Risk badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: riskColor.withOpacity(0.35)),
                  ),
                  child: Text(
                    player.riskLevel == 'none'
                        ? AppLocalizations.get('no_data_label')
                        : _riskLevelLabel(player.riskLevel),
                    style: TextStyle(color: riskColor, fontSize: 11,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),

            // Risk flags
            if (player.riskFlags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: player.riskFlags.map((f) {
                  final label = _flagLabels[f] ?? f;
                  final isCritical = f == 'knee_valgus' || f == 'high_asymmetry';
                  final c = isCritical
                      ? AppColors.destructive
                      : AppColors.warning;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.withOpacity(0.30)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: c, size: 10),
                        const SizedBox(width: 3),
                        Text(label,
                            style: TextStyle(color: c, fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],

            // Per-type scores row
            if (player.assessments.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 8),
              _buildScoreRow(player.assessments),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreRow(Map<String, TypeAssessmentSummary> assessments) {
    final typeIcons = {
      'squat':               Icons.accessibility_new_rounded,
      'countermovementJump': Icons.arrow_upward_rounded,
      'squatJump':           Icons.trending_up_rounded,
      'dropJump':            Icons.south_rounded,
      'singleLegDropJump':   Icons.directions_run_rounded,
      'singleLegBalance':    Icons.sports_gymnastics_rounded,
      'jumpLanding':         Icons.arrow_downward_rounded,
    };
    final typeColors = {
      'squat':               AppColors.primary,
      'countermovementJump': const Color(0xffF59E0B),
      'squatJump':           const Color(0xffEF4444),
      'dropJump':            const Color(0xff06B6D4),
      'singleLegDropJump':   const Color(0xff8B5CF6),
      'singleLegBalance':    AppColors.coachAccent,
      'jumpLanding':         const Color(0xff7B68EE),
    };
    final trendIcons = {
      'improving': (Icons.trending_up_rounded,   Colors.greenAccent),
      'declining': (Icons.trending_down_rounded, Colors.redAccent),
      'stable':    (Icons.trending_flat_rounded, Colors.amber),
      'no_data':   (Icons.remove,               AppColors.muted),
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: assessments.entries.map((entry) {
          final type  = entry.key;
          final sum   = entry.value;
          final color = typeColors[type] ?? AppColors.muted;
          final icon  = typeIcons[type]  ?? Icons.sports_score_rounded;
          final (tIcon, tColor) = trendIcons[sum.trend] ?? (Icons.remove, AppColors.muted);
          final scoreColor = sum.score >= 75
              ? Colors.greenAccent
              : sum.score >= 55
                  ? Colors.amber
                  : Colors.redAccent;

          return Container(
            margin: const EdgeInsetsDirectional.only(end: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.20)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 13),
                const SizedBox(height: 4),
                Text('${sum.score}',
                    style: TextStyle(color: scoreColor,
                        fontWeight: FontWeight.w900, fontSize: 13)),
                Icon(tIcon, color: tColor, size: 11),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
