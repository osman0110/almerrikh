import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../models/coach_monitoring_models.dart';
import '../../models/physical_report_models.dart';
import '../../services/club_service.dart';
import '../../services/coach_monitoring_service.dart';
import '../../services/physical_report_service.dart';
import '../../shared/club_status_color.dart';
import '../../shared/club_ui_tokens.dart';
import '../../utils/metric_formatter.dart';
import 'add_edit_player_page.dart';
import 'club_dashboard.dart';
import 'club_widgets.dart';
import 'injury_case_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Smart filter enum — performance-based, not just administrative
// ─────────────────────────────────────────────────────────────────────────────

enum _PFilter {
  all,
  ready,
  monitoring,
  danger,
  notReady,
  injured,
  missingWellness,
  highFatigue,
  noAssessment,
  disciplineThreat,
  oneCardAway,
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class PlayerManagementPage extends StatefulWidget {
  const PlayerManagementPage({
    super.key,
    this.filterTeamId,
    this.initialFilter,
  });
  final String? filterTeamId;
  final String? initialFilter;

  @override
  State<PlayerManagementPage> createState() => _PlayerManagementPageState();
}

class _PlayerManagementPageState extends State<PlayerManagementPage> {
  List<ClubPlayer> _all = [];
  CoachDashboardData? _wellness;
  PhysicalReportData? _physicalReport;
  bool _loading = false;
  bool _showArchived = false;
  String _query = '';
  _PFilter _filter = _PFilter.all;

  @override
  void initState() {
    super.initState();
    _filter = _filterFromName(widget.initialFilter);
    _load();
  }

  bool _loadError = false;
  Map<String, CoachPlayerStatus> _wellnessMap = {}; // Cache for O(1) lookup
  Map<String, PlayerManagementReportRow> _managementMap = {};
  Map<String, PhysicalReportPlayer> _physicalMap = {};
  Map<String, _PhysioPlayerSummary> _physioMap = {}; // physiotherapist card body

  _PFilter _filterFromName(String? value) {
    switch (value) {
      case 'ready':
        return _PFilter.ready;
      case 'not_ready':
        return _PFilter.notReady;
      case 'injured':
        return _PFilter.injured;
      case 'missing_wellness':
        return _PFilter.missingWellness;
      case 'high_strain':
        return _PFilter.danger;
      case 'discipline_threat':
        return _PFilter.disciplineThreat;
      case 'one_card_away':
        return _PFilter.oneCardAway;
      default:
        return _PFilter.all;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      if (_showArchived) {
        final players = await ClubService().getPlayers(
          teamId: widget.filterTeamId,
          archived: true,
        );
        if (mounted) {
          setState(() {
            _all = players;
            _managementMap = {};
            _physicalMap = {};
            _wellnessMap = {};
            _physioMap = {};
            _wellness = null;
            _physicalReport = null;
            _loading = false;
          });
        }
        return;
      }
      if (canViewManagementReport) {
        final results = await Future.wait([
          ClubService().getPlayers(teamId: widget.filterTeamId),
          ClubService().getManagementReport(
            teamId: int.tryParse(widget.filterTeamId ?? ''),
          ),
          const PhysicalReportService().getReport(),
          CoachMonitoringService.getDashboard(),
        ]);
        if (mounted) {
          final managementRows =
              results[1] as List<PlayerManagementReportRow>;
          final physicalReport = results[2] as PhysicalReportData?;
          final wellness = results[3] as CoachDashboardData;
          final wellnessMap = <String, CoachPlayerStatus>{
            for (final item in wellness.players)
              item.name.toLowerCase().trim(): item,
          };
          setState(() {
            _all = results[0] as List<ClubPlayer>;
            _managementMap = {
              for (final row in managementRows) row.playerId: row,
            };
            _physicalReport = physicalReport;
            _physicalMap = {
              for (final player in physicalReport?.players ?? const [])
                player.id: player,
            };
            _wellness = wellness;
            _wellnessMap = wellnessMap;
            _physioMap = {};
          });
        }
      } else {
        final futures = <Future>[
          ClubService().getPlayers(teamId: widget.filterTeamId),
          CoachMonitoringService.getDashboard(),
        ];
        // Physiotherapist's card body shows this player's session summary
        // instead of coach-only wellness metrics — only fetched for them.
        if (isPhysiotherapistRole) {
          futures.add(ApiService.getAllPhysioSessions(limit: 300));
        }
        final results = await Future.wait(futures);
        if (mounted) {
          final wellness = results[1] as CoachDashboardData;
          final wellnessMap = <String, CoachPlayerStatus>{};
          for (final w in wellness.players) {
            wellnessMap[w.name.toLowerCase().trim()] = w;
          }
          final physioMap = <String, _PhysioPlayerSummary>{};
          if (isPhysiotherapistRole && results.length > 2) {
            final sessions = results[2] as List<Map<String, dynamic>>;
            for (final row in sessions) {
              final pid = row['player_id']?.toString();
              if (pid == null || pid.isEmpty) continue;
              final entry = physioMap.putIfAbsent(pid, () => _PhysioPlayerSummary());
              final status = (row['status'] ?? '').toString();
              if (status == 'completed') {
                entry.completed++;
              } else if (status == 'scheduled' || status == 'late') {
                entry.scheduled++;
                final at = row['scheduled_at']?.toString();
                if (at != null &&
                    at.isNotEmpty &&
                    (entry.nextAt == null || at.compareTo(entry.nextAt!) < 0)) {
                  entry.nextAt = at;
                }
              }
            }
          }
          setState(() {
            _all = results[0] as List<ClubPlayer>;
            _wellness = wellness;
            _wellnessMap = wellnessMap;
            _managementMap = {};
            _physicalReport = null;
            _physicalMap = {};
            _physioMap = physioMap;
          });
        }
      }
    } catch (e) {
      AppLogger.e('PlayerManagement', 'Load failed', e);
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Wellness helpers ───────────────────────────────────────────────────────

  CoachPlayerStatus? _wellnessFor(ClubPlayer p) {
    final name = p.fullName.toLowerCase().trim();
    return _wellnessMap[name];
  }

  PlayerManagementReportRow? _managementFor(ClubPlayer p) =>
      _managementMap[p.id];

  // A player with no wellness data at all defaults to status:'normal'
  // server-side — don't count that as genuinely "ready".
  bool _isReadyWellness(CoachPlayerStatus? w) =>
      w != null && w.hasAnyMetric && w.status == 'normal';

  bool _hasIncompleteWellness(CoachPlayerStatus? w) =>
      w == null || !w.hasAnyMetric;

  bool? _readinessFor(ClubPlayer p) {
    if (_physicalReport == null) return null;
    return _physicalMap[p.id]?.isReady ?? true;
  }

  bool get _hasWellnessData => (_wellness?.summary.totalPlayers ?? 0) > 0;

  // ── KPI computations ───────────────────────────────────────────────────────

  int get _readyCount => _all.where((p) {
    if (canViewManagementReport) return _readinessFor(p) == true;
    final w = _wellnessFor(p);
    return p.status == PlayerStatus.active && _isReadyWellness(w);
  }).length;

  int get _notReadyCount =>
      _all.where((p) => _readinessFor(p) == false).length;

  int get _atRiskCount => _all.where((p) {
    final w = _wellnessFor(p);
    return p.status == PlayerStatus.active && w?.status == 'high_risk';
  }).length;

  int get _fatigueCount => _all.where((p) {
    final w = _wellnessFor(p);
    return p.status == PlayerStatus.active && w?.status == 'moderate';
  }).length;

  int get _injuredCount => _all
      .where(
        (p) =>
            p.status == PlayerStatus.injured ||
            p.status == PlayerStatus.recovering,
      )
      .length;

  int get _missingWellnessCount {
    if (!_hasWellnessData) return 0;
    return _all
        .where(
          (p) =>
              p.status == PlayerStatus.active &&
              _hasIncompleteWellness(_wellnessFor(p)),
        )
        .length;
  }

  int get _noAssessmentCount {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    return _all
        .where(
          (p) =>
              p.lastAssessmentAt == null ||
              p.lastAssessmentAt!.isBefore(cutoff),
        )
        .length;
  }

  int get _disciplineThreatCount => _all.where((p) {
        final r = _managementFor(p);
        return r != null && r.currentYellowCards > 0;
      }).length;

  int get _oneCardAwayCount => _all.where((p) {
        final r = _managementFor(p);
        return r?.oneCardToSuspension == true;
      }).length;

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<ClubPlayer> get _filtered {
    return _all.where((p) {
      final q = _query.toLowerCase();
      final matchQ =
          q.isEmpty ||
          p.fullName.toLowerCase().contains(q) ||
          (p.nickname?.toLowerCase().contains(q) ?? false) ||
          p.number.contains(q) ||
          p.position.toLowerCase().contains(q);
      if (!matchQ) return false;

      final w = _wellnessFor(p);
      if (canViewManagementReport) {
        switch (_filter) {
          case _PFilter.all:
            return true;
          case _PFilter.ready:
            return _hasWellnessData
                ? p.status == PlayerStatus.active && _isReadyWellness(w)
                : _readinessFor(p) == true;
          case _PFilter.notReady:
            return _readinessFor(p) == false;
          case _PFilter.injured:
            return p.status == PlayerStatus.injured ||
                p.status == PlayerStatus.recovering;
          case _PFilter.missingWellness:
            return p.status == PlayerStatus.active &&
                _hasIncompleteWellness(w);
          case _PFilter.danger:
            return p.status == PlayerStatus.active &&
                w?.status == 'high_risk';
          case _PFilter.monitoring:
            return w?.status == 'moderate';
          case _PFilter.highFatigue:
            return (w?.hooperScore ?? 0) > 16;
          case _PFilter.noAssessment:
            final cutoff = DateTime.now().subtract(const Duration(days: 14));
            return p.lastAssessmentAt == null ||
                p.lastAssessmentAt!.isBefore(cutoff);
          case _PFilter.disciplineThreat:
            return (_managementFor(p)?.currentYellowCards ?? 0) > 0;
          case _PFilter.oneCardAway:
            return _managementFor(p)?.oneCardToSuspension == true;
        }
      }
      switch (_filter) {
        case _PFilter.all:
          return true;
        case _PFilter.ready:
          return p.status == PlayerStatus.active && _isReadyWellness(w);
        case _PFilter.monitoring:
          return w?.status == 'moderate';
        case _PFilter.danger:
          return w?.status == 'high_risk';
        case _PFilter.notReady:
          return true;
        case _PFilter.injured:
          return p.status == PlayerStatus.injured ||
              p.status == PlayerStatus.recovering;
        case _PFilter.missingWellness:
          return p.status == PlayerStatus.active && _hasIncompleteWellness(w);
        case _PFilter.highFatigue:
          return (w?.hooperScore ?? 0) > 16;
        case _PFilter.noAssessment:
          final cutoff = DateTime.now().subtract(const Duration(days: 14));
          return p.lastAssessmentAt == null ||
              p.lastAssessmentAt!.isBefore(cutoff);
        case _PFilter.disciplineThreat:
          return (_managementFor(p)?.currentYellowCards ?? 0) > 0;
        case _PFilter.oneCardAway:
          return _managementFor(p)?.oneCardToSuspension == true;
      }
    }).toList();
  }

  // ── Attention logic ────────────────────────────────────────────────────────

  bool _needsAttention(ClubPlayer p) {
    if (canViewManagementReport) {
      return _readinessFor(p) == false ||
          p.status == PlayerStatus.injured ||
          p.status == PlayerStatus.recovering;
    }
    if (p.status == PlayerStatus.injured || p.status == PlayerStatus.recovering)
      return true;
    final w = _wellnessFor(p);
    if (w?.status == 'high_risk') return true;
    if ((w?.hooperScore ?? 0) > 16) return true;
    if (p.lastAssessmentAt == null) return true;
    return false;
  }

  int _riskScore(ClubPlayer p) {
    if (canViewManagementReport) {
      if (_readinessFor(p) == false) return 4;
      if (p.status == PlayerStatus.injured) return 3;
      if (p.status == PlayerStatus.recovering) return 2;
      return 0;
    }
    final w = _wellnessFor(p);
    if (p.status == PlayerStatus.injured) return 6;
    if (p.status == PlayerStatus.recovering) return 5;
    if (w?.status == 'high_risk') return 4;
    if ((w?.hooperScore ?? 0) > 16) return 3;
    if (w?.status == 'moderate') return 2;
    if (p.lastAssessmentAt == null) return 1;
    return 0;
  }

  // ── Left-border color (readiness indicator) ────────────────────────────────

  Color _borderColor(ClubPlayer p) {
    if (canViewManagementReport) {
      if (p.status == PlayerStatus.injured) return AppColors.destructive;
      if (p.status == PlayerStatus.recovering) return AppColors.warning;
      final readiness = _readinessFor(p);
      if (readiness == false) return AppColors.destructive;
      if (readiness == true) return AppColors.success;
      return AppColors.border;
    }
    final w = _wellnessFor(p);
    if (p.status == PlayerStatus.injured) return AppColors.destructive;
    if (p.status == PlayerStatus.recovering) return AppColors.warning;
    if (p.status == PlayerStatus.suspended ||
        p.status == PlayerStatus.inactive) {
      return AppColors.muted;
    }
    if (_hasIncompleteWellness(w)) return AppColors.border;
    switch (w!.status) {
      case 'high_risk':
        return AppColors.destructive;
      case 'moderate':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ClubShell(
      currentIndex: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CoachBrandHeader(),
          _Header(
            count: _all.length,
            showingArchived: _showArchived,
            onToggleArchived: () {
              setState(() {
                _showArchived = !_showArchived;
                _query = '';
                _filter = _PFilter.all;
              });
              _load();
            },
            onAdd: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const AddEditPlayerPage()),
              );
              if (changed == true) _load();
            },
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    if (_loadError) return _errorState();

    if (_all.isEmpty) return _emptyState();

    final list = _filtered;
    final widgets = <Widget>[
      // Search + stat cards scroll away with the list (not pinned with the
      // header), so scrolling reveals more of the roster.
      _PlayersSearchField(onQueryChanged: (v) => setState(() => _query = v)),
      if (canViewManagementReport) ...[
        _ManagementMonitoringStrip(
          total: _all.length,
          ready: _readyCount,
          notReady: _notReadyCount,
          filter: _filter,
          onTap: (f) => setState(() => _filter = f),
          disciplineThreat: _disciplineThreatCount,
          oneCardAway: _oneCardAwayCount,
        ),
        const SizedBox(height: 8),
      ] else if (!_showArchived) ...[
        _MonitoringStrip(
          total: _all.length,
          ready: _readyCount,
          atRisk: _atRiskCount,
          fatigue: _fatigueCount,
          injured: _injuredCount,
          missing: _missingWellnessCount,
          noAssessment: _noAssessmentCount,
          filter: _filter,
          onTap: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: 8),
      ],
    ];

    if (list.isEmpty) {
      widgets.add(SizedBox(height: 240, child: _noResults()));
      return RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.card,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: widgets,
        ),
      );
    }

    // Sort: attention first → by risk score → alphabetical
    list.sort((a, b) {
      final aA = _needsAttention(a);
      final bA = _needsAttention(b);
      if (aA && !bA) return -1;
      if (!aA && bA) return 1;
      final rs = _riskScore(b).compareTo(_riskScore(a));
      if (rs != 0) return rs;
      return a.fullName.compareTo(b.fullName);
    });

    // Flat, sorted card list — no "needs attention" / "squad overview"
    // section headers.
    for (final p in list) {
      widgets.add(
        _PlayerPerfCard(
          player: p,
          wellness: _wellnessFor(p),
          management: _managementFor(p),
          readiness: _readinessFor(p),
          managementView: canViewManagementReport && !_showArchived,
          physioSummary: _physioMap[p.id],
          leftBorderColor: _borderColor(p),
          onView: () async {
            if (isDoctorRole) {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => InjuryCaseScreen(
                    playerId: p.id,
                    playerName: p.fullName,
                  ),
                ),
              );
            } else {
              await Navigator.of(context).pushNamed('/club/players/${p.id}');
            }
          },
          onEdit: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => AddEditPlayerPage(player: p)),
            );
            if (changed == true) _load();
          },
          onDelete: () => _confirmDelete(p),
          onArchive: () => _confirmArchive(p),
          onRestore: () => _confirmRestore(p),
          archived: _showArchived,
          onAiTest: () =>
              Navigator.of(context).pushNamed('/club/players/${p.id}'),
        ),
      );
      widgets.add(const SizedBox(height: 8));
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: widgets,
      ),
    );
  }

  Widget _emptyState() {
    if (_showArchived) {
      return ClubEmptyState(
        icon: Icons.inventory_2_outlined,
        title: AppLocalizations.get('no_archived_players'),
        description: AppLocalizations.get('no_archived_players_desc'),
        ctaLabel: AppLocalizations.get('show_active_players'),
        onCta: () {
          setState(() => _showArchived = false);
          _load();
        },
      );
    }
    return ClubEmptyState(
      icon: Icons.person_add_rounded,
      title: AppLocalizations.get('no_players_found_title'),
      description: AppLocalizations.get('add_first_player'),
      ctaLabel: AppLocalizations.get('add_first_player'),
      onCta: () async {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AddEditPlayerPage()));
        _load();
      },
    );
  }

  Widget _noResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: AppColors.muted,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            _query.isNotEmpty
                ? AppLocalizations.get('try_different_search')
                : AppLocalizations.get('no_filter_match'),
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() {
              _query = '';
              _filter = _PFilter.all;
            }),
            child: Text(
              AppLocalizations.get('clear_filters'),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return ClubErrorState(
      title: AppLocalizations.get('error_load_failed'),
      description: AppLocalizations.get('error_check_internet'),
      retryLabel: AppLocalizations.get('retry_btn'),
      onRetry: _load,
    );
  }

  Future<void> _confirmDelete(ClubPlayer p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClubConfirmDialog(
        title: AppLocalizations.get('delete_player_title'),
        confirmLabel: AppLocalizations.get('delete'),
        body: AppLocalizations.format('delete_player_permanent_warning', {
          'name': p.fullName,
        }),
      ),
    );
    if (ok == true && mounted) {
      final deleted = await ClubService().deletePlayerPermanently(p.id);
      if (!mounted) return;
      if (deleted) {
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.get('delete_player_failed'))),
        );
      }
    }
  }

  Future<void> _confirmArchive(ClubPlayer p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClubConfirmDialog(
        title: AppLocalizations.get('archive_player_title'),
        confirmLabel: AppLocalizations.get('archive_player'),
        confirmColor: AppColors.warning,
        body: AppLocalizations.format('archive_player_msg', {
          'name': p.fullName,
        }),
      ),
    );
    if (ok == true && mounted) {
      final archived = await ClubService().archivePlayer(p.id);
      if (!mounted) return;
      if (archived) {
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.get('archive_player_failed'))),
        );
      }
    }
  }

  Future<void> _confirmRestore(ClubPlayer p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClubConfirmDialog(
        title: AppLocalizations.get('restore_player_title'),
        confirmLabel: AppLocalizations.get('restore_player'),
        confirmColor: AppColors.success,
        body: AppLocalizations.format('restore_player_msg', {
          'name': p.fullName,
        }),
      ),
    );
    if (ok == true && mounted) {
      final restored = await ClubService().restorePlayer(p.id);
      if (!mounted) return;
      if (restored) {
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.get('restore_player_failed'))),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.showingArchived,
    required this.onToggleArchived,
    required this.onAdd,
  });
  final int count;
  final bool showingArchived;
  final VoidCallback onToggleArchived;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      color: Colors.transparent,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.people_rounded,
                color: AppColors.maroon,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${AppLocalizations.get(
                    showingArchived ? 'archived_players' : 'players_title',
                  )} ($count)',
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canDeletePlayers)
                IconButton(
                  onPressed: onToggleArchived,
                  tooltip: AppLocalizations.get(
                    showingArchived
                        ? 'show_active_players'
                        : 'show_archived_players',
                  ),
                  icon: Icon(
                    showingArchived
                        ? Icons.groups_rounded
                        : Icons.inventory_2_outlined,
                    color: showingArchived
                        ? AppColors.primary
                        : AppColors.muted,
                    size: 18,
                  ),
                ),
              if (canManagePlayers)
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_rounded,
                          color: Color(0xFF3A2A08),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.get('add_player_btn'),
                          style: const TextStyle(
                            color: Color(0xFF3A2A08),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
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
// Search field — scrolls away with the list content (not pinned with the
// header), so scrolling reveals more of the roster.
// ─────────────────────────────────────────────────────────────────────────────

class _PlayersSearchField extends StatelessWidget {
  const _PlayersSearchField({required this.onQueryChanged});
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: TextField(
        onChanged: onQueryChanged,
        style: const TextStyle(color: AppColors.foreground, fontSize: 14),
        decoration: InputDecoration(
          hintText: AppLocalizations.get('search_players'),
          hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.muted,
            size: 20,
          ),
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.primary,
              width: 1.2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Monitoring Strip — 6 tap-able KPIs
// ─────────────────────────────────────────────────────────────────────────────

class _MonitoringStrip extends StatelessWidget {
  const _MonitoringStrip({
    required this.total,
    required this.ready,
    required this.atRisk,
    required this.fatigue,
    required this.injured,
    required this.missing,
    required this.noAssessment,
    required this.filter,
    required this.onTap,
  });

  final int total, ready, atRisk, fatigue, injured, missing, noAssessment;
  final _PFilter filter;
  final ValueChanged<_PFilter> onTap;

  @override
  Widget build(BuildContext context) {
    // Exactly 4 equal, fully-visible cards, always in a single row (compact
    // padding/icon/font on narrow phones so nothing wraps to 2x2).
    // Injured/missing/no-AI-test remain reachable as real filters
    // (_PFilter still has them), just not shown as a 5th-7th chip here.
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 340;
          final cards = [
            ClubMetricCard(
              icon: Icons.groups_rounded,
              color: AppColors.gold,
              value: '$total',
              label: AppLocalizations.get('strip_total'),
              selected: filter == _PFilter.all,
              onTap: () => onTap(_PFilter.all),
              width: double.infinity,
              compact: compact,
            ),
            ClubMetricCard(
              icon: Icons.check_circle_rounded,
              color: AppColors.success,
              value: '$ready',
              label: AppLocalizations.get('status_ready'),
              selected: filter == _PFilter.ready,
              onTap: () => onTap(_PFilter.ready),
              width: double.infinity,
              compact: compact,
            ),
            ClubMetricCard(
              icon: Icons.warning_amber_rounded,
              color: AppColors.warning,
              value: '$fatigue',
              label: AppLocalizations.get('needs_follow_up'),
              selected: filter == _PFilter.monitoring,
              onTap: () => onTap(_PFilter.monitoring),
              width: double.infinity,
              compact: compact,
            ),
            ClubMetricCard(
              icon: Icons.error_rounded,
              color: AppColors.hero,
              value: '$atRisk',
              label: AppLocalizations.get('status_high_risk'),
              alert: atRisk > 0,
              selected: filter == _PFilter.danger,
              onTap: () => onTap(_PFilter.danger),
              width: double.infinity,
              compact: compact,
            ),
          ];
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) SizedBox(width: compact ? 6 : 8),
                Expanded(child: cards[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ManagementMonitoringStrip extends StatelessWidget {
  const _ManagementMonitoringStrip({
    required this.total,
    required this.ready,
    required this.notReady,
    required this.filter,
    required this.onTap,
    required this.disciplineThreat,
    required this.oneCardAway,
  });

  final int total;
  final int ready;
  final int notReady;
  final _PFilter filter;
  final ValueChanged<_PFilter> onTap;
  final int disciplineThreat;
  final int oneCardAway;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.get('management_player_summary_subtitle'),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ClubMetricCard(
                    icon: Icons.group_rounded,
                    color: AppColors.primary,
                    value: '$total',
                    label: AppLocalizations.get('strip_total'),
                    selected: filter == _PFilter.all,
                    onTap: () => onTap(_PFilter.all),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ClubMetricCard(
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success,
                    value: '$ready',
                    label: AppLocalizations.get('physical_status_ready'),
                    selected: filter == _PFilter.ready,
                    onTap: () => onTap(_PFilter.ready),
                  ),
                ),
                ClubMetricCard(
                  icon: Icons.pause_circle_rounded,
                  color: AppColors.destructive,
                  value: '$notReady',
                  label: AppLocalizations.get('physical_status_not_ready'),
                  alert: notReady > 0,
                  selected: filter == _PFilter.notReady,
                  onTap: () => onTap(_PFilter.notReady),
                ),
                const SizedBox(width: 8),
                ClubMetricCard(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  value: '$disciplineThreat',
                  label: 'المهددون بالإيقاف',
                  alert: disciplineThreat > 0,
                  selected: filter == _PFilter.disciplineThreat,
                  onTap: () => onTap(_PFilter.disciplineThreat),
                ),
                const SizedBox(width: 8),
                ClubMetricCard(
                  icon: Icons.style_rounded,
                  color: AppColors.destructive,
                  value: '$oneCardAway',
                  label: 'باقي كرت واحد ويوقف',
                  alert: oneCardAway > 0,
                  selected: filter == _PFilter.oneCardAway,
                  onTap: () => onTap(_PFilter.oneCardAway),
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
// Section Label
// ─────────────────────────────────────────────────────────────────────────────

// ignore: unused_element
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
  });
  final String label;
  final IconData icon;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Player Performance Card
// ─────────────────────────────────────────────────────────────────────────────

// Per-player physio session counts for the physiotherapist's card body —
// aggregated client-side from the club-wide recent sessions list.
class _PhysioPlayerSummary {
  int completed = 0;
  int scheduled = 0;
  String? nextAt;
}

class _PlayerPerfCard extends StatelessWidget {
  const _PlayerPerfCard({
    required this.player,
    required this.wellness,
    required this.management,
    required this.readiness,
    required this.managementView,
    this.physioSummary,
    required this.leftBorderColor,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
    required this.onRestore,
    required this.archived,
    required this.onAiTest,
  });

  final ClubPlayer player;
  final CoachPlayerStatus? wellness;
  final PlayerManagementReportRow? management;
  final bool? readiness;
  final bool managementView;
  final _PhysioPlayerSummary? physioSummary;
  final Color leftBorderColor;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final bool archived;
  final VoidCallback onAiTest;

  bool get _isInjured =>
      player.status == PlayerStatus.injured ||
      player.status == PlayerStatus.recovering;

  bool get _needsAiTest {
    if (player.lastAssessmentAt == null) return true;
    return DateTime.now().difference(player.lastAssessmentAt!).inDays > 14;
  }

  bool _hasIncompleteWellness(CoachPlayerStatus? w) =>
      w == null || !w.hasAnyMetric;

  String _missingFieldsLabel() {
    final w = wellness;
    final missing = <String>[];
    if (w?.hooperScore == null) missing.add(AppLocalizations.get('label_hooper'));
    if (w?.rpe == null) missing.add('RPE');
    if (w?.trainingLoad == null) missing.add(AppLocalizations.get('label_load'));
    if (w?.bodyFat == null) missing.add(AppLocalizations.get('body_fat'));
    if (w?.fmsScore == null) missing.add('FMS');
    return missing.join('، ');
  }

  Color get _scoreColor {
    final s = player.latestScore ?? 0;
    if (s >= 80) return AppColors.success;
    if (s >= 60) return AppColors.warning;
    return AppColors.destructive;
  }

  static final _latinOnly = RegExp(r'^[A-Za-z0-9\s.\-]+$');
  bool _isLatin(String s) => s.trim().isNotEmpty && _latinOnly.hasMatch(s.trim());

  // A long full name wraps to 2 lines and can still look cramped — prefer
  // the nickname (when set) once the name is long enough to likely wrap,
  // to keep every card's name area visually consistent.
  String get _displayName {
    final isArabic = getAppLanguage() == 'ar';
    final nameAr = player.nameArabic.trim();
    final baseName = (isArabic && nameAr.isNotEmpty) ? nameAr : player.fullName;

    final nickname = player.nickname?.trim() ?? '';
    if (nickname.isNotEmpty && baseName.trim().length > 18) {
      return nickname;
    }
    return baseName;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = clubStatusColor(player.status);

    return GestureDetector(
      onTap: archived ? null : onView,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [AppColors.gold.withOpacity(0.65), AppColors.card],
            stops: const [0.0, 0.42],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left status-tinted panel — shows the real player photo
                // when available (per the app's existing photo feature),
                // falling back to a faded silhouette like the design mock.
                // ~26% of the card's own width (flex, not the device width,
                // so it stays correct inside list padding).
                Expanded(
                  flex: 26,
                  child: Stack(
                    children: [
                      if (player.profileImageUrl?.isNotEmpty == true)
                        Positioned.fill(
                          child: Image.network(
                            player.profileImageUrl!,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (_, __, ___) => Container(
                              color: statusColor.withOpacity(0.08),
                              alignment: Alignment.center,
                              child: Icon(Icons.person_rounded,
                                  size: 48, color: statusColor.withOpacity(0.25)),
                            ),
                          ),
                        )
                      else
                        Positioned.fill(
                          child: Container(
                            color: statusColor.withOpacity(0.08),
                            alignment: Alignment.center,
                            child: Icon(Icons.person_rounded,
                                size: 48, color: statusColor.withOpacity(0.25)),
                          ),
                        ),
                      PositionedDirectional(
                        bottom: 8,
                        end: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.maroon,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white, width: 1.2),
                          ),
                          child: Text(
                            '#${player.number.isNotEmpty ? player.number : '-'}',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 74,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 7, 12, 9),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Directionality(
                                textDirection: _isLatin(_displayName)
                                    ? TextDirection.ltr
                                    : TextDirection.rtl,
                                child: Align(
                                  alignment: AlignmentDirectional.topStart,
                                  child: Text(
                                    _displayName,
                                    style: const TextStyle(
                                      color: AppColors.foreground,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      height: 1.15,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 7,
                                runSpacing: 3,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_positionTeam().isNotEmpty)
                                    Text(
                                      _positionTeam(),
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ClubStatusBadge(
                                    label: player.status.localizedLabel,
                                    color: statusColor,
                                  ),
                                ],
                              ),
                              if (_isInjured && player.expectedReturnDate != null) ...[
                                const SizedBox(height: 4),
                                _ReturnDateRow(
                                  date: player.expectedReturnDate!,
                                  color: statusColor,
                                ),
                              ],
                              const SizedBox(height: 4),
                              _PlayerVitalsRow(player: player),
                              const SizedBox(height: 4),
                              const Divider(color: AppColors.border, height: 1),
                              const SizedBox(height: 4),
                              if (managementView)
                                _ManagementIndicatorsRow(
                                  report: management,
                                  readiness: readiness,
                                )
                              else if (isDoctorRole)
                                _MedicalStatusRow(player: player)
                              else if (isPhysiotherapistRole)
                                _PhysioSessionsRow(summary: physioSummary)
                              else if (isCoachRole && _hasIncompleteWellness(wellness)) ...[
                                Text.rich(
                                  TextSpan(children: [
                                    TextSpan(
                                      text: '${AppLocalizations.get('missing_data_label')}: ',
                                      style: const TextStyle(
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                      ),
                                    ),
                                    TextSpan(
                                      text: _missingFieldsLabel(),
                                      style: const TextStyle(
                                        color: AppColors.textSoft,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  textDirection: TextDirection.rtl,
                                  children: [
                                    if (canRunAssessments) ...[
                                      Expanded(
                                        child: _CardActionButton(
                                          label: AppLocalizations.get('complete_data_btn'),
                                          filled: true,
                                          onTap: onAiTest,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: _CardActionButton(
                                        label: AppLocalizations.get('action_view_profile'),
                                        filled: false,
                                        onTap: onView,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                _WellnessRow(wellness: wellness),
                                if (player.latestScore != null) ...[
                                  const SizedBox(height: 10),
                                  _ScoreBar(
                                    score: player.latestScore!,
                                    color: _scoreColor,
                                    lastAt: player.lastAssessmentAt,
                                  ),
                                  if (!_needsAiTest && canRunAssessments) ...[
                                    const SizedBox(height: 7),
                                    Align(
                                      alignment: AlignmentDirectional.centerStart,
                                      child: _AiTestCta(onTap: onAiTest),
                                    ),
                                  ],
                                ],
                              ],
                            ],
                          ),
                        ),
                        PositionedDirectional(
                          top: 0,
                          end: 0,
                          child: _ActionMenu(
                            onView: onView,
                            onEdit: onEdit,
                            onDelete: onDelete,
                            onArchive: onArchive,
                            onRestore: onRestore,
                            archived: archived,
                          ),
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

  String _positionTeam() {
    final parts = <String>[];
    if (player.position.isNotEmpty) {
      parts.add(AppLocalizations.positionLabel(player.position));
    }
    if (player.teamName?.isNotEmpty == true) parts.add(player.teamName!);
    return parts.join('  ·  ');
  }
}

class _ManagementIndicatorsRow extends StatelessWidget {
  const _ManagementIndicatorsRow({
    required this.report,
    required this.readiness,
  });

  final PlayerManagementReportRow? report;
  final bool? readiness;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ManagementIndicator(
                icon: readiness == false
                    ? Icons.pause_circle_rounded
                    : Icons.check_circle_rounded,
                value: readiness == null
                    ? '—'
                    : AppLocalizations.get(
                        readiness!
                            ? 'physical_status_ready'
                            : 'physical_status_not_ready',
                      ),
                color: readiness == null
                    ? AppColors.muted
                    : readiness!
                    ? AppColors.success
                    : AppColors.destructive,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ManagementIndicator(
                icon: Icons.timer_rounded,
                value: report == null ? '—' : '${report!.minutes}',
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _ManagementIndicator(
                icon: Icons.task_alt_rounded,
                value: report == null
                    ? '—'
                    : '${report!.completedSessions}/${report!.assignedSessions}',
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ManagementIndicator(
                icon: Icons.style_rounded,
                value: report == null
                    ? '—'
                    : '${report!.yellowCards} / ${report!.redCards}',
                color: AppColors.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ManagementIndicator extends StatelessWidget {
  const _ManagementIndicator({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Doctor's card body — medical status only, never diagnosis/exam detail
// (that lives behind InjuryCaseScreen, which is where onView already sends
// the doctor role on tap).
// ─────────────────────────────────────────────────────────────────────────────

class _MedicalStatusRow extends StatelessWidget {
  const _MedicalStatusRow({required this.player});
  final ClubPlayer player;

  bool get _isInjured =>
      player.status == PlayerStatus.injured ||
      player.status == PlayerStatus.recovering;

  @override
  Widget build(BuildContext context) {
    final reason = player.unavailableReason?.trim();
    return _ManagementIndicator(
      icon: Icons.medical_services_rounded,
      value: reason?.isNotEmpty == true
          ? reason!
          : (_isInjured
              ? AppLocalizations.get('under_medical_followup')
              : AppLocalizations.get('no_medical_restrictions')),
      color: _isInjured ? AppColors.destructive : AppColors.success,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Physiotherapist's card body — this player's session counts, nothing
// clinical (specialist notes/contraindications stay behind the physio
// session detail screen).
// ─────────────────────────────────────────────────────────────────────────────

class _PhysioSessionsRow extends StatelessWidget {
  const _PhysioSessionsRow({required this.summary});
  final _PhysioPlayerSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Row(
      children: [
        Expanded(
          child: _ManagementIndicator(
            icon: Icons.task_alt_rounded,
            value: '${s?.completed ?? 0} ${AppLocalizations.get('physio_status_completed')}',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ManagementIndicator(
            icon: Icons.event_rounded,
            value: '${s?.scheduled ?? 0} ${AppLocalizations.get('physio_status_scheduled')}',
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wellness Indicators Row
// ─────────────────────────────────────────────────────────────────────────────

class _WellnessRow extends StatelessWidget {
  const _WellnessRow({required this.wellness});
  final CoachPlayerStatus? wellness;

  Color _hooColor(double h) {
    if (h <= 10) return AppColors.success;
    if (h <= 16) return AppColors.warning;
    return AppColors.destructive;
  }

  Color _rpeColor(double r) {
    if (r <= 5) return AppColors.success;
    if (r <= 7) return AppColors.warning;
    return AppColors.destructive;
  }

  Color _fatColor(double f) {
    if (f <= 18) return AppColors.success;
    if (f <= 25) return AppColors.warning;
    return AppColors.destructive;
  }

  Color _fmsColor(int s) {
    if (s >= 17) return AppColors.success;
    if (s >= 12) return AppColors.warning;
    return AppColors.destructive;
  }

  @override
  Widget build(BuildContext context) {
    final w = wellness;

    if (w == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle_outlined, color: AppColors.muted, size: 9),
            const SizedBox(width: 5),
            Text(
              AppLocalizations.get('no_wellness_today'),
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (isCoachRole)
          _WellnessChip(
            icon: Icons.battery_alert_rounded,
            value: MetricFormatter.number(
              w.hooperScore,
              digits: 0,
              zeroIsUnavailable: true,
            ),
            label: AppLocalizations.get('label_hooper'),
            color: w.hooperScore != null
                ? _hooColor(w.hooperScore!)
                : AppColors.muted,
          ),
        _WellnessChip(
          icon: Icons.bolt_rounded,
          value: MetricFormatter.rpe(w.rpe),
          label: AppLocalizations.get('label_rpe'),
          color: w.rpe != null ? _rpeColor(w.rpe!) : AppColors.muted,
        ),
        if (isCoachRole) ...[
          _WellnessChip(
            icon: Icons.fitness_center_rounded,
            value: MetricFormatter.load(w.trainingLoad),
            label: AppLocalizations.get('label_load'),
            color: AppColors.muted,
          ),
          _WellnessChip(
            icon: Icons.monitor_weight_rounded,
            value: MetricFormatter.bodyFat(w.bodyFat),
            label: AppLocalizations.get('body_fat'),
            color: w.bodyFat != null ? _fatColor(w.bodyFat!) : AppColors.muted,
          ),
          _WellnessChip(
            icon: Icons.checklist_rtl_rounded,
            value: MetricFormatter.number(
              w.fmsScore,
              digits: 0,
              zeroIsUnavailable: true,
            ),
            label: 'FMS',
            color: w.fmsScore != null ? _fmsColor(w.fmsScore!) : AppColors.muted,
          ),
        ],
      ],
    );
  }
}

class _WellnessChip extends StatelessWidget {
  const _WellnessChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '$value $label',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score Bar
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.score,
    required this.color,
    required this.lastAt,
  });
  final double score;
  final Color color;
  final DateTime? lastAt;

  String _ageLabel() {
    if (lastAt == null) return '';
    final d = DateTime.now().difference(lastAt!).inDays;
    if (d == 0) return AppLocalizations.get('today_label');
    if (d == 1) return AppLocalizations.get('yesterday_label');
    if (d < 7) return AppLocalizations.format('age_days_ago', {'days': d});
    if (d < 30)
      return AppLocalizations.format('age_weeks_ago', {
        'weeks': (d / 7).round(),
      });
    return AppLocalizations.format('age_months_ago', {
      'months': (d / 30).round(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final pct = (score / 100).clamp(0.0, 1.0);
    final ageLabel = _ageLabel();
    return Column(
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_graph_rounded,
              color: AppColors.muted,
              size: 13,
            ),
            const SizedBox(width: 5),
            Text(
              AppLocalizations.get('latest_assessment'),
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              score.toStringAsFixed(0),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            if (ageLabel.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                ageLabel,
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: AppColors.surface2,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact two-button row for a card with incomplete wellness data —
// "Complete data" (filled) / "View profile" (outlined).
// ─────────────────────────────────────────────────────────────────────────────

class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? AppColors.maroon : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: filled ? null : Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: filled ? Colors.white : AppColors.foreground,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI Test CTA — "view result" only; the "start test" CTA was removed from
// this list (still reachable from the player detail page).
// ─────────────────────────────────────────────────────────────────────────────

class _AiTestCta extends StatelessWidget {
  const _AiTestCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.10),
          borderRadius: BorderRadius.circular(ClubUiTokens.buttonRadius - 4),
          border: Border.all(color: AppColors.success.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bar_chart_rounded,
              color: AppColors.success,
              size: 12,
            ),
            const SizedBox(width: 5),
            Text(
              AppLocalizations.get('ai_view_result'),
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Return Date Row
// ─────────────────────────────────────────────────────────────────────────────

class _ReturnDateRow extends StatelessWidget {
  const _ReturnDateRow({required this.date, required this.color});
  final DateTime date;
  final Color color;

  String _text() {
    final diff = date.difference(DateTime.now()).inDays;
    if (diff <= 0) return AppLocalizations.get('return_overdue');
    if (diff == 1) return AppLocalizations.get('returns_tomorrow');
    if (diff < 7)
      return AppLocalizations.format('returns_in_days', {'days': diff});
    return AppLocalizations.format('returns_on_date', {
      'date': '${date.day}/${date.month}',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.event_rounded, size: 10, color: color),
        const SizedBox(width: 4),
        Text(
          _text(),
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vitals row — age / weight / height with dividers, per the design mock.
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerVitalsRow extends StatelessWidget {
  const _PlayerVitalsRow({required this.player});
  final ClubPlayer player;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _vital(
            icon: Icons.calendar_today_rounded,
            value: player.age > 0 ? '${player.age}' : '-',
            unit: AppLocalizations.get('unit_years'),
          ),
        ),
        Container(width: 1, height: 16, color: AppColors.border),
        Expanded(
          child: _vital(
            icon: Icons.monitor_weight_outlined,
            value: player.weight != null ? player.weight!.toStringAsFixed(0) : '-',
            unit: AppLocalizations.get('unit_kg'),
          ),
        ),
        Container(width: 1, height: 16, color: AppColors.border),
        Expanded(
          child: _vital(
            icon: Icons.height_rounded,
            value: player.height != null ? player.height!.toStringAsFixed(0) : '-',
            unit: AppLocalizations.get('unit_cm'),
          ),
        ),
      ],
    );
  }

  Widget _vital({required IconData icon, required String value, required String unit}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.muted),
        const SizedBox(width: 3),
        Text(value,
            style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
        const SizedBox(width: 2),
        Text(unit,
            style: const TextStyle(color: AppColors.muted, fontSize: 9)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar
// ─────────────────────────────────────────────────────────────────────────────

// ignore: unused_element
class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.player, required this.statusColor});
  final ClubPlayer player;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = player.profileImageUrl?.isNotEmpty == true;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor.withOpacity(0.10),
            border: Border.all(
              color: statusColor.withOpacity(0.40),
              width: 1.5,
            ),
          ),
          child: ClipOval(
            child: hasPhoto
                ? Image.network(
                    player.profileImageUrl!,
                    fit: BoxFit.cover,
                    width: 44,
                    height: 44,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        player.initials,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      player.initials,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
          ),
        ),
        if (player.number.isNotEmpty)
          Positioned(
            bottom: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.hero,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.card, width: 1.5),
              ),
              child: Text(
                '#${player.number}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action Menu
// ─────────────────────────────────────────────────────────────────────────────

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
    required this.onRestore,
    required this.archived,
  });
  final VoidCallback onView, onEdit, onDelete, onArchive, onRestore;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Action>(
      icon: const Icon(
        Icons.more_vert_rounded,
        color: AppColors.muted,
        size: 18,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      iconSize: 18,
      color: AppColors.card,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        if (!archived)
          _item(
            _Action.view,
            Icons.person_rounded,
            AppColors.foreground,
            AppLocalizations.get('action_view_profile'),
          ),
        if (!archived && canManagePlayers)
          _item(
            _Action.edit,
            Icons.edit_rounded,
            AppColors.primary,
            AppLocalizations.get('edit_btn'),
          ),
        if (canDeletePlayers) ...[
          const PopupMenuDivider(height: 1),
          _item(
            archived ? _Action.restore : _Action.archive,
            archived ? Icons.unarchive_rounded : Icons.archive_outlined,
            AppColors.warning,
            AppLocalizations.get(
              archived ? 'restore_player' : 'archive_player',
            ),
          ),
          _item(
            _Action.delete,
            Icons.delete_outline_rounded,
            AppColors.destructive,
            AppLocalizations.get('delete'),
          ),
        ],
      ],
      onSelected: (a) {
        switch (a) {
          case _Action.view:
            onView();
            break;
          case _Action.edit:
            onEdit();
            break;
          case _Action.archive:
            onArchive();
            break;
          case _Action.restore:
            onRestore();
            break;
          case _Action.delete:
            onDelete();
            break;
        }
      },
    );
  }

  PopupMenuItem<_Action> _item(
    _Action value,
    IconData icon,
    Color color,
    String label,
  ) {
    return PopupMenuItem(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Action { view, edit, archive, restore, delete }
