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

/// The four gestures the first run teaches, in the order they are prompted.
///
/// Hard drop before soft drop, and that order is load-bearing: a downward flick
/// enqueues `softDropStart` on its way to `hardDrop`
/// (`gesture_handler.dart:178` then `:189`) and the engine drains both in one
/// pass. Taught the other way round, a single flick would satisfy soft drop and
/// hard drop together and the player would be shown neither.
///
/// [_credit] closes the remaining half of that trap: soft drop is the one
/// lesson that is never credited ahead of its own prompt, so the stray
/// `softDropStart` a flick leaves behind lands on nothing.
enum TutorialLesson { move, rotate, hardDrop, softDrop, clearRow, cascadeRow }

/// Where a coached piece is parked: far enough down to be plainly visible, far
/// enough up to leave the player somewhere to drop it.
const _coachRow = 4;

/// Column moves needed to clear the `move` lesson. Two is enough to show the
/// piece tracking the finger without turning the prompt into a chore.
const _movesToAdvance = 2;

/// How many extra pieces a missed lesson gets before it is dropped.
///
/// A player who lets gravity land the piece, or who flicks when asked to drag,
/// gets the same prompt on the next piece. Twice, and then the tutorial stops
/// asking — being nagged by a prompt you cannot work out is worse than not
/// being taught the gesture at all, and Skip is not always found.
const _maxRearms = 2;

/// The floor lessons get one retry rather than two. Each retry raises a fresh
/// rig — one row for the clear, three for the cascade — and those stack on top
/// of everything the player has already dropped.
const _maxFloorRearms = 1;

/// How far from the square's spawn column the rigged gap is aimed.
///
/// Far enough that the lesson asks for the movement it just taught, close
/// enough that it is two or three swipes rather than a trek.
const _preferredGapDistance = 4;

/// How long one rigged floor takes to climb into place.
///
/// The real interval is 22 seconds at the opening checkpoint
/// (`difficulty.dart`) — the right pace for a run, and far too slow to hold a
/// player's attention while a floor arrives.
const _riseSeconds = 1.5;

/// Drives the first-run tutorial: one uninterrupted gameplay session with a
/// looping gesture hint and a word or two floating over the board.
///
/// It draws no modals, wipes nothing, rigs nothing and never restarts the run.
/// The session the player is coached through simply *is* their first run — at
/// the end the prompts stop, the rise is released, and nothing on screen
/// changes.
///
/// A `ChangeNotifier` rather than the hand-rolled listener lists across
/// `lib/game/engine/`: those exist because the engine deliberately has no
/// Flutter import. This is a UI-layer step machine consumed by a
/// `ListenableBuilder`, so the standard primitive is the right one.
class TutorialController extends ChangeNotifier {
  TutorialController({
    required this.game,
    required this.storage,
    required this.onFinished,
  }) {
    game.engine.addEventListener(_onEvent);
    // Written on the way in, not on the way out: the tutorial has been shown
    // the moment it appears, and a player who force-quits partway through
    // should not be met by it again on the next launch.
    storage.saveTutorialSeen(true);
    // The GA4 counterpart to `tutorial_complete`, for Google Ads rather than
    // the dashboard: together they are the earliest quality signal a new
    // install produces, and this one fires within seconds of first open.
    FirebaseAnalyticsService.logTutorialBegin();

    // The rise stays out of the way for the whole session. Because
    // `RiseController.elapsed` only advances while unfrozen, releasing it in
    // [_releaseEngine] hands the real run its full grace period untouched.
    final engine = game.engine;
    engine.freezeRise = true;
    // Nothing is dealt from here. This runs from the host widget's `initState`,
    // and Flame's `onLoad` has not called `GameEngine.start` yet — which clears
    // `_scriptedPieces` (`game_engine.dart:162`), so a piece queued now would
    // be thrown away before it could be spawned. The coach piece is dealt on
    // the first spawn instead, in [_onPieceSpawned].
    engine.freezeGravity = true;
    _arm(TutorialLesson.move);
  }

  final TetrofallGame game;
  final StorageService storage;

  /// Called once, on completion or skip, after the engine has been released.
  /// The host screen uses it to open a tracked run over this same session.
  final VoidCallback onFinished;

  /// The prompt currently on screen. Null once the tutorial has run out of
  /// lessons, which is also the frame it finishes on.
  TutorialLesson? _lesson;
  TutorialLesson? get lesson => _lesson;

  /// Lessons the player has already performed — including ones they did before
  /// being asked, which is why [_next] skips rather than re-prompts.
  final _done = <TutorialLesson>{};

  final _rearms = <TutorialLesson, int>{};

  /// Lessons the tutorial stopped asking for — in [_done] so they are skipped,
  /// but tracked apart from it so the closing report can tell a player who
  /// learned every gesture from one who was let off a couple.
  final _givenUp = <TutorialLesson>{};

  int _moveCount = 0;
  bool _finished = false;

  /// Which lesson was showing when the current piece spawned.
  ///
  /// A missed lesson is detected at the *next* spawn rather than on
  /// [PieceLockedEvent], and this is why. Hard drop credits itself from the
  /// same drain that locks the piece (`game_engine.dart:265-267`), so a
  /// lock-driven check would see the freshly armed soft-drop prompt and score
  /// it as missed before the player had been shown it once.
  TutorialLesson? _lessonAtSpawn;

  /// Whether the active piece has seen any input yet.
  ///
  /// Gravity is frozen on spawn and released by the player's first action,
  /// whatever it was — so a coached piece hangs perfectly still until it is
  /// touched, and then falls normally for the rest of its life. The freeze is
  /// per piece, not per prompt: once the player has engaged, no later prompt
  /// stops the board again.
  bool _pieceEngaged = false;

  /// Floors still waiting to be pushed up for the current lesson, bottom-most
  /// last: [commitRise] inserts at the floor and shoves everything above it up,
  /// so the first row raised ends up highest.
  final _pendingFloors = <List<Cell?>>[];

  /// Whether this lesson's floors have been ordered up yet. Cleared by [_arm],
  /// so a lesson that re-arms after a miss raises a fresh rig.
  bool _floorsRigged = false;

  /// The columns the current rig left open, chosen against the live board in
  /// [_pickGapColumns] each time a rig goes up.
  int _gapCol = 0;
  int _cascadeCol = 0;

  /// Whether they have all arrived. The prompt stays off until they have —
  /// asking someone to fill a row that is still sliding into place is asking
  /// them to aim at a moving target.
  bool _floorsReady = false;

  bool _boardTouched = false;

  /// Whether a finger is currently on the board. Mid-gesture the player is
  /// looking at the board rather than reading over it, so the prompt fades
  /// down until the touch ends.
  bool get boardTouched => _boardTouched;

  /// Whether the tutorial has run its course, by any route.
  bool get isFinished => _finished;

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

  // ---------------------------------------------------------------- content

  /// Whether this lesson is a floor lesson whose rig is still on its way up.
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
          // Both floor lessons are a steering problem: the piece already fits,
          // it just has to be over the gap.
          TutorialLesson.clearRow ||
          TutorialLesson.cascadeRow => TutorialHint.swipeHorizontal,
          null => TutorialHint.none,
        };

  /// The whole text of the tutorial. One or two words, naming what the gesture
  /// does rather than what it is — the animation underneath the label is
  /// already saying what it is.
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

  /// Horizontal alignment of the rigged gap, or null when there is no gap to
  /// point at. The overlay marks it, because "fill the row" is only actionable
  /// once you can see *where*.
  ///
  /// Both rigs leave the same two-wide opening, so the marker sits on the
  /// boundary between its two columns.
  double? get gapAlignX => _floorsPending || !_isFloorLesson(_lesson)
      ? null
      : (_gapCol + 1) / BoardConfig.cols * 2 - 1;

  /// Where the prompt sits inside the board, as an `Alignment` y.
  ///
  /// Derived from the row a coached piece is parked on rather than eyeballed,
  /// and offset a few rows below it: close enough to read as pointing at the
  /// piece, clear enough not to sit on top of it.
  double get hintAlignY => (_coachRow + 4) / BoardConfig.rows * 2 - 1;

  // ------------------------------------------------------------ transitions

  void skip() {
    AnalyticsService.design('tutorial:skip:${_lesson?.name ?? 'done'}');
    _end();
  }

  /// Ends the tutorial without handing off — used when the run has already
  /// ended underneath it and the game-over overlay owns the screen.
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
    // A finger that was down when the board changed under it never reports
    // lifting, and a prompt left faded would stay unreadable from here on.
    _boardTouched = false;
    // A new lesson brings its own floors, if it has any.
    _floorsRigged = false;
    _floorsReady = false;
  }

  /// Marks [lesson] done and, if it was the one on screen, moves on.
  ///
  /// Credit is given even for a gesture performed before it was asked for —
  /// a player who works out rotation on their own should not then be told to
  /// rotate. [_next] skips anything already in [_done].
  void _credit(TutorialLesson lesson) {
    if (!_done.add(lesson)) return;
    if (_lesson == lesson) _next();
  }

  /// Advances to the next lesson the player has not already performed, or ends
  /// the tutorial if there is none.
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
    // Only a player who actually performed every gesture completed it. A
    // lesson the tutorial gave up on (see [_onMissed]) still gets the player to
    // the live run, but scoring it as a completion would make this number an
    // exit rate dressed up as a success rate.
    AnalyticsService.design(
      _givenUp.isEmpty ? 'tutorial:complete' : 'tutorial:partial',
    );
    // GA4's `tutorial_complete` does fire either way. It is the signal Google
    // Ads bids on, and what it means there is "this install reached the game",
    // which a player who skipped one gesture has still done.
    FirebaseAnalyticsService.logTutorialComplete();
    _lesson = null;
    _end();
  }

  /// Settles the piece that just spawned, and closes the books on the one
  /// before it.
  ///
  /// Pieces spawn at `grid.minRow` — two rows above the top of the board — and
  /// only ordinary gravity carries them into view. A coached piece is frozen
  /// on arrival, so without the [lowerTo] here the player would be asked to
  /// steer something drawn off-screen.
  void _onPieceSpawned() {
    final engine = game.engine;

    // Close the books on the piece that just ended: if the lesson showing when
    // it spawned is still showing now, the player had a whole piece to do it
    // on and didn't.
    final stale = _lessonAtSpawn;
    _lessonAtSpawn = null;
    if (stale != null && stale == _lesson) _onMissed(stale);

    final lesson = _lesson;
    if (lesson == null) return;

    // A rotation prompt needs a piece that visibly rotates. An O's four
    // rotation states are identical (`tetromino.dart:37-42`), so `Rotate` over
    // one would show the player precisely nothing happening — and `move`
    // counts here too, because `rotate` follows it on that same piece.
    //
    // This is also where the opening piece is dealt. It cannot be queued from
    // the constructor: that runs in the host widget's `initState`, before
    // Flame's `onLoad` calls `GameEngine.start`, which clears `_scriptedPieces`
    // (`game_engine.dart:162`). The piece being replaced is still up in the
    // hidden spawn buffer and has never been drawn, so the swap is invisible;
    // and because the swap queues a T explicitly, it can never repeat.
    if ((lesson == TutorialLesson.move || lesson == TutorialLesson.rotate) &&
        engine.pieceController.piece?.type == TetrominoType.O) {
      engine.queuePieces([TetrominoType.T]);
      engine.respawnPiece();
      return;
    }

    // The floor lessons want the opposite piece, for the opposite reason: both
    // rigs leave a two-wide gap, and an `O` is the one piece that fills it
    // whatever way up it is turned.
    if (_isFloorLesson(lesson) &&
        engine.pieceController.piece?.type != TetrominoType.O) {
      engine.queuePieces([TetrominoType.O]);
      engine.respawnPiece();
      return;
    }

    _lessonAtSpawn = lesson;
    // Per piece, not per prompt: a lesson that re-arms on a later piece is
    // never carried there half-satisfied.
    _moveCount = 0;
    _pieceEngaged = false;
    engine.freezeGravity = true;
    engine.pieceController.lowerTo(_coachRow);

    // Ordered once per arming, from here rather than [_arm], so the floors
    // start climbing against a piece that is already parked and waiting.
    if (_isFloorLesson(lesson) && !_floorsRigged) {
      _floorsRigged = true;
      // Picked now, against the board as it actually stands — everything the
      // player has already dropped is still on it.
      final (gap, _) = _pickGapColumns();
      _gapCol = gap;
      _cascadeCol = _pickCascadeColumn(gap);
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

  // ------------------------------------------------------------------ floors

  /// A full row of wood with [gaps] left open.
  static List<Cell?> _floor(Set<int> gaps) => List<Cell?>.generate(
    BoardConfig.cols,
    (c) => gaps.contains(c) ? null : Cell(BlockType.wood),
  );

  /// How many blocks stand in [col] — anything a dropped square would land on
  /// before reaching the floor.
  int _blockersIn(int col) {
    final grid = game.engine.grid;
    var n = 0;
    for (var r = grid.minRow; r <= grid.maxRow; r++) {
      if (grid.isOccupied(r, col)) n++;
    }
    return n;
  }

  /// Picks the two adjacent columns the rig will leave open.
  ///
  /// Chosen against the live board rather than fixed, and that is the whole
  /// point: fixed columns were safe only while each lesson wiped the board
  /// first. They are not now — by the cascade the board is carrying the clear
  /// lesson's leftovers *and* four pieces the player placed wherever they
  /// liked, and a gap underneath any of that is a gap the square can never
  /// reach. It lands on the debris and the chain never fires.
  ///
  /// Emptiest pair wins, and only then the one nearest [_preferredGapDistance]
  /// — so the lesson still asks for the movement it just taught whenever it
  /// can, and [_clearRigColumns] has as little to tidy as possible.
  (int, int) _pickGapColumns() {
    final spawn = Tetromino.spawnColumn[TetrominoType.O]!;
    int score(int c) =>
        (_blockersIn(c) + _blockersIn(c + 1)) * 100 +
        ((c - spawn).abs() - _preferredGapDistance).abs();
    var best = 0;
    for (var c = 1; c <= BoardConfig.cols - 2; c++) {
      if (score(c) < score(best)) best = c;
    }
    return (best, best + 1);
  }

  /// Picks the column the cascade's chain runs down: as empty as possible, and
  /// well away from the two the square is going to fill.
  int _pickCascadeColumn(int gapCol) {
    final taken = {gapCol, gapCol + 1};
    var best = -1;
    for (var c = 0; c < BoardConfig.cols; c++) {
      if (taken.contains(c)) continue;
      if (best < 0 || _blockersIn(c) < _blockersIn(best)) best = c;
    }
    return best < 0 ? 0 : best;
  }

  /// Empties the columns the rig depends on, right before its floors go up.
  ///
  /// Insurance, and usually a no-op — [_pickGapColumns] goes looking for
  /// columns that are already bare. When it cannot find any, this is what keeps
  /// the lesson solvable: the square needs a clear run to the floor, and the
  /// cascade's lone block needs a clear run into the gap below it. Without it a
  /// player who stacked badly during the gesture lessons gets a rig they cannot
  /// complete and a prompt they cannot dismiss.
  ///
  /// It costs a handful of the player's own blocks, which is far less than the
  /// whole-board wipe the modal tutorial did between every lesson, and it lands
  /// under cover of the floors rising.
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

  /// The three rows that turn one drop into a cascade and a chain.
  ///
  /// Read together they are a small machine, and every column in it is
  /// load-bearing. Listed top-most first, because that is the order they have
  /// to be *raised* in — each rise inserts at the floor and shoves the previous
  /// one up:
  ///
  /// * a single block, which ends up two rows above the floor in
  ///   [_cascadeGapCol];
  /// * a row short of the square's landing *and* [_cascadeGapCol], so that once
  ///   the bottom row shatters it is released, falls a row, and lands one
  ///   column short of complete;
  /// * the bottom row, short only the two columns the square fills, so the drop
  ///   completes it exactly as the last lesson did.
  ///
  /// The lone block is what closes the chain: the wave reaches it last, it
  /// falls into the one column still missing, and that completes the row.
  ///
  /// The order matters because gravity here is a wave, not a collapse
  /// (`ripple_cascade.dart`): rows are released one at a time from the clear
  /// upward, so the lone block cannot arrive before the row it lands on.
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

  /// Sends the next rigged row up, or settles the board once they have all
  /// landed.
  ///
  /// The rise is wound forward past its grace period and compressed, the same
  /// trick the old rise demo used: left alone it would not deliver a first row
  /// for another twelve seconds, and then only every twenty-two.
  void _raiseNextFloor() {
    final engine = game.engine;
    final rise = engine.riseController;

    if (_pendingFloors.isEmpty) {
      engine.freezeRise = true;
      rise.debugSpeedMultiplier = 1.0;
      _floorsReady = true;
      // The rig shoved the coached piece up a row per floor. Put it back where
      // the prompt is pointing.
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

  /// A coached piece has landed with its lesson unperformed. Ask once more on
  /// the next piece, up to [_maxRearms], then let the lesson go.
  void _onMissed(TutorialLesson lesson) {
    final used = _rearms.update(lesson, (n) => n + 1, ifAbsent: () => 1);
    final cap = _isFloorLesson(lesson) ? _maxFloorRearms : _maxRearms;
    if (used <= cap) {
      // A spent rig teaches nothing on the second attempt — the row it asked
      // the player to fill is either gone or already ruined. Raise a fresh one.
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

  /// Hands the run back exactly as it was found. Idempotent, and reached from
  /// every exit — finishing, skipping, and a game over underneath.
  ///
  /// Pointedly does *not* clear `softDropActive`, which the modal version of
  /// this tutorial had to: its panels applied `IgnorePointer`, so a drag in
  /// progress never got its matching pointer-up. Nothing here blocks the
  /// board, and the soft-drop lesson ends the session the instant the drag
  /// starts — cancelling it would yank the piece out from under the finger
  /// that is still holding it down.
  void _releaseEngine() {
    final engine = game.engine;
    engine.freezeGravity = false;
    engine.freezeRise = false;
    // `RiseController.reset` does not touch this, so a floor lesson's
    // compressed clock would otherwise follow the player into their first run
    // and deliver rows fifteen times too fast.
    engine.riseController.debugSpeedMultiplier = 1.0;
  }

  // ----------------------------------------------------------------- events

  void _onEvent(GameEvent event) {
    if (_finished) return;

    switch (event) {
      case PieceSpawnedEvent():
        _onPieceSpawned();
        notifyListeners();

      // A coached session should be unloseable, but if the player somehow tops
      // out, get out of the way rather than float a prompt over the game-over
      // overlay.
      case GameOverEvent():
        abandon();

      // One rigged floor has landed. Send the next, or settle and let the
      // prompt come up.
      case RiseCommittedEvent():
        if (_isFloorLesson(_lesson) && !_floorsReady) _raiseNextFloor();

      // Both floor lessons require their own rig to have landed first, which
      // the [_floorsReady] guard is doing. Without it the lesson can be
      // satisfied by the *previous* lesson's resolve and skipped entirely:
      // a stacked pair of rigged rows clears two rows at once, that cascades
      // into a chain, and the chain credits a cascade lesson whose floors have
      // not been raised — so the player is never shown the thing it teaches.
      case RowsClearedEvent():
        // The clear lesson is satisfied by the shatter itself. The cascade
        // lesson is not — its first clear is only the thing that *starts* the
        // chain, and the chain is what it is teaching.
        if (_lesson == TutorialLesson.clearRow && _floorsReady) {
          _credit(TutorialLesson.clearRow);
        }

      case ChainAdvancedEvent(:final chainIndex):
        // A non-zero index is exactly "this clear was caused by the last one",
        // which is the thing being taught.
        if (_lesson == TutorialLesson.cascadeRow &&
            _floorsReady &&
            chainIndex > 0) {
          _credit(TutorialLesson.cascadeRow);
        }

      case PlayerActionEvent(:final action):
        // Before the credit below, and unconditionally: whatever the player
        // just did, the piece is theirs now and the board should be moving.
        _engagePiece();
        switch (action) {
          case PlayerAction.moveLeft || PlayerAction.moveRight:
            if (++_moveCount >= _movesToAdvance) _credit(TutorialLesson.move);
          case PlayerAction.rotate:
            _credit(TutorialLesson.rotate);
          case PlayerAction.hardDrop:
            _credit(TutorialLesson.hardDrop);
          case PlayerAction.softDrop:
            // The one lesson never credited ahead of its prompt — see the note
            // on [TutorialLesson]. A flick's stray `softDropStart` arrives
            // while some earlier lesson is showing, and lands on nothing.
            if (_lesson == TutorialLesson.softDrop) {
              _credit(TutorialLesson.softDrop);
            }
        }

      default:
        break;
    }
  }
}
