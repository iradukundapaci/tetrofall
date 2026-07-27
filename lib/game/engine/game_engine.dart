import 'dart:math';

import '../config/motion.dart';
import 'clear_detector.dart';
import 'column_cascade.dart';
import 'events.dart';
import 'gravity_resolver.dart';
import 'grid.dart';
import 'piece_controller.dart';
import 'tetromino.dart';

/// See game.md §3.3. PAUSED/BOOSTER_ARMED and the rise-driven transition
/// out of PLAYING join in later phases.
enum GamePhase { ready, spawning, playing, resolving, gameOver }

enum GameIntentType {
  moveLeft,
  moveRight,
  rotateCW,
  rotateCCW,
  softDropStart,
  softDropEnd,
  hardDrop,
}

/// Pure-Dart state machine + tick order (§3.4, trimmed to what Phase 1-3
/// need). UI/render reads state and sends intents; the engine emits
/// [GameEvent]s. Zero Flame or Flutter imports.
class GameEngine {
  GameEngine({Random? random, Grid? grid})
    : grid = grid ?? Grid(),
      _random = random ?? Random() {
    pieceController = PieceController(this.grid);
    bag = SevenBag(_random);
  }

  final Grid grid;
  final Random _random;

  late final PieceController pieceController;
  late final SevenBag bag;

  GamePhase phase = GamePhase.ready;

  /// Swappable at runtime (e.g. from the debug screen) to play-test
  /// [ColumnCascade] against `StickyGroup` — see §1.6.
  GravityResolver resolver = ColumnCascade();

  /// Cascade chain link count for the resolve currently in progress.
  /// Resets to 0 at the start of each new resolve; each follow-up clear
  /// within the same resolve increments it (§1.6, §1.7).
  int chainIndex = 0;

  /// Time remaining before RESOLVING re-scans for a chained clear. Mirrors
  /// how long the render layer's fall animation will take (§2.2's formula,
  /// computed here in pure Dart) so gameplay doesn't resume mid-cascade —
  /// even though the grid data itself is already final (§3.1).
  double _resolveTimer = 0;

  final _intentQueue = <GameIntentType>[];
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

  void enqueueIntent(GameIntentType intent) => _intentQueue.add(intent);

  /// Starts (or restarts) a run: clears the grid and spawns the first
  /// piece.
  void start() {
    grid.clearAll();
    _intentQueue.clear();
    phase = GamePhase.spawning;
    _trySpawn();
  }

  /// One simulation frame. See §3.4 for the full tick order — Phase 1
  /// only needs intents → gravity/lock → transitions.
  void tick(double dt) {
    _drainIntents();

    switch (phase) {
      case GamePhase.ready:
        return;
      case GamePhase.spawning:
        _trySpawn();
      case GamePhase.playing:
        final result = pieceController.tick(dt);
        if (result == PieceTickResult.locked) {
          _lockAndResolve();
        }
      case GamePhase.resolving:
        if (_resolveTimer > 0) {
          _resolveTimer -= dt;
          if (_resolveTimer <= 0) _resolvePass();
        }
      case GamePhase.gameOver:
        return;
    }
  }

  void _drainIntents() {
    if (phase != GamePhase.playing) {
      _intentQueue.clear();
      return;
    }
    for (final intent in _intentQueue) {
      switch (intent) {
        case GameIntentType.moveLeft:
          pieceController.moveLeft();
        case GameIntentType.moveRight:
          pieceController.moveRight();
        case GameIntentType.rotateCW:
          pieceController.rotateCW();
        case GameIntentType.rotateCCW:
          pieceController.rotateCCW();
        case GameIntentType.softDropStart:
          pieceController.softDropActive = true;
        case GameIntentType.softDropEnd:
          pieceController.softDropActive = false;
        case GameIntentType.hardDrop:
          pieceController.hardDrop();
          _lockAndResolve();
      }
    }
    _intentQueue.clear();
  }

  void _trySpawn() {
    final type = bag.next();
    final spawned = pieceController.spawn(type);
    if (!spawned) {
      phase = GamePhase.gameOver;
      _emit(const GameOverEvent(GameOverReason.blockOut));
      return;
    }
    phase = GamePhase.playing;
    _emit(const PieceSpawnedEvent());
  }

  void _lockAndResolve() {
    if (pieceController.piece == null) return;
    pieceController.lockPiece();
    _emit(const PieceLockedEvent());
    phase = GamePhase.resolving;
    chainIndex = 0;
    _resolvePass();
  }

  /// One clear + cascade pass. Runs immediately after a lock, then again
  /// each time [_resolveTimer] (mirroring the render layer's fall
  /// animation duration) expires — that's the chain-rescan loop (§1.6):
  /// clear, drop, rescan, repeat until a pass finds nothing to clear.
  void _resolvePass() {
    final fullRows = ClearDetector.findFullRows(grid);
    if (fullRows.isEmpty) {
      _resolveTimer = 0;
      phase = GamePhase.spawning;
      return;
    }

    for (final row in fullRows) {
      for (var col = 0; col < grid.cols; col++) {
        grid.set(row, col, null);
      }
    }
    _emit(RowsClearedEvent(fullRows));

    final falls = resolver.resolve(grid);
    if (falls.isNotEmpty) {
      _emit(
        BlocksFellEvent([
          for (final f in falls)
            BlockFallEvent(fromRow: f.fromRow, toRow: f.toRow, col: f.col),
        ]),
      );
    }
    _emit(ChainAdvancedEvent(chainIndex));
    chainIndex++;
    _resolveTimer = _settleDuration(falls);
    if (_resolveTimer <= 0) {
      // Nothing fell (e.g. the cleared row(s) had nothing above them) —
      // rescan immediately rather than waiting for an animation that
      // isn't happening.
      _resolvePass();
    }
  }

  /// How long the render layer's longest fall + impact squash will take,
  /// computed with the same formula as §2.2 so RESOLVING doesn't let the
  /// player act again before the cascade is visually settled.
  double _settleDuration(List<BlockFall> falls) {
    if (falls.isEmpty) return 0;
    final maxDistance = falls
        .map((f) => (f.toRow - f.fromRow).abs())
        .reduce(max);
    if (maxDistance == 0) return 0;
    final fallSeconds = sqrt(2 * maxDistance / Motion.gravityCellsPerS2);
    return fallSeconds + Motion.impactSquash.inMilliseconds / 1000;
  }
}
