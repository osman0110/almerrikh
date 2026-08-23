import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../utils/app_logger.dart';
import 'club_dashboard.dart';
import 'club_widgets.dart';
import 'physio_session_screen.dart'
    show PhysioGroupSessionScreen, PhysioSessionEntry, PhysioSessionScreen,
        groupPhysioSessions, sessionDisplayTitle;
import 'session_form_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// A row in the merged schedule: either a training session or a physio
// session entry (single booking or a grouped session with a player
// roster — see PhysioSessionEntry). Physio sessions are read-only here;
// tapping opens the physiotherapist screens, same as the Physio Home tab.
// ─────────────────────────────────────────────────────────────────────────────
class _ScheduleItem {
  _ScheduleItem.training(TrainingSession session)
      : training = session, physio = null;
  _ScheduleItem.physio(PhysioSessionEntry entry)
      : training = null, physio = entry;

  final TrainingSession? training;
  final PhysioSessionEntry? physio;

  DateTime get sortDate {
    if (training != null) return training!.date;
    final raw = physio!.scheduledAt.replaceFirst(' ', 'T');
    return DateTime.tryParse(raw) ?? DateTime(2000);
  }

  // Buckets into the same 4 filter chips the training-session UI already
  // has (all/scheduled/completed/cancelled) — 'active' and 'late' count as
  // still-pending ('scheduled'); 'no_show' counts as 'cancelled' (session
  // didn't happen), avoiding new filter chips for physio-only statuses.
  String get filterKey {
    if (training != null) {
      return training!.status == 'active' ? 'scheduled' : training!.status;
    }
    final status = (physio!.primary['status'] as String?) ?? 'scheduled';
    if (status == 'completed') return 'completed';
    if (status == 'cancelled' || status == 'no_show') return 'cancelled';
    return 'scheduled';
  }
}

class SessionListPage extends StatefulWidget {
  const SessionListPage({super.key});

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage> {
  List<TrainingSession> _all = [];
  List<PhysioSessionEntry> _physioEntries = [];
  bool _loading = false;
  bool _loadError = false;
  // Status filter (design's sessionFilters row): all / scheduled / completed /
  // cancelled. 'active' (live) sessions bucket under 'scheduled', same as the
  // design mock's filterKey mapping.
  String _statusFilter = 'all';

  String _filterKeyOf(TrainingSession s) =>
      s.status == 'active' ? 'scheduled' : s.status;

  List<_ScheduleItem> get _allItems => [
        ..._all.map(_ScheduleItem.training),
        ..._physioEntries.map(_ScheduleItem.physio),
      ];

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
        ClubService().getSessions(),
        canViewPhysioSessions ? ApiService.getAllPhysioSessions() : Future.value(<Map<String, dynamic>>[]),
      ]);
      if (mounted) {
        setState(() {
          _all = results[0] as List<TrainingSession>;
          _physioEntries = groupPhysioSessions(results[1] as List<Map<String, dynamic>>);
        });
      }
    } catch (e) {
      AppLogger.e('SessionList', 'Load failed', e);
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<_ScheduleItem> get _filtered {
    return _allItems
        .where((i) => _statusFilter == 'all' || i.filterKey == _statusFilter)
        .toList()
      ..sort((a, b) => b.sortDate.compareTo(a.sortDate));
  }

  List<_ScheduleItem> get _upcomingFiltered =>
      _filtered.where((i) => i.filterKey == 'scheduled').toList();

  List<_ScheduleItem> get _pastFiltered =>
      _filtered.where((i) => i.filterKey != 'scheduled').toList();

  @override
  Widget build(BuildContext context) {
    final showFilters = !_loading && !_loadError && _allItems.isNotEmpty;
    return ClubShell(
      currentIndex: 2,
      child: Column(
        children: [
          // Header + stats + filters stay fixed; only the session list scrolls.
          const CoachBrandHeader(),
          _buildHeader(),
          if (showFilters) _buildStatsRow(),
          if (showFilters) _buildStatusFilters(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.card,
              onRefresh: _load,
              child: CustomScrollView(
                slivers: _buildSlivers(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Design-mock stat tiles: upcoming this week / average attendance / cancelled.
  Widget _buildStatsRow() {
    final upcoming = _all.where((s) => _filterKeyOf(s) == 'scheduled').length;
    final cancelled = _all.where((s) => s.status == 'cancelled').length;
    final withAttendance = _all.where(
      (s) => s.playerIds.isNotEmpty && s.attendancePresentCount > 0,
    );
    final avgAttendance = withAttendance.isEmpty
        ? 0
        : (withAttendance.fold<double>(
                  0,
                  (sum, s) =>
                      sum + (s.attendancePresentCount / s.playerIds.length * 100),
                ) /
                withAttendance.length)
            .round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.calendar_today_rounded,
              iconBg: const Color(0xFFEAF0FB),
              iconColor: const Color(0xFF3E6FD9),
              value: '$upcoming',
              label: AppLocalizations.get('sessions_stat_upcoming'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatTile(
              icon: Icons.check_circle_rounded,
              iconBg: const Color(0xFFE7F5EC),
              iconColor: AppColors.success,
              value: '$avgAttendance%',
              label: AppLocalizations.get('sessions_stat_avg_attendance'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatTile(
              icon: Icons.access_time_rounded,
              iconBg: AppColors.primarySoft,
              iconColor: AppColors.maroon,
              value: '$cancelled',
              label: AppLocalizations.get('sessions_stat_cancelled'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilters() {
    final filters = [
      ('all', AppLocalizations.get('category_all'), AppColors.maroon),
      ('scheduled', AppLocalizations.get('session_status_scheduled'), const Color(0xFF3E6FD9)),
      ('completed', AppLocalizations.get('session_status_completed'), AppColors.success),
      ('cancelled', AppLocalizations.get('session_status_cancelled'), const Color(0xFF9299A5)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: filters.map((f) {
          final key = f.$1;
          final label = f.$2;
          final color = f.$3;
          final active = _statusFilter == key;
          final count = key == 'all'
              ? _allItems.length
              : _allItems.where((i) => i.filterKey == key).length;
          return GestureDetector(
            onTap: () => setState(() => _statusFilter = key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsetsDirectional.only(end: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: active ? color : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? color : AppColors.border, width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: active ? Colors.white : AppColors.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5)),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: active ? Colors.white.withOpacity(0.25) : AppColors.background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                            color: active ? Colors.white : color,
                            fontWeight: FontWeight.w700,
                            fontSize: 9.5)),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildSlivers() {
    if (_loading) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      ];
    }
    if (_loadError) {
      return [SliverFillRemaining(hasScrollBody: false, child: _buildErrorState())];
    }
    if (_filtered.isEmpty) {
      return [SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())];
    }
    final groups = [
      (AppLocalizations.get('sessions_group_upcoming'), Icons.schedule_rounded,
          const Color(0xFF3E6FD9), _upcomingFiltered),
      (AppLocalizations.get('sessions_group_past'), Icons.show_chart_rounded,
          const Color(0xFF9299A5), _pastFiltered),
    ].where((g) => g.$4.isNotEmpty).toList();
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        sliver: SliverList.list(children: [
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: group.$3.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(group.$2, color: group.$3, size: 12),
                  ),
                  const SizedBox(width: 7),
                  Text(group.$1,
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const SizedBox(width: 4),
                  Text('(${group.$4.length})',
                      style: const TextStyle(
                          color: Color(0xFF9299A5),
                          fontWeight: FontWeight.w600,
                          fontSize: 10)),
                ],
              ),
            ),
            for (final item in group.$4)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: item.training != null
                    ? _SessionCard(
                        session: item.training!,
                        onTap: () async {
                          await Navigator.of(context).pushNamed('/club/sessions/${item.training!.id}');
                          _load();
                        },
                        onEdit: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => SessionFormPage(sessionId: item.training!.id)),
                          );
                          _load();
                        },
                      )
                    : _PhysioSessionCard(
                        entry: item.physio!,
                        onTap: () async {
                          final entry = item.physio!;
                          if (entry.isGroup) {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PhysioGroupSessionScreen(rows: entry.rows),
                            ));
                          } else {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PhysioSessionScreen(
                                playerId: (entry.primary['player_id'] ?? '').toString(),
                                playerName: (entry.primary['player_name'] as String?) ?? '',
                              ),
                            ));
                          }
                          _load();
                        },
                      ),
              ),
          ],
        ]),
      ),
    ];
  }

  Widget _buildHeader() {
    return ClubSectionTitle(
      icon: Icons.calendar_today_rounded,
      title: '${AppLocalizations.get('sessions_title')} (${_allItems.length})',
      trailing: canManageSessions
          ? GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SessionFormPage()),
                );
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, color: Color(0xFF3A2A08), size: 16),
                    const SizedBox(width: 4),
                    Text(AppLocalizations.get('new_session'), style: const TextStyle(
                        color: Color(0xFF3A2A08),
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle),
            child: const Icon(Icons.sports_rounded, color: AppColors.primary, size: 34),
          ),
          const SizedBox(height: 16),
          Text(AppLocalizations.get('no_sessions'),
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            _statusFilter != 'all'
                ? AppLocalizations.get('try_again')
                : AppLocalizations.get('new_session'),
            style: const TextStyle(
                color: AppColors.muted,
                fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
            child: const Icon(Icons.error_outline_rounded,
                color: AppColors.destructive, size: 26),
          ),
          const SizedBox(height: 14),
          Text(AppLocalizations.get('error_load_failed'),
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          const SizedBox(height: 6),
          Text(AppLocalizations.get('error_check_internet'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Text(AppLocalizations.get('retry_btn'),
                  style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session Card
// ─────────────────────────────────────────────────────────────────────────────

Color _sessionTypeColor(SessionType t) {
  switch (t) {
    case SessionType.fitness:
    case SessionType.strength:
    case SessionType.speedAgility:
    case SessionType.physicalAssessment:
      return AppColors.maroon;
    case SessionType.tactical:
    case SessionType.technical:
    case SessionType.teamTraining:
    case SessionType.positionSpecific:
    case SessionType.individual:
    case SessionType.goalkeeper:
      return const Color(0xFF3E6FD9);
    case SessionType.recovery:
    case SessionType.mobility:
    case SessionType.injuryPrevention:
    case SessionType.rehab:
      return AppColors.success;
    case SessionType.match:
    case SessionType.preMatch:
    case SessionType.postMatch:
      return AppColors.gold;
    case SessionType.custom:
      return const Color(0xFF9299A5);
  }
}

IconData _sessionTypeIcon(SessionType t) {
  switch (t) {
    case SessionType.fitness:
    case SessionType.strength:
    case SessionType.speedAgility:
    case SessionType.physicalAssessment:
      return Icons.fitness_center_rounded;
    case SessionType.tactical:
    case SessionType.technical:
    case SessionType.teamTraining:
    case SessionType.positionSpecific:
    case SessionType.individual:
    case SessionType.goalkeeper:
      return Icons.assignment_rounded;
    case SessionType.recovery:
    case SessionType.mobility:
    case SessionType.injuryPrevention:
    case SessionType.rehab:
      return Icons.favorite_rounded;
    case SessionType.match:
    case SessionType.preMatch:
    case SessionType.postMatch:
      return Icons.sports_soccer_rounded;
    case SessionType.custom:
      return Icons.event_note_rounded;
  }
}

(Color, Color) _sessionStatusColors(String status) {
  switch (status) {
    case 'active':
      return (AppColors.maroon, AppColors.primarySoft);
    case 'completed':
      return (AppColors.success, const Color(0xFFE7F5EC));
    case 'cancelled':
      return (const Color(0xFF9299A5), const Color(0xFFF1EEEC));
    default:
      return (const Color(0xFF3E6FD9), const Color(0xFFEAF0FB));
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onTap, required this.onEdit});
  final TrainingSession session;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final pct = session.playerIds.isEmpty
        ? 0.0
        : session.completedPlayerIds.length / session.playerIds.length;
    final hasAttendance = session.playerIds.isNotEmpty &&
        (session.completedPlayerIds.isNotEmpty || session.attendancePresentCount > 0);
    final typeColor = _sessionTypeColor(session.type);
    final (statusColor, statusBg) = _sessionStatusColors(session.status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 3)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: typeColor),
                Container(
                  width: 56,
                  color: typeColor.withOpacity(0.06),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(AppLocalizations.weekdayShort(session.date.weekday),
                          style: TextStyle(
                              color: typeColor,
                              fontWeight: FontWeight.w500,
                              fontSize: 8.5)),
                      Text('${session.date.day}',
                          style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              height: 1.1)),
                      Text(AppLocalizations.monthName(session.date.month),
                          style: const TextStyle(
                              color: Color(0xFF9299A5),
                              fontWeight: FontWeight.w500,
                              fontSize: 8.5)),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: AppColors.card,
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(session.name,
                                style: const TextStyle(
                                    color: AppColors.foreground,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: onEdit,
                            child: const Icon(Icons.edit_rounded,
                                color: Color(0xFF9299A5), size: 15),
                          ),
                        ]),
                        if (session.teamName != null && session.teamName!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.groups_rounded,
                                color: Color(0xFF9299A5), size: 11),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(session.teamName!,
                                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ],
                        const SizedBox(height: 5),
                        Row(children: [
                              const Icon(Icons.schedule_rounded,
                                  color: Color(0xFF9299A5), size: 11),
                              const SizedBox(width: 4),
                              Text(
                                  session.endTime != null && session.endTime!.isNotEmpty
                                      ? '${session.startTime} – ${session.endTime}'
                                      : session.startTime,
                                  style: const TextStyle(
                                      color: AppColors.muted, fontSize: 10)),
                              if (session.location != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 3,
                                  height: 3,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFFD8D4D0), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.location_on_rounded,
                                    color: Color(0xFF9299A5), size: 11),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(session.location!,
                                      style: const TextStyle(
                                          color: AppColors.muted, fontSize: 10),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _MetaChip(
                                  icon: Icons.hourglass_bottom_rounded,
                                  label: '${session.durationMin} ${AppLocalizations.get('minute_unit')}',
                                  color: const Color(0xFF9299A5),
                                ),
                                _MetaChip(
                                  icon: Icons.speed_rounded,
                                  label: session.intensityLabel,
                                  color: const Color(0xFF9299A5),
                                ),
                                if (session.assessmentCount > 0)
                                  _MetaChip(
                                    icon: Icons.insights_rounded,
                                    label: '${session.assessmentCount}',
                                    color: AppColors.maroon,
                                  ),
                                if (session.wellnessRequired)
                                  const _MetaChip(
                                    icon: Icons.favorite_rounded,
                                    label: 'Hooper',
                                    color: AppColors.gold,
                                  ),
                                if (session.rpeRequired)
                                  const _MetaChip(
                                    icon: Icons.poll_rounded,
                                    label: 'RPE',
                                    color: AppColors.gold,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: typeColor.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(_sessionTypeIcon(session.type),
                                          color: typeColor, size: 10),
                                      const SizedBox(width: 4),
                                      Text(session.type.label,
                                          style: TextStyle(
                                              color: typeColor,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 9)),
                                    ],
                                  ),
                                ),
                                Container(
                                  height: 17,
                                  padding: const EdgeInsets.symmetric(horizontal: 9),
                                  decoration: BoxDecoration(
                                    color: statusBg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                            color: statusColor, shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(session.statusLabel,
                                          style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 8.5)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (hasAttendance) ...[
                              const SizedBox(height: 6),
                              Row(children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: pct.clamp(0.0, 1.0),
                                      minHeight: 3.5,
                                      backgroundColor: AppColors.surface2,
                                      valueColor: AlwaysStoppedAnimation(typeColor),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${session.completedPlayerIds.length}/${session.playerIds.length}',
                                  style: const TextStyle(
                                      color: Color(0xFF9299A5),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 9),
                                ),
                              ]),
                            ],
                          ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Physio session card — same date-badge + colored-bar layout as _SessionCard,
// simplified (no attendance %, no assessment/wellness/RPE chips — those are
// training-session-only concepts). Read-only here: tapping opens the
// physiotherapist screens (group roster or single-player session).
// ─────────────────────────────────────────────────────────────────────────────

class _PhysioSessionCard extends StatelessWidget {
  const _PhysioSessionCard({required this.entry, required this.onTap});
  final PhysioSessionEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = entry.primary;
    final date = DateTime.tryParse(entry.scheduledAt.replaceFirst(' ', 'T'));
    final time = entry.scheduledAt.split(' ').last;
    final status = (s['status'] as String?) ?? 'scheduled';
    final (statusColor, statusBg) = _sessionStatusColors(
        status == 'no_show' || status == 'late' ? 'cancelled' : status);
    const typeColor = AppColors.success; // matches SessionType.recovery/rehab

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 3)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: typeColor),
                Container(
                  width: 56,
                  color: typeColor.withOpacity(0.06),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (date != null)
                        Text(AppLocalizations.weekdayShort(date.weekday),
                            style: const TextStyle(color: typeColor, fontWeight: FontWeight.w500, fontSize: 8.5)),
                      Text(date != null ? '${date.day}' : '-',
                          style: const TextStyle(
                              color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 19, height: 1.1)),
                      if (date != null)
                        Text(AppLocalizations.monthName(date.month),
                            style: const TextStyle(color: Color(0xFF9299A5), fontWeight: FontWeight.w500, fontSize: 8.5)),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: AppColors.card,
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sessionDisplayTitle(s),
                            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Row(children: [
                          const Icon(Icons.groups_rounded, color: Color(0xFF9299A5), size: 11),
                          const SizedBox(width: 4),
                          Text(
                              entry.isGroup
                                  ? '${entry.rows.length} ${AppLocalizations.get('nav_players')}'
                                  : (s['player_name'] as String?) ?? '-',
                              style: const TextStyle(color: AppColors.muted, fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ]),
                        const SizedBox(height: 5),
                        Row(children: [
                          const Icon(Icons.schedule_rounded, color: Color(0xFF9299A5), size: 11),
                          const SizedBox(width: 4),
                          Text(time, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                          if ((s['room'] as String?)?.isNotEmpty == true) ...[
                            const SizedBox(width: 6),
                            Container(width: 3, height: 3, decoration: const BoxDecoration(color: Color(0xFFD8D4D0), shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            const Icon(Icons.meeting_room_rounded, color: Color(0xFF9299A5), size: 11),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(s['room'] as String,
                                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: typeColor.withOpacity(0.08), borderRadius: BorderRadius.circular(999)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.favorite_rounded, color: typeColor, size: 10),
                                  const SizedBox(width: 4),
                                  Text(AppLocalizations.get('physio_sessions_title'),
                                      style: const TextStyle(color: typeColor, fontWeight: FontWeight.w600, fontSize: 9)),
                                ],
                              ),
                            ),
                            Container(
                              height: 17,
                              padding: const EdgeInsets.symmetric(horizontal: 9),
                              decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(999)),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(width: 5, height: 5, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                                  const SizedBox(width: 4),
                                  Text(AppLocalizations.get('physio_status_$status'),
                                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 8.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Meta chip — small icon+label pill for session card extras (duration,
// intensity, assessment count, wellness/RPE requirement).
// ─────────────────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 9.5),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 8.5)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat tile — design-mock's 3-tile summary row (upcoming / attendance / cancelled)
// ─────────────────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, color: iconColor, size: 11),
          ),
          const SizedBox(height: 5),
          Text(value,
              style: const TextStyle(
                  color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 8, height: 1.2)),
        ],
      ),
    );
  }
}
