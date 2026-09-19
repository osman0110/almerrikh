import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_merrikh/feature_flags.dart';
import 'package:al_merrikh/screens/physical_assessment/assessment_hub_page.dart';
import 'package:al_merrikh/screens/physical_assessment/player_selection_page.dart';

// AI tests are hidden for the production launch (2026-09-19). These screens
// are reachable by deep link / stale navigation state, so they must refuse to
// start the flow themselves — not only rely on hidden buttons.
void main() {
  test('AI tests are disabled by default (single central flag)', () {
    expect(kAiTestsEnabled, isFalse);
  });

  testWidgets('test selection screen shows the unavailable page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlayerSelectionPage()));
    await tester.pump();
    expect(find.byType(AiTestsUnavailablePage), findsOneWidget);
  });

  testWidgets('assessment hub shows the unavailable page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AssessmentHubPage()));
    await tester.pump();
    expect(find.byType(AiTestsUnavailablePage), findsOneWidget);
  });
}
