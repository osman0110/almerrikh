import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_constants.dart';
import 'app_localizations.dart';
import 'app_state.dart';
import 'screens/auth_page.dart';
import 'screens/club/club_dashboard.dart';
import 'screens/club/club_player_profile_page.dart';
import 'screens/club/player_management.dart';
import 'screens/club/team_management.dart';
import 'screens/club/session_list_page.dart';
import 'screens/club/session_form_page.dart';
import 'screens/club/session_detail_page.dart';
import 'screens/physical_assessment/assessment_hub_page.dart';
import 'screens/physical_assessment/assessment_camera_page.dart';
import 'screens/physical_assessment/assessment_result_page.dart';
import 'screens/physical_assessment/player_history_page.dart';
import 'screens/physical_assessment/player_profile_form_page.dart';
import 'screens/physical_assessment/player_selection_page.dart';
import 'screens/academy/academy_dashboard.dart';
import 'screens/player/player_dashboard.dart';
import 'screens/player/body_metrics_screen.dart';
import 'screens/player/hooper_index_screen.dart';
import 'screens/player/rpe_screen.dart';
import 'screens/player/monitoring_dashboard_screen.dart';
import 'screens/club/team_wellness_screen.dart';
import 'screens/parent/parent_dashboard.dart';
import 'models/assessment_result_model.dart';
import 'models/player_profile_model.dart';
import 'services/sound_manager.dart';
import 'services/club_service.dart';
import 'screens/onboarding_page.dart';
import 'screens/profile_onboarding_page.dart';
import 'widgets/common_widgets.dart';
import 'storage.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase integration is frozen for now.
  // The app will run with offline/local fallbacks.
  // try {
  //   await Firebase.initializeApp(
  //     options: DefaultFirebaseOptions.currentPlatform,
  //   );
  // } catch (e) {
  //   debugPrint('Firebase init error: $e');
  // }

  await SoundManager.instance.init();

  runApp(const SsotApp());
}

class SsotApp extends StatelessWidget {
  const SsotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Al Merrikh SC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          surface: AppColors.card,
          error: AppColors.destructive,
        ),
        fontFamily: 'Inter',
      ),
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
          } else {
            page = AssessmentCameraPage(player: args.player, testType: args.testType);
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
        // ── Academy routes ──────────────────────────────────────────────
        } else if (uri.path == '/academy' || uri.path == '/academy/dashboard') {
          page = const AcademyDashboardPage();
        } else if (uri.path == '/academy/students') {
          page = const PlayerManagementPage();
        } else if (uri.path == '/academy/sessions') {
          page = const SessionListPage();
        } else if (uri.path == '/academy/reports') {
          page = const _ClubComingSoon(title: 'Reports', icon: Icons.bar_chart_rounded);
        } else if (uri.path == '/academy/settings') {
          page = const AcademySettingsPage();
        // ── Player routes ────────────────────────────────────────────────
        } else if (uri.path == '/player') {
          page = const PlayerDashboardPage();
        } else if (uri.path == '/player/assessments') {
          page = const AssessmentHubPage();
        } else if (uri.path == '/player/history') {
          page = const _ClubComingSoon(title: 'History', icon: Icons.history_rounded);
        } else if (uri.path == '/player/profile') {
          page = const PlayerProfilePage();
        } else if (uri.path == '/player/monitoring') {
          page = const MonitoringDashboardScreen();
        } else if (uri.path == '/player/monitoring/body-metrics') {
          page = const BodyMetricsScreen();
        } else if (uri.path == '/player/monitoring/hooper') {
          page = const HooperIndexScreen();
        } else if (uri.path == '/player/monitoring/rpe') {
          page = const RpeScreen();
        } else if (uri.path == '/club/wellness') {
          page = const TeamWellnessScreen();
        // ── Parent routes ────────────────────────────────────────────────
        } else if (uri.path == '/parent') {
          page = const ParentDashboardPage();
        } else if (uri.path == '/parent/child') {
          page = const ParentChildPage();
        } else if (uri.path == '/parent/reports') {
          page = const ParentReportsPage();
        } else if (uri.path == '/parent/profile') {
          page = const ParentProfilePage();
        // ── Club routes ──────────────────────────────────────────────────
        } else if (uri.path == '/club' || uri.path == '/club/dashboard') {
          page = const ClubDashboardPage();
        } else if (uri.path == '/club/players') {
          page = const PlayerManagementPage();
        } else if (uri.path.startsWith('/club/players/')) {
          page = ClubPlayerProfilePage(playerId: uri.pathSegments.last);
        } else if (uri.path == '/club/teams') {
          page = const TeamManagementPage();
        } else if (uri.path == '/club/settings') {
          page = const ClubSettingsPage();
        } else if (uri.path == '/club/sessions') {
          page = const SessionListPage();
        } else if (uri.path == '/club/sessions/new') {
          page = const SessionFormPage();
        } else if (uri.path.startsWith('/club/sessions/')) {
          page = SessionDetailPage(sessionId: uri.pathSegments.last);
        } else if (uri.path == '/club/reports') {
          page = const _ClubComingSoon(title: 'Reports', icon: Icons.bar_chart_rounded);
        } else {
          debugPrint('[onGenerateRoute] Unknown route: ${uri.path}');
          page = _ErrorPage(route: uri.path);
        }
        debugPrint('[onGenerateRoute] Showing page for route: ${uri.path}');
        return PageRouteBuilder(
          settings: settings,
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 180),
        );
      },
    );
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
    if (nextSignedIn) {
      final name = await store.getUserName();
      if (name != null && name.isNotEmpty) currentUserName = name;
      final role = await store.getUserRole();
      currentUserRole = role;
      _role = role;

      if (role == UserRole.club || role == UserRole.academy) {
        try {
          await ClubService().seedDefaultTeamsIfEmpty().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
        } catch (e) {
          debugPrint('[RootGate] Seed error: $e');
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
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text('Loading...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
    if (seen != true) return const SplashPage();
    if (signedIn != true) return const AuthPage();
    switch (_role) {
      case UserRole.academy: return const AcademyDashboardPage();
      case UserRole.player:  return const PlayerDashboardPage();
      case UserRole.parent:  return const ParentDashboardPage();
      case UserRole.club:    return const ClubDashboardPage();
    }
  }
}

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
      child: Theme(
        data: isAr
            ? Theme.of(context).copyWith(
                textTheme: GoogleFonts.tajawalTextTheme(
                  Theme.of(context).textTheme,
                ),
              )
            : Theme.of(context),
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
          color: AppColors.card.withOpacity(0.96),
          border: const Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: tabs.map((tab) {
            final active = activeFor(tab.path);
            return Expanded(
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(tab.path, (_) => false);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    padding: EdgeInsets.symmetric(
                      horizontal: active ? 14 : 11,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primarySoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            tab.icon,
                            size: 22,
                            color: active ? AppColors.primary : AppColors.muted,
                          ),
                          if (active) ...[
                            const SizedBox(width: 8),
                            Text(
                              tab.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xff0D0B16), Color(0xff08090F)],
              ),
            ),
            child: Stack(
              children: [
                const Positioned(
                  top: -60,
                  left: -45,
                  child: SoftOrb(size: 230, opacity: 0.14),
                ),
                const Positioned(
                  top: -90,
                  right: -30,
                  child: SoftOrb(size: 290, opacity: 0.10),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Transform.translate(
                      offset: const Offset(0, -34),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.92, end: 1),
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutBack,
                            builder: (_, value, child) =>
                                Transform.scale(scale: value, child: child),
                            child: Image.asset(
                              logoAsset,
                              width: math.min(148, safeWidth * 0.38),
                              height: math.min(148, safeWidth * 0.38),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Al Merrikh SC',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: displayBold.copyWith(fontSize: 28),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'AI Physical Performance Platform',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 40),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress / 100,
                              minHeight: 8,
                              backgroundColor: AppColors.surface2,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Setting things up...',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(3, (i) {
                              final active = i == step;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 280),
                                width: active ? 24 : 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(
                                    active ? 1 : 0.30,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
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

class SoftOrb extends StatelessWidget {
  const SoftOrb({super.key, required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(opacity),
            blurRadius: 52,
            spreadRadius: 18,
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

// ─────────────────────────────────────────────────────────────────────────────
// Coming Soon placeholder for unbuilt club pages
// ─────────────────────────────────────────────────────────────────────────────

class _ClubComingSoon extends StatelessWidget {
  const _ClubComingSoon({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.of(context).padding.top > 0 ? 16 : 16, 20, 14),
              decoration: const BoxDecoration(
                color: AppColors.card,
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.8)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
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
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
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
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.30),
                            width: 1.5),
                      ),
                      child: Icon(icon,
                          color: AppColors.primary, size: 36),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Coming in Phase 2',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.40),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
      backgroundColor: Colors.red.shade900,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_rounded, color: Colors.white, size: 64),
            const SizedBox(height: 20),
            const Text(
              'ROUTE ERROR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Unknown route: $route',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Go Home',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
