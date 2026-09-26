import 'dart:math' as math;

/// What one finished run says about the player.
class RunOutcome {
  const RunOutcome({
    required this.seconds,
    required this.lines,
    required this.maxChain,
    required this.placementQuality,
  });

  /// How long the run lasted, on the player's own clock.
  final double seconds;
  final int lines;
  final int maxChain;

  /// Mean placement quality against the bot's best, 0–1, or null when nothing
  /// was measured.
  final double? placementQuality;
}

/// The long-run estimate of how well someone plays, 0 (new) to 1 (expert),
/// updated at the end of each run and persisted between sessions.
abstract final class SkillModel {
  /// New players start low so they get the most help early.
  static const initial = 0.2;

  /// Runs shorter than this say nothing about skill (an accidental quit).
  static const minRunSeconds = 15.0;

  static const _learningRate = 0.3;

  static double updated(double previous, RunOutcome run) {
    if (run.seconds < minRunSeconds) return previous;

    final time = (run.seconds / 480).clamp(0.0, 1.0);
    final linesPerMinute = run.lines / (run.seconds / 60);
    final lines = (linesPerMinute / 10).clamp(0.0, 1.0);
    final chain = (run.maxChain / 5).clamp(0.0, 1.0);

    // Placement quality is the most accurate signal, so it weighs most;
    // without it the rest is renormalised.
    final quality = run.placementQuality;
    final estimate = quality == null
        ? (0.4 * time + 0.35 * lines + 0.25 * chain)
        : (0.4 * quality + 0.25 * time + 0.2 * lines + 0.15 * chain);

    final next = previous + _learningRate * (estimate - previous);
    return math.min(1.0, math.max(0.0, next));
  }

  /// `low` / `mid` / `high`, for analytics.
  static String bucketOf(double skill) {
    if (skill < 0.35) return 'low';
    if (skill < 0.7) return 'mid';
    return 'high';
  }
}
