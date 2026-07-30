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
  /// [initialElapsed] seeds the difficulty clock past its default zero —
  /// used by the adaptive start-speed setting to drop an experienced player
  /// further into the timeline. Since [difficultyNow], the grace-period
  /// check in [tick], and the easy-well cutoff in [_generateRow] all key off
  /// [elapsed], seeding it here naturally skips the grace period and eases
  /// straight into scattered gaps for a run that starts past those
  /// thresholds — no other logic needs to know about the adaptive start.
  void reset({Duration initialElapsed = Duration.zero}) {
    riseProgress = 0.0;
    elapsed = initialElapsed.inMicroseconds / 1e6;
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
  ///
  /// During [Difficulty.riseGracePeriod], [elapsed] still advances (so the
  /// difficulty checkpoint clock keeps moving) but [riseProgress] doesn't —
  /// a beginner gets a few seconds with gravity but no rising floor (§2).
  bool tick(double dt) {
    elapsed += dt;
    if (elapsed < Difficulty.riseGracePeriod.inMicroseconds / 1e6) return false;
    riseProgress += (dt * debugSpeedMultiplier) / riseInterval;
    if (riseProgress >= 1.0) {
      riseProgress -= 1.0; // carry the remainder — never reset to 0 (§2.1)
      return true;
    }
    return false;
  }

  /// Advances only the wall-clock [elapsed] timer, without touching
  /// [riseProgress] — used while RESOLVING so the difficulty timeline
  /// keeps moving through long cascades (§6.4) without the rise itself
  /// advancing mid-resolve.
  void tickElapsedOnly(double dt) {
    elapsed += dt;
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

  /// Difficulty-scaled row generation (§1.4). Every filled cell is plain
  /// wood — no special blocks. Gaps never leave a full row (which would
  /// auto-clear): `cols * (1 - fillRatio)`, clamped proportionally to the
  /// board width (2/5 of the columns at most, at least 1). Early on, gaps
  /// cluster into one easy well; later they scatter and avoid repeating
  /// the previous row's gap columns.
  List<Cell?> _generateRow() {
    final maxGaps = (grid.cols * 0.4).round().clamp(1, grid.cols - 1);
    final gapCount = (grid.cols * (1 - fillRatio)).round().clamp(1, maxGaps);
    final gapCols = elapsed < 60
        ? _adjacentGaps(gapCount)
        : _scatteredGaps(gapCount);

    final row = List<Cell?>.generate(
      grid.cols,
      (c) => gapCols.contains(c) ? null : Cell(BlockType.wood),
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
