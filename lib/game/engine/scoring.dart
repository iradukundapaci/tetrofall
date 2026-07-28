import '../config/motion.dart';

/// Base line-clear score before multipliers (§1.7). A single resolve step
/// clears every simultaneously-full row as one group, so this is keyed by
/// how many rows cleared together, not a per-row amount.
const _lineBaseScore = {1: 100, 2: 300, 3: 500, 4: 800};

/// Score, combo, and session-stat bookkeeping (§1.7). Pure Dart, driven
/// entirely by [GameEngine] — never touches the grid or render layer
/// itself.
class Scoring {
  int score = 0;

  /// Blocks destroyed so far in the resolve currently in progress — reset
  /// at the start of each lock-triggered resolve, accumulated across every
  /// chain link within it. Drives the combo banner thresholds (§1.7).
  int blocksDestroyedThisResolve = 0;

  /// Session totals, kept for the achievements system (Phase 11).
  int totalBlocksDestroyed = 0;
  int maxChain = 0;

  /// Currency earned from Diamond/Treasure specials (§1.8). A wallet, not
  /// a per-run stat — real persistence lands in Phase 11, so this simply
  /// isn't touched by [reset].
  int coins = 0;

  /// Set by the Score Multiplier booster while it's active (Phase 8);
  /// applies the ×2 [boosterMultiplier] from §1.7 until it wears off.
  bool scoreMultiplierActive = false;

  int _lineScoreFor(int lines) {
    if (lines <= 0) return 0;
    final tabled = _lineBaseScore[lines];
    if (tabled != null) return tabled;
    // Beyond the tabled 1-4 lines (an aggressive cascade could in theory
    // clear more at once): keep extrapolating at the last step's rate
    // rather than crashing on a lookup miss.
    return _lineBaseScore[4]! + (lines - 4) * 300;
  }

  /// Awards one clear-group's score (§1.7's multipliers, applied in
  /// order): base line score × chain × level × booster. [chainIndex] is
  /// this clear's link number within the current resolve (0 = the first,
  /// pre-cascade clear).
  void awardLineClear({
    required int lines,
    required int chainIndex,
    required double elapsedSeconds,
  }) {
    final base = _lineScoreFor(lines);
    final chainMultiplier = 1.0 + 0.5 * chainIndex;
    final levelMultiplier = 1.0 + (elapsedSeconds / 60) * 0.1;
    final boosterMultiplier = scoreMultiplierActive ? 2.0 : 1.0;
    score +=
        (base * chainMultiplier * levelMultiplier * boosterMultiplier)
            .round();
    final chainLength = chainIndex + 1;
    if (chainLength > maxChain) maxChain = chainLength;
  }

  /// Soft drop awards 1 pt/row, hard drop 2 pt/row (§1.3).
  void awardDrop({required int rows, required bool hard}) {
    score +=
        rows *
        (hard ? Motion.hardDropPointsPerRow : Motion.softDropPointsPerRow);
  }

  /// Gold's +250 payout (§1.8), scaled by however many cleared in one pass.
  void awardGold(int count) => score += 250 * count;

  void addCoins(int amount) => coins += amount;

  void addDestroyed(int count) {
    blocksDestroyedThisResolve += count;
    totalBlocksDestroyed += count;
  }

  /// Call once per lock, before the first clear-check of a new resolve.
  void startResolve() {
    blocksDestroyedThisResolve = 0;
  }

  void reset() {
    score = 0;
    blocksDestroyedThisResolve = 0;
    totalBlocksDestroyed = 0;
    maxChain = 0;
    scoreMultiplierActive = false;
  }
}
