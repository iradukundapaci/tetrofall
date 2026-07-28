import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/engine/game_engine.dart';
import 'package:tetrofall/game/input/gesture_handler.dart';

/// Regression test for the "hard drop lands in the wrong column" report:
/// a mostly-straight-down swipe with a little natural sideways wobble used
/// to be able to fire a horizontal move before the hard drop triggered,
/// shifting the piece off the column the player actually swiped down on.
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
}
