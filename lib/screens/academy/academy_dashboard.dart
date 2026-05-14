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

// ─────────────────────────────────────────────────────────────────────────────
// Shell
// ─────────────────────────────────────────────────────────────────────────────

class AcademyShell extends StatelessWidget {
  const AcademyShell({super.key, required this.child, this.currentIndex = 0});

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
                    _AcademyBottomNav(currentIndex: currentIndex),
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

class _AcademyBottomNav extends StatelessWidget {
  const _AcademyBottomNav({required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final tabs = [
      _Tab('/academy', Icons.grid_view_rounded, 'الرئيسية'),
      _Tab('/academy/students', Icons.group_rounded, 'الطلاب'),
      _Tab('/academy/sessions', Icons.sports_rounded, 'البرامج'),
      _Tab('/academy/reports', Icons.bar_chart_rounded, 'التقارير'),
      _Tab('/academy/settings', Icons.settings_rounded, 'الإعدادات'),
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
                if (!active) AcademyShell.go(context, tab.route);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 2,
                    width: active ? 24 : 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xff1565C0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Icon(
                    tab.icon,
                    size: 21,
                    color: active ? const Color(0xff1565C0) : Colors.white.withOpacity(0.30),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active ? const Color(0xff1565C0) : Colors.white.withOpacity(0.30),
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
  _Tab(this.route, this.icon, this.label);
  final String route;
  final IconData icon;
  final String label;
}

// ─────────────────────────────────────────────────────────────────────────────
// Academy Dashboard Page
// ─────────────────────────────────────────────────────────────────────────────

class AcademyDashboardPage extends StatefulWidget {
  const AcademyDashboardPage({super.key});

  @override
  State<AcademyDashboardPage> createState() => _AcademyDashboardPageState();
}

class _AcademyDashboardPageState extends State<AcademyDashboardPage>
    with SingleTickerProviderStateMixin {
  DashboardStats _stats = DashboardStats();
  List<ClubPlayer> _recentStudents = [];
  bool _loading = false;
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
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ClubService().getDashboardStats(),
        ClubService().getPlayers(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as DashboardStats;
        _recentStudents = (results[1] as List<ClubPlayer>).take(6).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AcademyShell(
      currentIndex: 0,
      child: RefreshIndicator(
        onRefresh: _load,
        color: const Color(0xff1565C0),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildStatRow()),
            SliverToBoxAdapter(child: _buildQuickActions(context)),
            SliverToBoxAdapter(child: _buildRecentStudents(context)),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مرحباً، $currentUserName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'لوحة تحكم الأكاديمية',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          _IconBtn(
            icon: Icons.notifications_outlined,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          _IconBtn(
            icon: Icons.person_outline_rounded,
            onTap: () => Navigator.of(context).pushNamed('/academy/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow() {
    final items = [
      _StatItem('الطلاب', '${_stats.totalPlayers}', Icons.group_rounded),
      _StatItem('الفرق', '${_stats.totalTeams}', Icons.sports_soccer_rounded),
      _StatItem('اليوم', '${_stats.sessionsToday}', Icons.calendar_today_rounded),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: items
            .map((s) => Expanded(child: _buildStatCard(s)))
            .toList(),
      ),
    );
  }

  Widget _buildStatCard(_StatItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xff0F0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          Icon(item.icon, color: const Color(0xff1565C0), size: 20),
          const SizedBox(height: 8),
          Text(
            item.value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إجراءات سريعة',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  icon: Icons.add_rounded,
                  label: 'تقييم جديد',
                  color: const Color(0xff1565C0),
                  onTap: () => Navigator.of(context).pushNamed('/physical-assessment'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.group_add_rounded,
                  label: 'إضافة طالب',
                  color: const Color(0xff1565C0),
                  onTap: () => Navigator.of(context).pushNamed('/academy/students'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.bar_chart_rounded,
                  label: 'التقارير',
                  color: const Color(0xff1565C0),
                  onTap: () => Navigator.of(context).pushNamed('/academy/reports'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentStudents(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الطلاب الأخيرون',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/academy/students'),
                child: const Text(
                  'عرض الكل',
                  style: TextStyle(color: Color(0xff1565C0), fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Color(0xff1565C0)),
              ),
            )
          else if (_recentStudents.isEmpty)
            _EmptyState(
              icon: Icons.group_outlined,
              message: 'لا يوجد طلاب بعد',
              actionLabel: 'إضافة طالب',
              onAction: () => Navigator.of(context).pushNamed('/academy/students'),
            )
          else
            ..._recentStudents.map((s) => _StudentTile(student: s)),
        ],
      ),
    );
  }
}

class _StatItem {
  _StatItem(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.student});
  final ClubPlayer student;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xff0F0E1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xff1565C0).withOpacity(0.18),
            child: Text(
              student.fullName.isNotEmpty ? student.fullName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Color(0xff1565C0),
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  student.position.isNotEmpty ? student.position : 'طالب',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.25), size: 20),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.18), size: 48),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Colors.white.withOpacity(0.40), fontSize: 14),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xff1565C0).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xff1565C0).withOpacity(0.35)),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  color: Color(0xff1565C0),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Academy Settings Page (stub)
// ─────────────────────────────────────────────────────────────────────────────

class AcademySettingsPage extends StatelessWidget {
  const AcademySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AcademyShell(
      currentIndex: 4,
      child: _ComingSoonBody(
        title: 'الإعدادات',
        icon: Icons.settings_rounded,
        onSignOut: () async {
          await OnboardingStore().clearSignedIn();
          if (!context.mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
        },
      ),
    );
  }
}

class _ComingSoonBody extends StatelessWidget {
  const _ComingSoonBody({
    required this.title,
    required this.icon,
    this.onSignOut,
  });
  final String title;
  final IconData icon;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white.withOpacity(0.18), size: 56),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'قريباً',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 14,
                  ),
                ),
                if (onSignOut != null) ...[
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: onSignOut,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.30)),
                      ),
                      child: const Text(
                        'تسجيل الخروج',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
