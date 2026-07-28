import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tetrofall/app.dart';
import 'package:tetrofall/services/storage_service.dart';

void main() {
  testWidgets('App boots and shows the game widget', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.load();

    await tester.pumpWidget(TetrofallApp(storage: storage));
    await tester.pump();

    expect(find.byType(TetrofallApp), findsOneWidget);
  });
}
