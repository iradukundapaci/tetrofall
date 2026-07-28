import 'events.dart';
import 'grid.dart';

/// The four HUD boosters plus the two reserved (non-HUD) ones (§1.9).
/// Only the first four go through the arm/target/apply flow below —
/// Time Freeze and Score Multiplier are instant-use timed effects instead
/// (see [useTimeFreeze]/[useScoreMultiplier]), matching their blank
/// "Input" column in §1.9's table.
enum BoosterType { hammer, bomb, drill, lightning, timeFreeze, scoreMultiplier }

const _armableBoosters = {
  BoosterType.hammer,
  BoosterType.bomb,
  BoosterType.drill,
  BoosterType.lightning,
};

const _timeFreezeSeconds = 8.0;
const _scoreMultiplierSeconds = 30.0;

/// Arm -> target -> apply -> (caller runs) cascade -> clear-check (§1.9).
/// This class owns charges and the destruction geometry; [GameEngine]
/// owns arming's game-phase gating and drives the resulting cascade
/// through the same shatter/cascade pipeline a line clear uses, so
/// booster removals can start chains exactly like the rule requires.
class BoosterEngine {
  final Map<BoosterType, int> charges = {
    for (final t in BoosterType.values) t: 0,
  };

  /// The booster currently armed and awaiting a target tap, if any.
  BoosterType? armed;

  double _timeFreezeRemaining = 0;
  double _scoreMultiplierRemaining = 0;

  bool get timeFreezeActive => _timeFreezeRemaining > 0;
  bool get scoreMultiplierActive => _scoreMultiplierRemaining > 0;

  void addCharge(BoosterType type, [int count = 1]) {
    charges[type] = (charges[type] ?? 0) + count;
  }

  /// Phase 8's debug helper: refill every booster to [count] charges.
  void debugGiveCharges(int count) {
    for (final t in BoosterType.values) {
      charges[t] = count;
    }
  }

  /// Arms [type] if it's one of the four tap-to-target boosters and a
  /// charge is available. Returns false (and arms nothing) otherwise.
  bool arm(BoosterType type) {
    if (!_armableBoosters.contains(type)) return false;
    if ((charges[type] ?? 0) <= 0) return false;
    armed = type;
    return true;
  }

  void disarm() => armed = null;

  void useTimeFreeze() {
    if ((charges[BoosterType.timeFreeze] ?? 0) <= 0) return;
    charges[BoosterType.timeFreeze] = charges[BoosterType.timeFreeze]! - 1;
    _timeFreezeRemaining = _timeFreezeSeconds;
  }

  void useScoreMultiplier() {
    if ((charges[BoosterType.scoreMultiplier] ?? 0) <= 0) return;
    charges[BoosterType.scoreMultiplier] =
        charges[BoosterType.scoreMultiplier]! - 1;
    _scoreMultiplierRemaining = _scoreMultiplierSeconds;
  }

  /// Advances the two timed effects. Called once per frame while playing.
  void tickTimedEffects(double dt) {
    if (_timeFreezeRemaining > 0) {
      _timeFreezeRemaining = (_timeFreezeRemaining - dt).clamp(
        0,
        double.infinity,
      );
    }
    if (_scoreMultiplierRemaining > 0) {
      _scoreMultiplierRemaining = (_scoreMultiplierRemaining - dt).clamp(
        0,
        double.infinity,
      );
    }
  }

  /// The cells a commit at ([row], [col]) would affect — shared by the
  /// real [commit] and the render layer's pre-commit highlight, so the
  /// preview can never lie about what's about to be destroyed.
  static List<(int, int)> targetCells(
    BoosterType type,
    int row,
    int col,
    Grid grid,
  ) {
    switch (type) {
      case BoosterType.hammer:
        return grid.inBounds(row, col) ? [(row, col)] : const [];
      case BoosterType.bomb:
        return [
          for (var dr = -1; dr <= 1; dr++)
            for (var dc = -1; dc <= 1; dc++)
              if (grid.inBounds(row + dr, col + dc)) (row + dr, col + dc),
        ];
      case BoosterType.drill:
        if (col < 0 || col >= grid.cols) return const [];
        return [for (var r = 0; r <= grid.maxRow; r++) (r, col)];
      case BoosterType.lightning:
        if (row < 0 || row > grid.maxRow) return const [];
        return [for (var c = 0; c < grid.cols; c++) (row, c)];
      case BoosterType.timeFreeze:
      case BoosterType.scoreMultiplier:
        return const []; // not tap-to-target
    }
  }

  /// Commits the armed booster at ([row], [col]): destroys every targeted
  /// cell unconditionally — bypassing ice's hp, Locked's key requirement,
  /// even Stone, since boosters are the designated tool for all of them
  /// (§1.8) — and consumes a charge only if something was actually
  /// destroyed. Always disarms. Returns what was destroyed, for the
  /// caller to feed into the normal shatter/cascade pipeline.
  List<ClearedCell> commit(int row, int col, Grid grid) {
    final type = armed;
    armed = null;
    if (type == null) return const [];
    if (!grid.inBounds(row, col) || row < grid.minRow) return const [];

    final removed = <ClearedCell>[];
    for (final (r, c) in targetCells(type, row, col, grid)) {
      final cell = grid.at(r, c);
      if (cell == null) continue;
      removed.add(ClearedCell(row: r, col: c, type: cell.type));
      grid.set(r, c, null);
    }
    if (removed.isNotEmpty) {
      charges[type] = (charges[type] ?? 1) - 1;
    }
    return removed;
  }
}
