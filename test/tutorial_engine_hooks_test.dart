import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/config/difficulty.dart';
import 'package:tetrofall/game/engine/events.dart';
import 'package:tetrofall/game/engine/game_engine.dart';
import 'package:tetrofall/game/engine/tetromino.dart';

/// The three seams the first-run tutorial hangs off: freezing the run without
/// deafening it to input, announcing player actions that actually landed, and
/// scripting which piece comes next.
///
/// The freeze is the load-bearing one. `pauseEngine()` cannot stand in for it:
/// that halts the whole loop, and the gameplay screen's `Listener`
/// short-circuits on `game.paused` — so a paused game ignores exactly the
/// gestures a coach card is asking the player to make.
void main() {
  const step = 1 / 60;

  GameEngine startedEngine() => GameEngine(random: Random(7))..start();

  void tickFor(GameEngine engine, double seconds) {
    for (var t = 0.0; t < seconds; t += step) {
      engine.tick(step);
    }
  }

  test('a frozen piece hovers but still obeys the player', () {
    final engine = startedEngine()..freezeGravity = true;
    final startRow = engine.pieceController.piece!.anchorRow;
    final startCol = engine.pieceController.piece!.anchorCol;

    tickFor(engine, 5);

    expect(
      engine.pieceController.piece!.anchorRow,
      startRow,
      reason: 'frozen gravity must not advance the piece at all',
    );
    expect(
      engine.phase,
      GamePhase.playing,
      reason: 'freezing is not pausing — the run is still live',
    );

    engine.enqueueIntent(GameIntentType.moveLeft);
    engine.tick(step);

    expect(
      engine.pieceController.piece!.anchorCol,
      startCol - 1,
      reason: 'the whole point of the freeze is that input still applies',
    );
  });

  test('a soft drop is inert against frozen gravity', () {
    // Why the soft-drop step is the one that has to let the clock run: soft
    // drop only divides an interval nothing is counting.
    final engine = startedEngine()..freezeGravity = true;
    final startRow = engine.pieceController.piece!.anchorRow;

    engine.enqueueIntent(GameIntentType.softDropStart);
    tickFor(engine, 3);

    expect(engine.pieceController.piece!.anchorRow, startRow);
  });

  test('a frozen rise stops its clock as well as its board', () {
    final engine = startedEngine()..freezeRise = true;
    var committed = false;
    engine.addEventListener((e) {
      if (e is RiseCommittedEvent) committed = true;
    });

    tickFor(engine, Difficulty.riseGracePeriod.inSeconds + 40);

    expect(engine.riseController.riseProgress, 0);
    expect(
      engine.riseController.elapsed,
      0,
      reason: 'the difficulty curve must not creep while a card is up',
    );
    expect(committed, isFalse);
  });

  test('lowering a spawned piece brings it into view', () {
    // Pieces spawn inside the two-row hidden buffer above the board, so a
    // coached step that freezes gravity would otherwise ask the player to
    // steer something that is never drawn.
    final engine = startedEngine();
    expect(
      engine.pieceController.piece!.anchorRow,
      lessThan(0),
      reason: 'a fresh spawn starts in the hidden buffer',
    );

    final resting = engine.pieceController.lowerTo(4);

    expect(resting, 4);
    expect(engine.pieceController.piece!.anchorRow, 4);
  });

  test('only an action that landed announces itself', () {
    final engine = startedEngine();
    final actions = <PlayerAction>[];
    engine.addEventListener((e) {
      if (e is PlayerActionEvent) actions.add(e.action);
    });

    // Far more moves than there are columns, so the last of them are pressing
    // against the wall and must produce nothing.
    for (var i = 0; i < engine.grid.cols + 6; i++) {
      engine.enqueueIntent(GameIntentType.moveLeft);
      engine.tick(step);
    }
    final afterWall = actions.length;
    engine.enqueueIntent(GameIntentType.moveLeft);
    engine.tick(step);

    expect(
      actions.length,
      afterWall,
      reason: 'a swipe into the wall moved nothing and must not count',
    );
    expect(actions, everyElement(PlayerAction.moveLeft));
  });

  test('drops and rotations announce themselves too', () {
    final engine = startedEngine();
    final actions = <PlayerAction>[];
    engine.addEventListener((e) {
      if (e is PlayerActionEvent) actions.add(e.action);
    });

    engine
      ..enqueueIntent(GameIntentType.rotateCW)
      ..enqueueIntent(GameIntentType.softDropStart)
      ..tick(step);
    expect(actions, [PlayerAction.rotate, PlayerAction.softDrop]);

    engine
      ..enqueueIntent(GameIntentType.hardDrop)
      ..tick(step);
    expect(
      actions.last,
      PlayerAction.hardDrop,
      reason: 'the hard drop must be announced before the lock cascade',
    );
  });

  test('a scripted spawn outranks the bag', () {
    // Mirrors how the tutorial actually does it: script *into* a run that is
    // already going, then ask for the piece to be re-dealt. Scripting before
    // `start()` would not work — see the next test.
    final engine = startedEngine()
      ..queuePieces([TetrominoType.T, TetrominoType.O])
      ..respawnPiece()
      ..tick(step);

    expect(engine.pieceController.piece!.type, TetrominoType.T);

    engine
      ..enqueueIntent(GameIntentType.hardDrop)
      ..tick(step);
    // A lone piece on an empty board clears nothing, so the resolve is short.
    tickFor(engine, 6);
    expect(engine.pieceController.piece!.type, TetrominoType.O);
  });

  test('start() drops the script', () {
    // A restart must not inherit a scripted piece — that is what would
    // otherwise leak the tutorial's rig into the real run that follows it.
    final control = GameEngine(random: Random(7))..start();
    final fromBag = control.pieceController.piece!.type;
    expect(
      fromBag,
      isNot(TetrominoType.S),
      reason: 'test premise: the bag must not open with the scripted type, or '
          'this proves nothing — change the seed if it ever does',
    );

    final scripted = GameEngine(random: Random(7))
      ..queuePieces([TetrominoType.S, TetrominoType.S, TetrominoType.S]);
    scripted.start();

    expect(
      scripted.pieceController.piece!.type,
      fromBag,
      reason: 'the same seed must deal the same piece, script or no script',
    );
  });
}
