/// What one finished run amounted to, gathered at game over for the rating
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

  /// The best before this run; storage already holds this run's score.
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
}

/// The last finished run this session, for the feedback form.
abstract final class LastRun {
  static EndlessRunSummary? summary;
}
