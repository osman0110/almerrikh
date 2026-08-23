import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_colors.dart';
import '../../app_constants.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import 'organization_config.dart';
import 'org_nav_helper.dart';

// Re-export OrganizationType so existing importers (ClubShell) don't need an
// additional import for OrganizationConfig.
export 'organization_config.dart' show OrganizationType;

// ─────────────────────────────────────────────────────────────────────────────
// OrganizationShell — club app shell (bottom nav + safe area + RTL/LTR)
// ─────────────────────────────────────────────────────────────────────────────

class OrganizationShell extends StatelessWidget {
  const OrganizationShell({
    super.key,
    required this.child,
    required this.organizationType,
    this.currentIndex = 0,
  });

  final Widget child;
  final OrganizationType organizationType;
  final int currentIndex;

  OrganizationConfig get _config => OrganizationConfig.forType(organizationType);

  static void go(BuildContext ctx, String route) =>
      Navigator.of(ctx).pushNamedAndRemoveUntil(route, (_) => false);

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final isAr = getAppLanguage() == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: GoogleFonts.alexandriaTextTheme(Theme.of(context).textTheme),
        ),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
                child: Column(
                  children: [
                    if (config.showTopStripe)
                      Container(height: 2, color: config.accentColor),
                    Expanded(child: child),
                    _OrgBottomNav(currentIndex: currentIndex, config: config),
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
// Unified Bottom Navigation
// ─────────────────────────────────────────────────────────────────────────────

class _OrgBottomNav extends StatelessWidget {
  const _OrgBottomNav({required this.currentIndex, required this.config});

  final int currentIndex;
  final OrganizationConfig config;

  List<_NavTab> _tabs() {
    if (OrgNavHelper.useCompactAdminNavigation) {
      return [
        _NavTab(
          config.homeRoute,
          Icons.grid_view_rounded,
          AppLocalizations.get('nav_dashboard'),
          activeIndexes: const {0},
        ),
        _NavTab(
          config.playersRoute,
          Icons.group_rounded,
          _resolveLabel(config.playersLabelKey),
          activeIndexes: const {1},
        ),
        _NavTab(
          config.sessionsRoute,
          Icons.calendar_month_rounded,
          AppLocalizations.get('admin_nav_schedule'),
          activeIndexes: const {2},
        ),
        _NavTab(
          config.reportsRoute,
          Icons.bar_chart_rounded,
          AppLocalizations.get('nav_reports_tab'),
          activeIndexes: const {4},
        ),
        _NavTab(
          '',
          Icons.more_horiz_rounded,
          AppLocalizations.get('nav_more'),
          activeIndexes: const {3, 5, 6},
          isMore: true,
        ),
      ];
    }

    return [
      _NavTab(
        config.homeRoute,
        Icons.grid_view_rounded,
        AppLocalizations.get('nav_dashboard'),
        activeIndexes: const {0},
      ),
      if (OrgNavHelper.showPlayers)
        _NavTab(
          config.playersRoute,
          Icons.group_rounded,
          _resolveLabel(config.playersLabelKey),
          activeIndexes: const {1},
        ),
      if (OrgNavHelper.showSessions)
        _NavTab(
          config.sessionsRoute,
          Icons.sports_rounded,
          _resolveLabel(config.sessionsLabelKey),
          activeIndexes: const {2},
        ),
      if (OrgNavHelper.showMatches)
        _NavTab(
          '${config.routePrefix}/matches',
          Icons.sports_soccer_rounded,
          AppLocalizations.get('nav_matches'),
          activeIndexes: const {3},
        ),
      if (OrgNavHelper.showReports)
        _NavTab(
          config.reportsRoute,
          Icons.bar_chart_rounded,
          AppLocalizations.get('nav_reports_tab'),
          activeIndexes: const {4},
        ),
      if (OrgNavHelper.showSettings)
        _NavTab(
          config.settingsRoute,
          Icons.settings_rounded,
          AppLocalizations.get('nav_settings_tab'),
          activeIndexes: const {6},
        ),
    ];
  }

  static String _resolveLabel(String key) => AppLocalizations.get(key);

  @override
  Widget build(BuildContext context) {
    final tabs   = _tabs();
    final bottom = MediaQuery.of(context).padding.bottom;
    return _buildPillNav(context, tabs, bottom);
  }

  // ── Club nav — floating rounded pill bar (Al Merrikh design) ──────────────

  Widget _buildPillNav(
      BuildContext context, List<_NavTab> tabs, double bottom) {
    final isAr = getAppLanguage() == 'ar';
    final showLabels = isDoctorRole;
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, math.max(14, bottom)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: showLabels ? 72 : 60,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: config.navBackground.withOpacity(0.94),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: config.navBorderColor),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.foreground.withOpacity(0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(tabs.length, (i) {
                  final tab    = tabs[i];
                  final active = tab.activeIndexes.contains(currentIndex);
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (tab.isMore) {
                          _showMoreSheet(context);
                        } else if (!active) {
                          OrganizationShell.go(context, tab.route);
                        }
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 2.5,
                            width: active ? 16 : 0,
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: config.navActiveIconColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? config.navActiveIconColor.withOpacity(0.12)
                                  : Colors.transparent,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              tab.icon,
                              size: 22,
                              color: active
                                  ? config.navActiveIconColor
                                  : config.navInactiveColor,
                            ),
                          ),
                          if (showLabels) ...[
                            const SizedBox(height: 2),
                            Text(
                              tab.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active
                                    ? config.navActiveIconColor
                                    : config.navInactiveColor,
                                fontSize: 9,
                                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMoreSheet(BuildContext context) {
    final items = [
      (
        Icons.sports_soccer_rounded,
        AppLocalizations.get('nav_matches'),
        '${config.routePrefix}/matches'
      ),
      (
        Icons.manage_accounts_rounded,
        AppLocalizations.get('staff_title'),
        '${config.routePrefix}/staff'
      ),
      (
        Icons.settings_rounded,
        AppLocalizations.get('nav_settings_tab'),
        config.settingsRoute
      ),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.get('admin_more_title'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              for (final item in items)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(item.$1, color: config.accentColor),
                  title: Text(
                    item.$2,
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    OrganizationShell.go(context, item.$3);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Internal model
// ─────────────────────────────────────────────────────────────────────────────

class _NavTab {
  _NavTab(
    this.route,
    this.icon,
    this.label, {
    required this.activeIndexes,
    this.isMore = false,
  });
  final String route;
  final IconData icon;
  final String label;
  final Set<int> activeIndexes;
  final bool isMore;
}
