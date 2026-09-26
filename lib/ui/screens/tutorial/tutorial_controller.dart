import 'package:flutter/foundation.dart';

import '../../../game/config/board_config.dart';
import '../../../game/config/difficulty.dart';
import '../../../game/engine/cell.dart';
import '../../../game/engine/events.dart';
import '../../../game/engine/tetromino.dart';
import '../../../game/tetrofall_game.dart';
import '../../../services/analytics_service.dart';
import '../../../services/firebase_analytics_service.dart';
import '../../../services/storage_service.dart';
import 'gesture_hint.dart';

/// The lessons, in prompt order. Hard drop comes before soft drop because a
/// downward flick enqueues `softDropStart` on its way to `hardDrop`; taught the
/// other way round one flick would credit both. [_credit] closes the other half
/// by never crediting soft drop ahead of its own prompt.
enum TutorialLesson { move, rotate, hardDrop, softDrop, clearRow, cascadeRow }

/// Where a coached piece is parked: visible, with room left to drop it.
const _coachRow = 4;

/// Column moves needed to clear the `move` lesson.
const _movesToAdvance = 2;

/// Extra pieces a missed lesson gets before it is dropped; nagging is worse
/// than not teaching the gesture.
const _maxRearms = 2;

/// Floor lessons get one retry: each raises a fresh rig on top of the stack.
const _maxFloorRearms = 1;

/// How far from the square's spawn column the rigged gap is aimed: two or
/// three swipes.
const _preferredGapDistance = 4;

/// How long one rigged floor takes to climb into place (the real opening
/// interval is 22 s).
const _riseSeconds = 1.5;

/// Drives the first-run tutorial: one uninterrupted gameplay session with a
/// looping gesture hint and a word or two over the board. It never restarts
/// the run; the coached session is the player's first run, and at the end the
/// prompts stop and the rise is released.
class TutorialController extends ChangeNotifier {
  TutorialController({
    required this.game,
    required this.storage,
    required this.onFinished,
  }) {
    game.engine.addEventListener(_onEvent);
    // Written on the way in so a force-quit doesn't repeat the tutorial.
    storage.saveTutorialSeen(true);
    // GA4 counterpart to `tutorial_complete`, for Google Ads.
    FirebaseAnalyticsService.logTutorialBegin();

    // `RiseController.elapsed` only advances while unfrozen, so releasing the
    // rise later hands the real run its full grace period.
    final engine = game.engine;
    engine.freezeRise = true;
    // Nothing is dealt here: this runs before Flame's `onLoad` calls
    // `GameEngine.start`, which clears queued pieces. The coach piece is dealt
    // on the first spawn, in [_onPieceSpawned].
    engine.freezeGravity = true;
    _arm(TutorialLesson.move);
  }

  final TetrofallGame game;
  final StorageService storage;

  /// Called once, on completion or skip, after the engine is released.
  final VoidCallback onFinished;

  /// The prompt on screen; null once the lessons run out.
  TutorialLesson? _lesson;
  TutorialLesson? get lesson => _lesson;

  /// Lessons already performed, including ahead of being asked, so [_next]
  /// skips them.
  final _done = <TutorialLesson>{};

  final _rearms = <TutorialLesson, int>{};

  /// Lessons given up on; in [_done] too, but tracked apart so the closing
  /// report can tell "learned everything" from "let off a couple".
  final _givenUp = <TutorialLesson>{};

  int _moveCount = 0;
  bool _finished = false;

  /// The lesson showing when the current piece spawned. Misses are detected at
  /// the next spawn, not on lock: a hard drop credits itself in the same drain
  /// that locks, so a lock check would score the freshly armed soft-drop prompt
  /// as missed.
  TutorialLesson? _lessonAtSpawn;

  /// Whether the active piece has seen input. Gravity is frozen on spawn and
  /// released by the first action, per piece rather than per prompt.
  bool _pieceEngaged = false;

  /// Floors still to be pushed up, bottom-most last: each rise inserts at the
  /// floor and shoves the rest up, so the first raised ends highest.
  final _pendingFloors = <List<Cell?>>[];

  /// Whether this lesson's floors have been ordered up; cleared by [_arm] so a
  /// re-armed lesson raises a fresh rig.
  bool _floorsRigged = false;

  /// The columns the current rig leaves open, picked against the live board.
  int _gapCol = 0;
  int _cascadeCol = 0;

  /// Whether they have all arrived; the prompt stays off until then.
  bool _floorsReady = false;

  bool _boardTouched = false;

  /// Whether a finger is on the board; the prompt fades until it lifts.
  bool get boardTouched => _boardTouched;

  @override
  void dispose() {
    game.engine.removeEventListener(_onEvent);
    super.dispose();
  }

  void setBoardTouched(bool touched) {
    if (_finished || _boardTouched == touched) return;
    _boardTouched = touched;
    notifyListeners();
  }

  /// Whether this is a floor lesson whose rig is still on its way up.
  bool get _floorsPending => _isFloorLesson(_lesson) && !_floorsReady;

  static bool _isFloorLesson(TutorialLesson? lesson) =>
      lesson == TutorialLesson.clearRow || lesson == TutorialLesson.cascadeRow;

  /// Which looping hint plays over the board, if any.
  TutorialHint get hint => _floorsPending
      ? TutorialHint.none
      : switch (_lesson) {
          TutorialLesson.move => TutorialHint.swipeHorizontal,
          TutorialLesson.rotate => TutorialHint.tap,
          TutorialLesson.hardDrop => TutorialHint.flickDown,
          TutorialLesson.softDrop => TutorialHint.dragDown,
          // Both floor lessons are steering: the piece fits, it must reach the
          // gap.
          TutorialLesson.clearRow ||
          TutorialLesson.cascadeRow => TutorialHint.swipeHorizontal,
          null => TutorialHint.none,
        };

  /// The whole text of the tutorial: what the gesture does, since the
  /// animation shows what it is.
  String? get label => _floorsPending
      ? null
      : switch (_lesson) {
          TutorialLesson.move => 'Move',
          TutorialLesson.rotate => 'Rotate',
          TutorialLesson.hardDrop => 'Slam',
          TutorialLesson.softDrop => 'Fall faster',
          TutorialLesson.clearRow => 'Fill the row',
          TutorialLesson.cascadeRow => 'Again',
          null => null,
        };

  /// Horizontal alignment of the rigged gap, or null. Both rigs leave the same
  /// two-wide opening, so the marker sits on the boundary between its columns.
  double? get gapAlignX => _floorsPending || !_isFloorLesson(_lesson)
      ? null
      : (_gapCol + 1) / BoardConfig.cols * 2 - 1;

  /// The prompt's `Alignment` y: a few rows below the coached piece.
  double get hintAlignY => (_coachRow + 4) / BoardConfig.rows * 2 - 1;

  void skip() {
    AnalyticsService.design('tutorial:skip:${_lesson?.name ?? 'done'}');
    _end();
  }

  /// Ends the tutorial without handing off, for when the run already ended
  /// underneath it.
  void abandon() {
    if (_finished) return;
    AnalyticsService.design('tutorial:abandon:${_lesson?.name ?? 'done'}');
    _finished = true;
    _releaseEngine();
    notifyListeners();
  }

  /// Puts [lesson] on screen and prepares the board for it.
  void _arm(TutorialLesson lesson) {
    AnalyticsService.design('tutorial:step:${lesson.name}');
    _lesson = lesson;
    _moveCount = 0;
    // A finger down as the board changes never reports lifting.
    _boardTouched = false;
    // A new lesson brings its own floors, if it has any.
    _floorsRigged = false;
    _floorsReady = false;
  }

  /// Marks [lesson] done and moves on if it was showing. Credited even when
  /// performed early; [_next] skips anything in [_done].
  void _credit(TutorialLesson lesson) {
    if (!_done.add(lesson)) return;
    if (_lesson == lesson) _next();
  }

  /// Advances to the next unperformed lesson, or ends the tutorial.
  void _next() {
    final current = _lesson;
    final from = current == null ? 0 : current.index + 1;
    for (var i = from; i < TutorialLesson.values.length; i++) {
      final candidate = TutorialLesson.values[i];
      if (_done.contains(candidate)) continue;
      _arm(candidate);
      notifyListeners();
      return;
    }
    // Only performing every gesture counts as complete; a given-up lesson
    // would turn this into an exit rate.
    AnalyticsService.design(
      _givenUp.isEmpty ? 'tutorial:complete' : 'tutorial:partial',
    );
    // GA4's `tutorial_complete` fires either way: for Google Ads it means the
    // install reached the game.
    FirebaseAnalyticsService.logTutorialComplete();
    _lesson = null;
    _end();
  }

  /// Settles the piece that just spawned and closes the books on the one
  /// before. Pieces spawn above the board and a coached piece is frozen, so
  /// [lowerTo] brings it into view.
  void _onPieceSpawned() {
    final engine = game.engine;

    // If the lesson showing at the last spawn is still showing, it was missed.
    final stale = _lessonAtSpawn;
    _lessonAtSpawn = null;
    if (stale != null && stale == _lesson) _onMissed(stale);

    final lesson = _lesson;
    if (lesson == null) return;

    // A rotation prompt needs a piece that visibly rotates (an O doesn't), and
    // `move` counts because `rotate` follows it on the same piece. This is
    // also where the opening piece is dealt; the replaced piece is still in the
    // hidden spawn buffer, so the swap is invisible, and it queues a T so it
    // can't repeat.
    if ((lesson == TutorialLesson.move || lesson == TutorialLesson.rotate) &&
        engine.pieceController.piece?.type == TetrominoType.O) {
      engine.queuePieces([TetrominoType.T]);
      engine.respawnPiece();
      return;
    }

    // Floor lessons want an O, the one piece that fills the two-wide gap
    // however it is turned.
    if (_isFloorLesson(lesson) &&
        engine.pieceController.piece?.type != TetrominoType.O) {
      engine.queuePieces([TetrominoType.O]);
      engine.respawnPiece();
      return;
    }

    _lessonAtSpawn = lesson;
    // Per piece, so a re-armed lesson never carries over half-satisfied.
    _moveCount = 0;
    _pieceEngaged = false;
    engine.freezeGravity = true;
    engine.pieceController.lowerTo(_coachRow);

    // Ordered once per arming, from here so the floors climb against an
    // already-parked piece.
    if (_isFloorLesson(lesson) && !_floorsRigged) {
      _floorsRigged = true;
      // Picked against the board as it stands, with the player's pieces on it.
      _gapCol = _pickGapColumn();
      _cascadeCol = _pickCascadeColumn(_gapCol);
      _clearRigColumns(
        lesson == TutorialLesson.clearRow
            ? {_gapCol, _gapCol + 1}
            : {_gapCol, _gapCol + 1, _cascadeCol},
      );
      _raiseFloors(
        lesson == TutorialLesson.clearRow ? _clearFloors() : _cascadeFloors(),
      );
    }
  }

  /// A full row of wood with [gaps] left open.
  static List<Cell?> _floor(Set<int> gaps) => List<Cell?>.generate(
    BoardConfig.cols,
    (c) => gaps.contains(c) ? null : Cell(BlockType.wood),
  );

  /// How many blocks stand in [col]: anything a dropped square would land on.
  int _blockersIn(int col) {
    final grid = game.engine.grid;
    var n = 0;
    for (var r = grid.minRow; r <= grid.maxRow; r++) {
      if (grid.isOccupied(r, col)) n++;
    }
    return n;
  }

  /// Picks the left column of the two adjacent columns the rig leaves open.
  /// Chosen against the live board because the player's own pieces may cover
  /// fixed columns, and the square would land on the debris. Emptiest pair
  /// wins, then the one nearest [_preferredGapDistance].
  int _pickGapColumn() {
    final spawn = Tetromino.spawnColumn[TetrominoType.O]!;
    int score(int c) =>
        (_blockersIn(c) + _blockersIn(c + 1)) * 100 +
        ((c - spawn).abs() - _preferredGapDistance).abs();
    var best = 0;
    for (var c = 1; c <= BoardConfig.cols - 2; c++) {
      if (score(c) < score(best)) best = c;
    }
    return best;
  }

  /// The column the cascade's chain runs down: as empty as possible, away from
  /// the two the square fills.
  int _pickCascadeColumn(int gapCol) {
    final taken = {gapCol, gapCol + 1};
    var best = -1;
    for (var c = 0; c < BoardConfig.cols; c++) {
      if (taken.contains(c)) continue;
      if (best < 0 || _blockersIn(c) < _blockersIn(best)) best = c;
    }
    return best < 0 ? 0 : best;
  }

  /// Empties the columns the rig depends on before its floors go up. Usually a
  /// no-op ([_pickGapColumn] seeks bare columns), but it keeps the lesson
  /// solvable when a badly stacked board leaves none: the square and the
  /// cascade's lone block both need a clear run down.
  void _clearRigColumns(Set<int> cols) {
    final grid = game.engine.grid;
    for (var r = grid.minRow; r <= grid.maxRow; r++) {
      for (final c in cols) {
        grid.set(r, c, null);
      }
    }
  }

  /// One row, one square short. The `O` the lesson deals fills it exactly.
  List<List<Cell?>> _clearFloors() => [
    _floor({_gapCol, _gapCol + 1}),
  ];

  /// The three rows that turn one drop into a cascade and a chain, top-most
  /// first (the order they are raised in):
  ///
  /// * a single block, ending two rows above the floor in [_cascadeCol];
  /// * a row short of the square's landing *and* [_cascadeCol], which once the
  ///   bottom row shatters falls a row and lands one column short of complete;
  /// * the bottom row, short only the two columns the square fills.
  ///
  /// The lone block closes the chain: the wave reaches it last and it falls
  /// into the one missing column. Order matters because gravity is a wave
  /// (`ripple_cascade.dart`), so it can't arrive before the row it lands on.
  List<List<Cell?>> _cascadeFloors() => [
    _floor({
      for (var c = 0; c < BoardConfig.cols; c++)
        if (c != _cascadeCol) c,
    }),
    _floor({_gapCol, _gapCol + 1, _cascadeCol}),
    _floor({_gapCol, _gapCol + 1}),
  ];

  /// Orders [floors] up from the bottom of the board.
  void _raiseFloors(List<List<Cell?>> floors) {
    _pendingFloors
      ..clear()
      ..addAll(floors);
    _floorsReady = false;
    _raiseNextFloor();
  }

  /// Sends the next rigged row up, or settles the board once all have landed.
  /// The rise is wound past its grace period and compressed; left alone it
  /// would take twelve seconds for a first row, then twenty-two per row.
  void _raiseNextFloor() {
    final engine = game.engine;
    final rise = engine.riseController;

    if (_pendingFloors.isEmpty) {
      engine.freezeRise = true;
      rise.debugSpeedMultiplier = 1.0;
      _floorsReady = true;
      // The rig shoved the coached piece up; put it back under the prompt.
      if (!_pieceEngaged) engine.pieceController.lowerTo(_coachRow);
      notifyListeners();
      return;
    }

    rise.pendingRow = _pendingFloors.removeAt(0);
    rise.elapsed = Difficulty.riseGracePeriod.inMicroseconds / 1e6 + 1;
    rise.riseProgress = 0.0;
    rise.debugSpeedMultiplier = rise.riseInterval / _riseSeconds;
    engine.freezeRise = false;
  }

  /// Releases the board on the player's first action of this piece.
  void _engagePiece() {
    if (_pieceEngaged) return;
    _pieceEngaged = true;
    game.engine.freezeGravity = false;
  }

  /// A coached piece landed with its lesson unperformed: ask again on the next
  /// piece up to the cap, then let it go.
  void _onMissed(TutorialLesson lesson) {
    final used = _rearms.update(lesson, (n) => n + 1, ifAbsent: () => 1);
    final cap = _isFloorLesson(lesson) ? _maxFloorRearms : _maxRearms;
    if (used <= cap) {
      // A spent rig teaches nothing; raise a fresh one.
      if (_isFloorLesson(lesson)) _floorsRigged = false;
      return;
    }
    AnalyticsService.design('tutorial:gaveup:${lesson.name}');
    _givenUp.add(lesson);
    _done.add(lesson);
    _next();
  }

  void _end() {
    if (_finished) return;
    _finished = true;
    _lesson = null;
    _releaseEngine();
    onFinished();
  }

  /// Hands the run back as found; idempotent, reached from finish, skip and
  /// game over. Deliberately leaves `softDropActive` alone: the soft-drop
  /// lesson ends the instant a drag starts, and cancelling would yank the piece
  /// from under the finger.
  void _releaseEngine() {
    final engine = game.engine;
    engine.freezeGravity = false;
    engine.freezeRise = false;
    // `RiseController.reset` doesn't touch this, so the compressed clock would
    // otherwise deliver rows fifteen times too fast in the real run.
    engine.riseController.debugSpeedMultiplier = 1.0;
  }

  void _onEvent(GameEvent event) {
    if (_finished) return;

    switch (event) {
      case PieceSpawnedEvent():
        _onPieceSpawned();
        notifyListeners();

      // If the player somehow tops out, get out of the game-over overlay's
      // way.
      case GameOverEvent():
        abandon();

      // One rigged floor landed: send the next, or settle.
      case RiseCommittedEvent():
        if (_isFloorLesson(_lesson) && !_floorsReady) _raiseNextFloor();

      // [_floorsReady] guards against the previous lesson's resolve crediting
      // a floor lesson whose rig hasn't been raised.
      case RowsClearedEvent():
        // The shatter itself satisfies the clear lesson; the cascade lesson
        // needs the chain it starts.
        if (_lesson == TutorialLesson.clearRow && _floorsReady) {
          _credit(TutorialLesson.clearRow);
        }

      case ChainAdvancedEvent(:final chainIndex):
        // A non-zero index means this clear was caused by the last one.
        if (_lesson == TutorialLesson.cascadeRow &&
            _floorsReady &&
            chainIndex > 0) {
          _credit(TutorialLesson.cascadeRow);
        }

      case PlayerActionEvent(:final action):
        // Unconditional: whatever the player did, the board should now move.
        _engagePiece();
        switch (action) {
          case PlayerAction.moveLeft || PlayerAction.moveRight:
            if (++_moveCount >= _movesToAdvance) _credit(TutorialLesson.move);
          case PlayerAction.rotate:
            _credit(TutorialLesson.rotate);
          case PlayerAction.hardDrop:
            _credit(TutorialLesson.hardDrop);
          case PlayerAction.softDrop:
            // Never credited ahead of its prompt; see [TutorialLesson].
            if (_lesson == TutorialLesson.softDrop) {
              _credit(TutorialLesson.softDrop);
            }
        }

      default:
        break;
    }
  }
}
