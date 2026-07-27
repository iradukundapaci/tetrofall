import 'package:flutter_test/flutter_test.dart';

import 'package:tetrofall/app.dart';

void main() {
  testWidgets('App boots and shows the game widget', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TetrofallApp());
    await tester.pump();

    expect(find.byType(TetrofallApp), findsOneWidget);
  });
}
