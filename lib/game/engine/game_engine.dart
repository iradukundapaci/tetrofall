import 'dart:collection';
import 'dart:math';

import '../ai/placement_scorer.dart';
import '../config/difficulty.dart';
import '../config/motion.dart';
import '../config/run_config.dart';
import '../director/director.dart';
import 'block_fall.dart';
import 'board_metrics.dart';
import 'clear_detector.dart';
import 'events.dart';
import 'grid.dart';
import 'piece_controller.dart';
import 'rise_controller.dart';
import 'ripple_cascade.dart';
import 'scoring.dart';
import 'tetromino.dart';

enum GamePhase { ready, spawning, playing, resolving, gameOver, continuing }

enum GameIntentType {
  moveLeft,
  moveRight,
  rotateCW,
  rotateCCW,
  softDropStart,
  softDropEnd,
  hardDrop,
}

/// A resolve alternates between shattering the rows it just completed and
/// rippling gravity up the stack. `settle` lets blocks already in flight
/// finish landing before anything else touches the grid.
enum _ResolveStage { shatter, ripple, settle }

enum _ContinueStage { filling, clearing }

class _BufferedIntent {
  _BufferedIntent(this.type);

  final GameIntentType type;

  /// Seconds spent waiting for a phase that can act on it.
  double age = 0;
}

class GameEngine {
  GameEngine({Random? random, Grid? grid, RunConfig config = RunConfig.plain})
    : grid = grid ?? Grid(),
      _random = random ?? Random() {
    pieceController = PieceController(this.grid);
    riseController = RiseController(this.grid, random: _random);
    _bag = SevenBag(_random);
    _applyConfig(config);
  }

  final Grid grid;
  final Random _random;

  late final PieceController pieceController;
  late final RiseController riseController;
  late final SevenBag _bag;

  final Scoring scoring = Scoring();

  late RunConfig _config;
  late Director _director;

  /// A [NullDirector] unless the config supplies one.
  Director get director => _director;

  void _applyConfig(RunConfig config) {
    _config = config;
    _director = config.director ?? NullDirector();
    riseController.riseConfig = config.rise;
    riseController.rowPlanner = _director.takeRowPlan;
  }

  /// Swaps in [config] mid-run without touching the board. The tutorial plays
  /// on a plain engine and hands the same run to the Director with this.
  void adoptConfig(RunConfig config) {
    _applyConfig(config);
    _director.reset(elapsed: riseController.elapsed);
    _directorClock = 0;
  }

  /// The piece after the one in play, drawn a spawn early for the HUD. Tutorial
  /// pieces come first. The Director may bias a piece only as it is drawn into
  /// this slot, never after the player could have seen it.
  TetrominoType? get nextPiece =>
      _scriptedPieces.isNotEmpty ? _scriptedPieces.first : _lookahead;

  TetrominoType? _lookahead;

  /// Time since the Director was last consulted.
  double _directorClock = 0;
  static const _directorInterval = 0.25;

  GamePhase phase = GamePhase.ready;

  int chainIndex = 0;

  /// Tutorial hold: stops the rise clock and the active piece's gravity and
  /// lock delay. Intents are unaffected ([_drainIntents] runs before the phase
  /// switch), so a frozen board still answers every gesture.
  bool freezeRise = false;
  bool freezeGravity = false;

  /// Pieces to deal before the bag, for the tutorial. Cleared by [start].
  final _scriptedPieces = Queue<TetrominoType>();

  void queuePieces(Iterable<TetrominoType> types) =>
      _scriptedPieces.addAll(types);

  double _resolveTimer = 0;
  _ResolveStage _resolveStage = _ResolveStage.shatter;

  /// Row gravity is releasing next; everything above stays frozen until its
  /// turn.
  int _rippleRow = 0;

  /// Rows still holding blocks at or above [_rippleRow], for pacing the wave
  /// against [Motion.rippleBudget].
  int _rippleRowsRemaining = 0;

  /// Bottom-most row cleared so far this resolve. Gravity releases only rows
  /// strictly above it; overhangs beneath stay as the player left them. Null
  /// until the first clear.
  int? _gravityFloor;

  /// Longest flight still in the air. Nothing may clear a row until it lands.
  double _flightRemaining = 0;

  /// Whole-resolve clock, against [Motion.resolveHardCap].
  double _resolveElapsed = 0;
  bool _flushed = false;

  _ContinueStage _continueStage = _ContinueStage.filling;
  int _continueRow = 0;

  /// How long a move or rotation survives while the board is resolving.
  static const inputBufferWindow = Duration(milliseconds: 250);

  final _intentQueue = <_BufferedIntent>[];
  final _eventListeners = <void Function(GameEvent)>[];

  void addEventListener(void Function(GameEvent) listener) =>
      _eventListeners.add(listener);

  void removeEventListener(void Function(GameEvent) listener) =>
      _eventListeners.remove(listener);

  void _emit(GameEvent event) {
    for (final listener in List.of(_eventListeners)) {
      listener(event);
    }
  }

  void enqueueIntent(GameIntentType intent) =>
      _intentQueue.add(_BufferedIntent(intent));

  /// How many times one run can be bought back with a rewarded ad.
  static const maxContinuesPerRun = 2;

  int continuesUsedThisRun = 0;

  bool get canContinueThisRun => continuesUsedThisRun < maxContinuesPerRun;

  void continueAfterAd() {
    if (phase != GamePhase.gameOver || !canContinueThisRun) return;
    continuesUsedThisRun++;
    _intentQueue.clear();
    pieceController.discard();
    grid.clearSpawnRows();
    phase = GamePhase.continuing;
    _continueStage = _ContinueStage.filling;
    _continueRow = grid.maxRow;
    _resolveTimer = 0;
  }

  /// Starts a run. [config] replaces the engine's for this and later runs;
  /// [initialElapsed] overrides the config's difficulty clock start.
  void start({Duration? initialElapsed, RunConfig? config}) {
    if (config != null) _applyConfig(config);
    final startAt = initialElapsed ?? _config.initialElapsed;
    grid.clearAll();
    _intentQueue.clear();
    _scriptedPieces.clear();
    _lookahead = null;
    _directorClock = 0;
    _director.reset(elapsed: startAt.inMicroseconds / 1e6);
    riseController.reset(initialElapsed: startAt);
    scoring.reset();
    continuesUsedThisRun = 0;
    phase = GamePhase.spawning;
    _trySpawn();
  }

  /// Abandons the active piece and deals the next without [start], which would
  /// also wipe the grid, score and rise clock. The tutorial uses it to swap
  /// pieces mid-run.
  void respawnPiece() {
    _intentQueue.clear();
    pieceController.softDropActive = false;
    chainIndex = 0;
    phase = GamePhase.spawning;
  }

  void tick(double dt) {
    if (phase == GamePhase.playing || phase == GamePhase.resolving) {
      _directorClock += dt;
    }
    _drainIntents(dt);

    switch (phase) {
      case GamePhase.ready:
        return;
      case GamePhase.spawning:
        _trySpawn();
      case GamePhase.playing:
        if (!freezeRise && riseController.tick(dt)) {
          _handleRiseCommit();
        }
        if (phase == GamePhase.playing && _directorClock >= _directorInterval) {
          _consultDirector();
        }
        if (phase == GamePhase.playing && !freezeGravity) {
          pieceController.dropInterval =
              riseController.difficultyNow.dropInterval;
          final result = pieceController.tick(dt);
          if (result == PieceTickResult.locked) {
            _lockAndResolve();
          }
        }
      case GamePhase.resolving:
        riseController.tickElapsedOnly(dt);
        _resolveElapsed += dt;
        _flightRemaining = max(0, _flightRemaining - dt);
        if (!_flushed && _resolveElapsed > _hardCapSeconds) {
          // Checked every frame so a long chain can't overshoot the cap by a
          // whole shatter.
          _flushResolve();
        } else if (_resolveTimer > 0) {
          _resolveTimer -= dt;
          if (_resolveTimer <= 0) {
            switch (_resolveStage) {
              case _ResolveStage.shatter:
                _beginRipple();
              case _ResolveStage.ripple:
                _rippleStep();
              case _ResolveStage.settle:
                _resolvePass();
            }
          }
        }
      case GamePhase.gameOver:
        return;
      case GamePhase.continuing:
        _resolveTimer -= dt;
        if (_resolveTimer <= 0) {
          _advanceContinue();
        }
    }
  }

  void _drainIntents(double dt) {
    if (phase != GamePhase.playing) {
      _ageBufferedIntents(dt);
      return;
    }
    for (final buffered in _intentQueue) {
      // A hard drop leaves the playing phase mid-drain; anything queued behind
      // it belonged to the piece that just landed.
      if (phase != GamePhase.playing) break;
      switch (buffered.type) {
        case GameIntentType.moveLeft:
          if (pieceController.moveLeft()) {
            _emit(const PlayerActionEvent(PlayerAction.moveLeft));
          }
        case GameIntentType.moveRight:
          if (pieceController.moveRight()) {
            _emit(const PlayerActionEvent(PlayerAction.moveRight));
          }
        case GameIntentType.rotateCW:
          // Emitted whether or not the piece turned (an O rotates onto itself,
          // a kick can fail): the player did what they were asked either way.
          pieceController.rotateCW();
          _emit(const PlayerActionEvent(PlayerAction.rotate));
        case GameIntentType.rotateCCW:
          pieceController.rotateCCW();
          _emit(const PlayerActionEvent(PlayerAction.rotate));
        case GameIntentType.softDropStart:
          pieceController.softDropActive = true;
          _emit(const PlayerActionEvent(PlayerAction.softDrop));
        case GameIntentType.softDropEnd:
          pieceController.softDropActive = false;
        case GameIntentType.hardDrop:
          _emit(const PlayerActionEvent(PlayerAction.hardDrop));
          pieceController.hardDrop();
          _lockAndResolve();
      }
    }
    _intentQueue.clear();
  }

  /// Carries recent moves and rotations across a resolve so they land on the
  /// next piece. Drops and soft-drop toggles are not held.
  void _ageBufferedIntents(double dt) {
    final window = inputBufferWindow.inMilliseconds / 1000;
    for (var i = _intentQueue.length - 1; i >= 0; i--) {
      final buffered = _intentQueue[i];
      buffered.age += dt;
      if (buffered.age > window || !_isBufferable(buffered.type)) {
        _intentQueue.removeAt(i);
      }
    }
  }

  static bool _isBufferable(GameIntentType type) => switch (type) {
    GameIntentType.moveLeft ||
    GameIntentType.moveRight ||
    GameIntentType.rotateCW ||
    GameIntentType.rotateCCW => true,
    GameIntentType.softDropStart ||
    GameIntentType.softDropEnd ||
    GameIntentType.hardDrop => false,
  };

  void _handleRiseCommit() {
    if (riseController.wouldTopOut()) {
      _endRun(GameOverReason.topOut);
      return;
    }

    riseController.commitRise();

    final piece = pieceController.piece;
    if (piece != null) {
      final originalRow = piece.anchorRow;
      final shiftedRow = originalRow - 1;
      final pushedRow = shiftedRow - 1;
      if (shiftedRow >= grid.minRow &&
          !pieceController.collidesAt(shiftedRow, piece.anchorCol)) {
        piece.anchorRow = shiftedRow;
      } else if (pushedRow >= grid.minRow &&
          !pieceController.collidesAt(pushedRow, piece.anchorCol)) {
        piece.anchorRow = pushedRow;
      } else if (!pieceController.collidesAt(originalRow, piece.anchorCol)) {
        piece.anchorRow = originalRow;
      } else {
        _endRun(GameOverReason.topOut);
        return;
      }
    }
    _emit(const RiseCommittedEvent());
  }

  void _trySpawn() {
    final TetrominoType type;
    if (_scriptedPieces.isNotEmpty) {
      type = _scriptedPieces.removeFirst();
    } else {
      type = _lookahead ?? _draw();
      _lookahead = null;
    }
    // Drawn here, after the previous clears have settled, so a biased pick is
    // judged against the board the player is actually facing.
    _lookahead ??= _draw();

    final spawned = pieceController.spawn(type);
    if (!spawned) {
      _endRun(GameOverReason.blockOut);
      return;
    }
    phase = GamePhase.playing;
    _emit(const PieceSpawnedEvent());
  }

  TetrominoType _draw() {
    if (!_director.takeBagBias()) return _bag.pickNext();
    return _bag.pickNext(
      chooser: (remaining) {
        var best = remaining.first;
        var bestFit = double.negativeInfinity;
        for (final type in remaining) {
          final fit = PlacementScorer.bestFit(grid, type);
          if (fit > bestFit) {
            bestFit = fit;
            best = type;
          }
        }
        return best;
      },
    );
  }

  void _endRun(GameOverReason reason) {
    phase = GamePhase.gameOver;
    _director.onRunEnded();
    _emit(GameOverEvent(reason));
  }

  void _consultDirector() {
    if (!_director.isActive) {
      _directorClock = 0;
      return;
    }
    final output = _director.update(
      BoardSnapshot(
        metrics: BoardMetrics.of(grid),
        elapsed: riseController.elapsed,
      ),
      _directorClock,
    );
    _directorClock = 0;
    riseController.directorIntervalScale = output.riseIntervalScale;
  }

  void _lockAndResolve() {
    final piece = pieceController.piece;
    if (piece == null) return;
    if (_director.isActive) {
      // Before the piece is written in, so the Director sees the board the
      // player chose from.
      _director.onPlacement(
        PlacementReport(
          grid: grid,
          type: piece.type,
          rotation: piece.rotation,
          anchorRow: piece.anchorRow,
          anchorCol: piece.anchorCol,
        ),
      );
    }
    pieceController.lockPiece();
    pieceController.softDropActive = false;
    _emit(const PieceLockedEvent());
    _consultDirector();
    _beginResolve();
    _resolvePass();
  }

  void _beginResolve() {
    phase = GamePhase.resolving;
    chainIndex = 0;
    _resolveElapsed = 0;
    _flightRemaining = 0;
    _flushed = false;
    _gravityFloor = null;
  }

  /// How much the whole resolve is compressed, tracking the difficulty curve's
  /// drop interval so clearing gets faster at the rate the game does.
  double get resolveTimeScale {
    final base = Difficulty.checkpoints.first.dropInterval.inMicroseconds;
    final now = riseController.difficultyNow.dropInterval.inMicroseconds;
    return (now / base).clamp(Motion.resolveMinTimeScale, 1.0);
  }

  /// Arms the resolve timer, guaranteeing it survives at least one more tick
  /// so a zero-length stage can never leave the phase without a wake-up.
  void _schedule(_ResolveStage stage, double seconds) {
    _resolveStage = stage;
    _resolveTimer = max(seconds, 1e-6);
  }

  void _resolvePass() {
    final fullRows = ClearDetector.findFullRows(grid);
    if (fullRows.isEmpty) {
      // Gravity only runs as part of a clear; a plain lock keeps its overhangs.
      if (chainIndex == 0) {
        _resolveTimer = 0;
        phase = GamePhase.spawning;
        return;
      }
      _beginRipple();
      return;
    }

    final scale = _clearRows(fullRows);
    _schedule(
      _ResolveStage.shatter,
      Motion.shatterSequenceSeconds(grid.cols) * scale,
    );
  }

  /// Strips, scores and announces one clear, returning the time scale its
  /// shatter runs at. Shared by the animated resolve and its hard-cap flush.
  double _clearRows(List<int> fullRows) {
    final removedCells = <ClearedCell>[];
    for (final r in fullRows) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.at(r, c);
        if (cell == null) continue;
        removedCells.add(ClearedCell(row: r, col: c, type: cell.type));
        grid.set(r, c, null);
      }
    }
    _lowerGravityFloor(fullRows);

    scoring.addDestroyed(removedCells.length);
    scoring.awardLineClear(
      lines: fullRows.length,
      chainIndex: chainIndex,
      elapsedSeconds: riseController.elapsed,
    );
    _director.onClear(lines: fullRows.length, chainIndex: chainIndex);

    final scale = _chainTimeScale();
    _emit(RowsClearedEvent(fullRows, removedCells, timeScale: scale));
    _emit(ChainAdvancedEvent(chainIndex));
    chainIndex++;
    return scale;
  }

  /// Widens the settle window down to the rows just cleared. Monotonic: a later
  /// link clearing higher up must not re-freeze rows the wave was already
  /// allowed to release.
  void _lowerGravityFloor(List<int> clearedRows) {
    final lowest = clearedRows.reduce(max);
    final current = _gravityFloor;
    if (current == null || lowest > current) _gravityFloor = lowest;
  }

  /// [resolveTimeScale], tightened further as a chain deepens.
  double _chainTimeScale() {
    final falloff = max(
      Motion.chainShatterFloor,
      1 - Motion.chainShatterFalloff * chainIndex,
    );
    return resolveTimeScale * falloff;
  }

  /// When the engine gives up on animating and collapses the rest at once.
  double get _hardCapSeconds =>
      Motion.resolveHardCap.inMilliseconds / 1000 * resolveTimeScale;

  /// Starts the gravity wave just above the cleared line. Every clear restarts
  /// it there, because a cleared row reopens a gap below whatever is still
  /// frozen higher up.
  void _beginRipple() {
    final floor = _gravityFloor;
    final row = floor == null
        ? null
        : RippleCascade.nextFloatingRow(grid, fromRow: floor - 1);
    if (row == null) {
      _resolveTimer = 0;
      phase = GamePhase.spawning;
      return;
    }
    _rippleRow = row;
    _rippleRowsRemaining = RippleCascade.rowsRemaining(grid, fromRow: row);
    _schedule(_ResolveStage.ripple, 0);
  }

  /// Emits [falls] and returns the flight time budgeted for the longest.
  double _emitFalls(List<BlockFall> falls) {
    final maxDistance = falls
        .map((f) => (f.toRow - f.fromRow).abs())
        .reduce(max);
    final fallSeconds =
        sqrt(2 * maxDistance / Motion.gravityCellsPerS2) * _chainTimeScale();
    _emit(
      BlocksFellEvent([
        for (final f in falls)
          BlockFallEvent(
            fromRow: f.fromRow,
            toRow: f.toRow,
            col: f.col,
            type: f.type,
            durationSeconds: fallSeconds,
          ),
      ]),
    );
    return fallSeconds;
  }

  /// Releases one row: its blocks drop to rest, everything above stays put.
  void _rippleStep() {
    final falls = RippleCascade.settleRow(grid, _rippleRow);
    if (falls.isNotEmpty) {
      final fallSeconds = _emitFalls(falls);
      _flightRemaining = max(
        _flightRemaining,
        fallSeconds + Motion.impactSquash.inMilliseconds / 1000,
      );
    }
    if (_rippleRowsRemaining > 0) _rippleRowsRemaining--;

    // Landing blocks can complete partial rows, but those clear only once
    // everything in the air has landed: shattering a cell the fall animator is
    // still drawing would tear the frame.
    if (ClearDetector.findFullRows(grid).isNotEmpty) {
      _schedule(_ResolveStage.settle, _flightRemaining);
      return;
    }

    final next = RippleCascade.nextFloatingRow(grid, fromRow: _rippleRow - 1);
    if (next == null) {
      _schedule(_ResolveStage.settle, _flightRemaining);
      return;
    }
    _rippleRow = next;
    _schedule(_ResolveStage.ripple, _stepInterval());
  }

  /// Gap between releasing one row and the next: shorter than a one-cell fall
  /// so the wave reads as continuous, compressed further when a tall stack
  /// would overrun the budget.
  double _stepInterval() {
    final scale = _chainTimeScale();
    final budget = Motion.rippleBudget.inMilliseconds / 1000 * scale;
    final paced = budget / max(1, _rippleRowsRemaining);
    final base = Motion.rippleStepBase.inMilliseconds / 1000 * scale;
    return max(Motion.rippleStepMin.inMilliseconds / 1000, min(base, paced));
  }

  List<BlockFall> _settleAboveFloor() {
    final floor = _gravityFloor;
    if (floor == null) return const [];
    return RippleCascade.settleAbove(grid, floorRow: floor);
  }

  /// Escape hatch for a resolve that outran [Motion.resolveHardCap]: collapse
  /// everything above the cleared line in one pass and sweep out any rows that
  /// completes. Only the final settle animates.
  void _flushResolve() {
    _flushed = true;
    var falls = _settleAboveFloor();
    for (var guard = 0; guard <= grid.visibleRows; guard++) {
      final fullRows = ClearDetector.findFullRows(grid);
      if (fullRows.isEmpty) break;
      _clearRows(fullRows);
      falls = _settleAboveFloor();
    }

    if (falls.isNotEmpty) {
      _flightRemaining =
          _emitFalls(falls) + Motion.impactSquash.inMilliseconds / 1000;
    }
    _schedule(
      _ResolveStage.settle,
      max(
        _flightRemaining,
        Motion.shatterSequenceSeconds(grid.cols) * _chainTimeScale(),
      ),
    );
  }

  void _advanceContinue() {
    switch (_continueStage) {
      case _ContinueStage.filling:
        grid.fillRow(_continueRow);
        if (_continueRow == 0) {
          _continueStage = _ContinueStage.clearing;
          _continueRow = 0;
          _resolveTimer = Motion.continueFullHold.inMilliseconds / 1000;
        } else {
          _continueRow--;
          _resolveTimer = Motion.continueFillRowStep.inMilliseconds / 1000;
        }
      case _ContinueStage.clearing:
        _clearContinueRow(_continueRow);
        if (_continueRow == grid.maxRow) {
          phase = GamePhase.spawning;
          return;
        }
        _continueRow++;
        _resolveTimer = Motion.continueClearRowStep.inMilliseconds / 1000;
    }
  }

  void _clearContinueRow(int row) {
    final removedCells = <ClearedCell>[];
    for (var c = 0; c < grid.cols; c++) {
      final cell = grid.at(row, c);
      if (cell == null) continue;
      removedCells.add(ClearedCell(row: row, col: c, type: cell.type));
      grid.set(row, c, null);
    }
    if (removedCells.isNotEmpty) {
      _emit(RowsClearedEvent([row], removedCells, forced: true));
    }
  }
}
