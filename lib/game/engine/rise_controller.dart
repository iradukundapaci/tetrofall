import 'dart:math';

import '../config/difficulty.dart';
import 'cell.dart';
import 'grid.dart';

/// The rise mechanic's timer and row generator (§1.4) — the core twist.
/// Pure Dart; the render layer reads [riseProgress] and [pendingRow] to
/// draw the continuous slide (§2.1). `commitRise()` itself only touches
/// the grid — carrying the active piece around a commit is the caller's
/// job (`GameEngine`), since that crosses into `PieceController`'s domain.
class RiseController {
  RiseController(this.grid, {Random? random}) : _random = random ?? Random() {
    pendingRow = _generateRow();
  }

  final Grid grid;
  final Random _random;

  /// Fraction of one cell height the board is offset upward, in [0, 1).
  double riseProgress = 0.0;

  /// Debug-only multiplier on the rise rate (Phase 4's rise-speed slider,
  /// 0.5x-10x) so the commit boundary can be inspected slowly or
  /// stress-tested quickly. Never touched by shipping gameplay code.
  double debugSpeedMultiplier = 1.0;

  /// Wall-clock seconds since this controller started ticking. Drives the
  /// difficulty-scaled fill ratio and gap placement style.
  double elapsed = 0.0;

  late List<Cell?> pendingRow;

  List<int> _previousGapCols = const [];

  /// Resets to a fresh run's starting state, regenerating the pending row.
  void reset() {
    riseProgress = 0.0;
    elapsed = 0.0;
    _previousGapCols = const [];
    pendingRow = _generateRow();
  }

  double get riseInterval => difficultyNow.riseInterval;

  double get fillRatio => difficultyNow.fillRatio;

  /// The §1.10 difficulty timeline at the current [elapsed] time. Also
  /// read by [GameEngine] each frame to drive [PieceController.dropInterval]
  /// — one difficulty clock shared by both systems (Phase 6).
  DifficultyCheckpoint get difficultyNow =>
      Difficulty.at(Duration(milliseconds: (elapsed * 1000).round()));

  /// Advances the timer by [dt] seconds. Returns true exactly on the frame
  /// a commit boundary is crossed — the caller must then check for top-out
  /// and call [commitRise] (handling the active-piece carry around it).
  bool tick(double dt) {
    elapsed += dt;
    riseProgress += (dt * debugSpeedMultiplier) / riseInterval;
    if (riseProgress >= 1.0) {
      riseProgress -= 1.0; // carry the remainder — never reset to 0 (§2.1)
      return true;
    }
    return false;
  }

  /// True if committing right now would push a settled block above row 0
  /// (top-out, §1.11). The caller must check this *before* calling
  /// [commitRise] and end the run instead of committing.
  bool wouldTopOut() => grid.rowHasAnyBlock(0);

  /// Shifts every settled row up by one and writes [pendingRow] into the
  /// floor, then generates the next pending row.
  void commitRise() {
    for (var r = 1; r <= grid.maxRow; r++) {
      for (var c = 0; c < grid.cols; c++) {
        grid.set(r - 1, c, grid.at(r, c));
      }
    }
    for (var c = 0; c < grid.cols; c++) {
      grid.set(grid.maxRow, c, pendingRow[c]);
    }
    pendingRow = _generateRow();
  }

  /// Special types eligible to spawn in a filled cell (§1.8). Wood is the
  /// "nothing special happened" case and Key never spawns on its own — it
  /// only appears as Locked's forced pairing below.
  static const _specialPool = [
    BlockType.stone,
    BlockType.ice,
    BlockType.bomb,
    BlockType.gold,
    BlockType.diamond,
    BlockType.treasure,
    BlockType.locked,
    BlockType.rainbow,
  ];

  /// Difficulty-scaled row generation (§1.4). Gaps never leave a full row
  /// (which would auto-clear): `cols * (1 - fillRatio)`, clamped to
  /// `[1, 4]`. Early on, gaps cluster into one easy well; later they
  /// scatter and avoid repeating the previous row's gap columns.
  ///
  /// After `Difficulty.specialBlocksStart`, each filled cell independently
  /// rolls a chance to become a special block (§1.8, Phase 7). A Locked
  /// roll additionally forces a paired Key onto another filled column of
  /// the same row — "keys spawn in the same row" — or backs off to plain
  /// wood if the row has no other filled column to hold one.
  List<Cell?> _generateRow() {
    final gapCount = (grid.cols * (1 - fillRatio)).round().clamp(1, 4);
    final gapCols = elapsed < 60
        ? _adjacentGaps(gapCount)
        : _scatteredGaps(gapCount);

    final filledCols = [
      for (var c = 0; c < grid.cols; c++)
        if (!gapCols.contains(c)) c,
    ];
    final types = {for (final c in filledCols) c: BlockType.wood};

    if (elapsed >= Difficulty.specialBlocksStart.inSeconds) {
      for (final c in filledCols) {
        if (_random.nextDouble() < Difficulty.specialBlockChance) {
          types[c] = _specialPool[_random.nextInt(_specialPool.length)];
        }
      }
      for (final lockedCol in filledCols.where(
        (c) => types[c] == BlockType.locked,
      )) {
        final candidates = filledCols
            .where((c) => c != lockedCol && types[c] != BlockType.key)
            .toList();
        if (candidates.isEmpty) {
          types[lockedCol] = BlockType.wood; // no room for its Key — skip it
        } else {
          types[candidates[_random.nextInt(candidates.length)]] =
              BlockType.key;
        }
      }
    }

    final row = List<Cell?>.generate(
      grid.cols,
      (c) => gapCols.contains(c) ? null : Cell(types[c]!),
    );
    _previousGapCols = gapCols;
    return row;
  }

  List<int> _adjacentGaps(int count) {
    final start = _random.nextInt(grid.cols - count + 1);
    return [for (var i = 0; i < count; i++) start + i];
  }

  List<int> _scatteredGaps(int count) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final cols = <int>{};
      while (cols.length < count) {
        cols.add(_random.nextInt(grid.cols));
      }
      final overlapsPrevious = cols.any(_previousGapCols.contains);
      if (!overlapsPrevious) return cols.toList();
    }
    final cols = <int>{};
    while (cols.length < count) {
      cols.add(_random.nextInt(grid.cols));
    }
    return cols.toList();
  }
}
