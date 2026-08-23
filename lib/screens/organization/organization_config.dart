import 'package:flutter/material.dart';

import '../../core/theme/app_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Core enums
// ─────────────────────────────────────────────────────────────────────────────

enum OrganizationType { club }

/// Whether the Reports section is live or pending.
enum ReportsMode { enabled, comingSoon }

/// Visual style of the nav active indicator.
enum NavIndicatorType {
  /// Filled pill behind icon (club style).
  pill,
}

// ─────────────────────────────────────────────────────────────────────────────
// OrganizationConfig
//
// Single source of truth for the club shell's visual, typography, labels,
// routes, and feature flags.
// ─────────────────────────────────────────────────────────────────────────────

class OrganizationConfig {
  const OrganizationConfig({
    required this.type,
    required this.routePrefix,
    required this.playersRouteSegment,
    required this.sessionsRouteSegment,
    required this.accentColor,
    required this.navBackground,
    required this.navBorderColor,
    required this.navActiveIconColor,
    required this.navInactiveColor,
    required this.indicatorType,
    required this.showTopStripe,
    required this.fontFamily,
    required this.playersLabelKey,
    required this.sessionsLabelKey,
    required this.reportsMode,
  });

  // ── Identity ─────────────────────────────────────────────────────────────────
  final OrganizationType type;

  // ── Routes ───────────────────────────────────────────────────────────────────
  final String routePrefix;
  final String playersRouteSegment;
  final String sessionsRouteSegment;

  String get homeRoute     => routePrefix;
  String get playersRoute  => '$routePrefix/$playersRouteSegment';
  String get sessionsRoute => '$routePrefix/$sessionsRouteSegment';
  String get reportsRoute  => '$routePrefix/reports';
  String get settingsRoute => '$routePrefix/settings';

  // ── Visual ───────────────────────────────────────────────────────────────────
  final Color accentColor;
  final Color navBackground;
  final Color navBorderColor;

  /// Icon/text color when tab is active.
  final Color navActiveIconColor;

  /// Icon/text color when tab is inactive.
  final Color navInactiveColor;

  final NavIndicatorType indicatorType;

  /// Show the 3-pixel accent stripe at the top of the screen (club only).
  final bool showTopStripe;

  // Typography — both org types use Cairo (see AppFonts.primary).
  final String fontFamily;

  // ── Labels (localization keys) ────────────────────────────────────────────────
  /// AppLocalizations key for the Players tab label.
  final String playersLabelKey;
  final String sessionsLabelKey;

  // ── Features ─────────────────────────────────────────────────────────────────
  final ReportsMode reportsMode;

  // ── Derived ──────────────────────────────────────────────────────────────────
  bool get reportsEnabled => reportsMode == ReportsMode.enabled;

  // ── Presets ──────────────────────────────────────────────────────────────────

  /// Club config — Al Merrikh SC defaults.
  static const OrganizationConfig club = OrganizationConfig(
    type: OrganizationType.club,
    routePrefix: '/club',
    playersRouteSegment: 'players',
    sessionsRouteSegment: 'sessions',
    // Gold pill nav on warm white bar — maroon icon/text on gold pill (Al Merrikh brand)
    accentColor: Color(0xFFC8A34D),        // premium gold
    navBackground: Color(0xFFFFFFFF),      // white bar
    navBorderColor: Color(0xFFEDEAE8),     // warm border
    navActiveIconColor: Color(0xFF8A001C), // maroon — brand identity
    navInactiveColor: Color(0xFF9299A5),   // lighter gray muted
    indicatorType: NavIndicatorType.pill,
    showTopStripe: true,
    fontFamily: AppFonts.primary,
    playersLabelKey: 'nav_players',
    sessionsLabelKey: 'nav_sessions_tab',
    reportsMode: ReportsMode.enabled,
  );

  static OrganizationConfig forType(OrganizationType type) => club;
}
