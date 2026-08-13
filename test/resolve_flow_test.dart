import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/config/motion.dart';
import 'package:tetrofall/game/engine/cell.dart';
import 'package:tetrofall/game/engine/events.dart';
import 'package:tetrofall/game/engine/game_engine.dart';
import 'package:tetrofall/game/engine/grid.dart';
import 'package:tetrofall/game/engine/tetromino.dart';

/// The ripple resolve: gravity releases one row at a time, a row that merges
/// into a full row clears mid-cascade, and the whole thing keeps pace with the
/// difficulty curve.
void main() {
  const step = 1 / 60;
  const holeCol = 5;

  /// A board rigged so a single O piece dropped into columns 0-1 starts a
  /// two-link chain:
  ///
  /// - the bottom row completes on the lock and clears;
  /// - the row above it is released, lands, and is one cell short;
  /// - the lone block a row higher — frozen until its turn — then drops in
  ///   and completes it, clearing again.
  ///
  /// If gravity collapsed the whole stack at once, both rows would land
  /// together and this would be one clear, not two.
  Grid riggedBoard() {
    final grid = Grid();
    final m = grid.maxRow;
    for (var c = 2; c < grid.cols; c++) {
      grid.set(m, c, Cell(BlockType.wood));
      if (c != holeCol) grid.set(m - 1, c, Cell(BlockType.wood));
    }
    grid.set(m - 2, holeCol, Cell(BlockType.wood));
    return grid;
  }

  /// Drops an O into the two empty columns on the left, entering the resolve
  /// through the real lock path.
  void dropIntoCorner(GameEngine engine) {
    engine.phase = GamePhase.playing;
    engine.pieceController.spawn(TetrominoType.O);
    for (var i = 0; i < engine.grid.cols; i++) {
      engine.enqueueIntent(GameIntentType.moveLeft);
    }
    engine.tick(step);
    engine.enqueueIntent(GameIntentType.hardDrop);
    engine.tick(step);
  }

  /// Runs the resolve to completion, recording what came out of it.
  ({int ticks, List<RowsClearedEvent> clears, bool clearedMidFlight}) runResolve(
    GameEngine engine,
  ) {
    final clears = <RowsClearedEvent>[];
    var airborne = 0.0;
    var clearedMidFlight = false;

    engine.addEventListener((event) {
      if (event is BlocksFellEvent) {
        for (final f in event.falls) {
          airborne = max(airborne, f.durationSeconds);
        }
      } else if (event is RowsClearedEvent) {
        if (airborne > 1e-9) clearedMidFlight = true;
        clears.add(event);
      }
    });

    dropIntoCorner(engine);

    var ticks = 0;
    while (engine.phase == GamePhase.resolving && ticks < 6000) {
      airborne = max(0, airborne - step);
      engine.tick(step);
      ticks++;
    }
    return (ticks: ticks, clears: clears, clearedMidFlight: clearedMidFlight);
  }

  test('a merge during the ripple clears as its own chain link', () {
    final engine = GameEngine(grid: riggedBoard(), random: Random(1));
    final result = runResolve(engine);

    expect(
      result.clears.length,
      2,
      reason: 'the lock clear, then the clear the released row merged into',
    );
    expect(engine.chainIndex, 2, reason: 'one chain link per clear');
    expect(engine.phase, GamePhase.spawning);
  });

  test('nothing clears while blocks are still in the air', () {
    final engine = GameEngine(grid: riggedBoard(), random: Random(1));

    // Shattering a cell the fall animator is mid-way through drawing would
    // tear the frame, so the engine waits out every flight before clearing.
    expect(runResolve(engine).clearedMidFlight, isFalse);
  });

  test('the resolve speeds up with the difficulty curve', () {
    final early = GameEngine(grid: riggedBoard(), random: Random(1));
    final earlyTicks = runResolve(early).ticks;

    final late = GameEngine(grid: riggedBoard(), random: Random(1))
      ..riseController.elapsed = const Duration(minutes: 12).inSeconds
          .toDouble();
    final lateTicks = runResolve(late).ticks;

    expect(late.chainIndex, 2, reason: 'same chain, just faster');
    expect(
      lateTicks,
      lessThan(earlyTicks),
      reason: 'clearing must not drag while the game is running fast',
    );
    expect(
      earlyTicks * step,
      lessThan(Motion.resolveHardCap.inMilliseconds / 1000),
      reason: 'the ordinary case stays well inside the hard cap',
    );
  });

  test('a full-height cascade still finishes inside the hard cap', () {
    // Every row occupied and the bottom one completed by the lock: the worst
    // case the ripple can be handed.
    final grid = Grid();
    for (var r = 0; r <= grid.maxRow; r++) {
      for (var c = 2; c < grid.cols; c++) {
        if (r.isEven && c == holeCol) continue;
        grid.set(r, c, Cell(BlockType.wood));
      }
    }
    final engine = GameEngine(grid: grid, random: Random(1));
    final result = runResolve(engine);

    expect(engine.phase, GamePhase.spawning);
    // Past the cap the engine stops starting new work and collapses the rest;
    // only the final settle plays out beyond it.
    expect(
      result.ticks * step,
      lessThan(
        Motion.resolveHardCap.inMilliseconds / 1000 +
            Motion.shatterSequenceSeconds(grid.cols),
      ),
      reason: 'the budget and hard cap keep even a full board bounded',
    );
  });
}
