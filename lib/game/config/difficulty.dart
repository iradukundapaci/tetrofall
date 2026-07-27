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
  static const checkpoints = <DifficultyCheckpoint>[
    DifficultyCheckpoint(
      elapsed: Duration.zero,
      dropInterval: Duration(milliseconds: 800),
      riseInterval: 14,
      fillRatio: 0.40,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(minutes: 1),
      dropInterval: Duration(milliseconds: 700),
      riseInterval: 11,
      fillRatio: 0.50,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(minutes: 2),
      dropInterval: Duration(milliseconds: 600),
      riseInterval: 9,
      fillRatio: 0.60,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(minutes: 3),
      dropInterval: Duration(milliseconds: 480),
      riseInterval: 7,
      fillRatio: 0.65,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(minutes: 5),
      dropInterval: Duration(milliseconds: 320),
      riseInterval: 5,
      fillRatio: 0.70,
    ),
    DifficultyCheckpoint(
      elapsed: Duration(minutes: 8),
      dropInterval: Duration(milliseconds: 200),
      riseInterval: 4,
      fillRatio: 0.75,
    ),
  ];

  /// Elapsed time after which special blocks begin appearing in rising rows.
  static const specialBlocksStart = Duration(minutes: 3);

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
