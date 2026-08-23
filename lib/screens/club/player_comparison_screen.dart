import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../models/coach_monitoring_models.dart';
import '../../services/club_service.dart';
import '../../services/coach_monitoring_service.dart';
import '../../services/readiness_helper.dart';
import '../../shared/club_status_color.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Player Comparison Screen — Coach only
// ─────────────────────────────────────────────────────────────────────────────

enum _CompareMode { assessment, readiness, hooper, rpe }

class PlayerComparisonScreen extends StatefulWidget {
  const PlayerComparisonScreen({super.key});

  @override
  State<PlayerComparisonScreen> createState() => _PlayerComparisonScreenState();
}

class _PlayerComparisonScreenState extends State<PlayerComparisonScreen> {
  List<_PlayerCompRow> _rows = [];
  _CompareMode _mode = _CompareMode.assessment;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ClubService().getPlayers(),
        CoachMonitoringService.getDashboard(),
      ]);

      final players   = results[0] as List<ClubPlayer>;
      final dashboard = results[1] as CoachDashboardData;

      // Build per-player map from wellness data
      final wellnessMap = <String, CoachPlayerStatus>{};
      for (final wp in dashboard.players) {
        wellnessMap[wp.id.toString()] = wp;
      }

      final rows = players.map((p) {
        final w = wellnessMap[p.id];
        final hooperScore = w?.hooperScore;
        final hooper = hooperScore != null && hooperScore > 0
            ? hooperScore.round() : null;
        final rpeValue = w?.rpe;
        final rpe    = rpeValue != null && rpeValue > 0
            ? rpeValue.round() : null;

        final readiness = ReadinessHelper.calculate(
          hooperScore:           hooper,
          lastRpe:               rpe,
          latestAssessmentScore: p.latestScore,
          trendDirection:        null,
        );

        return _PlayerCompRow(
          id:               p.id,
          name:             p.fullName,
          position:         p.position,
          initials:         p.initials,
          status:           p.status,
          assessmentScore:  p.latestScore,
          hooperScore:      hooper,
          rpeScore:         rpe,
          readiness:        readiness,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
          _sortRows();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sortRows() {
    _rows.sort((a, b) {
      switch (_mode) {
        case _CompareMode.assessment:
          final as_ = a.assessmentScore ?? -1;
          final bs_ = b.assessmentScore ?? -1;
          return bs_.compareTo(as_);
        case _CompareMode.readiness:
          return b.readiness.score.compareTo(a.readiness.score);
        case _CompareMode.hooper:
          final ah = a.hooperScore ?? 99;
          final bh = b.hooperScore ?? 99;
          return ah.compareTo(bh); // lower hooper = better
        case _CompareMode.rpe:
          final ar = a.rpeScore ?? 99;
          final br = b.rpeScore ?? 99;
          return ar.compareTo(br); // lower RPE = better
      }
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
            _buildModeChips(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary))
                  : _rows.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          color: AppColors.primary,
                          backgroundColor: AppColors.card,
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                            children: [
                              _buildSectionHeader(
                                  AppLocalizations.get('comparison_top5'),
                                  AppColors.success),
                              ..._topRows.asMap().entries.map(
                                    (e) => _buildRow(e.value, e.key + 1, true),
                                  ),
                              if (_bottomRows.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _buildSectionHeader(
                                    AppLocalizations.get('comparison_bottom5'),
                                    AppColors.destructive),
                                ..._bottomRows.asMap().entries.map(
                                      (e) => _buildRow(
                                          e.value,
                                          _rows.length - _bottomRows.length + e.key + 1,
                                          false),
                                    ),
                              ],
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  List<_PlayerCompRow> get _topRows {
    final count = (_rows.length).clamp(0, 5);
    return _rows.take(count).toList();
  }

  List<_PlayerCompRow> get _bottomRows {
    if (_rows.length <= 5) return [];
    final count = (_rows.length - 5).clamp(0, 5);
    return _rows.reversed.take(count).toList().reversed.toList();
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.foreground, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            AppLocalizations.get('comparison_title'),
            style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 17),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _load,
            child: const Icon(Icons.refresh_rounded,
                color: AppColors.muted, size: 20),
          ),
        ],
      ),
    );
  }

  // ── Mode Chips ────────────────────────────────────────────────────────────

  Widget _buildModeChips() {
    final modes = [
      (_CompareMode.assessment, AppLocalizations.get('comparison_by_assessment'),
          Icons.sports_score_rounded),
      (_CompareMode.readiness, AppLocalizations.get('comparison_by_readiness'),
          Icons.shield_rounded),
      (_CompareMode.hooper, AppLocalizations.get('comparison_by_hooper'),
          Icons.monitor_heart_rounded),
      (_CompareMode.rpe, AppLocalizations.get('comparison_by_rpe'),
          Icons.speed_rounded),
    ];

    return Container(
      height: 48,
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: modes.map((m) {
          final active = _mode == m.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _mode = m.$1;
                _sortRows();
              }),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(m.$3,
                        size: 13,
                        color: active ? AppColors.foreground : AppColors.muted),
                    const SizedBox(height: 1),
                    Text(
                      m.$2,
                      style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          color: active ? AppColors.foreground : AppColors.muted),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Section Header ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4, height: 14,
            decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(title.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 9,
                  letterSpacing: 1.0)),
        ],
      ),
    );
  }

  // ── Player Row ────────────────────────────────────────────────────────────

  Widget _buildRow(_PlayerCompRow row, int rank, bool isTop) {
    final value = _rowValue(row);
    final color = _rowColor(row);
    final statusColor = clubStatusColor(row.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isTop
            ? AppColors.success.withOpacity(0.15)
            : AppColors.destructive.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.maroon, AppColors.maroonDark],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                  color: statusColor.withOpacity(0.4), width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(row.initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12)),
          ),
          const SizedBox(width: 10),
          // Name + position
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name.split(' ').first,
                  style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(row.position,
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 10)),
              ],
            ),
          ),
          // Value badge
          if (value != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.30)),
              ),
              child: Text(
                value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 14),
              ),
            )
          else
            Text('—', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ),
    );
  }

  String? _rowValue(_PlayerCompRow row) {
    switch (_mode) {
      case _CompareMode.assessment:
        return row.assessmentScore != null
            ? '${row.assessmentScore!.round()}'
            : null;
      case _CompareMode.readiness:
        return '${row.readiness.score}';
      case _CompareMode.hooper:
        return row.hooperScore != null ? '${row.hooperScore}/28' : null;
      case _CompareMode.rpe:
        return row.rpeScore != null ? '${row.rpeScore}/10' : null;
    }
  }

  Color _rowColor(_PlayerCompRow row) {
    switch (_mode) {
      case _CompareMode.assessment:
        final s = row.assessmentScore ?? 0;
        if (s >= 75) return AppColors.success;
        if (s >= 55) return AppColors.warning;
        return AppColors.destructive;
      case _CompareMode.readiness:
        return row.readiness.color;
      case _CompareMode.hooper:
        final h = row.hooperScore ?? 0;
        if (h <= 10) return AppColors.success;
        if (h <= 16) return AppColors.warning;
        return AppColors.destructive;
      case _CompareMode.rpe:
        final r = row.rpeScore ?? 0;
        if (r <= 5) return AppColors.success;
        if (r <= 7) return AppColors.warning;
        return AppColors.destructive;
    }
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.group_outlined, color: AppColors.muted, size: 48),
          const SizedBox(height: 12),
          Text(AppLocalizations.get('no_players_yet'),
              style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        ],
      ),
    );
  }
}

// ── Data class ──────────────────────────────────────────────────────────────

class _PlayerCompRow {
  final String id, name, position, initials;
  final PlayerStatus status;
  final double? assessmentScore;
  final int? hooperScore, rpeScore;
  final ReadinessResult readiness;

  const _PlayerCompRow({
    required this.id,
    required this.name,
    required this.position,
    required this.initials,
    required this.status,
    required this.assessmentScore,
    required this.hooperScore,
    required this.rpeScore,
    required this.readiness,
  });
}
