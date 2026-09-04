import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/main.dart';

void main() {
  testWidgets('App launches to the dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const BakeryApp());
    await tester.pump();

    expect(find.text('Dashboard'), findsWidgets);
  });
}
