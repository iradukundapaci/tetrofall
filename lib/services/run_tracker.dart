import '../game/config/difficulty.dart';
import '../game/engine/events.dart';
import 'analytics_service.dart';
import 'firebase_analytics_service.dart';

typedef DesignSink = void Function(String eventId, {double? value});
typedef ProgressionStartSink = void Function();
typedef ProgressionFailSink = void Function({required int score});
typedef LevelStartSink = void Function();
typedef LevelEndSink = void Function({required int score, required int tier});

/// Turns the engine's [GameEvent] stream into a few analytics events: it
/// counts per-piece noise and reports a summary at the run boundary, with line
/// clears (bucketed into five ids) the only per-occurrence event. Sinks are
/// injectable for tests.
class RunTracker {
  RunTracker({
    DesignSink? design,
    ProgressionStartSink? progressionStart,
    ProgressionFailSink? progressionFail,
    LevelStartSink? levelStart,
    LevelEndSink? levelEnd,
  }) : _design = design ?? AnalyticsService.design,
       _progressionStart = progressionStart ?? AnalyticsService.progressionStart,
       _progressionFail = progressionFail ?? AnalyticsService.progressionFail,
       _levelStart = levelStart ?? FirebaseAnalyticsService.logLevelStart,
       _levelEnd = levelEnd ?? FirebaseAnalyticsService.logLevelEnd;

  final DesignSink _design;
  final ProgressionStartSink _progressionStart;
  final ProgressionFailSink _progressionFail;

  /// The GA4 half of the run boundary, which exists for Google Ads.
  final LevelStartSink _levelStart;
  final LevelEndSink _levelEnd;

  int _pieces = 0;
  int _hardDrops = 0;
  int _lines = 0;
  int _rises = 0;
  int _continues = 0;
  int _chainLength = 1;
  int _bestBefore = 0;

  /// Guards events arriving before the first [runStarted] (Flame's `onLoad`
  /// lands after `initState`) and a second [runEnded] for the same run.
  bool _running = false;

  bool get isRunning => _running;

  /// Opens a run. [initialElapsed] is the adaptive-start head start, reported
  /// so shorter runs can be told from harder starts.
  void runStarted({
    Duration initialElapsed = Duration.zero,
    int bestBefore = 0,
    bool resumed = false,
  }) {
    _reset();
    _running = true;
    _bestBefore = bestBefore;
    _design(
      resumed ? 'run:resume' : 'run:start',
      value: initialElapsed.inMilliseconds / 1000,
    );
    if (!resumed) {
      _progressionStart();
      _levelStart();
    }
  }

  void onEvent(GameEvent event) {
    if (!_running) return;
    switch (event) {
      case PieceLockedEvent():
        _pieces++;
      case PlayerActionEvent(action: PlayerAction.hardDrop):
        _hardDrops++;
      case RiseCommittedEvent():
        _rises++;
      case ChainAdvancedEvent(:final chainIndex):
        // Arrives right after its RowsClearedEvent, so this holds that clear's
        // chain.
        _chainLength = chainIndex + 1;
      // The continue sweep looks like clears but isn't.
      case RowsClearedEvent(forced: true):
        break;
      case RowsClearedEvent(:final rows):
        _lines += rows.length;
        _design(_clearEventId(rows.length), value: _chainLength.toDouble());
      case _:
        break;
    }
  }

  /// Closes the run out. [reason] is lower-cased because GameAnalytics treats
  /// `blockOut` and `blockout` as separate series. Idempotent, so the game-over
  /// and quit paths can both call it.
  void runEnded({
    required String reason,
    required Duration elapsed,
    required int score,
    required int maxChain,
    required int blocksDestroyed,
  }) {
    if (!_running) return;
    _running = false;
    final seconds = elapsed.inMilliseconds / 1000;
    _design('run:end:${reason.toLowerCase()}', value: seconds);
    _design('run:tier', value: tierFor(elapsed).toDouble());
    _design('run:pieces', value: _pieces.toDouble());
    _design('run:lines', value: _lines.toDouble());
    _design('run:harddrops', value: _hardDrops.toDouble());
    _design('run:rises', value: _rises.toDouble());
    _design('run:blocks', value: blocksDestroyed.toDouble());
    if (_continues > 0) {
      _design('run:continues', value: _continues.toDouble());
    }
    _design('chain:max', value: maxChain.toDouble());
    // Reported at the end: mid-run, the crossing value measures nothing.
    if (score > _bestBefore) _design('score:best', value: score.toDouble());
    _progressionFail(score: score);
    _levelEnd(score: score, tier: tierFor(elapsed));
  }

  /// A rewarded continue extends the run; its counters keep accumulating.
  void continueUsed() {
    if (!_running) return;
    _continues++;
  }

  void _reset() {
    _pieces = 0;
    _hardDrops = 0;
    _lines = 0;
    _rises = 0;
    _continues = 0;
    _chainLength = 1;
    _bestBefore = 0;
  }

  static String _clearEventId(int rows) => switch (rows) {
    1 => 'clear:single',
    2 => 'clear:double',
    3 => 'clear:triple',
    4 => 'clear:tetris',
    _ => 'clear:multi',
  };

  /// How far up the curve the run got, as a 1-based index into
  /// [Difficulty.checkpoints]; synthesised for the dashboard only.
  static int tierFor(Duration elapsed) {
    var tier = 1;
    for (var i = 0; i < Difficulty.checkpoints.length; i++) {
      if (elapsed >= Difficulty.checkpoints[i].elapsed) tier = i + 1;
    }
    return tier;
  }
}
