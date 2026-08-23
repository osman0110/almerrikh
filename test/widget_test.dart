import 'package:flutter_test/flutter_test.dart';

import 'package:al_merrikh/main.dart';

void main() {
  testWidgets('App boots smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SsotApp());
    expect(find.byType(SsotApp), findsOneWidget);
  });
}
