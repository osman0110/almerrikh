import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_localizations.dart';

// ─── Feature flags — single source of truth ──────────────────────────────────
//
// AI / computer-vision tests (camera + pose detection + automated scoring:
// squat, CMJ, drop jumps, balance, jump landing, session batch tests).
// Disabled for the production launch (decision 2026-09-19): every entry
// point is hidden and every AI screen refuses to start. NOTHING is deleted —
// code, routes, models, APIs, stored results and tests stay intact, and past
// results remain viewable in history.
//
// Re-enable without code changes:
//   flutter build ... --dart-define=AI_TESTS_ENABLED=true
// or flip the default below.
const bool kAiTestsEnabled =
    bool.fromEnvironment('AI_TESTS_ENABLED', defaultValue: false);

/// State used by AI screens (camera, pose setup, test selection, session
/// queue) when [kAiTestsEnabled] is false. Returned from `createState()` so
/// the real screen's initState never runs — no camera/permission prompt, no
/// pose model load — even when reached through a deep link or stale route.
class AiTestsDisabledState<T extends StatefulWidget> extends State<T> {
  @override
  Widget build(BuildContext context) => const AiTestsUnavailablePage();
}

class AiTestsUnavailablePage extends StatelessWidget {
  const AiTestsUnavailablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_rounded,
                    color: AppColors.muted, size: 40),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.get('ai_tests_unavailable'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).canPop()
                      ? Navigator.of(context).pop()
                      : Navigator.of(context)
                          .pushNamedAndRemoveUntil('/', (_) => false),
                  child: Text(AppLocalizations.get('back_btn')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
