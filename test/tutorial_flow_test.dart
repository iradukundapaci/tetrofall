import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/game/engine/events.dart';
import 'package:tetrofall/game/engine/game_engine.dart';
import 'package:tetrofall/game/engine/tetromino.dart';
import 'package:tetrofall/game/tetrofall_game.dart';
import 'package:tetrofall/services/storage_service.dart';
import 'package:tetrofall/ui/screens/tutorial/tutorial_controller.dart';

/// The first-run tutorial's step machine, driven through a real engine.
///
/// The test that matters most is the last one: the tutorial reaches into the
/// engine and stops its clocks, and if any of that survives the hand-off the
/// player inherits a run that does not work.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const step = 1 / 60;

  Future<(TetrofallGame, TutorialController, List<void>)> build() async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.load();
    final game = TetrofallGame(storage: storage, feedbackEnabled: false);
    final finishes = <void>[];
    final controller = TutorialController(
      game: game,
      storage: storage,
      onFinished: () => finishes.add(null),
    );
    // Stands in for Flame's `onLoad`, which is what starts a real run.
    game.engine.start();
    return (game, controller, finishes);
  }

  /// Plays [intent] and lets the engine act on it.
  void act(GameEngine engine, GameIntentType intent) {
    engine
      ..enqueueIntent(intent)
      ..tick(step);
  }

  void settle(GameEngine engine, [double seconds = 3]) {
    for (var t = 0.0; t < seconds; t += step) {
      engine.tick(step);
    }
  }

  /// The rigged row has exactly one two-wide gap; slide the square over it and
  /// drop. Returns the gap's left column.
  int clearRiggedRow(GameEngine engine) {
    final bottom = engine.grid.maxRow;
    final gaps = [
      for (var c = 0; c < engine.grid.cols; c++)
        if (!engine.grid.isOccupied(bottom, c)) c,
    ];
    expect(gaps, hasLength(2), reason: 'an O fills exactly two columns');
    expect(gaps[1], gaps[0] + 1, reason: 'the gap must be contiguous');
    while (engine.pieceController.piece!.anchorCol < gaps[0]) {
      act(engine, GameIntentType.moveRight);
    }
    while (engine.pieceController.piece!.anchorCol > gaps[0]) {
      act(engine, GameIntentType.moveLeft);
    }
    act(engine, GameIntentType.hardDrop);
    return gaps[0];
  }

  /// Plays the tutorial the way a compliant player would until it reaches
  /// [target]. Bounded, so a machine that stalls fails loudly instead of
  /// hanging the suite.
  void driveTo(
    TutorialController controller,
    GameEngine engine,
    TutorialStep target,
  ) {
    for (var i = 0; controller.step != target; i++) {
      if (i > 40) fail('stuck on ${controller.step} trying to reach $target');
      if (controller.mode == TutorialMode.modal) {
        controller.advance();
      } else {
        switch (controller.step) {
          case TutorialStep.move:
            act(engine, GameIntentType.moveLeft);
            act(engine, GameIntentType.moveLeft);
          case TutorialStep.rotate:
            act(engine, GameIntentType.rotateCW);
          case TutorialStep.hardDrop:
            act(engine, GameIntentType.hardDrop);
          case TutorialStep.softDrop:
            act(engine, GameIntentType.softDropStart);
          case TutorialStep.clearRow:
            clearRiggedRow(engine);
          default:
            break;
        }
      }
      settle(engine);
    }
  }

  test('the intro freezes the run without pausing it', () async {
    final (game, controller, _) = await build();

    expect(controller.step, TutorialStep.intro);
    expect(controller.mode, TutorialMode.modal);
    expect(controller.dimsBoard, isTrue);
    expect(game.engine.freezeGravity, isTrue);
    expect(game.engine.freezeRise, isTrue);
    expect(
      game.paused,
      isFalse,
      reason: 'a paused game is deaf to gestures; freezing is not pausing',
    );
  });

  test('the coached piece is one the player can see, and can rotate', () async {
    final (game, controller, _) = await build();
    controller.advance();
    game.engine.tick(step);

    final piece = game.engine.pieceController.piece!;
    expect(
      piece.type,
      TetrominoType.T,
      reason: "an O's four rotation states are identical, so the rotate step "
          'taught on one would show the player nothing happening',
    );
    expect(
      piece.anchorRow,
      greaterThanOrEqualTo(0),
      reason: 'a piece left in the spawn buffer is drawn above the board',
    );
  });

  test('coach steps advance on the gesture they teach', () async {
    final (game, controller, _) = await build();
    final engine = game.engine;

    controller.advance();
    engine.tick(step);
    expect(controller.step, TutorialStep.move);
    expect(controller.mode, TutorialMode.coach);
    expect(
      controller.dimsBoard,
      isFalse,
      reason: 'dimming applies IgnorePointer and would eat the gesture',
    );

    act(engine, GameIntentType.moveLeft);
    expect(
      controller.step,
      TutorialStep.move,
      reason: 'one nudge is not yet a demonstration',
    );
    act(engine, GameIntentType.moveLeft);
    expect(controller.step, TutorialStep.rotate);

    act(engine, GameIntentType.rotateCW);
    expect(controller.step, TutorialStep.hardDrop);

    act(engine, GameIntentType.hardDrop);
    expect(controller.step, TutorialStep.softDrop);
    expect(
      engine.freezeGravity,
      isFalse,
      reason: 'soft drop only divides an interval, so the clock must run',
    );
  });

  test('one flick cannot tick off both drop steps', () async {
    // A downward flick enqueues softDropStart on its way to hardDrop. Teaching
    // hard drop first is what makes the stray softDropStart land on a step
    // that is not listening for it.
    final (game, controller, _) = await build();
    final engine = game.engine;

    controller.advance();
    engine.tick(step);
    act(engine, GameIntentType.moveLeft);
    act(engine, GameIntentType.moveLeft);
    act(engine, GameIntentType.rotateCW);
    expect(controller.step, TutorialStep.hardDrop);

    // The whole flick, exactly as GestureHandler emits it.
    engine
      ..enqueueIntent(GameIntentType.softDropStart)
      ..enqueueIntent(GameIntentType.softDropEnd)
      ..enqueueIntent(GameIntentType.hardDrop)
      ..tick(step);

    expect(
      controller.step,
      TutorialStep.softDrop,
      reason: 'the flick may satisfy the hard-drop step and nothing beyond it',
    );
  });

  test('the rigged row is one square short, and clearing it moves on', () async {
    final (game, controller, _) = await build();
    final engine = game.engine;

    driveTo(controller, engine, TutorialStep.clearRow);

    expect(
      engine.pieceController.piece!.type,
      TetrominoType.O,
      reason: 'the square is what the rigged gap is cut for',
    );
    clearRiggedRow(engine);

    expect(controller.step, TutorialStep.riseIntro);
  });

  test('the scripted rise arrives in seconds, not half a minute', () async {
    final (game, controller, _) = await build();
    final engine = game.engine;
    var committed = false;
    engine.addEventListener((e) {
      if (e is RiseCommittedEvent) committed = true;
    });

    // Stop one short and step in by hand: the rise lands fast enough that
    // driving *to* riseWatch sails straight through it.
    driveTo(controller, engine, TutorialStep.riseIntro);
    controller.advance();
    expect(controller.step, TutorialStep.riseWatch);
    expect(engine.freezeRise, isFalse);

    for (var t = 0.0; t < 5 && !committed; t += step) {
      engine.tick(step);
    }

    expect(
      committed,
      isTrue,
      reason: 'the rise has a 12s grace period; the tutorial must skip past it',
    );
    expect(controller.step, TutorialStep.done);
  });

  test('finishing hands the run back exactly as it was found', () async {
    final (game, controller, finishes) = await build();
    final engine = game.engine;

    // The states the tutorial is allowed to leave behind are none of them.
    controller.advance();
    engine.tick(step);
    controller.skip();

    expect(finishes, hasLength(1));
    expect(controller.isFinished, isTrue);
    expect(engine.freezeGravity, isFalse);
    expect(engine.freezeRise, isFalse);
    expect(engine.pieceController.softDropActive, isFalse);
    expect(await StorageService.load().then((s) => s.tutorialSeen), isTrue);

    // And the run really does move again.
    final row = engine.pieceController.piece!.anchorRow;
    for (var t = 0.0; t < 3; t += step) {
      engine.tick(step);
    }
    expect(engine.pieceController.piece!.anchorRow, greaterThan(row));
  });

  test('a game over underneath releases the engine without a hand-off', () async {
    final (game, controller, finishes) = await build();

    game.engine.phase = GamePhase.gameOver;
    controller.advance();
    // Delivered the way the engine would.
    game.engine.tick(step);
    controller.abandon();

    expect(controller.isFinished, isTrue);
    expect(game.engine.freezeGravity, isFalse);
    expect(
      finishes,
      isEmpty,
      reason: 'the game-over overlay owns the screen; do not restart under it',
    );
  });
}
