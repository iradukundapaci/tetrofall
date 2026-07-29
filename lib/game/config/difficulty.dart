/// The §1.10 difficulty timeline. Values are interpolated linearly between
/// checkpoints — never stepped.
class DifficultyCheckpoint {
  const DifficultyCheckpoint({
    required this.elapsed,
    required this.dropInterval,
    required this.riseInterval,
    required this.fillRatio,
  });

  /// Time since run start.
  final Duration elapsed;

  /// Gravity: piece descends 1 row every [dropInterval].
  final Duration dropInterval;

  /// Seconds for one full pending row to arrive.
  final double riseInterval;

  /// Fraction of a generated row's cells that are filled.
  final double fillRatio;
}

/// The §1.10 timeline and the interpolation over it. Pure Dart, no Flame —
/// lives in the engine layer conceptually even though it's a config file.
abstract final class Difficulty {
  /// Beginner-friendly ramp (see improvement.md §2): the original table
  /// hit 700ms/11s by the 1-minute mark, which read as brutal to new
  /// players. This starts noticeably slower and stretches the early
  /// checkpoints out further before catching back up to the same late-game
  /// pace.
  static const checkpoints = <DifficultyCheckpoint>[
    DifficultyCheckpoint(
      elapsed: Duration.zero,
      dropInterval: Duration(milliseconds: 1000),
      riseInterval: 22,
      fillRatio: 0.35,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(seconds: 90),
      dropInterval: Duration(milliseconds: 850),
      riseInterval: 16,
      fillRatio: 0.45,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(minutes: 3),
      dropInterval: Duration(milliseconds: 700),
      riseInterval: 12,
      fillRatio: 0.55,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(minutes: 5),
      dropInterval: Duration(milliseconds: 550),
      riseInterval: 9,
      fillRatio: 0.62,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(minutes: 8),
      dropInterval: Duration(milliseconds: 400),
      riseInterval: 6,
      fillRatio: 0.70,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(minutes: 12),
      dropInterval: Duration(milliseconds: 250),
      riseInterval: 4.5,
      fillRatio: 0.75,
    ),
  ];

  /// No rise pressure at all for the first stretch of a run — gravity
  /// still runs, but the rising floor doesn't start climbing until a
  /// beginner has had a moment to get their bearings (§2).
  static const riseGracePeriod = Duration(seconds: 12);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static DifficultyCheckpoint at(Duration elapsed) {
    if (elapsed <= checkpoints.first.elapsed) return checkpoints.first;
    if (elapsed >= checkpoints.last.elapsed) return checkpoints.last;

    for (var i = 0; i < checkpoints.length - 1; i++) {
      final a = checkpoints[i];
      final b = checkpoints[i + 1];
      if (elapsed >= a.elapsed && elapsed <= b.elapsed) {
        final span = (b.elapsed - a.elapsed).inMicroseconds;
        final t = span == 0
            ? 0.0
            : (elapsed - a.elapsed).inMicroseconds / span;
        return DifficultyCheckpoint(
          elapsed: elapsed,
          dropInterval: Duration(
            microseconds: _lerp(
              a.dropInterval.inMicroseconds.toDouble(),
              b.dropInterval.inMicroseconds.toDouble(),
              t,
            ).round(),
          ),
          riseInterval: _lerp(a.riseInterval, b.riseInterval, t),
          fillRatio: _lerp(a.fillRatio, b.fillRatio, t),
        );
      }
    }
    return checkpoints.last;
  }
}
