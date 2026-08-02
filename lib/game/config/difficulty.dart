import 'dart:math';

class DifficultyCheckpoint {
  const DifficultyCheckpoint({
    required this.elapsed,
    required this.dropInterval,
    required this.riseInterval,
    required this.fillRatio,
  });

  final Duration elapsed;

  final Duration dropInterval;

  final double riseInterval;

  final double fillRatio;
}

abstract final class Difficulty {
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

  static const riseGracePeriod = Duration(seconds: 12);

  static const _adaptiveStartCeiling = Duration(minutes: 3);
  static const _adaptiveStartFullScore = 8000;

  static Duration adaptiveStartElapsed(int bestScore) {
    if (bestScore <= 0) return Duration.zero;
    final t = sqrt((bestScore / _adaptiveStartFullScore).clamp(0.0, 1.0));
    return _adaptiveStartCeiling * t;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static DifficultyCheckpoint at(Duration elapsed) {
    if (elapsed <= checkpoints.first.elapsed) return checkpoints.first;
    if (elapsed >= checkpoints.last.elapsed) return checkpoints.last;

    for (var i = 0; i < checkpoints.length - 1; i++) {
      final a = checkpoints[i];
      final b = checkpoints[i + 1];
      if (elapsed >= a.elapsed && elapsed <= b.elapsed) {
        final span = (b.elapsed - a.elapsed).inMicroseconds;
        final t = span == 0 ? 0.0 : (elapsed - a.elapsed).inMicroseconds / span;
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
