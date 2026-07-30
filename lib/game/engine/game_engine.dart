import 'dart:math';

import '../config/motion.dart';
import 'clear_detector.dart';
import 'column_cascade.dart';
import 'events.dart';
import 'gravity_resolver.dart';
import 'grid.dart';
import 'piece_controller.dart';
import 'rise_controller.dart';
import 'scoring.dart';
import 'tetromino.dart';

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

enum _ResolveStage { shatter, cascade }

class GameEngine {
  GameEngine({Random? random, Grid? grid})
    : grid = grid ?? Grid(),
      _random = random ?? Random() {
    pieceController = PieceController(this.grid);
    riseController = RiseController(this.grid, random: _random);
    bag = SevenBag(_random);
  }

  final Grid grid;
  final Random _random;

  late final PieceController pieceController;
  late final RiseController riseController;
  late final SevenBag bag;

  final Scoring scoring = Scoring();

  GamePhase phase = GamePhase.ready;

  GravityResolver resolver = ColumnCascade();

  int chainIndex = 0;

  double _resolveTimer = 0;
  _ResolveStage _resolveStage = _ResolveStage.shatter;

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

  void start({Duration initialElapsed = Duration.zero}) {
    grid.clearAll();
    _intentQueue.clear();
    riseController.reset(initialElapsed: initialElapsed);
    scoring.reset();
    phase = GamePhase.spawning;
    _trySpawn();
  }

  void tick(double dt) {
    _drainIntents();

    switch (phase) {
      case GamePhase.ready:
        return;
      case GamePhase.spawning:
        _trySpawn();
      case GamePhase.playing:
        if (riseController.tick(dt)) {
          _handleRiseCommit();
        }
        if (phase == GamePhase.playing) {
          pieceController.dropInterval =
              riseController.difficultyNow.dropInterval;
          final result = pieceController.tick(dt);
          if (result == PieceTickResult.locked) {
            _lockAndResolve();
          }
        }
      case GamePhase.resolving:
        riseController.tickElapsedOnly(dt);
        if (_resolveTimer > 0) {
          _resolveTimer -= dt;
          if (_resolveTimer <= 0) {
            switch (_resolveStage) {
              case _ResolveStage.shatter:
                _runCascade();
              case _ResolveStage.cascade:
                _resolvePass();
            }
          }
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

  void _handleRiseCommit() {
    if (riseController.wouldTopOut()) {
      phase = GamePhase.gameOver;
      _emit(const GameOverEvent(GameOverReason.topOut));
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
        phase = GamePhase.gameOver;
        _emit(const GameOverEvent(GameOverReason.topOut));
        return;
      }
    }
    _emit(const RiseCommittedEvent());
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
    pieceController.softDropActive = false;
    _emit(const PieceLockedEvent());
    _beginResolve();
    _resolvePass();
  }

  void _beginResolve() {
    phase = GamePhase.resolving;
    chainIndex = 0;
    scoring.startResolve();
  }

  void _resolvePass() {
    final fullRows = ClearDetector.findFullRows(grid);
    if (fullRows.isEmpty) {
      _resolveTimer = 0;
      phase = GamePhase.spawning;
      return;
    }

    final removedCells = <ClearedCell>[];
    for (final r in fullRows) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.at(r, c);
        if (cell == null) continue;
        removedCells.add(ClearedCell(row: r, col: c, type: cell.type));
        grid.set(r, c, null);
      }
    }

    scoring.addDestroyed(removedCells.length);
    scoring.awardLineClear(
      lines: fullRows.length,
      chainIndex: chainIndex,
      elapsedSeconds: riseController.elapsed,
    );
    _startShatterThenCascade(fullRows, removedCells);
  }

  void _startShatterThenCascade(
    List<int> rows,
    List<ClearedCell> removedCells,
  ) {
    _emit(RowsClearedEvent(rows, removedCells));
    _resolveStage = _ResolveStage.shatter;
    _resolveTimer = Motion.shatterSequenceSeconds(grid.cols);
  }

  void _runCascade() {
    final falls = resolver.resolve(grid);
    if (falls.isNotEmpty) {
      _emit(
        BlocksFellEvent([
          for (final f in falls)
            BlockFallEvent(
              fromRow: f.fromRow,
              toRow: f.toRow,
              col: f.col,
              type: f.type,
            ),
        ]),
      );
    }
    _emit(ChainAdvancedEvent(chainIndex));
    chainIndex++;
    _resolveStage = _ResolveStage.cascade;
    _resolveTimer = _settleDuration(falls);
    if (_resolveTimer <= 0) {
      _resolvePass();
    }
  }

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
