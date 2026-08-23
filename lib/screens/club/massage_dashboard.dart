import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../core/theme/app_fonts.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../widgets/common_widgets.dart' show RoleAccessDeniedPage;
import 'club_widgets.dart';
import 'club_dashboard.dart' show ClubShell;
import 'club_player_profile_page.dart';
import 'physio_session_screen.dart'
    show PhysioDailyScheduleScreen, PhysioGroupSessionScreen, PhysioSessionEntry,
        PhysioSessionScreen, groupPhysioSessions, sessionDisplayTitle;
import 'physio_bulk_session_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Massage Dashboard — focused Home tab for the "massage_specialist"/
// "physiotherapist" org role. Matches the "Physiotherapist Home" design:
// next-session hero, today's KPI row, quick actions, today's queue and
// medical alerts (contraindications flagged on today's sessions). The full
// roster/booking flow now lives behind the Players tab and the "new session"
// quick action (both reachable from the shared club bottom nav), so this
// Home tab no longer embeds its own player list.
// ─────────────────────────────────────────────────────────────────────────────

Color _statusColor(String s) {
  switch (s) {
    case 'scheduled': return AppColors.risk;
    case 'completed': return AppColors.success;
    case 'late': return AppColors.warning;
    case 'cancelled':
    case 'no_show': return AppColors.destructive;
    default: return AppColors.muted;
  }
}

Color _statusBg(String s) => _statusColor(s).withOpacity(0.10);

String _initials(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '-';
  if (parts.length == 1) return parts.first.substring(0, 1);
  return '${parts[0].substring(0, 1)} ${parts[1].substring(0, 1)}';
}

class MassageDashboardPage extends StatefulWidget {
  const MassageDashboardPage({super.key});

  @override
  State<MassageDashboardPage> createState() => _MassageDashboardPageState();
}

class _MassageDashboardPageState extends State<MassageDashboardPage> {
  bool _loading = true;
  bool _loadError = false;
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _sessions = [];
  List<TrainingSession> _allSessions = [];
  List<MatchModel> _allMatches = [];

  String get _selectedDateString =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-'
      '${_selectedDate.month.toString().padLeft(2, '0')}-'
      '${_selectedDate.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final results = await Future.wait([
        ApiService.getPhysioScheduleForDate(_selectedDateString),
        ClubService().getSessions(),
        ClubService().getMatches(),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0] as List<Map<String, dynamic>>;
        _allSessions = results[1] as List<TrainingSession>;
        _allMatches = results[2] as List<MatchModel>;
      });
    } catch (e) {
      AppLogger.e('MassageDashboard', 'Load failed', e);
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _changeDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _sessions = [];
    });
    _load();
  }

  int get _scheduledCount =>
      _sessions.where((s) => s['status'] == 'scheduled').length;
  int get _completedCount =>
      _sessions.where((s) => s['status'] == 'completed').length;

  // Sessions booked together (same session_group_id, from the group-booking
  // flow) are collapsed into one entry so the coach manages them as a single
  // session with a player roster, not N unrelated rows.
  List<PhysioSessionEntry> get _entries => groupPhysioSessions(_sessions);

  PhysioSessionEntry? get _nextEntry {
    final upcoming = _entries
        .where((e) => e.rows.any((r) => r['status'] == 'scheduled'))
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  List<Map<String, dynamic>> get _alerts => _sessions
      .where((s) => ((s['contraindications'] as String?) ?? '').trim().isNotEmpty)
      .toList();

  void _openPlayerSession(String playerId, String playerName) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhysioSessionScreen(playerId: playerId, playerName: playerName),
    ));
  }

  Future<void> _openEntry(PhysioSessionEntry entry) async {
    if (entry.isGroup) {
      final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PhysioGroupSessionScreen(rows: entry.rows),
      ));
      if (changed == true && mounted) _load();
      return;
    }
    _openPlayerSession(
      (entry.primary['player_id'] ?? '').toString(),
      (entry.primary['player_name'] as String?) ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Admin/owner never enter the physiotherapist's operational interface —
    // the read-only management policy limits them to the aggregated reports.
    if (isOrgAdmin) return const RoleAccessDeniedPage();
    return ClubShell(
      currentIndex: 0,
      child: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.card,
        strokeWidth: 2,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: RoleBrandHeader(
                roleLabel: AppLocalizations.get('role_physiotherapist'),
              ),
            ),
            SliverToBoxAdapter(
              child: RoleHomeDateStrip(
                selectedDate: _selectedDate,
                onDateChanged: _changeDate,
                markerOf: (date) => RoleDateMarker(
                  hasMatch: _allMatches.any((m) => _sameDay(m.matchDate, date)),
                  hasSession: _allSessions.any((s) => _sameDay(s.date, date)),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_loadError)
                    ClubErrorState(
                      title: AppLocalizations.get('error_load_failed'),
                      description: AppLocalizations.get('error_check_internet'),
                      retryLabel: AppLocalizations.get('retry_btn'),
                      onRetry: _load,
                    )
                  else ...[
                    _buildNextSessionHero(context),
                    const SizedBox(height: 16),
                    _buildMetricsRow(),
                    const SizedBox(height: 20),
                    _buildQuickActions(context),
                    const SizedBox(height: 20),
                    _buildTodayQueue(context),
                    const SizedBox(height: 20),
                    _buildMedicalAlerts(context),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Next session hero ───────────────────────────────────────────────────

  Widget _heroLogoWatermark() {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxHeight.isFinite
              ? (constraints.maxHeight * 1.15).clamp(120.0, 220.0)
              : 140.0;
          return Align(
            alignment: Alignment.bottomLeft,
            child: Transform.translate(
              offset: Offset(-size * 0.22, size * 0.18),
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.10,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                    child: Image.asset('assets/images/logo.png',
                        width: size, height: size, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNextSessionHero(BuildContext context) {
    final entry = _nextEntry;
    final next = entry?.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 168),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.hero, AppColors.maroonDark],
          ),
        ),
        child: Stack(
          children: [
            _heroLogoWatermark(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(AppLocalizations.get('physio_next_session_title'),
                          style: const TextStyle(
                              color: AppColors.onDarkMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500)),
                      const Spacer(),
                      if (next != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: AppColors.hero.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                          ),
                          child: Text(_countdownLabel(next),
                              style: const TextStyle(
                                  color: AppColors.onDarkMuted,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (next == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        AppLocalizations.get('physio_no_upcoming_session'),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    )
                  else ...[
                    Text(
                      entry!.isGroup
                          ? '${entry.rows.length} ${AppLocalizations.get('nav_players')} · ${sessionDisplayTitle(next)}'
                          : '${(next['player_name'] as String?) ?? '-'} · ${sessionDisplayTitle(next)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17, height: 1.25),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        const Icon(Icons.schedule_rounded, size: 11, color: AppColors.gold),
                        Text(
                          ((next['scheduled_at'] as String?) ?? '').split(' ').last,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                              color: AppColors.onDarkMuted, fontWeight: FontWeight.w500, fontSize: 11),
                        ),
                        Container(
                          width: 3, height: 3,
                          decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                        ),
                        const Icon(Icons.meeting_room_rounded, size: 11, color: AppColors.gold),
                        Text(
                          ((next['room'] as String?)?.trim().isNotEmpty ?? false)
                              ? next['room'] as String
                              : '-',
                          style: const TextStyle(
                              color: AppColors.onDarkMuted, fontWeight: FontWeight.w500, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: entry == null ? null : () => _openEntry(entry),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.maroonDark,
                        disabledBackgroundColor: Colors.white.withOpacity(0.5),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 18, color: AppColors.maroonDark),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(AppLocalizations.get('physio_start_session_cta'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: AppFonts.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _countdownLabel(Map<String, dynamic> s) {
    final raw = (s['scheduled_at'] as String?) ?? '';
    final dt = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (dt == null) return AppLocalizations.get('physio_status_scheduled');
    final diffMin = dt.difference(DateTime.now()).inMinutes;
    if (diffMin <= 0) return AppLocalizations.get('physio_status_scheduled');
    return '$diffMin ${AppLocalizations.get('unit_minutes_short')}';
  }

  // ── KPI row ──────────────────────────────────────────────────────────────

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(child: _statTile('${_entries.length}', AppLocalizations.get('physio_sessions_label'))),
        const SizedBox(width: 8),
        Expanded(child: _statTile('$_scheduledCount', AppLocalizations.get('physio_status_scheduled'))),
        const SizedBox(width: 8),
        Expanded(child: _statTile('$_completedCount', AppLocalizations.get('physio_status_completed'))),
      ],
    );
  }

  Widget _statTile(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: AppColors.foreground.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: AppColors.maroon, fontWeight: FontWeight.w800, fontSize: 19, height: 1)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500, fontSize: 9.5)),
        ],
      ),
    );
  }

  // ── Quick actions ────────────────────────────────────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4, height: 4,
              decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(AppLocalizations.get('quick_actions'),
                style: const TextStyle(
                    color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 15.5)),
          ],
        ),
        const SizedBox(height: 12),
        _quickActionRow(
          icon: Icons.add_rounded,
          iconColor: Colors.white,
          label: AppLocalizations.get('physio_bulk_title'),
          primary: true,
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => const PhysioBulkSessionPage(),
            ));
            if (changed == true && mounted) _load();
          },
        ),
        const SizedBox(height: 12),
        _quickActionRow(
          icon: Icons.calendar_month_rounded,
          iconColor: AppColors.maroon,
          label: AppLocalizations.get('daily_schedule_title'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const PhysioDailyScheduleScreen(),
          )),
        ),
        const SizedBox(height: 12),
        _quickActionRow(
          icon: Icons.group_rounded,
          iconColor: AppColors.maroon,
          label: AppLocalizations.get('nav_players'),
          onTap: () => Navigator.of(context).pushNamed('/club/players'),
        ),
      ],
    );
  }

  Widget _quickActionRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final iconBoxColor = primary ? Colors.white.withOpacity(0.18) : iconColor.withOpacity(0.10);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        height: 84,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: primary ? AppColors.maroon : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: primary ? null : Border.all(color: AppColors.border),
          boxShadow: primary
              ? [BoxShadow(color: AppColors.maroon.withOpacity(0.20), blurRadius: 14, offset: const Offset(0, 6))]
              : [BoxShadow(color: AppColors.foreground.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: iconBoxColor, borderRadius: BorderRadius.circular(13)),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: primary ? Colors.white : AppColors.foreground,
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_left_rounded,
                color: primary ? Colors.white.withOpacity(0.7) : AppColors.muted, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Today's queue ─────────────────────────────────────────────────────────

  Widget _buildTodayQueue(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
                '${AppLocalizations.get('daily_schedule_title')} · '
                '${AppLocalizations.formatDate(_selectedDate)}',
                style: const TextStyle(
                    color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 15.5)),
            Text('${_entries.length} ${AppLocalizations.get('physio_sessions_label')}',
                style: const TextStyle(color: AppColors.maroon, fontWeight: FontWeight.w600, fontSize: 11.5)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: AppColors.foreground.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: _entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      AppLocalizations.get('no_physio_sessions'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final e in _entries) _queueRow(context, e),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _queueRow(BuildContext context, PhysioSessionEntry entry) {
    final s = entry.primary;
    final time = ((s['scheduled_at'] as String?) ?? '').split(' ').last;
    final playerName = (s['player_name'] as String?) ?? '';
    final isGroup = entry.isGroup;

    return InkWell(
      onTap: () => _openEntry(entry),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF1EEEC))),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: isGroup
                  ? Text('${entry.rows.length}',
                      style: const TextStyle(color: AppColors.maroon, fontWeight: FontWeight.w800, fontSize: 13))
                  : Text(_initials(playerName.isEmpty ? '-' : playerName),
                      style: const TextStyle(color: AppColors.maroon, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      isGroup ? sessionDisplayTitle(s) : (playerName.isEmpty ? '-' : playerName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text(
                      isGroup
                          ? '${entry.rows.length} ${AppLocalizations.get('nav_players')} · $time'
                          : '${sessionDisplayTitle(s)} · $time',
                      style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500, fontSize: 10.5)),
                ],
              ),
            ),
            if (isGroup)
              const Icon(Icons.chevron_left_rounded, color: AppColors.muted, size: 20)
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _statusBg((s['status'] ?? '').toString()), borderRadius: BorderRadius.circular(999)),
                child: Text(AppLocalizations.get('physio_status_${s['status']}'),
                    style: TextStyle(color: _statusColor((s['status'] ?? '').toString()), fontWeight: FontWeight.w600, fontSize: 9.5)),
              ),
          ],
        ),
      ),
    );
  }

  // ── Medical alerts (sessions flagged with contraindications) ─────────────

  Widget _buildMedicalAlerts(BuildContext context) {
    final alerts = _alerts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.get('physio_medical_alerts_title'),
            style: const TextStyle(
                color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 15.5)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: AppColors.foreground.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: alerts.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      AppLocalizations.get('no_alerts'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final a in alerts) _alertRow(context, a),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _alertRow(BuildContext context, Map<String, dynamic> s) {
    final playerId = (s['player_id'] ?? '').toString();
    final playerName = (s['player_name'] as String?) ?? '-';
    final note = (s['contraindications'] as String?) ?? '';

    return InkWell(
      onTap: playerId.isEmpty
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ClubPlayerProfilePage(playerId: playerId),
              )),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF1EEEC))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 7, height: 7,
                decoration: const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: playerName,
                      style: const TextStyle(
                          color: AppColors.foreground, fontWeight: FontWeight.w600, fontSize: 11.5),
                    ),
                    TextSpan(
                      text: ' · $note',
                      style: const TextStyle(
                          color: AppColors.muted, fontWeight: FontWeight.w500, fontSize: 10.5),
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
