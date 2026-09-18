import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tetrofall/app.dart';
import 'package:tetrofall/services/ads_service.dart';
import 'package:tetrofall/services/storage_service.dart';
import 'package:tetrofall/services/economy.dart';

void main() {
  testWidgets('App boots and shows the game widget', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.load();
    final ads = AdsService(storage);

    await tester.pumpWidget(
      TetrofallApp(
        storage: storage,
        ads: ads,
        economy: Economy(storage),
      ),
    );
    await tester.pump();

    expect(find.byType(TetrofallApp), findsOneWidget);
  });
}
