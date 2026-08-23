import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/monitoring_models.dart';
import '../../models/training_load_models.dart';
import '../../services/player_monitoring_service.dart';
import '../../services/report_service.dart';
import '../../services/settings_service.dart';
import 'club_widgets.dart' show ReportDateRangeChip, showReportSectionsSheet;

class TeamWellnessScreen extends StatefulWidget {
  const TeamWellnessScreen({super.key});

  @override
  State<TeamWellnessScreen> createState() => _TeamWellnessScreenState();
}

class _TeamWellnessScreenState extends State<TeamWellnessScreen> {
  TeamWellness _wellness = TeamWellness(
    teamReadinessScore: 0,
    injuryRiskCount: 0,
    averageRpe: 0,
    weeklyLoad: 0,
    recoveryScore: 0,
    playersNeedingAttention: 0,
    totalCheckedIn: 0,
    hasReadinessData: false,
    hasAverageRpeData: false,
    hasWeeklyLoadData: false,
    hasPeriodLoadData: false,
    hasRecoveryData: false,
  );
  List<PlayerWellnessEntry> _players = [];
  bool _loading = true;
  bool _error = false;
  bool _exporting = false;
  DateTimeRange? _dateRange;
  Set<String> _sections = SettingsService.getReportSections(
    'team_wellness_sections',
  );

  static const _sectionOptions = <(String, String)>[
    ('readiness_hero', 'مؤشر الجاهزية العام'),
    ('kpi_row', 'بطاقات المؤشرات'),
    ('attention_banner', 'تنبيه اللاعبين المحتاجين متابعة'),
    ('player_list', 'قائمة اللاعبين'),
  ];

  void _showCustomizeSheet() {
    showReportSectionsSheet(
      context: context,
      options: _sectionOptions,
      initial: _sections,
      onSave: (sel) {
        setState(() => _sections = sel);
        SettingsService.setReportSections('team_wellness_sections', sel);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await Future.wait([
        PlayerMonitoringService.getTeamWellness(
          from: _dateRange?.start,
          to: _dateRange?.end,
          throwOnError: true,
        ),
        PlayerMonitoringService.getPlayerWellnessList(throwOnError: true),
      ]);
      if (!mounted) return;
      final w = results[0] as TeamWellness?;
      final p = results[1] as List<PlayerWellnessEntry>;
      // Sort: high_risk → moderate → normal → no_data
      final sorted = [...p]
        ..sort((a, b) {
          const order = {
            'high_risk': 0,
            'moderate': 1,
            'normal': 2,
            'no_data': 3,
          };
          return (order[a.wellnessStatus] ?? 9).compareTo(
            order[b.wellnessStatus] ?? 9,
          );
        });
      setState(() {
        _wellness = w ?? _wellness;
        _players = sorted;
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
        });
    }
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await Printing.layoutPdf(
        onLayout: (format) => ReportService.instance.generateTeamWellnessReportPdf(
          wellness: _wellness,
          players: _players,
          metadata: ReportMetadata(
            team: 'الفريق',
            season: 'الموسم النشط',
            period: _dateRange == null
                ? 'اليوم'
                : '${_dateRange!.start.toIso8601String().split('T').first} — '
                      '${_dateRange!.end.toIso8601String().split('T').first}',
            issuedBy: currentUserName,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _loading
            ? _buildLoading()
            : _error
            ? _buildError()
            : RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.card,
                strokeWidth: 2,
                onRefresh: _load,
                child: CustomScrollView(
                  slivers: [
                    _buildAppBar(),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          const SizedBox(height: 16),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ReportDateRangeChip(
                              value: _dateRange,
                              onChanged: (range) {
                                setState(() => _dateRange = range);
                                _load();
                              },
                            ),
                          ),
                          if (_sections.contains('readiness_hero')) ...[
                            const SizedBox(height: 14),
                            _buildReadinessHero(),
                          ],
                          if (_sections.contains('kpi_row')) ...[
                            const SizedBox(height: 14),
                            _buildKpiRow(),
                          ],
                          if (_sections.contains('attention_banner') &&
                              _wellness.playersNeedingAttention > 0) ...[
                            const SizedBox(height: 14),
                            _buildAttentionBanner(),
                          ],
                          if (_sections.contains('player_list')) ...[
                            const SizedBox(height: 20),
                            _buildPlayerListSection(),
                          ],
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
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
        AppLocalizations.get('team_wellness'),
        style: const TextStyle(
          color: AppColors.foreground,
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.tune_rounded,
            color: AppColors.muted,
            size: 20,
          ),
          tooltip: AppLocalizations.get('report_customize_sections'),
          onPressed: _showCustomizeSheet,
        ),
        IconButton(
          icon: const Icon(
            Icons.fitness_center_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          tooltip: 'تقرير الحمل التدريبي للفريق',
          onPressed: () =>
              Navigator.of(context).pushNamed('/club/reports/training-load'),
        ),
        if (_players.isNotEmpty)
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
            tooltip: 'تصدير PDF',
            onPressed: _exporting ? null : _exportPdf,
          ),
        IconButton(
          icon: const Icon(
            Icons.refresh_rounded,
            color: AppColors.muted,
            size: 22,
          ),
          onPressed: _load,
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.primary.withOpacity(0.12)),
      ),
    );
  }

  // ── Hero Readiness Score ─────────────────────────────────────────────────

  Widget _buildReadinessHero() {
    final score = _wellness.teamReadinessScore;
    final hasData = _wellness.hasReadinessData;
    final Color scoreColor = !hasData
        ? AppColors.muted
        : score >= 70
        ? AppColors.success
        : score >= 40
        ? AppColors.warning
        : AppColors.destructive;
    final String statusKey = score >= 70
        ? 'readiness_good'
        : score >= 40
        ? 'wellness_moderate'
        : 'high_risk';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scoreColor.withOpacity(0.30)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Row(
        children: [
          // Circular score indicator
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: hasData ? score / 100 : 0,
                    strokeWidth: 6,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasData ? '$score' : '—',
                      style: TextStyle(
                        color: scoreColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                        height: 1.0,
                      ),
                    ),
                    if (hasData)
                      Text(
                        '%',
                        style: TextStyle(
                          color: scoreColor.withOpacity(0.70),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.get('team_readiness'),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scoreColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scoreColor.withOpacity(0.30)),
                  ),
                  child: Text(
                    hasData
                        ? AppLocalizations.get(statusKey)
                        : 'بيانات غير كافية',
                    style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Progress track
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: hasData ? score / 100 : 0,
                    minHeight: 5,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLocalizations.format('players_checked_in', {
                    'count': _wellness.totalCheckedIn,
                  }),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── KPI Row ──────────────────────────────────────────────────────────────

  Widget _buildKpiRow() {
    final periodDays = _wellness.rangeFrom != null && _wellness.rangeTo != null
        ? _wellness.rangeTo!.difference(_wellness.rangeFrom!).inDays + 1
        : 1;
    final items = [
      _KpiItem(
        icon: Icons.warning_amber_rounded,
        value: '${_wellness.injuryRiskCount}',
        label: AppLocalizations.get('injury_risk'),
        color: _wellness.injuryRiskCount > 0
            ? AppColors.destructive
            : AppColors.success,
      ),
      _KpiItem(
        icon: Icons.speed_rounded,
        value: _wellness.hasAverageRpeData
            ? _wellness.averageRpe.toStringAsFixed(1)
            : '—',
        label: AppLocalizations.get('average_rpe'),
        color: _wellness.hasAverageRpeData
            ? AppColors.warning
            : AppColors.muted,
      ),
      _KpiItem(
        icon: Icons.fitness_center_rounded,
        value: _wellness.hasPeriodLoadData && _wellness.periodLoad != null
            ? _wellness.periodLoad!.toStringAsFixed(0)
            : '—',
        label: periodLoadLabel(periodDays),
        color: _wellness.hasPeriodLoadData ? AppColors.risk : AppColors.muted,
      ),
      _KpiItem(
        icon: Icons.restore_rounded,
        value: _wellness.hasRecoveryData ? '${_wellness.recoveryScore}%' : '—',
        label: AppLocalizations.get('recovery_score'),
        color: !_wellness.hasRecoveryData
            ? AppColors.muted
            : _wellness.recoveryScore >= 70
            ? AppColors.success
            : _wellness.recoveryScore >= 40
            ? AppColors.warning
            : AppColors.destructive,
      ),
    ];

    return Row(
      children: items.asMap().entries.map((e) {
        final isLast = e.key == items.length - 1;
        return Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: isLast ? 0 : 8),
            child: _buildKpiCard(e.value),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKpiCard(_KpiItem k) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: k.color.withOpacity(0.22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: k.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(k.icon, color: k.color, size: 14),
          ),
          const SizedBox(height: 7),
          Text(
            k.value,
            style: TextStyle(
              color: k.color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            k.label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 9),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Attention Banner ──────────────────────────────────────────────────────

  Widget _buildAttentionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.destructive.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.destructive.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.destructive.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_rounded,
              color: AppColors.destructive,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.format('players_risk_msg', {
                'count': _wellness.playersNeedingAttention,
              }),
              style: const TextStyle(
                color: AppColors.destructive,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Player List ───────────────────────────────────────────────────────────

  Widget _buildPlayerListSection() {
    final submitted = _players
        .where((player) => player.hooperScore != null)
        .length;
    final missing = _players.length - submitted;
    final completion = _players.isEmpty
        ? 0
        : (submitted / _players.length * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            const Icon(Icons.group_rounded, color: AppColors.muted, size: 13),
            const SizedBox(width: 5),
            Text(
              AppLocalizations.get('player_wellness_section').toUpperCase(),
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 9,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            Text(
              '${_players.length}',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaChip(label: 'سجلوا $submitted', color: AppColors.success),
            _MetaChip(label: 'لم يسجلوا $missing', color: AppColors.warning),
            _MetaChip(label: 'الاكتمال $completion%', color: AppColors.primary),
          ],
        ),
        const SizedBox(height: 10),
        if (_players.isEmpty)
          _buildPlayersEmpty()
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: List.generate(_players.length, (i) {
                return _buildPlayerRow(
                  _players[i],
                  isLast: i == _players.length - 1,
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildPlayerRow(PlayerWellnessEntry p, {bool isLast = false}) {
    final color = _wellnessColor(p.wellnessStatus);
    final label = _wellnessLabel(p.wellnessStatus);
    final rec = _recText(p.wellnessStatus);
    final initials = _initials(p.name);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.maroon, AppColors.maroonDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.55), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 11),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    if (p.hooperScore != null) ...[
                      _MetaChip(label: 'H ${p.hooperScore}', color: color),
                      _MetaChip(
                        label:
                            'النوم ${p.sleepQuality?.toStringAsFixed(0) ?? 'غير متوفر'}',
                        color: color,
                      ),
                      _MetaChip(
                        label: 'التعب ${p.fatigue ?? 'غير متوفر'}',
                        color: color,
                      ),
                      _MetaChip(
                        label:
                            'ألم العضلات ${p.muscleSoreness?.toStringAsFixed(0) ?? 'غير متوفر'}',
                        color: color,
                      ),
                      _MetaChip(
                        label:
                            'الضغط ${p.stress?.toStringAsFixed(0) ?? 'غير متوفر'}',
                        color: color,
                      ),
                    ],
                    if (p.lastRpe != null) ...[
                      _MetaChip(
                        label: 'RPE ${p.lastRpe!.toStringAsFixed(1)}',
                        color: AppColors.warning,
                      ),
                      _MetaChip(
                        label:
                            'sRPE ${p.lastLoad?.toStringAsFixed(0) ?? 'غير متوفر'}',
                        color: AppColors.warning,
                      ),
                    ],
                    if (p.submittedAt != null)
                      _MetaChip(
                        label:
                            '${p.submittedAt!.hour.toString().padLeft(2, '0')}:${p.submittedAt!.minute.toString().padLeft(2, '0')}',
                        color: AppColors.muted,
                      ),
                    if (rec != null)
                      Text(
                        rec,
                        style: TextStyle(
                          color: color.withOpacity(0.80),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline_rounded, color: AppColors.muted, size: 36),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.get('no_wellness_data'),
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.get('wellness_empty_hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── States ────────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(
        color: AppColors.primary,
        strokeWidth: 2,
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.destructive.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              color: AppColors.destructive,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.get('failed_to_load'),
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                AppLocalizations.get('try_again'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _wellnessColor(String status) {
    switch (status) {
      case 'high_risk':
        return AppColors.destructive;
      case 'moderate':
        return AppColors.warning;
      case 'normal':
        return AppColors.success;
      default:
        return AppColors.muted;
    }
  }

  String _wellnessLabel(String status) {
    switch (status) {
      case 'high_risk':
        return AppLocalizations.get('high_risk');
      case 'moderate':
        return AppLocalizations.get('wellness_moderate');
      case 'normal':
        return AppLocalizations.get('kpi_ready');
      default:
        return AppLocalizations.get('no_data');
    }
  }

  String? _recText(String status) {
    switch (status) {
      case 'high_risk':
        return AppLocalizations.get('rec_reduce_load');
      case 'moderate':
        return AppLocalizations.get('rec_adjust_intensity');
      default:
        return null;
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _KpiItem {
  const _KpiItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String value, label;
  final Color color;
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
