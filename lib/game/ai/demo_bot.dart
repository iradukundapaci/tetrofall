import 'dart:math' as math;

import '../engine/game_engine.dart';
import '../engine/grid.dart';
import '../engine/tetromino.dart';
import 'placement_scorer.dart';

/// How a [DemoBot] picks where to put the piece it's holding.
enum BotPolicy {
  /// Hunts line clears. Rows cleared dominate, then holes created, then
  /// resulting height as tie-breakers, so it doesn't bury gaps chasing a
  /// clear two pieces away. This is what plays behind the main menu.
  skilled,

  /// Deliberately bad, and *legibly* bad: the clear term is negated, so it
  /// walks up to a completed row and refuses to finish it. Height is still
  /// penalised, which is what keeps the board filling in flat and readable
  /// instead of towering into a random mess — the viewer can see the line
  /// that should have been cleared. Used for the store's blunder reels.
  blunder,

  /// Replays an explicit list of placements, then falls back to [skilled]
  /// once the script runs out. Pair it with [GameEngine.queuePieces] so the
  /// piece and the placement stay in lockstep.
  scripted,
}

/// One chosen placement: the rotation to arrive in, and the anchor column.
typedef BotPlacement = (RotationState rotation, int column);

/// The self-playing search that drives the menu's attract mode and the
/// store-capture demo reels.
///
/// Brute-force over every (rotation, column) for the current piece — no
/// multi-piece lookahead, just whatever gets this one down best under
/// [policy]. Deliberately not an engine concern: it only ever reads [Grid]
/// and pushes intents, so it can drive any [GameEngine] without being one.
class DemoBot {
  DemoBot({
    this.policy = BotPolicy.skilled,
    math.Random? random,
    List<BotPlacement> script = const [],
    this.blunderRate = 1.0,
  }) : _random = random ?? math.Random(),
       _script = List.of(script);

  final BotPolicy policy;
  final math.Random _random;
  final List<BotPlacement> _script;

  /// Probability, per piece, that a [BotPolicy.blunder] bot actually throws
  /// the placement away. Below 1.0 it plays well most of the time and then
  /// misplays — which reads as a human mistake rather than as a broken bot.
  final double blunderRate;

  RotationState _targetRotation = RotationState.spawn;
  int _targetCol = 0;

  /// Placements the script still owes, for callers that want to know whether
  /// the set-piece beat has already played.
  int get scriptRemaining => _script.length;

  /// Call when a piece spawns. Picks where this one is going.
  void onPieceSpawned(Grid grid, TetrominoType type) {
    final placement = choose(grid, type);
    _targetRotation = placement.$1;
    _targetCol = placement.$2;
  }

  /// Steer the live piece toward the placement chosen at spawn, then drop it.
  /// The placement search is what does the work; this only drives there.
  void tick(GameEngine engine) {
    if (engine.phase != GamePhase.playing) return;
    final piece = engine.pieceController.piece;
    if (piece == null) return;
    if (piece.rotation != _targetRotation) {
      engine.enqueueIntent(GameIntentType.rotateCW);
    } else if (piece.anchorCol < _targetCol) {
      engine.enqueueIntent(GameIntentType.moveRight);
    } else if (piece.anchorCol > _targetCol) {
      engine.enqueueIntent(GameIntentType.moveLeft);
    } else {
      engine.enqueueIntent(GameIntentType.hardDrop);
    }
  }

  /// The search itself. Public so a caller can ask "where would a good player
  /// put this?" without driving anything — the near-miss reel uses that to
  /// aim one column off the placement that would have paid.
  BotPlacement choose(Grid grid, TetrominoType type) {
    if (policy == BotPolicy.scripted && _script.isNotEmpty) {
      return _script.removeAt(0);
    }
    final blunder =
        policy == BotPolicy.blunder && _random.nextDouble() < blunderRate;

    RotationState? bestRotation;
    int? bestCol;
    var bestScore = double.negativeInfinity;
    var ties = 0;

    for (final rotation in RotationState.values) {
      final cells = Tetromino.cellsFor(type, rotation);
      final cellCols = cells.map((c) => c.col);
      final minCol = cellCols.reduce(math.min);
      final maxCol = cellCols.reduce(math.max);

      for (var col = -minCol; col <= grid.cols - 1 - maxCol; col++) {
        final landingRow = PlacementScorer.landingRow(grid, cells, col);
        if (landingRow == null) continue;
        final score = PlacementScorer.score(
          grid,
          cells,
          landingRow,
          col,
          blunder: blunder,
        );
        if (score > bestScore) {
          bestScore = score;
          bestRotation = rotation;
          bestCol = col;
          ties = 1;
        } else if (score == bestScore) {
          // Reservoir sampling: ties are common (every rotation of an O
          // piece scores identically), so without this the demo would
          // always resolve them to the same rotation/column and look
          // robotic.
          ties++;
          if (_random.nextInt(ties) == 0) {
            bestRotation = rotation;
            bestCol = col;
          }
        }
      }
    }

    return (
      bestRotation ?? RotationState.spawn,
      bestCol ?? Tetromino.spawnColumn[type]!,
    );
  }
}
