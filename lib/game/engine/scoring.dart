const _lineBaseScore = {1: 100, 2: 300, 3: 500, 4: 800};

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

  int blocksDestroyedThisResolve = 0;

  int totalBlocksDestroyed = 0;
  int maxChain = 0;

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
    final base = _lineScoreFor(lines);
    final chainMultiplier = 1.0 + 0.5 * chainIndex;
    final levelMultiplier = 1.0 + (elapsedSeconds / 60) * 0.1;
    score += (base * chainMultiplier * levelMultiplier).round();
    final chainLength = chainIndex + 1;
    if (chainLength > maxChain) maxChain = chainLength;
    _notify();
  }

  void addDestroyed(int count) {
    blocksDestroyedThisResolve += count;
    totalBlocksDestroyed += count;
  }

  void startResolve() {
    blocksDestroyedThisResolve = 0;
  }

  void reset() {
    score = 0;
    blocksDestroyedThisResolve = 0;
    totalBlocksDestroyed = 0;
    maxChain = 0;
    _notify();
  }
}
