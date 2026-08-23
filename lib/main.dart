import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
// Web AI setup screen — real on web, stub on native.
import 'screens/physical_assessment/web_pose_setup_screen.dart'
    if (dart.library.io) 'screens/physical_assessment/web_pose_setup_screen_stub.dart';

import 'app_colors.dart';
import 'app_constants.dart';
import 'core/theme/app_fonts.dart';
import 'utils/app_logger.dart';
import 'utils/crash_reporter.dart';
import 'app_localizations.dart';
import 'app_state.dart';
import 'api_service.dart';
import 'screens/auth_page.dart';
import 'screens/club/club_settings_page.dart';
import 'screens/club/player_management.dart';
import 'screens/club/team_management.dart';
import 'screens/club/season_competition_management.dart';
import 'screens/club/team_management_report_screen.dart';
import 'screens/club/club_dashboard.dart';
import 'screens/club/physical_coach_dashboard.dart';
import 'screens/club/doctor_dashboard.dart';
import 'screens/club/massage_dashboard.dart';
import 'screens/club/nutritionist_dashboard.dart';
import 'screens/club/tactical_coach_dashboard.dart';
import 'screens/club/analyst_dashboard.dart';
import 'screens/club/session_list_page.dart';
import 'screens/club/global_search_page.dart';
import 'screens/club/session_detail_page.dart';
import 'screens/club/session_form_page.dart';
import 'screens/club/club_reports_page.dart';
import 'screens/club/data_quality_screen.dart';
import 'screens/club/physical_report_page.dart';
import 'screens/club/club_player_profile_page.dart';
import 'screens/physical_assessment/assessment_hub_page.dart';
import 'screens/physical_assessment/assessment_camera_page.dart';
import 'screens/physical_assessment/assessment_result_page.dart';
import 'screens/physical_assessment/player_history_page.dart';
import 'screens/physical_assessment/player_profile_form_page.dart';
import 'screens/physical_assessment/player_selection_page.dart';
import 'screens/player/player_dashboard.dart';
import 'screens/player/my_nutrition_screen.dart';
import 'screens/player/body_metrics_screen.dart';
import 'screens/player/body_composition_entry_screen.dart';
import 'screens/player/hooper_index_screen.dart';
import 'screens/player/rpe_screen.dart';
import 'screens/player/monitoring_dashboard_screen.dart';
import 'screens/player/player_history_screen.dart';
import 'screens/player/join_club_screen.dart';
import 'screens/player/independent_ai_plan_screen.dart';
import 'screens/player/ai_plan_preview_screen.dart';
import 'screens/player/pre_training_wellness_screen.dart';
import 'screens/player/session_runner_screen.dart';
import 'screens/player/post_training_feedback_screen.dart';
import 'screens/player/session_summary_screen.dart';
import 'screens/player/my_sessions_screen.dart';
import 'screens/player/my_matches_screen.dart';
import 'models/session_models.dart';
import 'screens/club/staff_screen.dart';
import 'screens/club/team_wellness_screen.dart';
import 'screens/club/body_composition_list_page.dart';
import 'screens/club/team_training_load_report_screen.dart';
import 'screens/club/match_list_page.dart';
import 'screens/club/match_form_page.dart';
import 'screens/club/match_detail_page.dart';
// Coach screens — coach is now a role within org, not a standalone shell.
// AI plan screens + training-plans + reports hub: Phase 2 / deprecated.
// Player/team/assessment report screens kept under /club/reports/* routes.
import 'screens/coach/coach_player_report_screen.dart';
import 'screens/coach/coach_team_report_screen.dart';
import 'screens/coach/coach_assessment_report_screen.dart';
import 'screens/player/player_progress_screen.dart';
import 'models/assessment_result_model.dart';
import 'models/player_profile_model.dart';
import 'services/sound_manager.dart';
import 'services/club_service.dart';
import 'services/notification_service.dart';
import 'services/navigation_service.dart';
import 'screens/onboarding_page.dart';
import 'screens/profile_onboarding_page.dart';
import 'widgets/common_widgets.dart';
import 'storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      AppLogger.e('main', 'Firebase.initializeApp failed', e);
    }
  }

  // A 401 from any endpoint means the token was revoked/expired server-side
  // — clear the local session and drop back to login instead of leaving
  // every screen to fail (or silently swallow the error) independently.
  ApiService.onUnauthorized = () {
    unawaited(OnboardingStore().clearSignedIn());
    navigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/onboarding', (route) => false);
  };

  // Hydrate the API token before resolving a direct/deep report route.
  // RootGate still performs the full account-state load for the normal home
  // flow, but report deep links must not issue their first requests as guests.
  await OnboardingStore().isSignedIn();

  await SoundManager.instance.init();
  unawaited(NotificationService.init());

  // CrashReporter.init() sets up:
  //   • FlutterError.onError  — widget / framework crashes
  //   • PlatformDispatcher.onError — native / plugin crashes
  //   • runZonedGuarded zone  — unhandled async errors
  // No-op in debug mode or when SENTRY_DSN is not injected at build time.
  await CrashReporter.init(() => runApp(const SsotApp()));
}

class SsotApp extends StatelessWidget {
  const SsotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLanguageNotifier,
      builder: (_, lang, __) => MaterialApp(
        title: AppLocalizations.get('club_brand_name'),
        debugShowCheckedModeBanner: false,
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: ColorScheme.fromSeed(
            brightness: Brightness.light,
            seedColor: AppColors.maroon,
            primary: AppColors.primary,
            surface: AppColors.background,
            onSurface: AppColors.foreground,
            error: AppColors.destructive,
          ),
          cardTheme: CardThemeData(
            color: AppColors.card,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.foreground,
              elevation: 4,
              shadowColor: AppColors.primary.withOpacity(0.38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontFamily: AppFonts.primary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.foreground,
              elevation: 4,
              shadowColor: AppColors.primary.withOpacity(0.38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontFamily: AppFonts.primary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.8,
              ),
            ),
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
            prefixIconColor: AppColors.muted,
          ),
          fontFamily: AppFonts.primary,
          textTheme: Typography.material2021().black.apply(
            fontFamily: AppFonts.primary,
            bodyColor: AppColors.foreground,
            displayColor: AppColors.foreground,
          ),
          primaryTextTheme: Typography.material2021().black.apply(
            fontFamily: AppFonts.primary,
            bodyColor: AppColors.foreground,
            displayColor: AppColors.foreground,
          ),
        ),
        navigatorKey: navigatorKey,
        home: const RootGate(),
        onGenerateRoute: (settings) {
          var uri = Uri.parse(settings.name ?? '/');
          if (uri.path == '/' && uri.fragment.isNotEmpty) {
            uri = Uri.parse(uri.fragment);
          }

          Widget page;
          if (uri.path == '/splash') {
            page = const SplashPage();
          } else if (uri.path == '/onboarding') {
            page = const OnboardingPage();
          } else if (uri.path == '/auth') {
            page = const AuthPage();
          } else if (uri.path == '/profile-onboarding') {
            page = const ProfileOnboardingPage();
          } else if (uri.path == '/') {
            page = const RootGate();
          } else if (uri.path == '/physical-assessment') {
            page = const AssessmentHubPage();
          } else if (uri.path == '/physical-assessment/select') {
            page = const PlayerSelectionPage();
          } else if (uri.path == '/physical-assessment/new-player') {
            page = const PlayerProfileFormPage();
          } else if (uri.path == '/physical-assessment/camera') {
            final args = settings.arguments as AssessmentCameraArguments?;
            if (args == null) {
              page = const NotFoundPage();
            } else if (kIsWeb) {
              // On web: AI setup screen first (handles preload + camera permission).
              // WebPoseSetupScreen fast-paths through when model is already loaded.
              page = WebPoseSetupScreen(cameraArgs: args);
            } else {
              page = AssessmentCameraPage(
                player: args.player,
                testType: args.testType,
                sessionId: args.sessionId,
              );
            }
          } else if (uri.path == '/physical-assessment/result') {
            final result = settings.arguments as AssessmentResult?;
            if (result == null) {
              page = const NotFoundPage();
            } else {
              page = AssessmentResultPage(result: result);
            }
          } else if (uri.path == '/physical-assessment/history') {
            final player = settings.arguments as PlayerProfile?;
            if (player == null) {
              page = const NotFoundPage();
            } else {
              page = PlayerHistoryPage(player: player);
            }
            // ── Player routes ────────────────────────────────────────────────
          } else if (uri.path == '/player') {
            page = const PlayerDashboardPage();
          } else if (uri.path == '/player/assessments') {
            page = const AssessmentHubPage();
          } else if (uri.path == '/player/history') {
            page = const PlayerHistoryScreen();
          } else if (uri.path == '/player/health') {
            page = const MyNutritionScreen();
          } else if (uri.path == '/player/join-club') {
            page = const JoinClubScreen();
          } else if (uri.path == '/player/profile') {
            page = const PlayerProfilePage();
          } else if (uri.path == '/player/sessions') {
            page = const MySessionsScreen();
          } else if (uri.path == '/player/matches') {
            page = const MyMatchesScreen();
          } else if (uri.path == '/player/monitoring') {
            page = const MonitoringDashboardScreen();
          } else if (uri.path == '/player/monitoring/body-metrics') {
            page = const BodyMetricsScreen();
          } else if (uri.path == '/player/monitoring/body-composition') {
            page = BodyCompositionEntryScreen(
              playerId: uri.queryParameters['playerId'],
            );
          } else if (uri.path == '/player/monitoring/hooper') {
            page = HooperIndexScreen(
              sessionId: uri.queryParameters['sessionId'],
            );
          } else if (uri.path == '/player/monitoring/rpe') {
            page = RpeScreen(
              sessionId: uri.queryParameters['sessionId'],
              durationMinutes: int.tryParse(
                uri.queryParameters['durationMinutes'] ?? '',
              ),
            );
            // ── AI Plan routes ─────────────────────────────────────────────────
          } else if (uri.path == '/player/ai-plan') {
            page = const IndependentAIPlanScreen();
          } else if (uri.path == '/player/ai-plan/preview') {
            final planId = uri.queryParameters['id'] ?? '';
            final planTitle = uri.queryParameters['title'] ?? 'My AI Plan';
            page = planId.isEmpty
                ? const NotFoundPage()
                : AIPlanPreviewScreen(planId: planId, planTitle: planTitle);
            // ── Session flow routes ────────────────────────────────────────────
          } else if (uri.path == '/player/session/pre-check') {
            final data = settings.arguments as PlayerSessionData?;
            page = data == null
                ? const NotFoundPage()
                : PreTrainingWellnessScreen(session: data);
          } else if (uri.path == '/player/session/run') {
            final data = settings.arguments as PlayerSessionData?;
            page = data == null
                ? const NotFoundPage()
                : SessionRunnerScreen(session: data);
          } else if (uri.path == '/player/session/post-feedback') {
            final data = settings.arguments as Map<String, dynamic>?;
            page = data == null
                ? const NotFoundPage()
                : PostTrainingFeedbackScreen(data: data);
          } else if (uri.path == '/player/session/summary') {
            final data = settings.arguments as SessionCompletionData?;
            page = data == null
                ? const NotFoundPage()
                : SessionSummaryScreen(completion: data);
          } else if (uri.path == '/club/wellness') {
            page = const TeamWellnessScreen();
            // ── Coach routes — redirected: coach is a role within org, not a shell ──
          } else if (uri.path == '/coach' || uri.path == '/coach/dashboard') {
            page = _orgHomePage();
            // ── Club route guard — player redirected to their own section ──
          } else if (uri.path.startsWith('/club') &&
              currentUserRole == UserRole.player) {
            page = const PlayerDashboardPage();
            // ── Club routes ──────────────────────────────────────────────────────
          } else if (uri.path == '/club' || uri.path == '/club/dashboard') {
            page = _orgHomePage();
          } else if (uri.path == '/club/players') {
            final args = settings.arguments as Map?;
            page = PlayerManagementPage(
              filterTeamId: args?['teamId'] as String?,
              initialFilter: args?['initialFilter'] as String?,
            );
          } else if (uri.path.startsWith('/club/players/')) {
            final pid = uri.pathSegments.last;
            page = pid.isEmpty
                ? const NotFoundPage()
                : ClubPlayerProfilePage(playerId: pid);
          } else if (uri.path == '/club/teams') {
            page = const TeamManagementPage();
          } else if (uri.path == '/club/classification') {
            page = const SeasonCompetitionManagementPage();
          } else if (uri.path == '/club/settings') {
            page = const ClubSettingsPage();
          } else if (uri.path == '/club/invites') {
            // Merged into the unified Staff & Access Codes screen (Codes tab).
            page = const ClubStaffScreen();
          } else if (uri.path == '/club/staff') {
            page = const ClubStaffScreen();
          } else if (uri.path == '/club/sessions') {
            page = const SessionListPage();
          } else if (uri.path == '/club/sessions/new') {
            page = const SessionFormPage();
          } else if (uri.path.startsWith('/club/sessions/')) {
            page = SessionDetailPage(sessionId: uri.pathSegments.last);
          } else if (uri.path == '/club/matches') {
            page = const MatchListPage();
          } else if (uri.path == '/club/matches/new') {
            page = const MatchFormPage();
          } else if (uri.path.startsWith('/club/matches/')) {
            page = MatchDetailPage(matchId: uri.pathSegments.last);
          } else if (uri.path == '/club/reports') {
            page = const ClubReportsPage();
          } else if (uri.path == '/club/data-quality') {
            page = const DataQualityScreen();
          } else if (uri.path == '/club/search') {
            page = const GlobalSearchPage();
            // ── Organization report drill-downs (proper /club/ prefix) ───────────
            // Also handle legacy /coach/reports/* aliases for backwards compat.
          } else if (uri.path == '/club/reports/player' ||
              uri.path == '/coach/reports/player') {
            final args = settings.arguments as Map<String, dynamic>?;
            final pid =
                args?['player_id'] as String? ??
                uri.queryParameters['player_id'] ??
                '';
            final name = args?['player_name'] as String? ?? 'لاعب';
            page = pid.isEmpty
                ? const NotFoundPage()
                : CoachPlayerReportScreen(playerId: pid, playerName: name);
          } else if (uri.path == '/club/reports/team' ||
              uri.path == '/coach/reports/team') {
            page = CoachTeamReportScreen(teamName: uri.queryParameters['team']);
          } else if (uri.path == '/club/reports/training-load') {
            page = const TeamTrainingLoadReportScreen();
          } else if (uri.path == '/club/reports/acwr') {
            // Backward-compatible alias: ACWR now lives inside the unified
            // training-load report instead of opening a separate report mode.
            page = const TeamTrainingLoadReportScreen();
          } else if (uri.path == '/club/reports/physical') {
            page = const ManagementPhysicalReportPage();
          } else if (uri.path == '/club/reports/management') {
            page = const TeamManagementReportScreen();
          } else if (uri.path == '/club/reports/body-composition' ||
              uri.path == '/club/reports/body-composition/') {
            page = const BodyCompositionListPage();
          } else if (uri.path == '/club/reports/assessments' ||
              uri.path == '/coach/reports/assessments') {
            final args = settings.arguments as Map<String, dynamic>?;
            final pid =
                args?['player_id'] as String? ??
                uri.queryParameters['player_id'] ??
                '';
            final name = args?['player_name'] as String? ?? 'لاعب';
            page = pid.isEmpty
                ? const NotFoundPage()
                : CoachAssessmentReportScreen(playerId: pid, playerName: name);
          } else if (uri.path == '/coach/reports') {
            // Deprecated: coach reports hub → org reports page
            page = const ClubReportsPage();
          } else if (uri.path == '/player/reports/progress') {
            page = const PlayerProgressScreen();
            // ── Training plans routes — deprecated, redirect to /club/sessions ────
          } else if (uri.path == '/club/training-plans') {
            page = const SessionListPage();
          } else if (uri.path == '/club/training-plans/new') {
            page = const SessionFormPage();
          } else if (uri.path.startsWith('/club/training-plans/report/')) {
            page = SessionDetailPage(sessionId: uri.pathSegments.last);
            // ── Coach AI Plan routes — Phase 2 / Coming Soon ─────────────────
          } else {
            AppLogger.w('Router', 'Unknown route: ${uri.path}');
            page = _ErrorPage(route: uri.path);
          }
          // ── Route guard: enforce role-based access ────────────────────────
          final path = uri.path;
          if (path.startsWith('/club') || path.startsWith('/coach')) {
            if (currentUserRole == UserRole.player) {
              page = _ForbiddenPage(redirectTo: _homeRouteFor(currentUserRole));
            }
          } else if (path.startsWith('/player')) {
            if (currentUserRole != UserRole.player) {
              page = _ForbiddenPage(redirectTo: _homeRouteFor(currentUserRole));
            }
          }
          // Admin-only club sections — a non-admin org role (coach, doctor,
          // physiotherapist, nutritionist, tactical coach, analyst, staff) must
          // not reach these even via a direct deep link. '/club/settings' is
          // NOT admin-only — every role has a personal profile/settings page
          // (club_settings_page.dart gates its own admin-only sections
          // internally via isOrgAdmin).
          const adminOnlyClubPaths = [
            '/club/staff',
            '/club/invites',
            '/club/data-quality',
          ];
          final isTeamsPath =
              path == '/club/teams' || path.startsWith('/club/teams/');
          if ((adminOnlyClubPaths.any(
                    (p) => path == p || path.startsWith('$p/'),
                  ) &&
                  !isOrgAdmin) ||
              (isTeamsPath && !canManageTeams)) {
            page = _ForbiddenPage(redirectTo: _homeRouteFor(currentUserRole));
          }
          if ((path.startsWith('/club') || path.startsWith('/coach')) &&
              _usesUnifiedRoleSidebar &&
              page is! _ForbiddenPage) {
            page = ClubRoleSidebarShell(child: page);
          }

          const assessmentPaths = [
            '/physical-assessment',
            '/physical-assessment/select',
            '/physical-assessment/new-player',
            '/physical-assessment/camera',
          ];
          if (assessmentPaths.contains(path) &&
              ApiService.token != null &&
              currentUserId != null &&
              currentUserRole == UserRole.club &&
              !canRunAssessments) {
            page = const RoleAccessDeniedPage();
          }

          AppLogger.i('Router', 'Navigating to ${uri.path}');
          CrashReporter.breadcrumb(uri.path, category: 'navigation');
          return PageRouteBuilder(
            settings: settings,
            pageBuilder: (_, __, ___) => page,
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 180),
          );
        },
      ),
    );
  }
}

/// The org "Home" tab widget for the current [currentOrgRole] — some roles
/// get a focused dashboard instead of the full [ClubDashboardPage].
Widget _orgHomePage() {
  if (isCoachRole) return const PhysicalCoachDashboardPage();
  if (isDoctorRole) return const DoctorDashboardPage();
  // Physiotherapist covers physiotherapy AND massage — one job, one
  // dashboard (see staff_screen.dart: 'massage_specialist' is no longer
  // offered as a separate invite type).
  if (isPhysiotherapistRole) return const MassageDashboardPage();
  if (isNutritionistRole) return const NutritionistDashboardPage();
  if (isTacticalCoachRole) return const TacticalCoachDashboardPage();
  if (isAnalystRole) return const AnalystDashboardPage();
  // performanceManager and staff intentionally fall through to
  // ClubDashboardPage — performanceManager's capabilities are broad enough
  // (players/sessions/matches/teams write, medical/physio/nutrition read+
  // write) that the full club-wide view fits their ops role, and staff is a
  // generic placeholder role with no fixed specialty yet.
  if (currentOrgRole == OrgRole.staff) return const RoleAccessDeniedPage();
  return const ClubDashboardPage();
}

String _homeRouteFor(UserRole role) {
  switch (role) {
    case UserRole.player:
      return '/player';
    case UserRole.club:
      return '/club';
  }
}

TextStyle get displayBold => const TextStyle(
  fontWeight: FontWeight.w900,
  letterSpacing: 0,
  color: AppColors.foreground,
);

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool? seen;
  bool? signedIn;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  UserRole _role = UserRole.club;

  Future<void> _loadState() async {
    final store = OnboardingStore();
    final nextSeen = await store.hasSeenOnboarding();
    final nextSignedIn = await store.isSignedIn();
    final savedLang = await store.getLanguage();
    if (savedLang != null) setAppLanguage(savedLang);

    if (nextSignedIn) {
      final name = await store.getUserName();
      if (name != null && name.isNotEmpty) currentUserName = name;
      currentUserAvatarUrl = await store.getUserAvatarUrl() ?? '';
      final role = await store.getUserRole();
      currentUserRole = role;
      _role = role;
      currentOrgRole = await store.getOrgRole();
      currentPlayerType = await store.getPlayerType();
      currentUserId = await store.getUserId();
      await store.getLinkedPlayerId();
      unawaited(NotificationService.registerPush());

      // Tag Sentry scope with role only — no PII (no name, no email)
      CrashReporter.setRole(role.name);

      if (role == UserRole.club) {
        try {
          await ClubService().seedDefaultTeamsIfEmpty().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
        } catch (e) {
          AppLogger.e('RootGate', 'Seed error', e);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      seen = nextSeen;
      signedIn = nextSignedIn;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (seen == null || signedIn == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.5,
          ),
        ),
      );
    }
    // Signed in → dashboard directly (no onboarding/auth screen)
    if (signedIn == true) {
      switch (_role) {
        case UserRole.player:
          return const PlayerDashboardPage();
        case UserRole.club:
          final page = _orgHomePage();
          return _usesUnifiedRoleSidebar
              ? ClubRoleSidebarShell(child: page)
              : page;
      }
    }
    // Not signed in → onboarding first time, then auth
    if (seen != true) return const SplashPage();
    return const AuthPage();
  }
}

bool get _usesUnifiedRoleSidebar =>
    isOrgUser && currentOrgRole != OrgRole.staff;

class MobileShell extends StatelessWidget {
  const MobileShell({
    super.key,
    required this.child,
    this.hideNav = false,
    this.bare = false,
    this.routeName,
  });

  final Widget child;
  final bool hideNav;
  final bool bare;
  final String? routeName;

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    children: [
                      Expanded(
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          removeBottom: true,
                          child: child,
                        ),
                      ),
                      if (!hideNav) BottomNav(currentRoute: routeName),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  const BottomNav({super.key, this.currentRoute});

  final String? currentRoute;

  @override
  Widget build(BuildContext context) {
    final route = currentRoute ?? ModalRoute.of(context)?.settings.name ?? '/';
    final bottom = MediaQuery.of(context).padding.bottom;
    final tabs = [
      _TabItem('/', AppLocalizations.get('nav_home'), Icons.home_rounded),
      _TabItem(
        '/drills',
        AppLocalizations.get('nav_training'),
        Icons.fitness_center_rounded,
      ),
      _TabItem(
        '/results',
        AppLocalizations.get('nav_stats'),
        Icons.bar_chart_rounded,
      ),
      _TabItem(
        '/profile',
        AppLocalizations.get('nav_profile'),
        Icons.person_rounded,
      ),
    ];

    bool activeFor(String path) =>
        path == '/' ? route == '/' : route.startsWith(path);

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(8, 8, 8, math.max(8, bottom * 0.15)),
        decoration: BoxDecoration(
          color: AppColors.card,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: tabs.map((tab) {
            final active = activeFor(tab.path);
            return Expanded(
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(tab.path, (_) => false);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: EdgeInsets.symmetric(
                      horizontal: active ? 14 : 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            tab.icon,
                            size: 20,
                            color: active ? AppColors.maroon : AppColors.muted,
                          ),
                          if (active) ...[
                            const SizedBox(width: 7),
                            Text(
                              tab.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                color: AppColors.maroon,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _TabItem {
  _TabItem(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final random = math.Random();
  Timer? progressTimer;
  Timer? stepTimer;
  Timer? navTimer;
  double progress = 8;
  int step = 0;

  @override
  void initState() {
    super.initState();
    progressTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      setState(
        () => progress = math.min(100, progress + 2 + random.nextDouble() * 4),
      );
    });
    stepTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      setState(() => step = (step + 1) % 3);
    });
    navTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) Navigator.of(context).pushReplacementNamed('/onboarding');
    });
  }

  @override
  void dispose() {
    progressTimer?.cancel();
    stepTimer?.cancel();
    navTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeWidth = math.min(
      MediaQuery.of(context).size.width,
      maxPhoneWidth,
    );
    return Scaffold(
      backgroundColor: AppColors.maroonDark,
      body: Stack(
        children: [
          // ── Stadium pitch grid — cinematic background ──────────────────
          Positioned.fill(
            child: Opacity(
              opacity: 0.09,
              child: Image.asset(
                'assets/images/login-bg.webp',
                fit: BoxFit.cover,
              ),
            ),
          ),
          // ── Vignette overlay: top transparent → bottom dark maroon ──────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.maroon.withOpacity(0.20),
                    AppColors.maroonDark.withOpacity(0.80),
                  ],
                ),
              ),
            ),
          ),
          // ── Content ────────────────────────────────────────────────────
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),
                    // ── Logo badge with gold ring ──────────────────────────
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.85, end: 1.0),
                      duration: const Duration(milliseconds: 520),
                      curve: Curves.easeOutBack,
                      builder: (_, v, child) => Transform.scale(
                        scale: v,
                        child: Opacity(
                          opacity: v.clamp(0.0, 1.0),
                          child: child,
                        ),
                      ),
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF9B1020), AppColors.maroonDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.65),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.22),
                              blurRadius: 36,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: AppColors.maroonDark.withOpacity(0.70),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Image.asset(
                          logoAsset,
                          width: math.min(64, safeWidth * 0.18),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    // ── Club name ─────────────────────────────────────────
                    Text(
                      AppLocalizations.get('club_brand_name'),
                      style: TextStyle(
                        color: AppColors.onDark,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 7),
                    // ── Arabic tagline in gold ─────────────────────────────
                    const Text(
                      'منصة الأداء البدني بالذكاء الاصطناعي',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    // ── Progress bar ──────────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 3,
                        backgroundColor: Colors.white.withOpacity(0.12),
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (i) {
                        final active = i == step;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          width: active ? 20 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary
                                : Colors.white.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileShell(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('404', style: displayBold.copyWith(fontSize: 42)),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.get('page_not_found'),
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              width: 160,
              label: AppLocalizations.get('go_home'),
              onTap: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (_) => false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForbiddenPage extends StatelessWidget {
  const _ForbiddenPage({required this.redirectTo});
  final String redirectTo;

  @override
  Widget build(BuildContext context) {
    Future.microtask(() {
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(redirectTo, (_) => false);
      }
    });
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.route});
  final String route;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.destructive.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.destructive,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Route Error',
                style: TextStyle(
                  color: AppColors.foreground,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                route,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () => Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/', (_) => false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Go Home',
                    style: TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
