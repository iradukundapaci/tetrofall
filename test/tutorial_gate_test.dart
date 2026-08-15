import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/services/storage_service.dart';

/// Who gets shown the first-run tutorial.
///
/// The derived default is the part worth pinning: this ships in an update to
/// players who already have hundreds of runs behind them, and dragging them
/// back through a beginner's tutorial on launch day would be worse than
/// having no tutorial at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> storageWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return StorageService.load();
  }

  test('a fresh install has not seen the tutorial', () async {
    expect((await storageWith({})).tutorialSeen, isFalse);
  });

  test('a player who already has a score is not dragged through it', () async {
    expect((await storageWith({'best_score': 500})).tutorialSeen, isTrue);
  });

  test('an explicit flag beats the derived default in both directions', () async {
    expect(
      (await storageWith({'best_score': 500, 'tutorial_seen': false}))
          .tutorialSeen,
      isFalse,
      reason: 'an explicit false must win, so the flag can be reset for QA',
    );
    expect((await storageWith({'tutorial_seen': true})).tutorialSeen, isTrue);
  });

  test('the flag survives being written', () async {
    final storage = await storageWith({});
    expect(storage.tutorialSeen, isFalse);
    await storage.saveTutorialSeen(true);
    expect(storage.tutorialSeen, isTrue);
  });
}
