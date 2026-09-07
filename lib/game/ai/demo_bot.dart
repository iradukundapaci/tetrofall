import 'dart:math' as math;

import '../engine/game_engine.dart';
import '../engine/grid.dart';
import '../engine/tetromino.dart';

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
        final landingRow = _landingRow(grid, cells, col);
        if (landingRow == null) continue;
        final score = _score(grid, cells, landingRow, col, blunder: blunder);
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

  static bool _collidesAt(
    Grid grid,
    List<GridOffset> cells,
    int anchorRow,
    int anchorCol,
  ) {
    for (final c in cells) {
      final row = anchorRow + c.row;
      final col = anchorCol + c.col;
      if (!grid.inBounds(row, col)) return true;
      if (grid.isOccupied(row, col)) return true;
    }
    return false;
  }

  static int? _landingRow(Grid grid, List<GridOffset> cells, int anchorCol) {
    var row = grid.minRow;
    if (_collidesAt(grid, cells, row, anchorCol)) return null;
    while (!_collidesAt(grid, cells, row + 1, anchorCol)) {
      row++;
    }
    return row;
  }

  static double _score(
    Grid grid,
    List<GridOffset> cells,
    int landingRow,
    int anchorCol, {
    required bool blunder,
  }) {
    final rows = grid.maxRow + 1;
    final occ = List.generate(
      rows,
      (r) => List.generate(grid.cols, (c) => grid.isOccupied(r, c)),
    );
    for (final cell in cells) {
      final r = landingRow + cell.row;
      final c = anchorCol + cell.col;
      if (r >= 0 && r < rows) occ[r][c] = true;
    }

    var cleared = 0;
    for (final row in occ) {
      if (row.every((occupied) => occupied)) cleared++;
    }

    var holes = 0;
    var maxHeight = 0;
    for (var c = 0; c < grid.cols; c++) {
      var seenBlock = false;
      for (var r = 0; r < rows; r++) {
        if (occ[r][c]) {
          if (!seenBlock) maxHeight = math.max(maxHeight, rows - r);
          seenBlock = true;
        } else if (seenBlock) {
          holes++;
        }
      }
    }

    if (blunder) {
      // Refuse the clear, tolerate holes — but keep penalising height, which
      // is what makes the resulting board read as a solvable position the bot
      // is fumbling rather than as noise.
      return -cleared * 800.0 + holes * 25.0 - maxHeight * 2.0;
    }
    return cleared * 1000.0 - holes * 40.0 - maxHeight * 2.0;
  }
}
