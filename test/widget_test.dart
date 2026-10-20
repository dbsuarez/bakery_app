import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/main.dart';

void main() {
  testWidgets('App explains missing build-time configuration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BakeryApp());
    await tester.pump();

    expect(
      find.textContaining('Missing Supabase configuration'),
      findsOneWidget,
    );
  });
}
