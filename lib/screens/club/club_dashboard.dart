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

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Navigation — enterprise minimal style
// ─────────────────────────────────────────────────────────────────────────────

class _ClubBottomNav extends StatelessWidget {
  const _ClubBottomNav({required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final tabs = [
      _Tab('/club', Icons.grid_view_rounded, Icons.grid_view_rounded, 'Home'),
      _Tab('/club/players', Icons.group_rounded, Icons.group_rounded, 'Players'),
      _Tab('/club/sessions', Icons.sports_rounded, Icons.sports_rounded, 'Sessions'),
      _Tab('/club/reports', Icons.bar_chart_rounded, Icons.bar_chart_rounded, 'Reports'),
      _Tab('/club/settings', Icons.settings_rounded, Icons.settings_rounded, 'Settings'),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(4, 0, 4, math.max(6, bottom * 0.25)),
      decoration: BoxDecoration(
        color: const Color(0xff0A0A12),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),
        ),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final tab = tabs[i];
          final active = i == currentIndex;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!active) ClubShell.go(context, tab.route);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Active indicator bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 2,
                    width: active ? 24 : 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Icon(
                    tab.icon,
                    size: 21,
                    color: active ? AppColors.primary : Colors.white.withOpacity(0.30),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active ? AppColors.primary : Colors.white.withOpacity(0.30),
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Tab {
  _Tab(this.route, this.icon, this.activeIcon, this.label);
  final String route;
  final IconData icon;
  final IconData activeIcon;
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
  late AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _statsLoading = true);
    try {
      final results = await Future.wait([
        ClubService().getDashboardStats(),
        ClubService().getSessions(),
        ClubService().getPlayers(),
        ClubService().getLatestAssessments(limit: 5),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as DashboardStats;
        _recentSessions = (results[1] as List<TrainingSession>).take(3).toList();
        _recentPlayers = (results[2] as List<ClubPlayer>).take(6).toList();
        _latestResults = results[3] as List<PlayerAssessment>;
        _statsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClubShell(
      currentIndex: 0,
      child: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: const Color(0xff14131E),
        strokeWidth: 2,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildInsightCards(),
            const SizedBox(height: 20),
            _buildPerformanceSection(),
            const SizedBox(height: 20),
            _buildQuickActions(),
            const SizedBox(height: 24),
            _sectionHeader('Recent Sessions', Icons.calendar_today_rounded,
                onTap: () => Navigator.of(context).pushNamed('/club/sessions')),
            const SizedBox(height: 12),
            if (_statsLoading)
              _buildListShimmer(height: 124)
            else if (_recentSessions.isNotEmpty)
              _buildRecentSessions()
            else
              _buildEmptyState(
                icon: Icons.sports_rounded,
                label: 'No sessions yet',
                sub: 'Create your first training session',
                onTap: () => Navigator.of(context).pushNamed('/club/sessions'),
              ),
            const SizedBox(height: 24),
            _sectionHeader('Squad Overview', Icons.group_rounded,
                onTap: () => Navigator.of(context).pushNamed('/club/players')),
            const SizedBox(height: 12),
            if (_statsLoading)
              _buildRowShimmer(count: 3)
            else if (_recentPlayers.isNotEmpty)
              _buildRecentPlayers()
            else
              _buildEmptyState(
                icon: Icons.person_rounded,
                label: 'No players added',
                sub: 'Add players to your squad first',
                onTap: () => Navigator.of(context).pushNamed('/club/players'),
              ),
            const SizedBox(height: 24),
            _sectionHeader('Latest Assessments', Icons.assessment_rounded,
                onTap: () => Navigator.of(context).pushNamed('/club/reports')),
            const SizedBox(height: 12),
            if (_statsLoading)
              _buildRowShimmer(count: 3)
            else if (_latestResults.isNotEmpty)
              _buildLatestResults()
            else
              _buildEmptyState(
                icon: Icons.assessment_rounded,
                label: 'No assessments recorded',
                sub: 'Run an AI assessment to see results here',
                onTap: () => Navigator.of(context).pushNamed('/club/players'),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final now = DateTime.now();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final dateStr = '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';

    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff120810), Color(0xff0D0C15)],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: logo + club info + bell
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Premium club badge
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primarySoft,
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.50),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.18),
                      blurRadius: 14,
                      spreadRadius: 0,
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
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Al Merrikh SC',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.gold.withOpacity(0.25),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                  color: AppColors.gold,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          'Performance Hub',
                          style: TextStyle(
                            color: AppColors.gold.withOpacity(0.70),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                        Container(
                          width: 3,
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _NotifBell(count: _stats.playersNeedingReview),
            ],
          ),
          const SizedBox(height: 14),
          // AI status badge (UI only — no data logic)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.20),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.55),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'AI Performance Active',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Greeting + name
          Text(
            _greeting(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            currentUserName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 24,
              height: 1.1,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 16),
          // Metric strip
          Row(
            children: [
              _MetricChip(
                value: _statsLoading ? '—' : '${_stats.totalPlayers}',
                label: 'Players',
                color: Colors.white,
                zeroHint: 'No players yet',
              ),
              _MetricDivider(),
              _MetricChip(
                value: _statsLoading ? '—' : '${_stats.sessionsToday}',
                label: 'Sessions Today',
                color: Colors.white,
                zeroHint: 'None scheduled',
              ),
              _MetricDivider(),
              _MetricChip(
                value: _statsLoading ? '—' : '${_stats.injuredPlayers}',
                label: 'Injured',
                color: _stats.injuredPlayers > 0 ? AppColors.warning : Colors.white,
                zeroHint: 'All clear',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Insight cards (2×2 grid) ────────────────────────────────────────────────

  Widget _buildInsightCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _insightTrainingLoad()),
              const SizedBox(width: 10),
              Expanded(child: _insightReadiness()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _insightInjuryRisk()),
              const SizedBox(width: 10),
              Expanded(child: _insightAIMotion()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _insightTrainingLoad() {
    final hasData = !_statsLoading && _stats.sessionsToday > 0;
    final isEmpty = !_statsLoading && _stats.sessionsToday == 0;
    return _InsightCard(
      icon: Icons.fitness_center_rounded,
      title: 'Training Load',
      accent: AppColors.primary,
      loading: _statsLoading,
      child: hasData
          ? _InsightValue(
              value: '${_stats.sessionsToday}',
              sub: 'sessions today',
            )
          : isEmpty
              ? _InsightEmpty(
                  message: 'No sessions today',
                  actionLabel: 'Create Session',
                  onTap: () => Navigator.of(context).pushNamed('/club/sessions'),
                )
              : const SizedBox.shrink(),
    );
  }

  Widget _insightReadiness() {
    final hasPlayers = !_statsLoading && _stats.totalPlayers > 0;
    final noPlayers = !_statsLoading && _stats.totalPlayers == 0;
    final pct = hasPlayers
        ? (_stats.activePlayers / _stats.totalPlayers * 100).round()
        : 0;
    return _InsightCard(
      icon: Icons.sports_score_rounded,
      title: 'Squad Readiness',
      accent: AppColors.gold,
      loading: _statsLoading,
      child: hasPlayers
          ? _InsightValue(
              value: '$pct%',
              sub: '${_stats.activePlayers}/${_stats.totalPlayers} active',
            )
          : noPlayers
              ? _InsightEmpty(
                  message: 'No players added',
                  actionLabel: 'Add Player',
                  onTap: () => Navigator.of(context).pushNamed('/club/players'),
                )
              : const SizedBox.shrink(),
    );
  }

  Widget _insightInjuryRisk() {
    final hasPlayers = !_statsLoading && _stats.totalPlayers > 0;
    final noPlayers = !_statsLoading && _stats.totalPlayers == 0;
    final injured = _stats.injuredPlayers;
    return _InsightCard(
      icon: Icons.medical_services_rounded,
      title: 'Injury Risk',
      accent: injured > 0 ? AppColors.warning : AppColors.primary,
      loading: _statsLoading,
      child: hasPlayers
          ? _InsightValue(
              value: '$injured',
              sub: injured > 0 ? 'players injured' : 'No injuries recorded',
              valueColor: injured > 0 ? AppColors.warning : null,
            )
          : noPlayers
              ? _InsightEmpty(
                  message: 'Add players first',
                  actionLabel: 'View Players',
                  onTap: () => Navigator.of(context).pushNamed('/club/players'),
                )
              : const SizedBox.shrink(),
    );
  }

  Widget _insightAIMotion() {
    final hasData = !_statsLoading &&
        (_stats.assessmentsToday > 0 || _latestResults.isNotEmpty);
    final noData = !_statsLoading &&
        _stats.assessmentsToday == 0 &&
        _latestResults.isEmpty;
    return _InsightCard(
      icon: Icons.auto_awesome_rounded,
      title: 'AI Analysis',
      accent: const Color(0xff7B68EE),
      loading: _statsLoading,
      child: hasData
          ? _InsightValue(
              value: '${_stats.assessmentsToday > 0 ? _stats.assessmentsToday : _latestResults.length}',
              sub: _stats.assessmentsToday > 0 ? 'analyses today' : 'total analyses',
            )
          : noData
              ? _InsightEmpty(
                  message: 'No analyses yet',
                  actionLabel: 'Start AI Test',
                  onTap: () => Navigator.of(context).pushNamed('/club/players'),
                )
              : const SizedBox.shrink(),
    );
  }

  // ── Performance section ─────────────────────────────────────────────────────

  Widget _buildPerformanceSection() {
    final hasData = !_statsLoading &&
        (_stats.avgMovementScore > 0 || _stats.avgStabilityScore > 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Squad Performance',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.1,
                  ),
                ),
                const Spacer(),
                if (hasData)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'NO DATA',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.25),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_statsLoading) ...[
              _ShimmerBox(width: double.infinity, height: 38, radius: 8),
              const SizedBox(height: 12),
              _ShimmerBox(width: double.infinity, height: 38, radius: 8),
            ] else if (hasData) ...[
              _PerformanceRow(
                label: 'Movement Quality',
                value: _stats.avgMovementScore / 100,
                score: _stats.avgMovementScore,
                color: AppColors.primary,
                loading: false,
              ),
              const SizedBox(height: 12),
              _PerformanceRow(
                label: 'Stability Index',
                value: _stats.avgStabilityScore / 100,
                score: _stats.avgStabilityScore,
                color: AppColors.gold,
                loading: false,
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white.withOpacity(0.18),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No analysis data yet',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.50),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Run an AI assessment to generate\nmovement & stability scores',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.25),
                              fontSize: 10.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () =>
                          Navigator.of(context).pushNamed('/club/players'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.30),
                            width: 0.5,
                          ),
                        ),
                        child: const Text(
                          'Start Test',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Quick actions ───────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              'Quick Actions',
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Row(
            children: [
              _QuickAction(
                icon: Icons.videocam_rounded,
                label: 'Start AI Test',
                accent: AppColors.primary,
                onTap: () => Navigator.of(context).pushNamed('/club/players'),
              ),
              const SizedBox(width: 8),
              _QuickAction(
                icon: Icons.person_add_rounded,
                label: 'Add Player',
                accent: AppColors.gold,
                onTap: () => Navigator.of(context).pushNamed('/club/players'),
              ),
              const SizedBox(width: 8),
              _QuickAction(
                icon: Icons.add_circle_outline_rounded,
                label: 'New Session',
                accent: const Color(0xff7B68EE),
                onTap: () => Navigator.of(context).pushNamed('/club/sessions'),
              ),
              const SizedBox(width: 8),
              _QuickAction(
                icon: Icons.bar_chart_rounded,
                label: 'Reports',
                accent: const Color(0xff20B2AA),
                onTap: () => Navigator.of(context).pushNamed('/club/reports'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Recent sessions ─────────────────────────────────────────────────────────

  Widget _buildRecentSessions() {
    return SizedBox(
      height: 124,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _recentSessions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _SessionCard(session: _recentSessions[i]),
      ),
    );
  }

  // ── Recent players ──────────────────────────────────────────────────────────

  Widget _buildRecentPlayers() {
    return Column(
      children: _recentPlayers
          .map((p) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _PlayerRow(
                  player: p,
                  onTap: () => Navigator.of(context)
                      .pushNamed('/club/players/${p.id}'),
                ),
              ))
          .toList(),
    );
  }

  // ── Latest results ──────────────────────────────────────────────────────────

  Widget _buildLatestResults() {
    return Column(
      children: _latestResults
          .map((a) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _ResultRow(assessment: a),
              ))
          .toList(),
    );
  }

  // ── Loading shimmer helpers ─────────────────────────────────────────────────

  Widget _buildListShimmer({required double height}) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, __) => _ShimmerBox(width: 190, height: height, radius: 16),
      ),
    );
  }

  Widget _buildRowShimmer({required int count}) {
    return Column(
      children: List.generate(count, (i) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: _ShimmerBox(width: double.infinity, height: 56, radius: 14),
      )),
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String label,
    required String sub,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white.withOpacity(0.20), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.25),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withOpacity(0.15),
                  size: 14,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section header ──────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.25), size: 14),
          const SizedBox(width: 7),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 1.1,
            ),
          ),
          const Spacer(),
          if (onTap != null)
            GestureDetector(
              onTap: onTap,
              child: Row(
                children: [
                  Text(
                    'See all',
                    style: TextStyle(
                      color: AppColors.primary.withOpacity(0.80),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppColors.primary.withOpacity(0.70),
                    size: 10,
                  ),
                ],
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
// Metric strip helpers
// ─────────────────────────────────────────────────────────────────────────────

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.value,
    required this.label,
    required this.color,
    this.zeroHint,
  });
  final String value;
  final String label;
  final Color color;
  final String? zeroHint;

  @override
  Widget build(BuildContext context) {
    final isZero = value == '0';
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isZero && zeroHint != null) ...[
            const SizedBox(height: 2),
            Text(
              zeroHint!,
              style: TextStyle(
                color: Colors.white.withOpacity(0.20),
                fontSize: 9,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white.withOpacity(0.08),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification Bell
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
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Icon(
            Icons.notifications_outlined,
            color: Colors.white.withOpacity(0.50),
            size: 19,
          ),
        ),
        if (count > 0)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 15,
              height: 15,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Performance Row — inside the squad performance card
// ─────────────────────────────────────────────────────────────────────────────

class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow({
    required this.label,
    required this.value,
    required this.score,
    required this.color,
    this.loading = false,
  });
  final String label;
  final double value;
  final double score;
  final Color color;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final pct = loading ? 0.0 : value.clamp(0.0, 1.0);
    final scoreStr = loading ? '--' : score.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              scoreStr,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              ' / 100',
              style: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            FractionallySizedBox(
              widthFactor: pct,
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withOpacity(0.7),
                      color,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Action
// ─────────────────────────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Insight Card — 2×2 grid card with empty state support
// ─────────────────────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.title,
    required this.accent,
    required this.child,
    this.loading = false,
  });
  final IconData icon;
  final String title;
  final Color accent;
  final Widget child;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      decoration: BoxDecoration(
        color: const Color(0xff0D0C15),
        borderRadius: BorderRadius.circular(18),
        border: Border(
          top: BorderSide(color: accent.withOpacity(0.45), width: 1.5),
          left: BorderSide(color: Colors.white.withOpacity(0.05)),
          right: BorderSide(color: Colors.white.withOpacity(0.05)),
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 15),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 22,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 70,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            )
          else
            child,
        ],
      ),
    );
  }
}

class _InsightValue extends StatelessWidget {
  const _InsightValue({
    required this.value,
    required this.sub,
    this.valueColor,
  });
  final String value;
  final String sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 26,
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          sub,
          style: TextStyle(
            color: Colors.white.withOpacity(0.38),
            fontSize: 10,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _InsightEmpty extends StatelessWidget {
  const _InsightEmpty({
    required this.message,
    required this.actionLabel,
    required this.onTap,
  });
  final String message;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: TextStyle(
            color: Colors.white.withOpacity(0.28),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.25),
                width: 0.5,
              ),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session Card
// ─────────────────────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});
  final TrainingSession session;

  @override
  Widget build(BuildContext context) {
    final pct = session.playerIds.isEmpty
        ? 0.0
        : session.completedPlayerIds.length / session.playerIds.length;
    final pctInt = (pct * 100).round();

    return GestureDetector(
      onTap: () =>
          Navigator.of(context).pushNamed('/club/sessions/${session.id}'),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    session.type.label.split(' ').first.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 8.5,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '$pctInt%',
                  style: TextStyle(
                    color: pctInt == 100
                        ? AppColors.success
                        : Colors.white.withOpacity(0.55),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
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
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              session.teamName ?? 'No team',
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 10.5,
              ),
            ),
            const Spacer(),
            Stack(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: pctInt == 100 ? AppColors.success : AppColors.primary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${session.completedPlayerIds.length}/${session.playerIds.length} assessed',
              style: TextStyle(
                color: Colors.white.withOpacity(0.30),
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Player Row
// ─────────────────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
                border: Border.all(
                  color: statusColor.withOpacity(0.40),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  player.initials,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
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
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${player.position}  ·  #${player.number}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
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
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    player.status.label,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 9.5,
                    ),
                  ),
                ),
                if (player.latestScore != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${player.latestScore!.toStringAsFixed(0)} pts',
                    style: TextStyle(
                      color: AppColors.gold.withOpacity(0.90),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.18),
              size: 16,
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
    final score = assessment.overallScore;
    final color = score >= 80
        ? AppColors.success
        : score >= 60
            ? AppColors.warning
            : AppColors.destructive;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_typeIcon(), color: color, size: 18),
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
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_typeLabel()}  ·  ${_formatDate(assessment.date)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                score.toStringAsFixed(0),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  height: 1,
                ),
              ),
              Text(
                'pts',
                style: TextStyle(
                  color: color.withOpacity(0.55),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
      case AssessmentType.squat:          return 'Squat';
      case AssessmentType.singleLegBalance: return 'Balance';
      case AssessmentType.jumpLanding:    return 'Jump Landing';
      default:                            return 'Assessment';
    }
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer Box — loading placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 12,
  });
  final double width;
  final double height;
  final double radius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(
            const Color(0xff14131E),
            const Color(0xff1E1D2C),
            _anim.value,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Club Settings Page
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
      backgroundColor: const Color(0xff10101A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Select Language',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 16),
            ...['English', 'العربية', 'Français'].map((lang) {
              return GestureDetector(
                onTap: () {
                  final code = lang == 'English' ? 'en' : lang == 'العربية' ? 'ar' : 'fr';
                  setAppLanguage(code);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Text(
                      lang,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
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
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 24,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Preferences & account',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          _SettingsTile(
            icon: Icons.language_rounded,
            title: 'Language',
            subtitle: 'Select app language',
            accent: const Color(0xff7B68EE),
            onTap: _showLanguageSelector,
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () async {
              await FirebaseService().signOut();
              await OnboardingStore().clearSignedIn();
              currentUserName = 'Player';
              if (!mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/auth', (_) => false);
            },
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.destructive.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.destructive.withOpacity(0.20)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.destructive.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.logout_rounded,
                        color: AppColors.destructive, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Sign Out',
                    style: TextStyle(
                      color: AppColors.destructive,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
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
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.20),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
