import 'package:flutter_test/flutter_test.dart';

import 'package:smart_sport_scribe_main/main.dart';

void main() {
  testWidgets('App boots smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SsotApp());
    expect(find.byType(SsotApp), findsOneWidget);
  });
}
