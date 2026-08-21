import '../game/config/difficulty.dart';
import '../game/engine/events.dart';
import 'analytics_service.dart';

typedef DesignSink = void Function(String eventId, {double? value});
typedef ProgressionStartSink = void Function();
typedef ProgressionFailSink = void Function({required int score});

/// Turns the engine's [GameEvent] stream into the handful of analytics events
/// that are actually worth reporting.
///
/// Most of what the engine emits is per-piece and far too noisy to send one
/// event per occurrence — a five-minute run locks hundreds of pieces. So this
/// counts as it goes and reports a summary at the run boundary; the only
/// per-occurrence event is a line clear, which is rare enough to be
/// interesting and bucketed into five fixed ids.
///
/// The sinks are injectable so tests can read the emitted ids back without a
/// platform channel underneath. Nothing in here touches Flutter or the SDK.
class RunTracker {
  RunTracker({
    DesignSink? design,
    ProgressionStartSink? progressionStart,
    ProgressionFailSink? progressionFail,
  }) : _design = design ?? AnalyticsService.design,
       _progressionStart = progressionStart ?? AnalyticsService.progressionStart,
       _progressionFail = progressionFail ?? AnalyticsService.progressionFail;

  final DesignSink _design;
  final ProgressionStartSink _progressionStart;
  final ProgressionFailSink _progressionFail;

  int _pieces = 0;
  int _hardDrops = 0;
  int _lines = 0;
  int _rises = 0;
  int _continues = 0;
  int _chainLength = 1;
  int _bestBefore = 0;

  /// Whether a run is currently being counted. Guards the pair of asymmetries
  /// this class has to survive: events arriving before the first
  /// [runStarted] (the engine is started from Flame's `onLoad`, which lands
  /// after the screen's `initState`), and a second [runEnded] for the same run
  /// — the game-over overlay's Home button reaches `_goHome` after the
  /// `GameOverEvent` already closed the run out.
  bool _running = false;

  bool get isRunning => _running;

  /// Opens a run. [initialElapsed] is the head start adaptive start speed
  /// granted, which is worth reporting on its own: it is the difference
  /// between "runs are getting shorter" and "runs are starting harder".
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
    if (!resumed) _progressionStart();
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
        // Arrives immediately after the RowsClearedEvent it belongs to, so by
        // the time the next clear is reported this holds that clear's chain.
        _chainLength = chainIndex + 1;
      // The continue sweep wipes the board a row at a time and each wipe
      // arrives here looking exactly like a clear. Counting them would credit
      // a player who bought a continue with a full board's worth of clears.
      case RowsClearedEvent(forced: true):
        break;
      case RowsClearedEvent(:final rows):
        _lines += rows.length;
        _design(_clearEventId(rows.length), value: _chainLength.toDouble());
      case _:
        break;
    }
  }

  /// Closes the run out. [reason] is `topout`, `blockout`, `quit` or
  /// `restart`; it is lower-cased on the way in, because the two that come
  /// from a [GameOverReason] arrive camelCase and GameAnalytics treats
  /// `run:end:blockOut` and `run:end:blockout` as two unrelated series.
  ///
  /// Idempotent: a run that already ended reports nothing, so the game-over
  /// path and the quit path can both call this without double-counting.
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
    // Reported once, here, rather than at the moment the old best is passed:
    // the crossing happens on some arbitrary mid-run line clear and its value
    // would be "the old best plus one clear", which measures nothing. What is
    // worth knowing is where a record run actually landed.
    if (score > _bestBefore) _design('score:best', value: score.toDouble());
    _progressionFail(score: score);
  }

  /// A rewarded continue extended the current run rather than starting a new
  /// one, so the run stays open and its counters keep accumulating.
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

  /// How far up the difficulty curve the run got, as a 1-based index into
  /// [Difficulty.checkpoints].
  ///
  /// The engine has no notion of a level — difficulty is a continuous lerp
  /// over elapsed time — so this is synthesised purely for the dashboard,
  /// where a run length in seconds is much harder to read than "reached
  /// tier 4".
  static int tierFor(Duration elapsed) {
    var tier = 1;
    for (var i = 0; i < Difficulty.checkpoints.length; i++) {
      if (elapsed >= Difficulty.checkpoints[i].elapsed) tier = i + 1;
    }
    return tier;
  }
}
