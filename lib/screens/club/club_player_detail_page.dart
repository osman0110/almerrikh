import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/assessment_result_model.dart';
import '../../models/body_composition_models.dart';
import '../../models/club_models.dart';
import '../../models/player_profile_model.dart';
import '../../services/assessment_storage_service.dart';
import '../../services/body_composition_service.dart';
import '../../services/club_service.dart';
import '../../shared/club_status_color.dart';
import '../../shared/responsive.dart';
import '../../utils/app_logger.dart';
import '../../utils/metric_formatter.dart';
import '../physical_assessment/assessment_camera_page.dart';
import '../physical_assessment/web_pose_setup_screen.dart'
    if (dart.library.io) '../physical_assessment/web_pose_setup_screen_stub.dart';
import '../player/body_composition_entry_screen.dart';
import 'add_edit_player_page.dart';
import 'club_widgets.dart';
import 'competition_stats_section.dart';
import 'fms_summary_section.dart';
import 'management_load_summary_card.dart';
import 'player_status_summary_card.dart';

// Picker result discriminated union
sealed class _AssessmentChoice {
  const _AssessmentChoice();
}

class _DisciplineCard extends StatelessWidget {
  const _DisciplineCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] == 'suspended'
        ? 'موقوف'
        : data['status'] == 'available_warning'
            ? 'متاح مع تحذير'
            : 'متاح';
    return Card(
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _item('الحالة', status),
            _item('إجمالي الأصفر', '${data['yellow_cards_total'] ?? 0}'),
            _item('الدورة الحالية', '${data['current_yellow_cards'] ?? 0}'),
            _item('إجمالي الأحمر', '${data['red_cards_total'] ?? 0}'),
            _item('الإيقافات', '${data['suspensions_total'] ?? 0}'),
            _item('النشطة', '${data['active_suspensions'] ?? 0}'),
            _item('المنفذة', '${data['executed_suspensions'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _item(String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
        ],
      );
}

class _CameraChoice extends _AssessmentChoice {
  const _CameraChoice(this.type);
  final AssessmentTestType type;
}

class _ManualChoice extends _AssessmentChoice {
  const _ManualChoice();
}

// ─────────────────────────────────────────────────────────────────────────────
// Club Player Detail Page
// Route: /club/players/:playerId
// ─────────────────────────────────────────────────────────────────────────────

class ClubPlayerDetailPage extends StatefulWidget {
  const ClubPlayerDetailPage({super.key, required this.playerId});
  final String playerId;

  @override
  State<ClubPlayerDetailPage> createState() => _ClubPlayerDetailPageState();
}

class _ClubPlayerDetailPageState extends State<ClubPlayerDetailPage> {
  ClubPlayerDetail? _detail;
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    AppLogger.i('ClubPlayerDetail', 'initState playerId=${widget.playerId}');
    _load();
  }

  @override
  void didUpdateWidget(ClubPlayerDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerId != widget.playerId) {
      AppLogger.i(
        'ClubPlayerDetail',
        'playerId changed ${oldWidget.playerId} → ${widget.playerId}',
      );
      _load();
    }
  }

  Future<void> _load() async {
    final requestedId = widget.playerId;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _notFound = false;
      _detail = null;
    });
    try {
      AppLogger.i('ClubPlayerDetail', 'fetching player id=$requestedId');
      final detail = await ClubService().getPlayerDetail(requestedId);
      if (!mounted) return;
      // Guard: if widget was replaced while loading, discard stale result
      if (requestedId != widget.playerId) {
        AppLogger.w(
          'ClubPlayerDetail',
          'Stale result for $requestedId — widget now has ${widget.playerId}, ignoring',
        );
        return;
      }
      if (detail != null) {
        AppLogger.i(
          'ClubPlayerDetail',
          'loaded player id=${detail.player.id}, name=${detail.player.fullName}',
        );
        if (detail.player.id.isNotEmpty && detail.player.id != requestedId) {
          AppLogger.e(
            'ClubPlayerDetail',
            'ID MISMATCH: requested=$requestedId got=${detail.player.id}',
            'mismatch',
          );
        }
      }
      setState(() {
        _detail = detail;
        _notFound = detail == null;
        _loading = false;
      });
    } catch (e) {
      AppLogger.e('ClubPlayerDetail', 'Load failed for $requestedId', e);
      if (mounted)
        setState(() {
          _loading = false;
          _notFound = true;
        });
    }
  }

  Future<void> _editPlayer() async {
    final player = _detail?.player;
    if (player == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddEditPlayerPage(player: player)),
    );
    if (mounted) _load();
  }

  Future<void> _startAssessment() async {
    final player = _detail?.player;
    if (player == null || !mounted) return;

    final choice = await showModalBottomSheet<_AssessmentChoice>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: Responsive.bottomSheetMaxHeight(ctx),
        ),
        child: const SingleChildScrollView(child: _PlayerAssessmentPicker()),
      ),
    );
    if (!mounted || choice == null) return;

    if (choice is _ManualChoice) {
      await _startManualAssessment();
      return;
    }

    if (choice is _CameraChoice) {
      final args = AssessmentCameraArguments(
        player: PlayerProfile(
          id: player.id,
          name: player.fullName,
          heightCm: player.height?.toInt(),
          weightKg: player.weight?.toInt(),
          position: player.position,
        ),
        testType: choice.type,
      );
      if (kIsWeb) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WebPoseSetupScreen(cameraArgs: args),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AssessmentCameraPage(
              player: args.player,
              testType: args.testType,
            ),
          ),
        );
      }
      if (mounted) _load();
    }
  }

  Future<void> _startManualAssessment() async {
    final player = _detail?.player;
    if (player == null || !mounted) return;
    final result = await showModalBottomSheet<AssessmentResult>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ManualAssessmentSheet(player: player),
    );
    if (result != null && mounted) {
      await AssessmentStorageService.instance.saveAssessment(result);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_notFound || _detail == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _Header(
                title: AppLocalizations.get('player_not_found'),
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_off_rounded,
                        color: AppColors.muted,
                        size: 52,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        AppLocalizations.get('player_not_found'),
                        style: const TextStyle(
                          color: AppColors.foreground,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ID: ${widget.playerId}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _load,
                        child: Text(AppLocalizations.get('retry_btn')),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(AppLocalizations.get('back_btn')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final d = _detail!;
    final p = d.player;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: p.fullName,
              subtitle: '#${p.number}  ·  ${p.position}',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.card,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ClubSectionLabel(
                              AppLocalizations.get('overview_section'),
                            ),
                            _PlayerHeroCard(player: p),
                            const SizedBox(height: 24),
                            if (canManagePlayers) ...[
                              ClubSectionLabel(
                                AppLocalizations.get('quick_actions'),
                              ),
                              _ActionsCard(onEdit: _editPlayer),
                              const SizedBox(height: 24),
                            ],
                            ClubSectionLabel(
                              AppLocalizations.get('daily_readiness_title'),
                            ),
                            PlayerStatusSummaryCard(
                              wellness: d.wellness,
                              assessments: d.assessments,
                              player: p,
                              showMedicalNotes: canViewMedicalNotes,
                            ),
                            if (d.discipline != null) ...[
                              const SizedBox(height: 16),
                              ClubSectionLabel('البطاقات والإيقافات'),
                              _DisciplineCard(data: d.discipline!),
                            ],
                            if (d.wellness != null) ...[
                              const SizedBox(height: 12),
                              _WellnessCard(wellness: d.wellness!),
                            ],
                            if (isCoachRole) ...[
                              const SizedBox(height: 24),
                              ClubSectionLabel(
                                AppLocalizations.get('training_load'),
                              ),
                              ManagementLoadSummaryCard(
                                playerId: widget.playerId,
                              ),
                            ],
                            const SizedBox(height: 24),
                            ClubSectionLabel(
                              AppLocalizations.get('performance_metrics'),
                            ),
                            _PerformanceAssessmentCard(
                              assessments: d.assessments,
                              onStartAssessment: _startAssessment,
                              onAddManual: _startManualAssessment,
                              onViewReport: () => Navigator.of(context).pushNamed(
                                '/club/reports/player',
                                arguments: {
                                  'player_id': p.id,
                                  'player_name': p.fullName,
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            // FMS is a technical/clinical assessment for the
                            // physical coach and remains role-gated.
                            if (isCoachRole) ...[
                              const ClubSectionLabel(
                                'فحص الحركة الوظيفية (FMS)',
                              ),
                              FmsSummarySection(
                                playerId: widget.playerId,
                                playerName: p.fullName,
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (isCoachRole) ...[
                              ClubSectionLabel(
                                AppLocalizations.get('body_composition_title'),
                              ),
                              _BodyFatSection(
                                playerId: widget.playerId,
                                playerName: p.fullName,
                              ),
                              const SizedBox(height: 24),
                            ],
                            ClubSectionLabel(
                              AppLocalizations.get('competitions_title'),
                            ),
                            CompetitionStatsSection(
                              playerId: widget.playerId,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title, this.subtitle, required this.onBack});
  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Player Card
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerHeroCard extends StatelessWidget {
  const _PlayerHeroCard({required this.player});
  final ClubPlayer player;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final statusColor = clubStatusColor(p.status);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.hero,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.20)),
        boxShadow: [
          BoxShadow(
            color: AppColors.maroon.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar — show photo if available, fall back to initials on 404
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.10),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.55),
                    width: 2.5,
                  ),
                ),
                child: ClipOval(
                  child: p.profileImageUrl?.isNotEmpty == true
                      ? Image.network(
                          p.profileImageUrl!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              p.initials,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            p.initials,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.fullName,
                            style: const TextStyle(
                              color: AppColors.onDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.50),
                            ),
                          ),
                          child: Text(
                            '#${p.number}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.position,
                      style: const TextStyle(
                        color: AppColors.onDarkMuted,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (p.nickname?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        p.nickname!,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: statusColor.withOpacity(0.45),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            p.status.localizedLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withOpacity(0.12), height: 1),
          const SizedBox(height: 14),
          // Bio stats row — Expanded must be a DIRECT child of Row
          Row(
            children: [
              Expanded(
                child: _Bio(
                  label: AppLocalizations.get('bio_age'),
                  value: p.age > 0 ? '${p.age} yr' : '—',
                ),
              ),
              _BioDivider(),
              Expanded(
                child: _Bio(
                  label: AppLocalizations.get('bio_height'),
                  value: MetricFormatter.height(p.height),
                ),
              ),
              _BioDivider(),
              Expanded(
                child: _Bio(
                  label: AppLocalizations.get('bio_weight'),
                  value: MetricFormatter.weight(p.weight),
                ),
              ),
              _BioDivider(),
              Expanded(
                child: _Bio(
                  label: AppLocalizations.get('bio_foot'),
                  value: _cap(p.dominantFoot),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withOpacity(0.12), height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.group_rounded,
                color: AppColors.onDarkMuted,
                size: 13,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p.teamName ?? AppLocalizations.get('no_team'),
                  style: const TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (p.lastAssessmentAt != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.assessment_rounded,
                      color: AppColors.onDarkMuted,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.format('last_assessment_days_ago', {
                        'days': DateTime.now()
                            .difference(p.lastAssessmentAt!)
                            .inDays,
                      }),
                      style: const TextStyle(
                        color: AppColors.onDarkMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _cap(String s) =>
      s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

class _Bio extends StatelessWidget {
  const _Bio({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: AppColors.onDark,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(color: AppColors.onDarkMuted, fontSize: 10),
      ),
    ],
  );
}

class _BioDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 32,
    color: Colors.white.withOpacity(0.12),
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Score Rings Card
// ─────────────────────────────────────────────────────────────────────────────

class _PerformanceAssessmentCard extends StatelessWidget {
  const _PerformanceAssessmentCard({
    required this.assessments,
    required this.onStartAssessment,
    required this.onAddManual,
    required this.onViewReport,
  });

  final List<PlayerAssessment> assessments;
  final VoidCallback onStartAssessment;
  final VoidCallback onAddManual;
  final VoidCallback onViewReport;

  bool get hasAssessment => assessments.isNotEmpty;

  PlayerAssessment? get latest => hasAssessment ? assessments.first : null;

  double get score => latest?.effectiveScore ?? 0;

  String get scoreLabel {
    if (score >= 85) return AppLocalizations.get('score_excellent');
    if (score >= 75) return AppLocalizations.get('score_very_good');
    if (score >= 60) return AppLocalizations.get('score_good');
    return AppLocalizations.get('score_needs_improvement');
  }

  String _dateLabel(DateTime date) {
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: hasAssessment ? _withAssessment() : _withoutAssessment(),
    );
  }

  Widget _header() => Text(
        AppLocalizations.get('perf_assessment_title'),
        textAlign: TextAlign.start,
        style: const TextStyle(
          color: AppColors.foreground,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      );

  Widget _withoutAssessment() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.get('perf_assessment_empty'),
            textAlign: TextAlign.start,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          _PrimaryAssessmentButton(
            label: AppLocalizations.get('start_camera_assessment_btn'),
            icon: Icons.camera_alt_rounded,
            onTap: onStartAssessment,
          ),
          const SizedBox(height: 8),
          _SecondaryAssessmentButton(
            label: AppLocalizations.get('add_manual_assessment_btn'),
            icon: Icons.edit_note_rounded,
            onTap: onAddManual,
          ),
        ],
      );

  Widget _withAssessment() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${score.toStringAsFixed(0)} / 100',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      scoreLabel,
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                AppLocalizations.format(
                  'last_assessment_label',
                  {'date': _dateLabel(latest!.date)},
                ),
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
              Text(
                AppLocalizations.format(
                  'assessment_count_label',
                  {'count': assessments.length},
                ),
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 340;
              final buttons = [
                Expanded(
                  child: _PrimaryAssessmentButton(
                    label: AppLocalizations.get('view_report_btn'),
                    icon: Icons.description_outlined,
                    onTap: onViewReport,
                  ),
                ),
                Expanded(
                  child: _SecondaryAssessmentButton(
                    label: AppLocalizations.get('start_new_assessment_btn'),
                    icon: Icons.refresh_rounded,
                    onTap: onStartAssessment,
                  ),
                ),
              ];
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buttons[0],
                    const SizedBox(height: 8),
                    buttons[1],
                  ],
                );
              }
              return Row(
                children: [
                  buttons[0],
                  const SizedBox(width: 8),
                  buttons[1],
                ],
              );
            },
          ),
        ],
      );
}

class _PrimaryAssessmentButton extends StatelessWidget {
  const _PrimaryAssessmentButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 42,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 17),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.foreground,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      );
}

class _SecondaryAssessmentButton extends StatelessWidget {
  const _SecondaryAssessmentButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.muted,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Wellness Card
// ─────────────────────────────────────────────────────────────────────────────

class _WellnessCard extends StatelessWidget {
  const _WellnessCard({required this.wellness});
  final Map<String, dynamic> wellness;

  @override
  Widget build(BuildContext context) {
    final hs = wellness['hooper_score'] as int?;
    final fat = (wellness['body_fat'] as num?)?.toDouble();
    // last_rpe is intentionally not shown here — the "الحمل التدريبي وRPE"
    // section below (TrainingLoadSection) already shows RPE per day/session
    // with full context, so a bare "last RPE" number here just duplicated it.

    Color hColor = AppColors.muted;
    String hLabel = AppLocalizations.get('no_wellness_today');
    if (hs != null) {
      if (hs >= 17) {
        hColor = AppColors.destructive;
        hLabel = AppLocalizations.get('flag_high_fatigue');
      } else if (hs >= 13) {
        hColor = AppColors.warning;
        hLabel = AppLocalizations.get('flag_moderate_fatigue');
      } else {
        hColor = AppColors.success;
        hLabel = AppLocalizations.get('wellness_ready');
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                color: AppColors.success,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.get('daily_health_title'),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _WellnessMini(
                  label: 'Hooper',
                  value: hs != null ? '$hs/28' : '—',
                  sub: hLabel,
                  color: hColor,
                  icon: Icons.monitor_heart_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WellnessMini(
                  label: AppLocalizations.get('body_fat'),
                  value: MetricFormatter.bodyFat(fat),
                  sub: fat == null
                      ? AppLocalizations.get('not_measured')
                      : fat <= 18
                      ? AppLocalizations.get('excellent')
                      : fat <= 25
                      ? AppLocalizations.get('status_normal')
                      : AppLocalizations.get('needs_follow_up'),
                  color: fat == null
                      ? AppColors.muted
                      : fat <= 18
                      ? AppColors.success
                      : fat <= 25
                      ? AppColors.warning
                      : AppColors.destructive,
                  icon: Icons.monitor_weight_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WellnessMini extends StatelessWidget {
  const _WellnessMini({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final String sub;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(color: color, fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body Fat / Body Composition — coach-entry summary
// ─────────────────────────────────────────────────────────────────────────────

class _BodyFatSection extends StatefulWidget {
  const _BodyFatSection({required this.playerId, required this.playerName});
  final String playerId;
  final String playerName;

  @override
  State<_BodyFatSection> createState() => _BodyFatSectionState();
}

class _BodyFatSectionState extends State<_BodyFatSection> {
  BodyCompositionEntry? _latest;
  BodyCompositionEntry? _previous;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final history = await BodyCompositionService.getHistory(
      playerId: widget.playerId,
      limit: 2,
    );
    if (!mounted) return;
    setState(() {
      _latest = history.isNotEmpty ? history.first : null;
      _previous = history.length > 1 ? history[1] : null;
      _loading = false;
    });
  }

  Widget? _delta(double? current, double? prev, String unit) {
    if (current == null || prev == null) return null;
    final diff = current - prev;
    if (diff.abs() < 0.05) {
      return Text(
        AppLocalizations.get('no_change_since_last_measure'),
        style: const TextStyle(color: AppColors.muted, fontSize: 9),
      );
    }
    final up = diff > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          color: AppColors.muted,
          size: 10,
        ),
        const SizedBox(width: 2),
        Text(
          '${diff.abs().toStringAsFixed(1)}$unit منذ آخر قياس',
          style: const TextStyle(color: AppColors.muted, fontSize: 9),
        ),
      ],
    );
  }

  Future<void> _addNew() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BodyCompositionEntryScreen(playerId: widget.playerId),
      ),
    );
    if (saved == true) _load();
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BodyCompositionHistoryPage(
          playerId: widget.playerId,
          playerName: widget.playerName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.success,
          ),
        ),
      );
    }

    final e = _latest;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e == null)
            Row(
              children: [
                const Icon(
                  Icons.monitor_weight_rounded,
                  color: AppColors.muted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.get('bc_no_history'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _WellnessMini(
                        label: AppLocalizations.get('bc_body_fat_percentage'),
                        value: MetricFormatter.bodyFat(e.bodyFatPercentage),
                        sub: e.assessmentDate,
                        color: AppColors.destructive,
                        icon: Icons.pie_chart_outline_rounded,
                      ),
                      if (_delta(
                            e.bodyFatPercentage,
                            _previous?.bodyFatPercentage,
                            '%',
                          ) !=
                          null) ...[
                        const SizedBox(height: 4),
                        _delta(
                          e.bodyFatPercentage,
                          _previous?.bodyFatPercentage,
                          '%',
                        )!,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      _WellnessMini(
                        label: AppLocalizations.get('bc_weight_kg'),
                        value: MetricFormatter.weight(e.weightKg),
                        sub: e.assessmentDate,
                        color: AppColors.primary,
                        icon: Icons.scale_outlined,
                      ),
                      if (_delta(e.weightKg, _previous?.weightKg, 'كجم') !=
                          null) ...[
                        const SizedBox(height: 4),
                        _delta(e.weightKg, _previous?.weightKg, 'كجم')!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (canManageBodyComposition)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _addNew,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'إضافة تقييم جديد',
                      style: TextStyle(
                        color: AppColors.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (canManageBodyComposition) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _openHistory,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'عرض السجل السابق',
                    style: TextStyle(
                      color: AppColors.foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body Composition — full history for one player
// ─────────────────────────────────────────────────────────────────────────────

class _BodyCompositionHistoryPage extends StatefulWidget {
  const _BodyCompositionHistoryPage({
    required this.playerId,
    required this.playerName,
  });
  final String playerId;
  final String playerName;

  @override
  State<_BodyCompositionHistoryPage> createState() =>
      _BodyCompositionHistoryPageState();
}

class _BodyCompositionHistoryPageState
    extends State<_BodyCompositionHistoryPage> {
  List<BodyCompositionEntry> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await BodyCompositionService.getHistory(
      playerId: widget.playerId,
      limit: 50,
    );
    if (!mounted) return;
    setState(() {
      _history = h;
      _loading = false;
    });
  }

  void _showDetail(BodyCompositionEntry e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: Responsive.bottomSheetMaxHeight(ctx),
        ),
        child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.assessmentDate,
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _detailLine(
              AppLocalizations.get('bc_weight_kg'),
              MetricFormatter.weight(e.weightKg),
            ),
            _detailLine(
              AppLocalizations.get('bc_body_fat_percentage'),
              MetricFormatter.bodyFat(e.bodyFatPercentage),
            ),
            _detailLine(
              AppLocalizations.get('bc_fat_mass_kg'),
              MetricFormatter.fatMass(e.fatMassKg),
            ),
            _detailLine(
              AppLocalizations.get('bc_fat_free_mass_kg'),
              MetricFormatter.fatFreeMass(e.fatFreeMassKg),
            ),
            _detailLine(
              AppLocalizations.get('bc_skinfold_sum'),
              MetricFormatter.skinfold(e.skinfoldSumMm),
            ),
            if (e.assessedBy != null) ...[
              const SizedBox(height: 8),
              Text(
                '${AppLocalizations.get('bc_assessed_by')}: ${e.assessedBy}',
                style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.55),
                  fontSize: 12.5,
                ),
              ),
            ],
            if (e.notes != null && e.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${AppLocalizations.get('bc_notes')}: ${e.notes}',
                style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.55),
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.foreground.withOpacity(0.6),
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: AppLocalizations.get('body_composition_title'),
              subtitle: widget.playerName,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : _history.isEmpty
                  ? Center(
                      child: Text(
                        AppLocalizations.get('bc_no_history'),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final e = _history[i];
                        return GestureDetector(
                          onTap: () => _showDetail(e),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.assessmentDate,
                                        style: const TextStyle(
                                          color: AppColors.foreground,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${AppLocalizations.get('bc_weight_kg')}: ${MetricFormatter.weight(e.weightKg)}'
                                        '${e.bodyFatPercentage != null ? '  ·  ${AppLocalizations.get('bc_body_fat_percentage')}: ${MetricFormatter.bodyFat(e.bodyFatPercentage)}' : ''}',
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: AppColors.muted,
                                  size: 13,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions Card
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    this.onEdit,
  });
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (onEdit != null)
        _ActionBtn(
          icon: Icons.edit_rounded,
          label: AppLocalizations.get('edit_player'),
          color: AppColors.maroon,
          onTap: onEdit!,
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (int i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full Assessment Type Picker (used from player detail page — no session context)
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerAssessmentPicker extends StatelessWidget {
  const _PlayerAssessmentPicker();

  static const _tests = <(AssessmentTestType, String, String, IconData, Color)>[
    (
      AssessmentTestType.squat,
      'assessment_squat_title',
      'assessment_test_short_squat',
      Icons.accessibility_new_rounded,
      AppColors.maroon,
    ),
    (
      AssessmentTestType.countermovementJump,
      'assessment_cmj_title',
      'assessment_test_short_countermovementJump',
      Icons.arrow_upward_rounded,
      AppColors.gold,
    ),
    (
      AssessmentTestType.dropJump,
      'assessment_short_drop_jump',
      'assessment_test_short_dropJump',
      Icons.arrow_downward_rounded,
      AppColors.warning,
    ),
    (
      AssessmentTestType.singleLegDropJump,
      'assessment_sldj_title',
      'assessment_test_short_singleLegDropJump',
      Icons.directions_run_rounded,
      AppColors.playerAccent,
    ),
    (
      AssessmentTestType.squatJump,
      'assessment_short_squat_jump',
      'assessment_test_short_squatJump',
      Icons.sports_gymnastics_rounded,
      AppColors.primary,
    ),
    (
      AssessmentTestType.singleLegBalance,
      'assessment_slb_title',
      'assessment_test_short_singleLegBalance',
      Icons.sports_kabaddi_rounded,
      AppColors.success,
    ),
    (
      AssessmentTestType.jumpLanding,
      'assessment_jl_title',
      'assessment_test_short_jumpLanding',
      Icons.sports_score_rounded,
      AppColors.risk,
    ),
  ];

  static (String, Color)? _badge(AssessmentTestStatus s) {
    switch (s) {
      case AssessmentTestStatus.complete:
        return null;
      case AssessmentTestStatus.partial:
        return (AppLocalizations.get('test_status_partial'), AppColors.warning);
      case AssessmentTestStatus.demoOnly:
        return (AppLocalizations.get('test_status_demo'), AppColors.muted);
      case AssessmentTestStatus.notImplemented:
        return (AppLocalizations.get('test_status_not_implemented'), AppColors.risk);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            AppLocalizations.get('select_test'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 12),
          for (final t in _tests) ...[
            Builder(
              builder: (ctx) {
                final badge = _badge(t.$1.testStatus);
                return GestureDetector(
                  onTap: () => Navigator.of(context).pop(_CameraChoice(t.$1)),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: t.$5.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.$5.withOpacity(0.22)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: t.$5.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(t.$4, color: t.$5, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.get(t.$2),
                                style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppLocalizations.get(t.$3),
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                              if (badge != null) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badge.$2.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: badge.$2.withOpacity(0.3),
                                      width: 0.7,
                                    ),
                                  ),
                                  child: Text(
                                    badge.$1,
                                    style: TextStyle(
                                      color: badge.$2,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: t.$5.withOpacity(0.5),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(const _ManualChoice()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      color: AppColors.muted,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.get('manual_assessment_title'),
                          style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppLocalizations.get('manual_assessment_subtitle'),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted.withOpacity(0.5),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Manual Assessment Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ManualAssessmentSheet extends StatefulWidget {
  const _ManualAssessmentSheet({required this.player});
  final ClubPlayer player;

  @override
  State<_ManualAssessmentSheet> createState() => _ManualAssessmentSheetState();
}

class _ManualAssessmentSheetState extends State<_ManualAssessmentSheet> {
  int _score = 70;
  final _notesCtrl = TextEditingController();
  String _selectedType = 'squat';

  static const _types = [
    ('squat', 'assessment_squat_title'),
    ('countermovementJump', 'assessment_short_cmj'),
    ('dropJump', 'assessment_short_drop_jump'),
    ('singleLegDropJump', 'assessment_short_sl_drop_jump'),
    ('singleLegBalance', 'assessment_slb_title'),
    ('jumpLanding', 'assessment_jl_title'),
  ];

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: Responsive.bottomSheetMaxHeight(context),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            AppLocalizations.get('manual_assessment_title'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 14),
          // Type selector
          DropdownButtonFormField<String>(
            value: _selectedType,
            decoration: InputDecoration(
              labelText: AppLocalizations.get('test_type_label'),
              labelStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            dropdownColor: AppColors.card,
            style: const TextStyle(color: AppColors.foreground, fontSize: 13),
            items: _types
                .map((t) => DropdownMenuItem(value: t.$1, child: Text(AppLocalizations.get(t.$2))))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedType = v);
            },
          ),
          const SizedBox(height: 14),
          // Score slider
          Row(
            children: [
              Text(
                AppLocalizations.get('overall_score_label'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_score / 100',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _score.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.border,
            onChanged: (v) => setState(() => _score = v.round()),
          ),
          const SizedBox(height: 8),
          // Notes
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            style: const TextStyle(color: AppColors.foreground, fontSize: 13),
            decoration: InputDecoration(
              hintText: AppLocalizations.get('coach_notes_optional_hint'),
              hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.foreground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                final type = AssessmentTestType.values.firstWhere(
                  (t) => t.name == _selectedType,
                  orElse: () => AssessmentTestType.squat,
                );
                final result = AssessmentResult(
                  id: '${widget.player.id}_manual_${DateTime.now().millisecondsSinceEpoch}',
                  playerId: widget.player.id,
                  playerName: widget.player.fullName,
                  testType: type,
                  overallScore: _score,
                  movementQualityScore: _score,
                  stabilityScore: _score,
                  symmetryScore: _score,
                  controlScore: _score,
                  qualityScore: 0,
                  angleMetrics: {},
                  issues: ['تقييم يدوي من المدرب'],
                  correctionTips: _notesCtrl.text.isNotEmpty
                      ? [_notesCtrl.text]
                      : [],
                  recommendedDrills: [],
                  coachNotes: _notesCtrl.text.isNotEmpty
                      ? _notesCtrl.text
                      : null,
                  createdAt: DateTime.now(),
                );
                Navigator.of(context).pop(result);
              },
              child: Text(
                AppLocalizations.get('save_assessment_btn'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
