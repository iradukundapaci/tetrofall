import 'package:fake_async/fake_async.dart';
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
/// Two tests matter most. The last one, because the tutorial reaches into the
/// engine and stops its clocks, and if any of that survives the hand-off the
/// player inherits a run that does not work. And the effect-beat ones, because
/// the whole reason a satisfied step lingers is that the player has to be able
/// to see what they just did a step that advances the instant the intent
/// lands shows them nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const step = 1 / 60;
  const frame = Duration(microseconds: 16667);

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

  /// Runs the engine and the wall clock forward together.
  ///
  /// Both are needed now: a satisfied coach step holds its card on screen with
  /// a real [Timer] while the board plays out underneath it, so a loop that
  /// only ticked the engine would sit on the same step forever.
  void run(FakeAsync fake, GameEngine engine, [double seconds = 3]) {
    for (var t = 0.0; t < seconds; t += step) {
      engine.tick(step);
      fake.elapse(frame);
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
    FakeAsync fake,
    TutorialStep target,
  ) {
    for (var i = 0; controller.step != target; i++) {
      if (i > 40) fail('stuck on ${controller.step} trying to reach $target');
      if (controller.mode == TutorialMode.modal) {
        controller.advance();
      } else if (controller.phase == TutorialPhase.prompt) {
        // A step already showing its work wants nothing but time.
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
          case TutorialStep.cascadeRow:
            clearRiggedRow(engine);
          default:
            break;
        }
      }
      run(fake, engine);
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
      reason:
          "an O's four rotation states are identical, so the rotate step "
          'taught on one would show the player nothing happening',
    );
    expect(
      piece.anchorRow,
      greaterThanOrEqualTo(0),
      reason: 'a piece left in the spawn buffer is drawn above the board',
    );
  });

  test('a satisfied step holds the board on screen before moving on', () async {
    // The complaint this whole beat exists to answer: the card used to swap
    // out inside the same frame as the gesture, so the player never saw the
    // piece move.
    final (game, controller, _) = await build();
    final engine = game.engine;

    fakeAsync((fake) {
      controller.advance();
      engine.tick(step);
      act(engine, GameIntentType.moveLeft);
      act(engine, GameIntentType.moveLeft);

      expect(controller.step, TutorialStep.move);
      expect(controller.phase, TutorialPhase.effect);
      expect(
        controller.body,
        isNot('Swipe left or right to move the piece.'),
        reason: 'the card should name what just happened, not repeat the ask',
      );
      expect(
        controller.hint,
        TutorialHint.none,
        reason:
            'a looping finger still asking for a gesture already made '
            'reads as a bug',
      );

      run(fake, engine, 1);
      expect(controller.step, TutorialStep.rotate);
      expect(controller.phase, TutorialPhase.prompt);
      expect(controller.hint, TutorialHint.tap);
    });
  });

  test('coach steps advance on the gesture they teach', () async {
    final (game, controller, _) = await build();
    final engine = game.engine;

    fakeAsync((fake) {
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
      run(fake, engine, 1);
      expect(
        controller.step,
        TutorialStep.move,
        reason: 'one nudge is not yet a demonstration',
      );
      act(engine, GameIntentType.moveLeft);
      run(fake, engine, 1);
      expect(controller.step, TutorialStep.rotate);

      act(engine, GameIntentType.rotateCW);
      run(fake, engine, 1);
      expect(controller.step, TutorialStep.hardDrop);

      act(engine, GameIntentType.hardDrop);
      run(fake, engine, 2);
      expect(controller.step, TutorialStep.softDrop);
      expect(
        engine.freezeGravity,
        isFalse,
        reason: 'soft drop only divides an interval, so the clock must run',
      );
    });
  });

  test('the hard-drop step waits for the slam, not the intent', () async {
    // The engine emits PlayerActionEvent(hardDrop) *before* it runs the drop,
    // so a step hung off that event changed the card while the piece was still
    // sitting where the player left it.
    final (game, controller, _) = await build();
    final engine = game.engine;

    fakeAsync((fake) {
      driveTo(controller, engine, fake, TutorialStep.hardDrop);

      final from = engine.pieceController.piece!.anchorRow;
      engine.enqueueIntent(GameIntentType.hardDrop);
      expect(
        controller.step,
        TutorialStep.hardDrop,
        reason: 'nothing has been dropped yet',
      );

      engine.tick(step);
      expect(
        controller.phase,
        TutorialPhase.effect,
        reason: 'the lock landed in the same pass, and that is the slam',
      );
      expect(
        controller.step,
        TutorialStep.hardDrop,
        reason: 'the card names the slam before the next lesson takes over',
      );
      expect(
        controller.captionAtTop,
        isTrue,
        reason:
            'the piece is on the floor now; the caption is not allowed to '
            'be sitting on it',
      );
      expect(from, lessThan(engine.grid.maxRow));

      run(fake, engine, 2);
      expect(controller.step, TutorialStep.softDrop);
    });
  });

  test('one flick cannot tick off both drop steps', () async {
    // A downward flick enqueues softDropStart on its way to hardDrop. Teaching
    // hard drop first is what makes the stray softDropStart land on a step
    // that is not listening for it and the effect beat now swallows it too.
    final (game, controller, _) = await build();
    final engine = game.engine;

    fakeAsync((fake) {
      driveTo(controller, engine, fake, TutorialStep.hardDrop);

      // The whole flick, exactly as GestureHandler emits it.
      engine
        ..enqueueIntent(GameIntentType.softDropStart)
        ..enqueueIntent(GameIntentType.softDropEnd)
        ..enqueueIntent(GameIntentType.hardDrop)
        ..tick(step);
      run(fake, engine, 2);

      expect(
        controller.step,
        TutorialStep.softDrop,
        reason:
            'the flick may satisfy the hard-drop step and nothing beyond it',
      );
    });
  });

  test(
    'the rigged row is one square short, and clearing it moves on',
    () async {
      final (game, controller, _) = await build();
      final engine = game.engine;

      fakeAsync((fake) {
        driveTo(controller, engine, fake, TutorialStep.clearRow);

        expect(
          engine.pieceController.piece!.type,
          TetrominoType.O,
          reason: 'the square is what the rigged gap is cut for',
        );
        clearRiggedRow(engine);
        run(fake, engine, 1);

        expect(
          controller.step,
          TutorialStep.clearRow,
          reason:
              'the shatter runs for the best part of a second; do not cover '
              'it with the next card',
        );
        expect(controller.phase, TutorialPhase.effect);

        run(fake, engine, 2);
        expect(controller.step, TutorialStep.cascadeIntro);
      });
    },
  );

  test('the cascade rig chains, and the step waits for it', () async {
    // Gravity in this game runs only as part of a clear, and as a wave rather
    // than a collapse. The rig leans on both: the row above is released first
    // and lands one column short, and the lone block two rows up arrives after
    // it, into exactly that column.
    final (game, controller, _) = await build();
    final engine = game.engine;
    final chains = <int>[];
    final clears = <int>[];
    engine.addEventListener((e) {
      if (e is ChainAdvancedEvent) chains.add(e.chainIndex);
      if (e is RowsClearedEvent) clears.add(e.rows.length);
    });

    fakeAsync((fake) {
      driveTo(controller, engine, fake, TutorialStep.cascadeRow);

      expect(
        engine.grid.rowHasAnyBlock(engine.grid.maxRow - 2),
        isTrue,
        reason: 'the block that lands last is what turns the drop into a chain',
      );

      clears.clear();
      chains.clear();
      clearRiggedRow(engine);
      run(fake, engine, 1);

      expect(
        controller.step,
        TutorialStep.cascadeRow,
        reason: 'the first shatter is not the lesson; the chain behind it is',
      );

      // Up to the chain, then stop the beat that follows it is short
      // enough that running past it would hide the thing being asserted.
      for (var i = 0; i < 16 && !chains.any((c) => c > 0); i++) {
        run(fake, engine, 0.25);
      }
      expect(
        chains.where((c) => c > 0),
        isNotEmpty,
        reason:
            'the cascade must complete a second row, or there is nothing here '
            'the last lesson did not already show',
      );
      expect(clears, hasLength(2), reason: 'the drop, then the chain');
      expect(controller.step, TutorialStep.cascadeRow);
      expect(controller.phase, TutorialPhase.effect);

      run(fake, engine, 3);
      expect(controller.step, TutorialStep.riseIntro);
    });
  });

  test('the scripted rise climbs where the player can watch it', () async {
    final (game, controller, _) = await build();
    final engine = game.engine;
    var committed = false;
    engine.addEventListener((e) {
      if (e is RiseCommittedEvent) committed = true;
    });

    fakeAsync((fake) {
      // Stop one short and step in by hand: the rise lands fast enough that
      // driving *to* riseWatch sails straight through it.
      driveTo(controller, engine, fake, TutorialStep.riseIntro);
      controller.advance();
      expect(controller.step, TutorialStep.riseWatch);
      expect(engine.freezeRise, isFalse);
      expect(
        engine.freezeGravity,
        isTrue,
        reason:
            'a piece drifting down the middle competes with the one thing '
            'the step is asking the player to watch',
      );
      expect(
        engine.riseController.riseProgress,
        0.0,
        reason: 'a row that starts nine tenths up has already arrived',
      );
      expect(
        engine.grid.rowHasAnyBlock(engine.grid.maxRow),
        isTrue,
        reason:
            'the rise needs a stack to shove, or it is just a row landing '
            'on an empty floor',
      );

      // Half a second in, the row must be visibly on its way but not yet home.
      run(fake, engine, 0.5);
      expect(committed, isFalse);
      expect(engine.riseController.riseProgress, greaterThan(0.05));

      for (var t = 0.0; t < 6 && !committed; t += step) {
        engine.tick(step);
        fake.elapse(frame);
      }
      expect(
        committed,
        isTrue,
        reason:
            'the rise has a 12s grace period and a 22s interval; the '
            'tutorial must compress both',
      );
      expect(
        controller.step,
        TutorialStep.riseWatch,
        reason:
            'the closing modal dims the board not over the one frame '
            'worth watching',
      );

      run(fake, engine, 2);
      expect(controller.step, TutorialStep.done);
    });
  });

  test('finishing hands the run back exactly as it was found', () async {
    final (game, controller, finishes) = await build();
    final engine = game.engine;

    // The states the tutorial is allowed to leave behind are none of them.
    controller.advance();
    engine.tick(step);
    engine.riseController.debugSpeedMultiplier = 5.5;
    controller.skip();

    expect(finishes, hasLength(1));
    expect(controller.isFinished, isTrue);
    expect(engine.freezeGravity, isFalse);
    expect(engine.freezeRise, isFalse);
    expect(engine.pieceController.softDropActive, isFalse);
    expect(
      engine.riseController.debugSpeedMultiplier,
      1.0,
      reason:
          "RiseController.reset does not touch this, so the demo's "
          'compressed clock would follow the player into their first real run',
    );
    expect(await StorageService.load().then((s) => s.tutorialSeen), isTrue);

    // And the run really does move again.
    final row = engine.pieceController.piece!.anchorRow;
    for (var t = 0.0; t < 3; t += step) {
      engine.tick(step);
    }
    expect(engine.pieceController.piece!.anchorRow, greaterThan(row));
  });

  test('a held beat cannot outlive the tutorial', () async {
    // Skip lands mid-beat often enough: the card sits there for the best part
    // of two seconds, and it carries the Skip button.
    final (game, controller, _) = await build();
    final engine = game.engine;

    fakeAsync((fake) {
      driveTo(controller, engine, fake, TutorialStep.rotate);
      act(engine, GameIntentType.rotateCW);
      expect(controller.phase, TutorialPhase.effect);

      controller.skip();
      run(fake, engine, 3);

      expect(controller.step, TutorialStep.rotate);
      expect(
        engine.freezeGravity,
        isFalse,
        reason:
            'a timer that fired after the hand-off would re-freeze the '
            "player's own run",
      );
    });
  });

  test(
    'a game over underneath releases the engine without a hand-off',
    () async {
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
        reason:
            'the game-over overlay owns the screen; do not restart under it',
      );
    },
  );
}
