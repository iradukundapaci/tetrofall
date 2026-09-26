/// What one finished endless run amounted to, gathered once at game over and
/// shared by everything that wants to know: the skill model, the rating
/// prompt, analytics and the feedback form.
class EndlessRunSummary {
  const EndlessRunSummary({
    required this.score,
    required this.bestBefore,
    required this.durationSeconds,
    required this.lines,
    required this.maxChain,
    required this.tetrofalls,
    required this.deathReason,
    required this.runIndex,
    required this.continuesUsed,
    this.directorOn = false,
    this.skillBucket = 'low',
    this.rescues = 0,
    this.rescuesSurvived = 0,
    this.comebacks = 0,
    this.giftRows = 0,
    this.bagBiasPicks = 0,
    this.placementQuality,
  });

  final int score;

  /// The player's best *before* this run. `best_score` in storage already
  /// holds this run's score by the time game over is shown.
  final int bestBefore;
  final double durationSeconds;
  final int lines;
  final int maxChain;

  /// Clears of four or more rows at once.
  final int tetrofalls;
  final String deathReason;

  /// Zero-based: how many endless runs came before this one.
  final int runIndex;
  final int continuesUsed;

  final bool directorOn;
  final String skillBucket;
  final int rescues;
  final int rescuesSurvived;
  final int comebacks;
  final int giftRows;
  final int bagBiasPicks;
  final double? placementQuality;

  bool get isNewBest => score > bestBefore;

  /// Points short of the previous best, or 0 when it was beaten.
  int get pointsFromBest => isNewBest ? 0 : bestBefore - score;
}

/// The most recent finished run of this session, for the feedback form's
/// "include my last run".
abstract final class LastRun {
  static EndlessRunSummary? summary;
}
