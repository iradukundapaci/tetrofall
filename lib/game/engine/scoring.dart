const _lineBaseScore = {1: 100, 2: 300, 3: 500, 4: 800};

/// Chain multiplier stops climbing here (5.0x).
const _maxChainMultiplierSteps = 8;

class Scoring {
  final _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  int score = 0;

  int totalBlocksDestroyed = 0;
  int maxChain = 0;

  /// Rows cleared this run, counting every chain link but not the continue
  /// sweep.
  int totalLines = 0;

  /// Clears of four or more rows at once.
  int tetrofalls = 0;

  int _lineScoreFor(int lines) {
    if (lines <= 0) return 0;
    final tabled = _lineBaseScore[lines];
    if (tabled != null) return tabled;
    return _lineBaseScore[4]! + (lines - 4) * 300;
  }

  void awardLineClear({
    required int lines,
    required int chainIndex,
    required double elapsedSeconds,
  }) {
    totalLines += lines;
    if (lines >= 4) tetrofalls++;
    final base = _lineScoreFor(lines);
    final cappedChain = chainIndex < _maxChainMultiplierSteps
        ? chainIndex
        : _maxChainMultiplierSteps;
    final chainMultiplier = 1.0 + 0.5 * cappedChain;
    final levelMultiplier = 1.0 + (elapsedSeconds / 60) * 0.1;
    score += (base * chainMultiplier * levelMultiplier).round();
    final chainLength = chainIndex + 1;
    if (chainLength > maxChain) maxChain = chainLength;
    _notify();
  }

  void addDestroyed(int count) => totalBlocksDestroyed += count;

  void reset() {
    score = 0;
    totalBlocksDestroyed = 0;
    maxChain = 0;
    totalLines = 0;
    tetrofalls = 0;
    _notify();
  }
}
