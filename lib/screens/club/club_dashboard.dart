import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_colors.dart';
import '../../app_constants.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../storage.dart';
import '../../api_service.dart';
import '../../services/firebase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shell – wraps every club management page with nav
// ─────────────────────────────────────────────────────────────────────────────

class ClubShell extends StatelessWidget {
  const ClubShell({
    super.key,
    required this.child,
    this.currentIndex = 0,
  });

  final Widget child;
  final int currentIndex;

  static void go(BuildContext ctx, String route) =>
      Navigator.of(ctx).pushNamedAndRemoveUntil(route, (_) => false);

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Theme(
        data: isAr
            ? Theme.of(context).copyWith(
                textTheme: GoogleFonts.tajawalTextTheme(Theme.of(context).textTheme),
              )
            : Theme.of(context),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
                child: Column(
                  children: [
                    Expanded(child: child),
                    _ClubBottomNav(currentIndex: currentIndex),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClubBottomNav extends StatelessWidget {
  const _ClubBottomNav({required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final tabs = [
      _Tab('/club', Icons.dashboard_rounded, 'Dashboard'),
      _Tab('/club/players', Icons.people_rounded, 'Players'),
      _Tab('/club/sessions', Icons.sports_rounded, 'Sessions'),
      _Tab('/club/reports', Icons.bar_chart_rounded, 'Reports'),
      _Tab('/club/settings', Icons.settings_rounded, 'Settings'),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, math.max(8, bottom * 0.3)),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(top: BorderSide(color: AppColors.border, width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(tabs.length, (i) {
          final tab = tabs[i];
          final active = i == currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (!active) ClubShell.go(context, tab.route);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                decoration: BoxDecoration(
                  color: active ? AppColors.primarySoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.icon,
                      size: 22,
                      color: active ? AppColors.primary : AppColors.muted,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tab.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                        color: active ? AppColors.primary : AppColors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Tab {
  _Tab(this.route, this.icon, this.label);
  final String route;
  final IconData icon;
  final String label;
}

// ─────────────────────────────────────────────────────────────────────────────
// Club Dashboard Page
// ─────────────────────────────────────────────────────────────────────────────

class ClubDashboardPage extends StatefulWidget {
  const ClubDashboardPage({super.key});

  @override
  State<ClubDashboardPage> createState() => _ClubDashboardPageState();
}

class _ClubDashboardPageState extends State<ClubDashboardPage>
    with SingleTickerProviderStateMixin {
  DashboardStats _stats = DashboardStats();
  List<TrainingSession> _recentSessions = [];
  List<ClubPlayer> _recentPlayers = [];
  List<PlayerAssessment> _latestResults = [];
  bool _statsLoading = false;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    // Load stats in background WITHOUT blocking UI
    _loadStatsAsync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadStatsAsync() async {
    // Load stats in background without blocking UI
    setState(() => _statsLoading = true);
    try {
      final start = DateTime.now();
      final stats = await ClubService().getDashboardStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _statsLoading = false;
      });
      final ms = DateTime.now().difference(start).inMilliseconds;
      debugPrint('[Dashboard] Stats loaded in ${ms}ms');
    } catch (e) {
      if (mounted) setState(() => _statsLoading = false);
      debugPrint('[Dashboard] Stats error: $e');
    }
  }

  Future<void> _load() async {
    // Manual refresh - load everything
    setState(() => _statsLoading = true);
    try {
      final results = await Future.wait([
        ClubService().getDashboardStats(),
        ClubService().getSessions(),
        ClubService().getPlayers(),
        ClubService().getLatestAssessments(limit: 4),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as DashboardStats;
        _recentSessions = (results[1] as List<TrainingSession>).take(3).toList();
        _recentPlayers = (results[2] as List<ClubPlayer>).take(5).toList();
        _latestResults = results[3] as List<PlayerAssessment>;
        _statsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _statsLoading = false);
      debugPrint('[Dashboard] Refresh error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always show dashboard UI immediately - stats load in background
    return ClubShell(
      currentIndex: 0,
      child: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.card,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildStatsGrid(),
            const SizedBox(height: 24),
            _buildQuickActions(),
            const SizedBox(height: 24),
            if (_recentSessions.isNotEmpty) ...[
              _buildSectionTitle('Recent Sessions', Icons.sports_rounded,
                  onTap: () => Navigator.of(context).pushNamed('/club/sessions')),
              const SizedBox(height: 12),
              _buildRecentSessions(),
              const SizedBox(height: 24),
            ],
            if (_recentPlayers.isNotEmpty) ...[
              _buildSectionTitle('Players', Icons.people_rounded,
                  onTap: () => Navigator.of(context).pushNamed('/club/players')),
              const SizedBox(height: 12),
              _buildRecentPlayers(),
              const SizedBox(height: 24),
            ],
            if (_latestResults.isNotEmpty) ...[
              _buildSectionTitle('Latest Results', Icons.assessment_rounded,
                  onTap: () => Navigator.of(context).pushNamed('/club/reports')),
              const SizedBox(height: 12),
              _buildLatestResults(),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff1A0A10), Color(0xff0E0810), Color(0xff150A12)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          // Red glow
          Positioned(
            right: -20,
            top: -20,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary
                          .withOpacity(0.06 + _pulse.value * 0.04),
                      blurRadius: 60,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Gold accent
          Positioned(
            left: -30,
            bottom: -10,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withOpacity(0.04),
                    blurRadius: 50,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Club logo
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primarySoft,
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.5), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.25),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        logoAsset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.shield_rounded,
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Al Merrikh SC',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          'Performance Management',
                          style: TextStyle(
                            color: AppColors.gold.withOpacity(0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _NotifBell(count: _stats.playersNeedingReview),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _greeting(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                currentUserName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              // Performance strip
              Row(
                children: [
                  _HeaderChip(
                    icon: Icons.people_rounded,
                    value: '${_stats.totalPlayers}',
                    label: 'Players',
                    pulse: _pulse,
                  ),
                  const SizedBox(width: 10),
                  _HeaderChip(
                    icon: Icons.sports_rounded,
                    value: '${_stats.sessionsToday}',
                    label: 'Sessions Today',
                    pulse: _pulse,
                  ),
                  const SizedBox(width: 10),
                  _HeaderChip(
                    icon: Icons.warning_amber_rounded,
                    value: '${_stats.injuredPlayers}',
                    label: 'Injured',
                    pulse: _pulse,
                    isAlert: _stats.injuredPlayers > 0,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stats grid ─────────────────────────────────────────────────────────────

  Widget _buildStatsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.people_alt_rounded,
                  label: 'Total Players',
                  value: '${_stats.totalPlayers}',
                  sub: '${_stats.activePlayers} active',
                  color: AppColors.primary,
                  loading: _statsLoading,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.sports_soccer_rounded,
                  label: 'Teams',
                  value: '${_stats.totalTeams}',
                  sub: 'registered',
                  color: AppColors.gold,
                  loading: _statsLoading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.assessment_rounded,
                  label: 'Assessments Today',
                  value: '${_stats.assessmentsToday}',
                  sub: 'completed',
                  color: const Color(0xff7B68EE),
                  loading: _statsLoading,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.healing_rounded,
                  label: 'Need Review',
                  value: '${_stats.playersNeedingReview}',
                  sub: 'score < 65',
                  color: AppColors.warning,
                  loading: _statsLoading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Performance bars
          _PerformanceBar(
            label: 'Avg Movement Quality',
            value: _stats.avgMovementScore / 100,
            color: AppColors.primary,
            score: _stats.avgMovementScore,
            loading: _statsLoading,
          ),
          const SizedBox(height: 8),
          _PerformanceBar(
            label: 'Avg Stability Score',
            value: _stats.avgStabilityScore / 100,
            color: AppColors.gold,
            score: _stats.avgStabilityScore,
            loading: _statsLoading,
          ),
        ],
      ),
    );
  }

  // ── Quick actions ──────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _QuickAction(
                icon: Icons.people_rounded,
                label: 'Players',
                color: AppColors.primary,
                onTap: () => Navigator.of(context).pushNamed('/club/players'),
              ),
              const SizedBox(width: 10),
              _QuickAction(
                icon: Icons.sports_rounded,
                label: 'Sessions',
                color: AppColors.gold,
                onTap: () => Navigator.of(context).pushNamed('/club/sessions'),
              ),
              const SizedBox(width: 10),
              _QuickAction(
                icon: Icons.videocam_rounded,
                label: 'AI Assess',
                color: const Color(0xff7B68EE),
                onTap: () => Navigator.of(context).pushNamed('/club/players'),
              ),
              const SizedBox(width: 10),
              _QuickAction(
                icon: Icons.bar_chart_rounded,
                label: 'Reports',
                color: const Color(0xff20B2AA),
                onTap: () => Navigator.of(context).pushNamed('/club/reports'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Recent sessions ────────────────────────────────────────────────────────

  Widget _buildRecentSessions() {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _recentSessions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _SessionCard(session: _recentSessions[i]),
      ),
    );
  }

  // ── Recent players ─────────────────────────────────────────────────────────

  Widget _buildRecentPlayers() {
    return Column(
      children: _recentPlayers
          .map((p) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: _PlayerRow(
                  player: p,
                  onTap: () => Navigator.of(context)
                      .pushNamed('/club/players/${p.id}'),
                ),
              ))
          .toList(),
    );
  }

  // ── Latest results ─────────────────────────────────────────────────────────

  Widget _buildLatestResults() {
    return Column(
      children: _latestResults
          .map((a) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: _ResultRow(assessment: a),
              ))
          .toList(),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon,
      {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          if (onTap != null)
            GestureDetector(
              onTap: onTap,
              child: Text(
                'See all',
                style: TextStyle(
                  color: AppColors.primary.withOpacity(0.85),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _NotifBell extends StatelessWidget {
  const _NotifBell({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: const Icon(Icons.notifications_rounded,
              color: Colors.white70, size: 20),
        ),
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.pulse,
    this.isAlert = false,
  });
  final IconData icon;
  final String value;
  final String label;
  final Animation<double> pulse;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    final color = isAlert ? AppColors.warning : AppColors.primary;
    return Expanded(
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08 + pulse.value * 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.20)),
          ),
          child: child,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    this.loading = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color color;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          loading
              ? Container(
                  height: 28,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    height: 1,
                  ),
                ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(
              color: Colors.white.withOpacity(0.40),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceBar extends StatelessWidget {
  const _PerformanceBar({
    required this.label,
    required this.value,
    required this.color,
    required this.score,
    this.loading = false,
  });
  final String label;
  final double value;
  final Color color;
  final double score;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: loading ? 0 : value.clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            loading ? '--' : score.toStringAsFixed(1),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});
  final TrainingSession session;

  @override
  Widget build(BuildContext context) {
    final pct = session.playerIds.isEmpty
        ? 0.0
        : session.completedPlayerIds.length / session.playerIds.length;
    return GestureDetector(
      onTap: () =>
          Navigator.of(context).pushNamed('/club/sessions/${session.id}'),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.06),
              blurRadius: 16,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    session.type.label.split(' ').first,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${(pct * 100).round()}%',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              session.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              session.teamName ?? 'No team',
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 11,
              ),
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct.clamp(0, 1),
                minHeight: 4,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${session.completedPlayerIds.length}/${session.playerIds.length} assessed',
              style: TextStyle(
                color: Colors.white.withOpacity(0.40),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.onTap});
  final ClubPlayer player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(player.status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primarySoft,
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.35), width: 1.5),
              ),
              child: Center(
                child: Text(
                  player.initials,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.fullName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${player.position} · #${player.number}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withOpacity(0.25)),
                  ),
                  child: Text(
                    player.status.label,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
                if (player.latestScore != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${player.latestScore!.toStringAsFixed(0)} pts',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(PlayerStatus s) {
    switch (s) {
      case PlayerStatus.active:     return AppColors.success;
      case PlayerStatus.injured:    return AppColors.destructive;
      case PlayerStatus.recovering: return AppColors.warning;
      case PlayerStatus.inactive:   return AppColors.muted;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Result Row — Latest Assessment
// ─────────────────────────────────────────────────────────────────────────────

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.assessment});
  final PlayerAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final color = assessment.overallScore >= 80
        ? AppColors.success
        : assessment.overallScore >= 60
            ? AppColors.warning
            : AppColors.destructive;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Type icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _typeIcon(),
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assessment.playerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _typeLabel(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '  ·  ',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.20),
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      _formatDate(assessment.date),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Score badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.30)),
            ),
            child: Text(
              assessment.overallScore.toStringAsFixed(0),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon() {
    switch (assessment.type) {
      case AssessmentType.squat:
        return Icons.airline_seat_legroom_extra_rounded;
      case AssessmentType.singleLegBalance:
        return Icons.accessibility_new_rounded;
      case AssessmentType.jumpLanding:
        return Icons.moving_rounded;
      default:
        return Icons.sports_score_rounded;
    }
  }

  String _typeLabel() {
    switch (assessment.type) {
      case AssessmentType.squat:
        return 'Squat';
      case AssessmentType.singleLegBalance:
        return 'Balance';
      case AssessmentType.jumpLanding:
        return 'Jump';
      default:
        return 'Custom';
    }
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Club Settings Page (simple placeholder with sign-out)
// ─────────────────────────────────────────────────────────────────────────────

class ClubSettingsPage extends StatefulWidget {
  const ClubSettingsPage({super.key});

  @override
  State<ClubSettingsPage> createState() => _ClubSettingsPageState();
}

class _ClubSettingsPageState extends State<ClubSettingsPage> {
  void _showLanguageSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Language',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            ...['English', 'العربية', 'Français'].map((lang) {
              return GestureDetector(
                onTap: () {
                  final code = lang == 'English' ? 'en' : lang == 'العربية' ? 'ar' : 'fr';
                  setAppLanguage(code);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      lang,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClubShell(
      currentIndex: 4,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 24),
          _SettingsTile(
            icon: Icons.language_rounded,
            title: 'Language',
            subtitle: 'Select app language',
            onTap: _showLanguageSelector,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () async {
              await ApiService.logout();
              await FirebaseService().signOut();
              await OnboardingStore().clearSignedIn();
              currentUserName = 'Player';
              if (!mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/auth', (_) => false);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.destructive.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.destructive.withOpacity(0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout_rounded, color: AppColors.destructive),
                  SizedBox(width: 12),
                  Text(
                    'Sign Out',
                    style: TextStyle(
                      color: AppColors.destructive,
                      fontWeight: FontWeight.w800,
                    ),
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

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
