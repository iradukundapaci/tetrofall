import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/engine/game_engine.dart';
import 'package:tetrofall/game/input/gesture_handler.dart';

/// Regression tests for the two ends of the horizontal-input balance: a
/// straight-down swipe must not be read as a sideways move, and a deliberate
/// sideways move must still register once the finger has drifted downward.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a wobbly-but-vertical swipe hard-drops in the starting column', () async {
    const cellSize = 30.0;
    final engine = GameEngine(random: Random(1));
    engine.start();

    final startCol = engine.pieceController.piece!.anchorCol;
    final handler = GestureHandler(engine, () => cellSize);

    const pointer = 1;
    var pos = const Offset(200, 100);
    handler.onPointerDown(PointerDownEvent(pointer: pointer, position: pos));

    // A predominantly-downward flick with a consistent few-px sideways
    // drift each step — the kind of gentle curve a real thumb swipe makes.
    // Cumulatively this stays well within the "predominantly vertical"
    // bar (dx drifts ~3px per 12px of drop, ratio ~4:1 vs. the 1.5:1
    // threshold), so it must never register as a deliberate column move.
    // Real (small) delays between samples matter here: the hard-drop
    // trigger reads actual wall-clock velocity, and executing every event
    // back-to-back with no delay produces artificially explosive velocity
    // readings that fire the drop before the drift has even accumulated —
    // masking the bug this test exists to catch.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      pos = pos + const Offset(3, 12);
      handler.onPointerMove(PointerMoveEvent(pointer: pointer, position: pos));
    }

    // The wobble alone must not have shifted the piece before it dropped.
    expect(engine.pieceController.piece?.anchorCol, anyOf(startCol, isNull));

    engine.tick(1 / 60); // drains the hard-drop intent

    // Whatever locked into the grid must be in the swiped-on column, not a
    // column nudged sideways by wobble.
    final grid = engine.grid;
    var lockedCol = -1;
    for (var c = 0; c < grid.cols; c++) {
      for (var r = grid.minRow; r <= grid.maxRow; r++) {
        if (grid.at(r, c) != null) {
          lockedCol = c;
          break;
        }
      }
      if (lockedCol != -1) break;
    }
    expect(lockedCol, startCol);
  });

  // The other half of the same balance. Horizontal intent used to be gated
  // on `totalDown > 1.5 * totalDx.abs()`, both measured from the touch-down
  // point, so vertical drift latched sideways control off for the rest of
  // the gesture — and permanently once a soft drop was engaged.
  test('sideways moves still register after the finger has drifted down', () async {
    const cellSize = 30.0;
    final engine = GameEngine(random: Random(1));
    engine.start();

    final startCol = engine.pieceController.piece!.anchorCol;
    final handler = GestureHandler(engine, () => cellSize);

    const pointer = 1;
    var pos = const Offset(200, 100);
    handler.onPointerDown(PointerDownEvent(pointer: pointer, position: pos));

    // Straight down far enough to engage the soft drop (1.25 cells) but well
    // short of a hard drop (4.7 cells).
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      pos = pos + const Offset(0, 20);
      handler.onPointerMove(PointerMoveEvent(pointer: pointer, position: pos));
    }

    // Now steer sideways without lifting, past the 0.85-cell column
    // threshold.
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      pos = pos + const Offset(10, 0);
      handler.onPointerMove(PointerMoveEvent(pointer: pointer, position: pos));
    }

    engine.tick(1 / 60);
    expect(engine.pieceController.piece!.anchorCol, startCol + 1);
  });

  // The board spends close to a second in `resolving` on an 18-wide clear,
  // and every intent enqueued during it used to be discarded outright.
  test('a move made during a resolve lands on the next piece', () {
    final engine = GameEngine(random: Random(2));
    engine.start();
    final startCol = engine.pieceController.piece!.anchorCol;

    engine.phase = GamePhase.resolving;
    engine.enqueueIntent(GameIntentType.moveRight);

    engine.tick(1 / 60);
    expect(
      engine.pieceController.piece!.anchorCol,
      startCol,
      reason: 'nothing should move while the board is resolving',
    );

    engine.phase = GamePhase.playing;
    engine.tick(1 / 60);
    expect(engine.pieceController.piece!.anchorCol, startCol + 1);
  });

  test('a move older than the buffer window is dropped', () {
    final engine = GameEngine(random: Random(2));
    engine.start();
    final startCol = engine.pieceController.piece!.anchorCol;

    engine.phase = GamePhase.resolving;
    engine.enqueueIntent(GameIntentType.moveRight);
    engine.tick(GameEngine.inputBufferWindow.inMilliseconds / 1000 + 0.05);

    engine.phase = GamePhase.playing;
    engine.tick(1 / 60);
    expect(engine.pieceController.piece!.anchorCol, startCol);
  });
}
