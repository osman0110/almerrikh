import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_colors.dart';
import '../../app_constants.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../storage.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shell
// ─────────────────────────────────────────────────────────────────────────────

class ParentShell extends StatelessWidget {
  const ParentShell({super.key, required this.child, this.currentIndex = 0});

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
                    _ParentBottomNav(currentIndex: currentIndex),
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

class _ParentBottomNav extends StatelessWidget {
  const _ParentBottomNav({required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final tabs = [
      _Tab('/parent', Icons.home_rounded, 'الرئيسية'),
      _Tab('/parent/child', Icons.child_care_rounded, 'نجلي'),
      _Tab('/parent/reports', Icons.bar_chart_rounded, 'التقارير'),
      _Tab('/parent/profile', Icons.person_rounded, 'حسابي'),
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
                if (!active) ParentShell.go(context, tab.route);
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
                      color: const Color(0xff6A1B9A),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Icon(
                    tab.icon,
                    size: 21,
                    color: active
                        ? const Color(0xff6A1B9A)
                        : Colors.white.withOpacity(0.30),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active
                          ? const Color(0xff6A1B9A)
                          : Colors.white.withOpacity(0.30),
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
// Parent Dashboard Page
// ─────────────────────────────────────────────────────────────────────────────

class ParentDashboardPage extends StatelessWidget {
  const ParentDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ParentShell(
      currentIndex: 0,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildChildCard(context)),
          SliverToBoxAdapter(child: _buildQuickActions(context)),
          SliverToBoxAdapter(child: _buildActivity()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
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
                  'متابعة أداء نجلك',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          _IconBtn(icon: Icons.notifications_outlined, onTap: () {}),
        ],
      ),
    );
  }

  Widget _buildChildCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff4A148C), Color(0xff6A1B9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.child_care_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'نجلك',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                const Text(
                  'لم يتم الربط بعد',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => ParentShell.go(context, '/parent/child'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'ربط حساب اللاعب',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                  icon: Icons.bar_chart_rounded,
                  label: 'التقارير',
                  color: const Color(0xff6A1B9A),
                  onTap: () => ParentShell.go(context, '/parent/reports'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.history_rounded,
                  label: 'السجل',
                  color: const Color(0xff6A1B9A),
                  onTap: () => ParentShell.go(context, '/parent/child'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.message_outlined,
                  label: 'المدرب',
                  color: const Color(0xff6A1B9A),
                  onTap: () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivity() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'آخر النشاطات',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.timeline_rounded,
                    color: Colors.white.withOpacity(0.18), size: 48),
                const SizedBox(height: 12),
                Text(
                  'لا يوجد نشاط بعد',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.40), fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'اربط حساب نجلك لمتابعة تقدمه',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.28), fontSize: 12),
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
// Parent Profile Page
// ─────────────────────────────────────────────────────────────────────────────

class ParentProfilePage extends StatelessWidget {
  const ParentProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ParentShell(
      currentIndex: 3,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: const Row(
              children: [
                Text(
                  'حسابي',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xff6A1B9A).withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        currentUserName.isNotEmpty
                            ? currentUserName[0].toUpperCase()
                            : 'P',
                        style: const TextStyle(
                          color: Color(0xff6A1B9A),
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    currentUserName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ولي الأمر',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _ProfileAction(
                    icon: Icons.child_care_rounded,
                    label: 'إدارة حساب نجلي',
                    onTap: () => ParentShell.go(context, '/parent/child'),
                  ),
                  const SizedBox(height: 10),
                  _ProfileAction(
                    icon: Icons.settings_rounded,
                    label: 'الإعدادات',
                    onTap: () {},
                  ),
                  const SizedBox(height: 10),
                  _ProfileAction(
                    icon: Icons.logout_rounded,
                    label: 'تسجيل الخروج',
                    color: Colors.red,
                    onTap: () async {
                      await OnboardingStore().clearSignedIn();
                      if (!context.mounted) return;
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/auth', (_) => false);
                    },
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
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

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
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xff0F0E1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.25), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coming Soon pages for unbuilt parent sections
// ─────────────────────────────────────────────────────────────────────────────

class ParentChildPage extends StatelessWidget {
  const ParentChildPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ParentShell(
      currentIndex: 1,
      child: _ComingSoon(title: 'نجلي', icon: Icons.child_care_rounded),
    );
  }
}

class ParentReportsPage extends StatelessWidget {
  const ParentReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ParentShell(
      currentIndex: 2,
      child: _ComingSoon(title: 'التقارير', icon: Icons.bar_chart_rounded),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}
