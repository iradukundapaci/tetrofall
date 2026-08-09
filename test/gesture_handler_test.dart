import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/engine/game_engine.dart';
import 'package:tetrofall/game/engine/tetromino.dart';
import 'package:tetrofall/game/input/gesture_handler.dart';

/// Regression tests for the two ends of the horizontal-input balance: a
/// straight-down swipe must not be read as a sideways move, and a deliberate
/// sideways move must still register once the finger has drifted downward.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a wobbly-but-vertical swipe hard-drops in the starting column',
    () async {
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
        handler.onPointerMove(
          PointerMoveEvent(pointer: pointer, position: pos),
        );
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
    },
  );

  // The other half of the same balance. Horizontal intent used to be gated
  // on `totalDown > 1.5 * totalDx.abs()`, both measured from the touch-down
  // point, so vertical drift latched sideways control off for the rest of
  // the gesture — and permanently once a soft drop was engaged.
  test(
    'sideways moves still register after the finger has drifted down',
    () async {
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
        handler.onPointerMove(
          PointerMoveEvent(pointer: pointer, position: pos),
        );
      }

      // Now steer sideways without lifting, past the 0.85-cell column
      // threshold.
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        pos = pos + const Offset(10, 0);
        handler.onPointerMove(
          PointerMoveEvent(pointer: pointer, position: pos),
        );
      }

      engine.tick(1 / 60);
      expect(engine.pieceController.piece!.anchorCol, startCol + 1);
    },
  );

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

  // Regression test for the "piece jitters — jumps and snaps back" report.
  // Real touch sensors don't jitter independently sample-to-sample: a couple
  // of correlated noisy samples during an otherwise straight vertical drag
  // can locally look sideways even though the drag as a whole is vertical.
  // Judging the axis on a single raw sample (an earlier attempt at fixing
  // "hard to move sideways") let a short noisy run accumulate a full column
  // shift, with the very next corrective run crossing back the other way —
  // visible as the piece jumping then snapping back.
  test('a brief sideways wobble mid-drag does not fire a move', () async {
    const cellSize = 30.0;
    final engine = GameEngine(random: Random(3));
    engine.start();

    final startCol = engine.pieceController.piece!.anchorCol;
    final handler = GestureHandler(engine, () => cellSize);

    const pointer = 1;
    var pos = const Offset(200, 100);
    handler.onPointerDown(PointerDownEvent(pointer: pointer, position: pos));

    Future<void> step(double dx, double dy) async {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      pos = pos + Offset(dx, dy);
      handler.onPointerMove(PointerMoveEvent(pointer: pointer, position: pos));
    }

    // A steady, mostly-vertical drag (ratio 0.2, well under any
    // threshold) with a brief two-sample sideways wobble (ratio 1.0)
    // dropped in the middle, then the drag returns to steady.
    for (var i = 0; i < 5; i++) {
      await step(2, 10);
    }
    await step(9, 9);
    await step(9, 9);
    for (var i = 0; i < 6; i++) {
      await step(2, 10);
    }

    // The wobble must never have accumulated into an actual column
    // shift — the piece should still be exactly where it started.
    expect(engine.pieceController.piece?.anchorCol, startCol);
  });

  // "When speeding the drop make sure it can not fast drop." Holding a soft
  // drop means keeping the finger down and dragging, and distance alone used
  // to decide the hard drop — so steering a piece far enough down the board
  // slammed it home unasked. Speed at the moment the soft drop engages is
  // what now separates a flick from a drag.
  test('a slow drag past the hard-drop distance soft drops instead', () async {
    const cellSize = 30.0;
    final engine = GameEngine(random: Random(1));
    engine.start();

    final handler = GestureHandler(engine, () => cellSize);

    const pointer = 1;
    var pos = const Offset(200, 100);
    handler.onPointerDown(PointerDownEvent(pointer: pointer, position: pos));

    // 300px straight down — more than twice the 141px hard-drop distance —
    // but at ~190px/s, well under the 300px/s flick speed for this cell.
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      pos = pos + const Offset(0, 6);
      handler.onPointerMove(PointerMoveEvent(pointer: pointer, position: pos));
    }

    engine.tick(1 / 60);

    expect(
      engine.pieceController.softDropActive,
      isTrue,
      reason: 'a slow downward drag is a soft drop',
    );
    expect(
      engine.grid.rowHasAnyBlock(engine.grid.maxRow),
      isFalse,
      reason: 'nothing should have been slammed to the floor',
    );
    expect(engine.pieceController.piece, isNotNull);
  });

  // "For some reason when I do hard drop the piece can rotate." The hard-drop
  // path cleared the tracked pointer instead of marking the gesture spent,
  // which re-armed the handler while the finger was still down: the next
  // touch it accepted could still be scored as a tap.
  test('a hard drop cannot also rotate the piece', () async {
    const cellSize = 30.0;
    final engine = GameEngine(random: Random(1));
    engine.start();

    final handler = GestureHandler(engine, () => cellSize);

    var pos = const Offset(200, 100);
    handler.onPointerDown(PointerDownEvent(pointer: 1, position: pos));

    // A fast, straight flick: past the 141px hard-drop distance at roughly
    // 1250px/s, four times the flick speed.
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      pos = pos + const Offset(0, 20);
      handler.onPointerMove(PointerMoveEvent(pointer: 1, position: pos));
    }

    // The drop resolves and the next piece spawns while the flicking finger
    // is still on its way off the glass — which is all the time a real
    // finger takes to lift, and why a leaked tap lands on a live piece.
    engine.tick(1 / 60);

    // A second finger touching down and lifting before the flicking one has
    // left the glass must not be read as a tap.
    handler.onPointerDown(PointerDownEvent(pointer: 2, position: pos));
    handler.onPointerUp(PointerUpEvent(pointer: 2, position: pos));
    handler.onPointerUp(PointerUpEvent(pointer: 1, position: pos));

    engine.tick(1 / 60); // any leaked rotation would land on the new piece

    expect(
      engine.pieceController.piece!.rotation,
      RotationState.spawn,
      reason: 'the hard drop spent the gesture; no rotation may follow it',
    );
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
