import 'dart:math' as math;

import '../engine/game_engine.dart';
import '../engine/grid.dart';
import '../engine/tetromino.dart';
import 'placement_scorer.dart';

enum BotPolicy {
  /// Hunts line clears; this plays behind the main menu.
  skilled,

  /// Legibly bad: refuses to finish a completed row while still penalising
  /// height, so the board stays flat and readable. Used for store reels.
  blunder,

  /// Replays an explicit list of placements, then falls back to [skilled].
  /// Pair with [GameEngine.queuePieces] to keep piece and placement in step.
  scripted,
}

/// One chosen placement: the rotation to arrive in, and the anchor column.
typedef BotPlacement = (RotationState rotation, int column);

/// The self-playing search behind the menu's attract mode and the store
/// capture reels: brute force over every (rotation, column) for the current
/// piece, with no lookahead. It only reads [Grid] and pushes intents.
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

  /// Probability, per piece, that a [BotPolicy.blunder] bot throws the
  /// placement away.
  final double blunderRate;

  RotationState _targetRotation = RotationState.spawn;
  int _targetCol = 0;

  /// Call when a piece spawns; picks where it is going.
  void onPieceSpawned(Grid grid, TetrominoType type) {
    final placement = choose(grid, type);
    _targetRotation = placement.$1;
    _targetCol = placement.$2;
  }

  /// Steers the live piece toward the placement chosen at spawn, then drops it.
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

  /// The search itself, public so a caller can ask where a good player would
  /// put a piece without driving anything.
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
          // Reservoir sampling over ties, so the demo doesn't look robotic.
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
