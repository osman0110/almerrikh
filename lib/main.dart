import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'api_service.dart';
import 'app_colors.dart';
import 'app_constants.dart';
import 'app_image.dart';
import 'app_localizations.dart';
import 'app_state.dart';
import 'camera_view.dart';
import 'data/mock_data.dart';
import 'firebase_options.dart';
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
import 'models/assessment_result_model.dart';
import 'models/player_profile_model.dart';
import 'services/firebase_service.dart';
import 'services/sound_manager.dart';
import 'services/club_service.dart';
import 'screens/live_exercise_page.dart';
import 'screens/onboarding_page.dart';
import 'screens/profile_onboarding_page.dart';
import 'storage.dart';
import 'widgets/common_widgets.dart';


Future<void> main() async {
  final mainStart = DateTime.now();
  debugPrint('[Main] Starting app initialization');

  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[Main] WidgetsFlutterBinding initialized');

  try {
    final fbStart = DateTime.now();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final fbMs = DateTime.now().difference(fbStart).inMilliseconds;
    debugPrint('[Main] Firebase.initializeApp completed in ${fbMs}ms');
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  await SoundManager.instance.init();
  debugPrint('[Main] SoundManager initialized');

  final totalMs = DateTime.now().difference(mainStart).inMilliseconds;
  debugPrint('[Main] App initialization complete in ${totalMs}ms');

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
        } else if (uri.path == '/drills') {
          page = const DrillsPage();
        } else if (uri.path.startsWith('/drills/')) {
          page = DrillDetailPage(id: uri.pathSegments.last);
        } else if (uri.path == '/capture') {
          page = LiveExercisePage(drillId: uri.queryParameters['drill']);
        } else if (uri.path == '/pipeline') {
          page = PipelinePage(drillId: uri.queryParameters['drill']);
        } else if (uri.path == '/results') {
          page = ResultsPage(drillId: uri.queryParameters['drill']);
        } else if (uri.path == '/profile') {
          page = const ProfilePage();
        } else if (uri.path == '/settings') {
          page = const SettingsPage();
        } else if (uri.path == '/achievements') {
          page = const AchievementsPage();
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

  Future<void> _loadState() async {
    final store = OnboardingStore();
    final nextSeen = await store.hasSeenOnboarding();
    final nextSignedIn = await store.isSignedIn();
    if (nextSignedIn) {
      final name = await store.getUserName();
      if (name != null && name.isNotEmpty) currentUserName = name;

      // Run Firestore benchmark in background (don't block startup)
      debugPrint('[RootGate] Queuing Firestore benchmark...');
      ClubService().benchmarkFirestore().then((_) {
        debugPrint('[RootGate] Benchmark completed');
      }).catchError((e) {
        debugPrint('[RootGate] Benchmark error: $e');
      });

      // Try seeding (with timeout to not block)
      try {
        await ClubService().seedDefaultTeamsIfEmpty().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
      } catch (e) {
        debugPrint('[RootGate] Seed error: $e');
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
    return signedIn == true ? const ClubDashboardPage() : const AuthPage();
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final isSmall = h < 720;
    final gap = isSmall ? 14.0 : 22.0;
    final challengeHeight = math.min(h * 0.28, 240.0);
    final bannerHeight = math.max(math.min(h * 0.32, 260.0), 240.0);
    final programHeight = math.min(h * 0.22, 190.0);
    final cardPadding = isSmall ? 16.0 : 20.0;

    return MobileShell(
      routeName: '/',
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff0A0810), Color(0xff070610), Color(0xff0E0810)],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ─── Hero Header (full-width, edge-to-edge) ───
            HeroHeader(
              paddingBottom: isSmall ? 16 : 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AvatarCircle(
                        size: isSmall ? 46 : 52,
                        iconSize: isSmall ? 24 : 27,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.get('good_afternoon'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.58),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                player.name,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: isSmall ? 26 : 32,
                                  height: 1.05,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Pill(
                        icon: Icons.shield_rounded,
                        label: '${AppLocalizations.get('level')} 1',
                        background: Colors.white.withOpacity(0.07),
                        foreground: AppColors.primary,
                        border: Colors.white.withOpacity(0.10),
                      ),
                    ],
                  ),
                  SizedBox(height: isSmall ? 14 : 20),
                  const HomeStatsRow(),
                ],
              ),
            ),
            // ─── Daily Challenges ───
            Padding(
              padding: EdgeInsets.fromLTRB(20, gap, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.get('daily_challenges'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: displayBold.copyWith(fontSize: isSmall ? 21 : 25),
                    ),
                  ),
                  Text(
                    "${dailyChallenges.where((c) => c.status == 'done').length}"
                    "/${dailyChallenges.length} ${AppLocalizations.get('done')}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, isSmall ? 10 : 12, 20, 0),
              child: ChallengeCard(
                challenge: dailyChallenges.first,
                height: challengeHeight,
                padding: cardPadding,
              ),
            ),
            // ─── First Drill Banner ───
            Padding(
              padding: EdgeInsets.fromLTRB(20, gap, 20, 0),
              child: FirstDrillCard(drill: drills.first, height: bannerHeight),
            ),
            // ─── Training Programs ───
            SectionHeader(
              title: AppLocalizations.get('training_programs'),
              action: AppLocalizations.get('see_all'),
              compact: isSmall,
              onAction: () => Navigator.of(context).pushNamed('/drills'),
            ),
            SizedBox(
              height: programHeight,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: programs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => ProgramCard(
                  program: programs[i],
                  height: programHeight,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/physical-assessment'),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.analytics_rounded, size: 34, color: AppColors.primary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.get('assessment_feature_label'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              AppLocalizations.get('assessment_feature_subtitle'),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 90),
          ],
        ),
      ),
    );
  }
}

class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.child,
    this.paddingBottom = 28,
    this.center = false,
  });

  final Widget child;
  final double paddingBottom;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.height < 720;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + (isSmall ? 12 : 20),
        20,
        isSmall ? paddingBottom * 0.7 : paddingBottom,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff150A12), Color(0xff0A0810), Color(0xff100812)],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.42),
            blurRadius: 38,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.85, -0.9),
                  radius: 1.2,
                  colors: [
                    AppColors.primary.withOpacity(0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-1.0, 0.85),
                  radius: 1.15,
                  colors: [
                    const Color(0xffC9A84C).withOpacity(0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: center ? Alignment.center : Alignment.topLeft,
            child: child,
          ),
        ],
      ),
    );
  }
}

class HomeStatsRow extends StatelessWidget {
  const HomeStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final chipH = math.min(h * 0.11, 88.0).clamp(72.0, 88.0);
    return Row(
      children: [
        Expanded(
          child: HomeStatChip(
            icon: Icons.local_fire_department_rounded,
            value: '0',
            label: AppLocalizations.get('day_streak'),
            height: chipH,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: HomeStatChip(
            icon: Icons.bolt_rounded,
            value: '120',
            label: AppLocalizations.get('coins'),
            height: chipH,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: HomeStatChip(
            icon: Icons.emoji_events_rounded,
            value: AppLocalizations.get('rank_rookie'),
            label: AppLocalizations.get('rank'),
            height: chipH,
          ),
        ),
      ],
    );
  }
}

class HomeStatChip extends StatelessWidget {
  const HomeStatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.height,
  });

  final IconData icon;
  final String value;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary.withOpacity(0.95), size: 19),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white.withOpacity(0.50),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HeroGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.045)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ChallengeCard extends StatelessWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    this.height,
    this.padding = 20,
  });

  final DailyChallenge challenge;
  final double? height;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final pct = challenge.goal == 0 ? 0.0 : challenge.done / challenge.goal;
    return Container(
      height: height,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(
                label: AppLocalizations.format('challenge_number', {
                  'index': challenge.index,
                }),
                background: Colors.white.withOpacity(0.08),
                foreground: AppColors.primary,
                border: Colors.white.withOpacity(0.08),
                small: true,
              ),
              const Spacer(),
              Text(
                '${(pct * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  height: 1,
                ),
              ),
            ],
          ),
          SizedBox(height: padding * 0.70),
          Flexible(
            child: Text(
              localizedChallengeTitle(challenge.id, challenge.title),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: padding <= 16 ? 20 : 24,
                height: 1.08,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.get('challenge_subtitle'),
            style: TextStyle(
              color: Colors.white.withOpacity(0.58),
              fontSize: 13,
              height: 1.35,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: padding * 0.70),
          RoundedProgress(value: pct, dark: true, height: 9),
          const SizedBox(height: 7),
          Text(
            '${challenge.done} / ${challenge.goal}',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              _RewardChip(
                icon: Icons.paid_rounded,
                value: '+${challenge.coins}',
                label: AppLocalizations.get('coins'),
              ),
              const SizedBox(width: 14),
              Container(
                width: 1,
                height: 30,
                color: Colors.white.withOpacity(0.10),
              ),
              const SizedBox(width: 14),
              _RewardChip(
                icon: Icons.hexagon_outlined,
                value: '+${challenge.xp}',
                label: 'XP',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.48),
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class FirstDrillCard extends StatelessWidget {
  const FirstDrillCard({super.key, required this.drill, this.height});

  final Drill drill;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final isSmall = screenH < 720;
    final cardH = height ?? math.max(math.min(screenH * 0.32, 260.0), 240.0);
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/drills/${drill.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: cardH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.38),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.hero),
              AppImage(asset: drill.image, fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x22000000),
                      Color(0x66000000),
                      Color(0xf2000000),
                    ],
                    stops: [0, 0.44, 1],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(isSmall ? 16 : 22),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Pill(
                      icon: Icons.star_rounded,
                      label: AppLocalizations.get('start_here'),
                      background: Colors.white.withOpacity(0.10),
                      foreground: AppColors.primary,
                      border: Colors.white.withOpacity(0.10),
                      small: true,
                    ),
                    SizedBox(height: isSmall ? 8 : 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppLocalizations.get('try_first_drill'),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: isSmall ? 28 : 32,
                          height: 0.98,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: isSmall ? 6 : 9),
                    Text(
                      AppLocalizations.get('first_drill_hint'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 14,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isSmall ? 10 : 18),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        height: isSmall ? 46 : 54,
                        width: isSmall ? 200 : 230,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.24),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              AppLocalizations.get('start_training'),
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.black,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
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

class ProgramCard extends StatelessWidget {
  const ProgramCard({super.key, required this.program, this.height});

  final Program program;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final cardH = height ?? math.min(MediaQuery.of(context).size.height * 0.22, 190.0);
    final isSmall = MediaQuery.of(context).size.height < 720;
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/drills'),
      child: SizedBox(
        width: isSmall ? 190 : 210,
        height: cardH,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xff0E0B15)),
              AppImage(asset: program.image, fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x11000000), Color(0xee000000)],
                    stops: [0.18, 1],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Pill(
                  label: localizedDifficulty(program.difficulty),
                  background: Colors.black.withOpacity(0.46),
                  foreground: AppColors.primary,
                  border: AppColors.primary.withOpacity(0.35),
                  small: true,
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: isSmall ? 10 : 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizedProgramName(program.id, program.name),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: isSmall ? 17 : 19,
                        height: 1.05,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _programSubtitle(program.id),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isSmall ? 9 : 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppLocalizations.format('drill_count', {
                              'count': program.drills,
                            }),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.09),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.45),
                            ),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 21,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
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

String _programSubtitle(String id) {
  return switch (id) {
    'reaction-starter' => 'Improve your reflexes',
    'body-control' => 'Master your movement',
    'elite-finisher' => 'Boost your performance',
    _ => 'Train smarter with AI',
  };
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.compact = false,
    this.horizontalPadding = 20,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final bool compact;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        compact ? 18 : 30,
        horizontalPadding,
        compact ? 10 : 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: displayBold.copyWith(fontSize: compact ? 21 : 24),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class DrillsPage extends StatefulWidget {
  const DrillsPage({super.key});

  @override
  State<DrillsPage> createState() => _DrillsPageState();
}

class _DrillsPageState extends State<DrillsPage> {
  String active = 'All';
  String query = '';

  List<String> get categories => [
    'All',
    'Reaction',
    'Control',
    'Fitness',
    'Shooting',
  ];

  int countFor(String category) => category == 'All'
      ? drills.length
      : drills.where((d) => d.category == category).length;

  @override
  Widget build(BuildContext context) {
    final filtered = drills.where((d) {
      final localizedName = localizedDrillName(d.id, d.name).toLowerCase();
      return (active == 'All' || d.category == active) &&
          (query.trim().isEmpty ||
              localizedName.contains(query.toLowerCase()) ||
              d.name.toLowerCase().contains(query.toLowerCase()));
    }).toList();

    return MobileShell(
      routeName: '/drills',
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.of(context).padding.top + 20,
          20,
          MediaQuery.of(context).padding.bottom + 90,
        ),
        children: [
          Text(
            AppLocalizations.get('nav_training'),
            textAlign: TextAlign.center,
            style: displayBold.copyWith(fontSize: 25),
          ),
          const SizedBox(height: 20),
          SearchBox(
            value: query,
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final cat = categories[i];
                final isActive = active == cat;
                return GestureDetector(
                  onTap: () => setState(() => active = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.primary : AppColors.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isActive ? AppColors.primary : AppColors.border,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.18),
                                blurRadius: 28,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Text(
                          localizedCategory(cat),
                          style: TextStyle(
                            color: isActive
                                ? Colors.black
                                : AppColors.foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white.withOpacity(0.20)
                                : AppColors.surface2,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${countFor(cat)}',
                            style: TextStyle(
                              color: isActive ? Colors.black : AppColors.muted,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.format('drill_count', {
              'count': filtered.length,
            }),
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Text(
                AppLocalizations.get('no_drills_found'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 3 / 4,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, i) => DrillGridCard(drill: filtered[i]),
            ),
        ],
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: AppLocalizations.get('search_training'),
        hintStyle: const TextStyle(color: AppColors.muted),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
        filled: true,
        fillColor: AppColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: AppColors.primary.withOpacity(0.40)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 18,
        ),
      ),
    );
  }
}

class DrillGridCard extends StatelessWidget {
  const DrillGridCard({super.key, required this.drill});

  final Drill drill;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/drills/${drill.id}'),
      child: DrillImageCard(
        image: drill.image,
        title: localizedDrillName(drill.id, drill.name),
        badge: localizedDifficulty(drill.difficulty),
        leadingBadge: localizedCategory(drill.category),
        badgeColor: difficultyColor(drill.difficulty),
      ),
    );
  }
}

Color difficultyColor(String difficulty) {
  if (difficulty == 'Beginner') return AppColors.success;
  if (difficulty == 'Intermediate') return AppColors.warning;
  return AppColors.primary;
}

class DrillImageCard extends StatelessWidget {
  const DrillImageCard({
    super.key,
    required this.image,
    required this.title,
    this.subtitle,
    this.badge,
    this.leadingBadge,
    this.badgeColor = AppColors.primary,
    this.width,
    this.height,
  });

  final String image;
  final String title;
  final String? subtitle;
  final String? badge;
  final String? leadingBadge;
  final Color badgeColor;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.hero),
            AppImage(asset: image, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary.withOpacity(0.24)),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xdd000000)],
                  stops: [0.32, 1],
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              right: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (leadingBadge != null)
                    Pill(
                      label: leadingBadge!,
                      background: Colors.black54,
                      foreground: Colors.white,
                      small: true,
                    )
                  else
                    const SizedBox.shrink(),
                  if (badge != null)
                    Pill(
                      label: badge!,
                      background: badgeColor,
                      foreground: Colors.black,
                      small: true,
                    ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      height: 1.08,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.22),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DrillDetailPage extends StatelessWidget {
  const DrillDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final drill = drillById(id);
    return MobileShell(
      routeName: '/drills',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(drill.image, fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Colors.transparent,
                        AppColors.background,
                      ],
                      stops: [0, 0.62, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: MediaQuery.of(context).padding.top + 16,
                  child: RoundIconButton(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 28,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Pill(
                            label: localizedCategory(drill.category),
                            background: Colors.black54,
                            foreground: Colors.white,
                            small: true,
                          ),
                          const SizedBox(width: 8),
                          Pill(
                            label: localizedDifficulty(drill.difficulty),
                            background: AppColors.primary,
                            foreground: Colors.white,
                            small: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        localizedDrillName(drill.id, drill.name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 32,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          icon: Icons.schedule_rounded,
                          label: AppLocalizations.get('duration'),
                          value: drill.duration,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MetricTile(
                          icon: Icons.local_fire_department_rounded,
                          label: AppLocalizations.get('intensity'),
                          value: AppLocalizations.get('medium'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MetricTile(
                          icon: Icons.photo_camera_rounded,
                          label: AppLocalizations.get('camera'),
                          value: AppLocalizations.get('required'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SoftCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.get('how_it_works'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.get('how_it_works_body'),
                          style: const TextStyle(
                            color: AppColors.muted,
                            height: 1.55,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: AppLocalizations.get('start_drill'),
                    icon: Icons.play_arrow_rounded,
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed('/capture?drill=${drill.id}'),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 90),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CapturePage extends StatefulWidget {
  const CapturePage({super.key, this.drillId});

  final String? drillId;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  static const targetDuration = 12.0;
  Timer? timer;
  bool recording = false;
  double elapsed = 0;
  int quality = 0;

  Drill get drill => drillById(widget.drillId);

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void start() {
    timer?.cancel();
    setState(() {
      recording = true;
      elapsed = 0;
    });
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final next = double.parse((elapsed + 0.1).toStringAsFixed(1));
      if (next >= targetDuration) {
        stop();
      } else {
        setState(() => elapsed = next);
      }
    });
  }

  void stop() {
    timer?.cancel();
    if (!mounted) return;
    setState(() => recording = false);
    Navigator.of(
      context,
    ).pushReplacementNamed('/pipeline?drill=${drill.id}&q=$quality');
  }

  @override
  Widget build(BuildContext context) {
    return MobileShell(
      hideNav: true,
      bare: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CameraPreviewView(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.95,
                colors: [Colors.transparent, Color(0x88000000)],
                stops: [0.52, 1],
              ),
            ),
          ),
          CaptureOverlay(
            recording: recording,
            elapsed: elapsed,
            duration: targetDuration,
            onQualityChange: (value) => quality = value,
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RoundIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                Pill(
                  label: localizedDrillName(drill.id, drill.name),
                  background: Colors.black54,
                  foreground: Colors.white,
                ),
                RoundIconButton(icon: Icons.rotate_left_rounded, onTap: () {}),
              ],
            ),
          ),
          if (recording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 86,
              left: 0,
              right: 0,
              child: Center(
                child: Pill(
                  label:
                      '${AppLocalizations.get('recording_short')} ${elapsed.toStringAsFixed(1)}s',
                  background: AppColors.primary,
                  foreground: Colors.white,
                  icon: Icons.circle,
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 48,
            child: Center(
              child: GestureDetector(
                onTap: recording ? stop : start,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    recording ? Icons.stop_rounded : Icons.circle,
                    size: recording ? 42 : 66,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CaptureOverlay extends StatefulWidget {
  const CaptureOverlay({
    super.key,
    required this.recording,
    required this.elapsed,
    required this.duration,
    this.onQualityChange,
  });

  final bool recording;
  final double elapsed;
  final double duration;
  final ValueChanged<int>? onQualityChange;

  @override
  State<CaptureOverlay> createState() => _CaptureOverlayState();
}

class _CaptureOverlayState extends State<CaptureOverlay> {
  Timer? timer;
  int tick = 0;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) setState(() => tick++);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tilt = math.sin(tick / 18) * 6;
    final levelOk = tilt.abs() < 4;
    final light = 78 + (math.sin(tick / 10) * 6).round();
    final distance = 82 + (math.cos(tick / 12) * 5).round();
    final checks = [
      _Check(AppLocalizations.get('subject_in_frame'), true),
      _Check(AppLocalizations.get('camera_level'), levelOk),
      _Check(AppLocalizations.get('lighting'), light >= 70),
      _Check(AppLocalizations.get('distance_3m'), distance >= 75),
    ];
    final quality = ((checks.where((c) => c.ok).length / checks.length) * 100)
        .round();
    widget.onQualityChange?.call(quality);
    final qualityColor = quality >= 90
        ? AppColors.success
        : quality >= 60
        ? AppColors.warning
        : AppColors.destructive;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 32,
            right: 32,
            top: 112,
            bottom: 160,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: levelOk ? AppColors.success : AppColors.warning,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (levelOk ? AppColors.success : AppColors.warning)
                        .withOpacity(0.25),
                    blurRadius: 32,
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  CustomPaint(size: Size.infinite, painter: ThirdsPainter()),
                  const Center(
                    child: Icon(
                      Icons.filter_center_focus_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                  Positioned(
                    top: -12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Pill(
                        icon: Icons.open_in_full_rounded,
                        label: AppLocalizations.get('place_player_here'),
                        background: Colors.black54,
                        foreground: Colors.white,
                        small: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 96,
            child: TiltIndicator(tilt: tilt, ok: levelOk),
          ),
          Positioned(
            left: 16,
            top: MediaQuery.of(context).padding.top + 96,
            child: QualityChip(
              quality: quality,
              qualityColor: qualityColor,
              checks: checks,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 36,
            child: Center(
              child: SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(108, 108),
                      painter: BigProgressRing(
                        widget.recording
                            ? math.min(1, widget.elapsed / widget.duration)
                            : 0,
                        widget.recording
                            ? AppColors.primary
                            : AppColors.primary.withOpacity(0.38),
                      ),
                    ),
                    if (widget.recording)
                      Align(
                        alignment: const Alignment(0, -1.18),
                        child: Pill(
                          label:
                              '${math.max(0, widget.duration - widget.elapsed).toStringAsFixed(1)}s',
                          background: AppColors.primary,
                          foreground: Colors.white,
                          small: true,
                        ),
                      ),
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

class _Check {
  _Check(this.label, this.ok);
  final String label;
  final bool ok;
}

class QualityChip extends StatelessWidget {
  const QualityChip({
    super.key,
    required this.quality,
    required this.qualityColor,
    required this.checks,
  });

  final int quality;
  final Color qualityColor;
  final List<_Check> checks;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(38, 38),
                      painter: RingPainter(quality / 100, color: qualityColor),
                    ),
                    Text(
                      '$quality',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.get('setup_quality'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      quality >= 90
                          ? AppLocalizations.get('excellent')
                          : quality >= 60
                          ? AppLocalizations.get('adjust_setup')
                          : AppLocalizations.get('poor'),
                      style: TextStyle(
                        color: qualityColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...checks.map((c) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Icon(
                    c.ok ? Icons.check_rounded : Icons.warning_amber_rounded,
                    color: c.ok ? AppColors.success : AppColors.warning,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      c.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class TiltIndicator extends StatelessWidget {
  const TiltIndicator({super.key, required this.tilt, required this.ok});

  final double tilt;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: const Size(80, 80),
            painter: TiltPainter(tilt: tilt, ok: ok),
          ),
          Positioned(
            bottom: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${tilt >= 0 ? '+' : ''}${tilt.toStringAsFixed(0)} '
                '${AppLocalizations.get('degrees_short')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PipelinePage extends StatefulWidget {
  const PipelinePage({super.key, this.drillId});

  final String? drillId;

  @override
  State<PipelinePage> createState() => _PipelinePageState();
}

class _PipelinePageState extends State<PipelinePage> {
  int step = 0;
  Timer? timer;

  final steps = const [
    _PipelineStep(Icons.visibility_rounded, 'pipeline_landmarks'),
    _PipelineStep(Icons.monitor_heart_rounded, 'pipeline_tracking'),
    _PipelineStep(Icons.memory_rounded, 'pipeline_biomechanics'),
    _PipelineStep(Icons.psychology_rounded, 'pipeline_scoring'),
  ];

  @override
  void initState() {
    super.initState();
    schedule();
  }

  void schedule() {
    timer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (step >= steps.length) {
        Navigator.of(context).pushReplacementNamed(
          '/results?drill=${widget.drillId ?? drills.first.id}',
        );
      } else {
        setState(() => step++);
        schedule();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileShell(
      hideNav: true,
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height,
          ),
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 128,
              height: 128,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.15),
                    ),
                  ),
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.20),
                    ),
                  ),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryGlow],
                      ),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              AppLocalizations.get('analyzing_performance'),
              textAlign: TextAlign.center,
              style: displayBold.copyWith(fontSize: 25),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.get('pipeline_subtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 32),
            ...List.generate(steps.length, (i) {
              final done = i < step;
              final active = i == step;
              final item = steps[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.success.withOpacity(0.10)
                        : active
                        ? AppColors.primary.withOpacity(0.10)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: done
                          ? AppColors.success.withOpacity(0.30)
                          : active
                          ? AppColors.primary.withOpacity(0.40)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: done
                              ? AppColors.success
                              : active
                              ? AppColors.primary
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          done ? Icons.check_circle_rounded : item.icon,
                          color: done || active
                              ? Colors.white
                              : AppColors.muted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.get(item.label),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: active || done
                                ? AppColors.foreground
                                : AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _PipelineStep {
  const _PipelineStep(this.icon, this.label);
  final IconData icon;
  final String label;
}

class ResultsPage extends StatelessWidget {
  const ResultsPage({super.key, this.drillId});

  final String? drillId;

  @override
  Widget build(BuildContext context) {
    final drill = drillById(drillId);
    const score = 84;
    return MobileShell(
      routeName: '/results',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroHeader(
            paddingBottom: 28,
            child: Column(
              children: [
                Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/', (_) => false),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.get('latest_analysis'),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            localizedDrillName(drill.id, drill.name),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (context, constraints) {
                  final ringSize = (MediaQuery.of(context).size.height * 0.22).clamp(130.0, 176.0);
                  return SizedBox(
                  width: ringSize,
                  height: ringSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(ringSize, ringSize),
                        painter: ScoreRingPainter(score / 100),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$score',
                            style: const TextStyle(
                              color: AppColors.primaryGlow,
                              fontSize: 50,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            AppLocalizations.get('score'),
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  );
                }),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: DarkMetric(
                        icon: Icons.bolt_rounded,
                        label: AppLocalizations.get('top_speed'),
                        value: '32.4 km/h',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DarkMetric(
                        icon: Icons.center_focus_strong_rounded,
                        label: AppLocalizations.get('accuracy'),
                        value: '78%',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DarkMetric(
                        icon: Icons.monitor_heart_rounded,
                        label: AppLocalizations.get('reps'),
                        value: '24',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 90),
            child: Column(
              children: [
                SoftCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppLocalizations.get('speed_over_time'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.trending_up_rounded,
                            color: AppColors.success,
                            size: 18,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: (MediaQuery.of(context).size.height * 0.20).clamp(110.0, 160.0),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: AreaChartPainter(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SoftCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.get('body_angles'),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 160,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: BarChartPainter(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AlertCard(
                  icon: Icons.warning_amber_rounded,
                  title: AppLocalizations.get('fatigue_alert'),
                  body: AppLocalizations.get('fatigue_body'),
                  color: AppColors.warning,
                ),
                const SizedBox(height: 16),
                AlertCard(
                  icon: Icons.chat_bubble_rounded,
                  title: AppLocalizations.get('virtual_coach'),
                  body: AppLocalizations.get('coach_tip'),
                  color: AppColors.primary,
                  soft: AppColors.primarySoft,
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: AppLocalizations.get('pick_next_drill'),
                  onTap: () => Navigator.of(context).pushNamed('/drills'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final levelLabel =
        '${AppLocalizations.get('rank_beginner')} - ${AppLocalizations.get('level')} ${player.level}';
    return MobileShell(
      routeName: '/profile',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroHeader(
            center: true,
            paddingBottom: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AvatarCircle(size: 96, iconSize: 50),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.format('by_player', {'name': player.name}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Pill(
                  icon: Icons.shield_rounded,
                  label: levelLabel,
                  background: Color(0x22CC0A00),
                  foreground: AppColors.gold,
                  border: Color(0x77CC0A00),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      icon: Icons.star_rounded,
                      label: AppLocalizations.get('xp'),
                      value: '0',
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      icon: Icons.emoji_events_rounded,
                      label: AppLocalizations.get('coins'),
                      value: '120',
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      icon: Icons.local_fire_department_rounded,
                      label: AppLocalizations.get('streak'),
                      value: '0d',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 90),
            child: Column(
              children: [
                MenuRow(
                  icon: Icons.settings_rounded,
                  label: AppLocalizations.get('settings'),
                  onTap: () => Navigator.of(context).pushNamed('/settings'),
                ),
                const SizedBox(height: 8),
                MenuRow(
                  icon: Icons.emoji_events_rounded,
                  label: AppLocalizations.get('achievements'),
                  onTap: () => Navigator.of(context).pushNamed('/achievements'),
                ),
                const SizedBox(height: 8),
                MenuRow(
                  icon: Icons.logout_rounded,
                  label: AppLocalizations.get('sign_out'),
                  onTap: () async {
                    await ApiService.logout();
                    await FirebaseService().signOut();
                    await OnboardingStore().clearSignedIn();
                    currentUserName = 'Player';
                    if (!context.mounted) return;
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/auth', (_) => false);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _soundEnabled = SoundManager.instance.enabled;

  Future<void> _changeLanguage(String language) async {
    await OnboardingStore().setLanguage(language);
    if (!mounted) return;
    setState(() => setAppLanguage(language));
  }

  Future<void> _toggleSound(bool value) async {
    await SoundManager.instance.setEnabled(value);
    if (!mounted) return;
    setState(() => _soundEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final current = getAppLanguage();
    return MobileShell(
      routeName: '/profile',
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.of(context).padding.top + 18,
          20,
          MediaQuery.of(context).padding.bottom + 90,
        ),
        children: [
          Row(
            children: [
              RoundBackButton(onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.get('settings'),
                      style: displayBold.copyWith(fontSize: 26),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.get('language_settings_desc'),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SoftCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.language_rounded,
                  title: AppLocalizations.get('app_language'),
                ),
                const SizedBox(height: 14),
                LanguageChoice(
                  code: 'en',
                  name: 'English',
                  short: 'EN',
                  selected: current == 'en',
                  onTap: () => _changeLanguage('en'),
                ),
                const SizedBox(height: 10),
                LanguageChoice(
                  code: 'fr',
                  name: 'Français',
                  short: 'FR',
                  selected: current == 'fr',
                  onTap: () => _changeLanguage('fr'),
                ),
                const SizedBox(height: 10),
                LanguageChoice(
                  code: 'ar',
                  name: 'العربية',
                  short: 'AR',
                  selected: current == 'ar',
                  onTap: () => _changeLanguage('ar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.person_rounded,
                  title: AppLocalizations.get('account'),
                ),
                const SizedBox(height: 14),
                SettingsInfoRow(
                  icon: Icons.badge_rounded,
                  label: AppLocalizations.get('player_name'),
                  value: player.name,
                ),
                const SizedBox(height: 10),
                SettingsInfoRow(
                  icon: Icons.mail_rounded,
                  label: AppLocalizations.get('email'),
                  value: 'player@ssot.app',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.volume_up_rounded,
                  title: AppLocalizations.get('sound_effects'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      _soundEnabled
                          ? Icons.music_note_rounded
                          : Icons.music_off_rounded,
                      color: _soundEnabled ? AppColors.primary : AppColors.muted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _soundEnabled
                            ? AppLocalizations.get('sound_on')
                            : AppLocalizations.get('sound_off'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Switch(
                      value: _soundEnabled,
                      onChanged: _toggleSound,
                      activeColor: AppColors.primary,
                      inactiveThumbColor: AppColors.muted,
                      inactiveTrackColor: AppColors.surface2,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.tune_rounded,
                  title: AppLocalizations.get('training_preferences'),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.get('training_preferences_desc'),
                  style: const TextStyle(color: AppColors.muted, height: 1.45),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: AppLocalizations.get('edit_profile'),
                  icon: Icons.edit_rounded,
                  onTap: () =>
                      Navigator.of(context).pushNamed('/profile-onboarding'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      AchievementItem(
        icon: Icons.shield_rounded,
        title: AppLocalizations.get('achievement_profile_ready'),
        body: AppLocalizations.get('achievement_profile_ready_desc'),
        unlocked: true,
      ),
      AchievementItem(
        icon: Icons.auto_awesome_rounded,
        title: AppLocalizations.get('achievement_first_session'),
        body: AppLocalizations.get('achievement_first_session_desc'),
        unlocked: false,
      ),
      AchievementItem(
        icon: Icons.emoji_events_rounded,
        title: AppLocalizations.get('achievement_challenge_starter'),
        body: AppLocalizations.get('achievement_challenge_starter_desc'),
        unlocked: dailyChallenges.any((c) => c.status == 'done'),
      ),
      AchievementItem(
        icon: Icons.local_fire_department_rounded,
        title: AppLocalizations.get('achievement_streak_builder'),
        body: AppLocalizations.get('achievement_streak_builder_desc'),
        unlocked: player.streak >= 3,
      ),
    ];
    final unlocked = items.where((item) => item.unlocked).length;

    return MobileShell(
      routeName: '/profile',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroHeader(
            paddingBottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RoundBackButton(onTap: () => Navigator.of(context).pop()),
                const SizedBox(height: 18),
                Text(
                  AppLocalizations.get('achievements'),
                  style: displayBold.copyWith(
                    fontSize: 30,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLocalizations.get('achievements_desc'),
                  style: TextStyle(color: Colors.white.withOpacity(0.68)),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          AppLocalizations.format('achievement_progress', {
                            'done': unlocked,
                            'total': items.length,
                          }),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).padding.bottom + 90),
            child: Column(
              children: items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AchievementCard(item: item),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class AchievementItem {
  const AchievementItem({
    required this.icon,
    required this.title,
    required this.body,
    required this.unlocked,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool unlocked;
}

class AchievementCard extends StatelessWidget {
  const AchievementCard({super.key, required this.item});

  final AchievementItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.unlocked ? AppColors.primary : AppColors.muted;
    return Opacity(
      opacity: item.unlocked ? 1 : 0.72,
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Pill(
                        small: true,
                        label: item.unlocked
                            ? AppLocalizations.get('unlocked')
                            : AppLocalizations.get('locked'),
                        background: item.unlocked
                            ? AppColors.primary
                            : AppColors.surface2,
                        foreground: item.unlocked
                            ? Colors.black
                            : AppColors.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.body,
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LanguageChoice extends StatelessWidget {
  const LanguageChoice({
    super.key,
    required this.code,
    required this.name,
    required this.short,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String name;
  final String short;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = code == 'ar' ? GoogleFonts.tajawal() : const TextStyle();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.34),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withOpacity(0.35)),
              ),
              child: Text(
                short,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: textStyle.copyWith(
                  color: selected ? AppColors.primary : AppColors.foreground,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class SettingsInfoRow extends StatelessWidget {
  const SettingsInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: displayBold.copyWith(fontSize: 18))),
      ],
    );
  }
}

class RoundBackButton extends StatelessWidget {
  const RoundBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
          color: AppColors.foreground,
        ),
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
