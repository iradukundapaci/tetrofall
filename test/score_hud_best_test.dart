import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/game/render/score_hud.dart';
import 'package:tetrofall/game/tetrofall_game.dart';
import 'package:tetrofall/services/storage_service.dart';

/// Who is allowed to write the player's best score.
///
/// [ScoreHud] banks a new best the instant the score passes the old one, which
/// is right for a run and wrong for the tutorial: the coached lesson hands the
/// player a rigged row worth a hundred points and then tells them to clear it.
/// Banked, that shows up as a best score on a brand new install and feeds
/// `Difficulty.adaptiveStartElapsed`, so the first real game starts faster
/// than a first real game should.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(TetrofallGame, StorageService)> build() async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.load();
    final game = TetrofallGame(storage: storage, feedbackEnabled: false);
    game.engine.start();
    return (game, storage);
  }

  Future<void> pumpHud(
    WidgetTester tester,
    TetrofallGame game,
    StorageService storage, {
    required bool recordsBest,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoreHud(
            game: game,
            storage: storage,
            recordsBest: recordsBest,
          ),
        ),
      ),
    );
  }

  /// What the tutorial's rigged row is worth when the player clears it.
  void scoreARow(TetrofallGame game) {
    game.engine.scoring.awardLineClear(
      lines: 1,
      chainIndex: 0,
      elapsedSeconds: 0,
    );
  }

  testWidgets('a scored run banks its best', (tester) async {
    final (game, storage) = await build();
    await pumpHud(tester, game, storage, recordsBest: true);

    scoreARow(game);
    await tester.pump();

    expect(game.engine.scoring.score, greaterThan(0));
    expect(storage.bestScore, game.engine.scoring.score);
    expect(find.text('BEST ${storage.bestScore}'), findsOneWidget);
  });

  testWidgets('the tutorial does not', (tester) async {
    final (game, storage) = await build();
    await pumpHud(tester, game, storage, recordsBest: false);

    scoreARow(game);
    await tester.pump();

    expect(
      game.engine.scoring.score,
      greaterThan(0),
      reason: 'the clear still scores; it just is not the player\'s best',
    );
    expect(
      storage.bestScore,
      0,
      reason: 'a rigged row the player was told to clear is not an achievement',
    );
    expect(
      find.text('BEST 0'),
      findsOneWidget,
      reason: 'and the HUD must not show it climbing either',
    );
  });
}
