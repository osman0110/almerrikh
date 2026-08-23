import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../widgets/common_widgets.dart' show RoleAccessDeniedPage;
import 'club_widgets.dart';
import 'club_dashboard.dart' show ClubShell;
import 'injury_case_screen.dart' show InjuryCaseScreen;
import 'physio_session_screen.dart' show PhysioDailyScheduleScreen;
import 'physio_bulk_session_page.dart';
import 'daily_readiness_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Doctor Dashboard — focused medical workbench for the "doctor" org role.
// Shows open clinical cases, readiness attention items, today's treatment
// sessions, and direct player-file actions.
// ─────────────────────────────────────────────────────────────────────────────

class DoctorDashboardPage extends StatefulWidget {
  const DoctorDashboardPage({super.key});

  @override
  State<DoctorDashboardPage> createState() => _DoctorDashboardPageState();
}

class _DoctorDashboardPageState extends State<DoctorDashboardPage> {
  bool _loading = true;
  bool _loadError = false;
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _cases = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _attention = [];
  List<Map<String, dynamic>> _players = [];
  List<TrainingSession> _allSessions = [];
  List<MatchModel> _allMatches = [];

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
        ApiService.getDoctorDashboard(date: _dateString(_selectedDate)),
        ClubService().getSessions(),
        ClubService().getMatches(),
      ]);
      if (!mounted) return;
      final response = results[0] as Map<String, dynamic>;
      if (response['success'] != true) {
        throw StateError(response['message']?.toString() ?? 'Doctor dashboard failed');
      }
      setState(() {
        _summary = (response['summary'] as Map?)?.cast<String, dynamic>() ?? {};
        _cases = (response['cases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _sessions = (response['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _attention = (response['attention'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _players = (response['players'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _allSessions = results[1] as List<TrainingSession>;
        _allMatches = results[2] as List<MatchModel>;
      });
    } catch (e) {
      AppLogger.e('DoctorDashboard', 'Load failed', e);
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  void _changeDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _sessions = [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // Admin/owner never enter the doctor's operational interface — the
    // read-only management policy limits them to the aggregated reports.
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
                roleLabel: AppLocalizations.get('doctor_team_role'),
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
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 32),
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
                    _buildMetricsRow(),
                    const SizedBox(height: 16),
                    _buildPrioritySection(context),
                    const SizedBox(height: 16),
                    _buildSessionsSection(context),
                    const SizedBox(height: 16),
                    _buildReadinessSection(context),
                    const SizedBox(height: 16),
                    _buildQuickActions(context),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── KPI row ──────────────────────────────────────────────────────────────

  Widget _buildMetricsRow() {
    final cards = [
      (
        Icons.local_hospital_rounded,
        '${_count('open_injury_cases')}',
        AppLocalizations.get('doctor_open_cases_short'),
        AppColors.primary,
        false,
      ),
      (
        Icons.warning_amber_rounded,
        '${_count('high_risk') + _count('pain_alerts')}',
        AppLocalizations.get('doctor_urgent_followup'),
        AppColors.destructive,
        _count('high_risk') + _count('pain_alerts') > 0,
      ),
      (
        Icons.check_circle_rounded,
        '${_count('readiness_submitted')}',
        AppLocalizations.get('doctor_readiness_submitted_short'),
        AppColors.success,
        false,
      ),
      (
        Icons.pending_actions_rounded,
        '${_count('readiness_missing')}',
        AppLocalizations.get('doctor_readiness_missing_short'),
        AppColors.warning,
        false,
      ),
    ];
    return Column(
      children: [
        Row(children: [
          Expanded(child: _metricCard(cards[0])),
          const SizedBox(width: 8),
          Expanded(child: _metricCard(cards[1])),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _metricCard(cards[2])),
          const SizedBox(width: 8),
          Expanded(child: _metricCard(cards[3])),
        ]),
      ],
    );
  }

  Widget _metricCard((IconData, String, String, Color, bool) card) {
    final (icon, value, label, color, alert) = card;
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: alert ? color.withOpacity(0.45) : AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.15)),
            ],
          ),
        ),
      ]),
    );
  }

  int _count(String key) => (_summary[key] as num?)?.toInt() ?? 0;

  Widget _panel({required String title, required Widget child, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: ClubSectionLabel(title)),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _priorityItems() {
    final byPlayer = <String, Map<String, dynamic>>{};
    for (final item in _attention.where((item) => item['severity'] == 'danger')) {
      final playerId = item['player_id']?.toString() ?? '';
      if (playerId.isNotEmpty) byPlayer.putIfAbsent(playerId, () => item);
    }
    for (final item in _cases) {
      final playerId = item['player_id']?.toString() ?? '';
      if (playerId.isNotEmpty) {
        byPlayer.putIfAbsent(playerId, () => {
          'type': 'open_injury_case',
          'severity': 'danger',
          'player_id': playerId,
          'player_name': item['player_name'],
        });
      }
    }
    return byPlayer.values.take(5).toList();
  }

  Widget _buildPrioritySection(BuildContext context) {
    final items = _priorityItems();
    return _panel(
      title: AppLocalizations.get('doctor_priority_today'),
      child: items.isEmpty
          ? Row(children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(AppLocalizations.get('doctor_no_urgent_cases'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13))),
            ])
          : Column(children: items.map((item) => _attentionRow(context, item)).toList()),
    );
  }

  String _attentionMessage(Map<String, dynamic> item) {
    switch (item['type']?.toString()) {
      case 'high_risk':
        return AppLocalizations.get('priority_reason_high_risk');
      case 'pain_reported':
        return AppLocalizations.get('pain_reported_short');
      case 'muscle_soreness':
        return AppLocalizations.get('priority_reason_fatigue');
      case 'open_injury_case':
        return AppLocalizations.get('priority_reason_injured');
      default:
        return AppLocalizations.get('doctor_no_urgent_cases');
    }
  }

  Widget _buildReadinessSection(BuildContext context) {
    final missing = _count('readiness_missing');
    return _panel(
      title: AppLocalizations.get('doctor_readiness_followup'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.format('doctor_missing_readiness_summary', {'count': missing}),
            style: const TextStyle(color: AppColors.foreground, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DailyReadinessScreen(initialDate: _selectedDate),
                )),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(AppLocalizations.get('doctor_view_players'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: missing == 0 ? null : _sendReadinessReminder,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: BorderSide(color: missing == 0 ? AppColors.border : AppColors.warning),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(AppLocalizations.get('send_reminder_btn'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _sendReadinessReminder() async {
    final response = await ApiService.sendReadinessReminder(_dateString(_selectedDate));
    if (!mounted) return;
    final message = response['success'] == true
        ? AppLocalizations.get('doctor_reminder_sent')
        : response['message']?.toString() ?? AppLocalizations.get('error_generic');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildQuickActions(BuildContext context) {
    return _panel(
      title: AppLocalizations.get('doctor_quick_actions'),
      child: Row(children: [
        Expanded(child: _quickAction(
          icon: Icons.medical_information_rounded,
          color: AppColors.destructive,
          title: AppLocalizations.get('doctor_register_case'),
          onTap: () => _showPlayerPicker(context),
        )),
        const SizedBox(width: 8),
        Expanded(child: _quickAction(
          icon: Icons.calendar_month_rounded,
          color: AppColors.primary,
          title: AppLocalizations.get('doctor_new_medical_session'),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => const PhysioBulkSessionPage(),
            ));
            if (changed == true && mounted) _load();
          },
        )),
        const SizedBox(width: 8),
        Expanded(child: _quickAction(
          icon: Icons.person_search_rounded,
          color: AppColors.coachAccent,
          title: AppLocalizations.get('doctor_search_player'),
          onTap: () => _showPlayerPicker(context),
        )),
      ]),
    );
  }

  Widget _quickAction({required IconData icon, required Color color, required String title, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.15)),
        ]),
      ),
    );
  }

  Widget _attentionRow(BuildContext context, Map<String, dynamic> item) {
    final danger = item['severity'] == 'danger';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openPlayer(
        context,
        item['player_id']?.toString(),
        playerName: item['player_name']?.toString(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(item['type'] == 'open_injury_case'
                  ? Icons.medical_information_rounded
                  : Icons.warning_amber_rounded,
              color: danger ? AppColors.destructive : AppColors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item['player_name']?.toString() ?? '', style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(_attentionMessage(item), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_left_rounded, color: AppColors.muted, size: 18),
        ]),
      ),
    );
  }

  Widget _buildSessionsSection(BuildContext context) {
    return _panel(
      title: AppLocalizations.get('daily_schedule_title'),
      trailing: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PhysioDailyScheduleScreen(initialDate: _selectedDate),
        )),
        child: Text(AppLocalizations.get('doctor_view_full_schedule'),
            style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
      child: _sessions.isEmpty
          ? Text(AppLocalizations.get('no_physio_sessions'), style: const TextStyle(color: AppColors.muted, fontSize: 13))
          : Column(children: _sessions.take(3).map((item) => _sessionRow(context, item)).toList()),
    );
  }

  Widget _sessionRow(BuildContext context, Map<String, dynamic> item) {
    final isDoctor = item['therapist_role']?.toString() == 'doctor';
    final scheduled = item['scheduled_at']?.toString() ?? '';
    final time = scheduled.contains(' ') && scheduled.split(' ').last.length >= 5
        ? scheduled.split(' ').last.substring(0, 5)
        : scheduled;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openPlayer(
        context,
        item['player_id']?.toString(),
        playerName: item['player_name']?.toString(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Text(time, style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(width: 10),
          Icon(isDoctor ? Icons.local_hospital_rounded : Icons.spa_rounded, color: isDoctor ? AppColors.warning : AppColors.risk, size: 17),
          const SizedBox(width: 8),
          Expanded(child: Text(item['player_name']?.toString() ?? '', style: const TextStyle(color: AppColors.foreground, fontSize: 13))),
          Text(isDoctor ? AppLocalizations.get('doctor_session_title') : AppLocalizations.get('physio_sessions_title'), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ]),
      ),
    );
  }

  void _openPlayer(BuildContext context, String? playerId, {String? playerName}) {
    if (playerId == null || playerId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InjuryCaseScreen(
        playerId: playerId,
        playerName: playerName ?? '',
      ),
    ));
  }

  void _showPlayerPicker(BuildContext context) {
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final filtered = _players.where((p) => query.trim().isEmpty ||
              (p['player_name']?.toString().toLowerCase() ?? '').contains(query.toLowerCase())).toList();
          return SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLocalizations.get('doctor_search_player'), style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (value) => setSheetState(() => query = value),
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.get('search_players'),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, index) {
                    final player = filtered[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(backgroundColor: AppColors.primarySoft, child: Icon(Icons.person_rounded, color: AppColors.primary, size: 18)),
                      title: Text(player['player_name']?.toString() ?? '', style: const TextStyle(color: AppColors.foreground, fontSize: 13, fontWeight: FontWeight.w700)),
                      subtitle: Text(player['position']?.toString() ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openPlayer(
                          context,
                          player['player_id']?.toString(),
                          playerName: player['player_name']?.toString(),
                        );
                      },
                    );
                  },
                )),
              ]),
            ),
          );
        },
      ),
    );
  }
}

