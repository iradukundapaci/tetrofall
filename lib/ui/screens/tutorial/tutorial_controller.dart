import 'dart:async';

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

/// How a step presents itself.
enum TutorialMode {
  /// Board dimmed behind a centred panel the player reads and dismisses.
  /// Reuses gameplay's existing dim treatment, which also blocks board
  /// touches correct here, since these steps ask for a button press.
  modal,

  /// Board live and fully touchable, with a caption and a looping hint
  /// floating over it. The player advances it by *doing* the thing.
  coach,
}

/// Where a coach step is in its own little arc.
///
/// The split exists because the engine announces an *intent*, not its
/// consequences `PlayerActionEvent(hardDrop)` is emitted before
/// `pieceController.hardDrop()` even runs (`game_engine.dart:258-259`), and
/// `PlayerAction.softDrop` the instant the drag crosses its threshold, long
/// before the piece has fallen anywhere. Advancing straight off those events
/// swapped the card out before the player had seen a single thing happen.
enum TutorialPhase { prompt, effect }

/// Which hint animation plays over the board, if any.
enum TutorialHint { none, swipeHorizontal, tap, dragDown, flickDown }

/// The order is load-bearing, and hard drop coming before soft drop is the
/// part that matters.
///
/// A downward flick enqueues `softDropStart` on its way to `hardDrop`
/// (`gesture_handler.dart:178` then `:189`) and the engine drains both in one
/// pass. Taught in the other order, a single flick would satisfy the soft-drop
/// step and then immediately satisfy the hard-drop step behind it, and the
/// player would never read either card. This way the stray `softDropStart`
/// lands on a step that is not listening for it and is harmlessly ignored.
enum TutorialStep {
  intro,
  move,
  rotate,
  hardDrop,
  softDrop,
  clearIntro,
  clearRow,
  cascadeIntro,
  cascadeRow,
  riseIntro,
  riseWatch,
  done,
}

/// Where the tutorial's rigged row leaves its gap. Off-centre on purpose: an
/// `O` spawns over columns 8–9 of 18, so a gap here costs four swipes right
/// and puts the movement the player was just taught straight to work.
const _clearGapCol = 12;

/// The column the cascade rig leaves open in its second row, and the column
/// the lone block two rows up is parked in. They are the same column, and that
/// is the whole trick see [TutorialController._rigCascade].
const _cascadeGapCol = 3;

/// Column moves needed to clear the `move` step. Two is enough to show the
/// piece tracking the finger without turning the step into a chore.
const _movesToAdvance = 2;

/// Where a coached piece is parked: far enough down to be plainly visible,
/// far enough up to leave the player somewhere to drop it.
const _coachRow = 4;

/// How long a satisfied step stays on screen while its effect plays out.
///
/// A gesture whose whole point is instant gets a beat just long enough to read
/// the confirmation; one that has to travel gets long enough to travel.
const _holdShort = Duration(milliseconds: 700);
const _holdLand = Duration(milliseconds: 900);

/// Long enough for the piece to visibly cover ground. Soft drop divides the
/// drop interval by `Motion.softDropDivisor`, so nearly two seconds of it
/// reads unmistakably as *faster, but still steerable*.
const _holdSoftDrop = Duration(milliseconds: 1800);

/// Past the end of a single row's shatter, which runs about 940ms
/// (`Motion.crackHold` + half a board of `shatterStep` + `shatterBeat`).
const _holdClear = Duration(milliseconds: 1400);
const _holdRise = Duration(milliseconds: 1400);

/// The chain's own shatter, once the cascade has finished delivering it.
const _holdChain = Duration(milliseconds: 1600);

/// How long the cascade step will wait for a chain that should arrive in
/// under three. Only a safety net: the rig is deterministic, but a step whose
/// exit condition can no longer happen is a step the player is stuck on.
const _cascadeFallback = Duration(seconds: 5);

/// How long the demo rise takes to climb one whole row. The real interval is
/// 22 seconds at the opening checkpoint (`difficulty.dart:26`) the right
/// pace for a run, and far too slow to hold a caption on screen.
const _riseDemoSeconds = 4.0;

/// Drives the first-run coached tutorial owns which step is showing,
/// freezes and unfreezes the run around each one, and rigs the board for the
/// row-clearing lesson.
///
/// A `ChangeNotifier` rather than the hand-rolled listener lists used across
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
    // The opening step is set as a field initialiser and so never passes
    // through [_goTo] without this the funnel would have no entry count to
    // measure the later steps against.
    AnalyticsService.design('tutorial:step:${_step.name}');
    // The GA4 counterpart, for Google Ads rather than the dashboard: paired
    // with `tutorial_complete` below it is the earliest quality signal a new
    // install produces, and it fires within a minute of first open.
    FirebaseAnalyticsService.logTutorialBegin();
    _applyStep();
  }

  final TetrofallGame game;
  final StorageService storage;

  /// Called once, on completion or skip, after the engine has been released.
  /// The host screen uses it to hand off into a clean scored run.
  final VoidCallback onFinished;

  TutorialStep _step = TutorialStep.intro;
  TutorialStep get step => _step;

  TutorialPhase _phase = TutorialPhase.prompt;
  TutorialPhase get phase => _phase;

  int _moveCount = 0;
  bool _finished = false;

  /// Set when the hard-drop step sees the *intent*, so the lock that follows
  /// can be told apart from any other piece coming to rest.
  bool _dropSeen = false;

  /// Runs out the [TutorialPhase.effect] beat before the next step is entered.
  Timer? _holdTimer;

  bool _boardTouched = false;

  /// Whether a finger is currently on the board. Mid-gesture the player is
  /// looking at the board rather than reading about it, so the chrome fades
  /// down until the touch ends.
  bool get boardTouched => _boardTouched;

  /// Whether the tutorial has run its course, by any route.
  bool get isFinished => _finished;

  @override
  void dispose() {
    _holdTimer?.cancel();
    game.engine.removeEventListener(_onEvent);
    super.dispose();
  }

  void setBoardTouched(bool touched) {
    if (_finished || _boardTouched == touched) return;
    _boardTouched = touched;
    notifyListeners();
  }

  // ---------------------------------------------------------------- content

  TutorialMode get mode => switch (_step) {
    TutorialStep.intro ||
    TutorialStep.clearIntro ||
    TutorialStep.cascadeIntro ||
    TutorialStep.riseIntro ||
    TutorialStep.done => TutorialMode.modal,
    _ => TutorialMode.coach,
  };

  /// Whether gameplay should dim behind the tutorial. Never true on a coach
  /// step: dimming also applies `IgnorePointer`, which would swallow the very
  /// gestures the step is teaching.
  bool get dimsBoard => mode == TutorialMode.modal;

  String get title => switch (_step) {
    TutorialStep.intro => 'HOW TO PLAY',
    TutorialStep.clearIntro => 'CLEARING ROWS',
    TutorialStep.cascadeIntro => 'THE CASCADE',
    TutorialStep.riseIntro => 'THE RISE',
    TutorialStep.done => "YOU'RE READY",
    _ => '',
  };

  String get body =>
      _phase == TutorialPhase.effect ? _confirmation : _instruction;

  String get _instruction => switch (_step) {
    TutorialStep.intro =>
      'Blocks fall from the top. New rows push up from the bottom.\n\n'
          'Complete a row to clear it and buy back space.',
    TutorialStep.move => 'Swipe left or right to move the piece.',
    TutorialStep.rotate => 'Tap the board to rotate it.',
    TutorialStep.hardDrop => 'Flick down hard to slam it into place.',
    TutorialStep.softDrop => 'Or hold and drag down to fall at your own pace.',
    TutorialStep.clearIntro =>
      'This is how you survive. Fill a row all the way across and it '
          'shatters.',
    TutorialStep.clearRow => 'Two gaps left. Drop the square in to clear it.',
    TutorialStep.cascadeIntro =>
      'Blocks only fall when a row clears.\n\n'
          'Clear one and everything above drops into the space and if that '
          'fills another row, it goes too.',
    TutorialStep.cascadeRow => 'Same gap. Drop it in and watch the stack fall.',
    TutorialStep.riseIntro =>
      'New rows push up from below, faster the longer you last.\n\n'
          'If the stack reaches the top, the run is over.',
    TutorialStep.riseWatch => 'Here it comes clear rows to hold it back.',
    TutorialStep.done => 'Good luck.',
  };

  /// What the caption says while the board is showing its work. Naming what
  /// just happened is the whole reason the beat exists a card that simply
  /// froze for a second would read as a stall.
  String get _confirmation => switch (_step) {
    TutorialStep.move => 'It follows your finger.',
    TutorialStep.rotate => "That's a rotation.",
    TutorialStep.hardDrop => 'Slam. Straight to the floor.',
    TutorialStep.softDrop => 'Slower and you stay in control.',
    TutorialStep.clearRow => 'Row cleared.',
    TutorialStep.cascadeRow => 'Chain! The falling stack finished another row.',
    TutorialStep.riseWatch => "That's the rise. Clear rows to hold it back.",
    _ => _instruction,
  };

  /// Null on coach steps, which have no button the gesture is the button.
  String? get buttonLabel => switch (_step) {
    TutorialStep.intro => "Let's Go",
    TutorialStep.clearIntro ||
    TutorialStep.cascadeIntro ||
    TutorialStep.riseIntro => 'Continue',
    TutorialStep.done => 'Play',
    _ => null,
  };

  /// Which end of the board the caption hides always the end the player is
  /// *not* being asked to look at.
  ///
  /// It defaults to the bottom, where nothing is happening while the piece
  /// hovers up top. The two steps that are about the floor the rigged row,
  /// and the rise pushing in beneath it start at the top instead, and the
  /// two drop steps change ends the moment the piece sets off, so the card is
  /// never sitting on the landing the player was told to watch.
  bool get captionAtTop => switch (_step) {
    TutorialStep.clearRow ||
    TutorialStep.cascadeRow ||
    TutorialStep.riseWatch => true,
    TutorialStep.hardDrop ||
    TutorialStep.softDrop => _phase == TutorialPhase.effect,
    _ => false,
  };

  TutorialHint get hint => _phase == TutorialPhase.effect
      ? TutorialHint.none
      : switch (_step) {
          TutorialStep.move => TutorialHint.swipeHorizontal,
          TutorialStep.rotate => TutorialHint.tap,
          TutorialStep.hardDrop => TutorialHint.flickDown,
          TutorialStep.softDrop => TutorialHint.dragDown,
          _ => TutorialHint.none,
        };

  /// Where the looping hint sits inside the board, as an `Alignment` y.
  ///
  /// Derived from the row a coached piece is parked on rather than eyeballed,
  /// and offset a few rows below it: close enough to read as pointing at the
  /// piece, clear enough not to sit on top of it.
  double get hintAlignY => (_coachRow + 4) / BoardConfig.rows * 2 - 1;

  // ------------------------------------------------------------ transitions

  /// Advances a modal step. Coach steps ignore it they advance on events.
  void advance() {
    if (mode != TutorialMode.modal) return;
    if (_step == TutorialStep.done) {
      // The only genuine completion: tapping through the closing step. Every
      // other exit Skip, or a top-out underneath the coach also lands in
      // [_end] and then in the host screen's hand-off, so reporting from
      // there would score a skip as a completion and read 100% forever.
      AnalyticsService.design('tutorial:complete');
      FirebaseAnalyticsService.logTutorialComplete();
      _end();
      return;
    }
    _goTo(TutorialStep.values[_step.index + 1]);
  }

  void skip() {
    AnalyticsService.design('tutorial:skip:${_step.name}');
    _end();
  }

  /// Ends the tutorial without asking for a hand-off restart used when the
  /// run has already ended underneath it and the game-over overlay owns the
  /// screen.
  void abandon() {
    if (_finished) return;
    AnalyticsService.design('tutorial:abandon:${_step.name}');
    _finished = true;
    _releaseEngine();
    notifyListeners();
  }

  /// Marks the current coach step done and lets the board finish saying so
  /// before [next] takes over.
  void _satisfy(TutorialStep next, Duration hold) {
    if (_phase == TutorialPhase.effect) return;
    _phase = TutorialPhase.effect;
    notifyListeners();
    _armHold(next, hold);
  }

  void _armHold(TutorialStep next, Duration hold) {
    _holdTimer?.cancel();
    _holdTimer = Timer(hold, () {
      _holdTimer = null;
      if (_finished) return;
      // A beat that ripens behind the pause menu would advance a step the
      // player cannot see the host screen drops the overlay while paused
      // (`gameplay_screen.dart:321-325`). Wait the pause out instead.
      if (game.paused) {
        _armHold(next, const Duration(milliseconds: 200));
        return;
      }
      _goTo(next);
    });
  }

  void _goTo(TutorialStep next) {
    // The per-step drop-off funnel. [TutorialStep] is a closed enum, so this
    // is a fixed set of ids however the tutorial is navigated.
    AnalyticsService.design('tutorial:step:${next.name}');
    _holdTimer?.cancel();
    _holdTimer = null;
    _step = next;
    _phase = TutorialPhase.prompt;
    _moveCount = 0;
    _dropSeen = false;
    // Same reason the soft drop is cleared below: a finger that was down
    // when a modal step took over never reports lifting, and a caption left
    // faded would stay unreadable for the rest of the tutorial.
    _boardTouched = false;
    _applyStep();
    notifyListeners();
  }

  /// Everything a step needs done to the run on the way in.
  void _applyStep() {
    final engine = game.engine;

    // A drag still in progress when its step ends never gets its matching
    // `softDropEnd`: the modal that follows applies `IgnorePointer`, so the
    // pointer-up never reaches the board's `Listener`. Left set, it would
    // quietly run the next lesson's piece at seven times gravity.
    if (_step != TutorialStep.softDrop) {
      engine.pieceController.softDropActive = false;
    }

    // Soft drop is a no-op against frozen gravity it only divides an
    // interval that is not being counted so its step is the one that has to
    // let the clock run. The rigged clear needs it too, so that a player who
    // never drops the square still gets there eventually.
    //
    // The rise demo deliberately does *not*: gravity and the rise tick
    // independently (`game_engine.dart:181-190`), and a piece drifting down
    // the middle of the board is competing with the one thing the step is
    // asking the player to watch.
    engine.freezeGravity = switch (_step) {
      TutorialStep.softDrop ||
      TutorialStep.clearRow ||
      TutorialStep.cascadeRow => false,
      _ => true,
    };
    engine.freezeRise = _step != TutorialStep.riseWatch;

    switch (_step) {
      case TutorialStep.move:
        // Deal a T for the gesture lessons rather than take whatever the bag
        // offers: an O's four rotation states are identical
        // (`tetromino.dart:37-42`), so a rotate step taught on one would show
        // the player precisely nothing happening.
        engine.queuePieces([TetrominoType.T]);
        engine.respawnPiece();
      case TutorialStep.clearRow:
        _rigClearRow();
      case TutorialStep.cascadeRow:
        _rigCascade();
      case TutorialStep.riseWatch:
        _rigRiseDemo();
        _startRiseDemo();
      default:
        break;
    }
  }

  /// Brings a just-spawned piece down out of the hidden spawn buffer.
  ///
  /// Pieces spawn at `grid.minRow` two rows above the top of the board —
  /// and only ordinary gravity carries them into view. The coach steps switch
  /// gravity off, so without this the player would be asked to steer
  /// something drawn off-screen.
  void _showSpawnedPiece() {
    if (!game.engine.freezeGravity) return;
    game.engine.pieceController.lowerTo(_coachRow);
  }

  /// Wipes whatever the practice drops left behind and lays out a bottom row
  /// that is one square short, then deals the square that fits it.
  ///
  /// The board changes in the same frame the `clearIntro` panel is dismissed,
  /// so the swap reads as the next scene rather than as blocks appearing out
  /// of nowhere.
  void _rigClearRow() {
    final engine = game.engine;
    game.boardOrNull?.resetForRestart();
    engine.grid.clearAll();
    final bottom = engine.grid.maxRow;
    for (var col = 0; col < BoardConfig.cols; col++) {
      if (col == _clearGapCol || col == _clearGapCol + 1) continue;
      engine.grid.set(bottom, col, Cell(BlockType.wood));
    }
    engine.queuePieces([TetrominoType.O]);
    engine.respawnPiece();
  }

  /// Lays out the three rows that turn one drop into a cascade and a chain.
  ///
  /// Read together they are a small machine, and every column in it is load-
  /// bearing:
  ///
  /// * the bottom row is short only the two columns the square fills, so the
  ///   drop completes it exactly as the last lesson did;
  /// * the row above is short those two *and* [_cascadeGapCol], so once the
  ///   bottom row shatters it is released, falls a row, and lands one column
  ///   short of complete;
  /// * a single block sits two rows up in [_cascadeGapCol] the wave reaches
  ///   it last, it falls into the one column still missing, and that completes
  ///   the row and chains.
  ///
  /// The order matters because gravity here is a wave, not a collapse
  /// (`ripple_cascade.dart`): rows are released one at a time from the clear
  /// upward, so the lone block cannot arrive before the row it lands on.
  void _rigCascade() {
    final engine = game.engine;
    game.boardOrNull?.resetForRestart();
    engine.grid.clearAll();
    final bottom = engine.grid.maxRow;
    for (var col = 0; col < BoardConfig.cols; col++) {
      // The square's own landing, left open all the way down.
      if (col == _clearGapCol || col == _clearGapCol + 1) continue;
      engine.grid.set(bottom, col, Cell(BlockType.wood));
      if (col != _cascadeGapCol) {
        engine.grid.set(bottom - 1, col, Cell(BlockType.wood));
      }
    }
    engine.grid.set(bottom - 2, _cascadeGapCol, Cell(BlockType.wood));
    engine.queuePieces([TetrominoType.O]);
    engine.respawnPiece();
  }

  /// Gap columns for the two rows the rise demo shoves upward. Both rows are
  /// deliberately short of complete, so nothing here clears itself.
  static const _riseRigGaps = <List<int>>[
    [5, 6, 13],
    [2, 9, 10, 14],
  ];

  /// Leaves a short stack for the rise to push against.
  ///
  /// The clear lesson ends with an empty board, and a single row arriving on
  /// an empty board looks like a row arriving on an empty board nothing
  /// like the thing that ends runs. Two ragged rows above it turn the same
  /// commit into a visible shove.
  void _rigRiseDemo() {
    final grid = game.engine.grid;
    for (var i = 0; i < _riseRigGaps.length; i++) {
      final row = grid.maxRow - i;
      if (row < 0) break;
      for (var col = 0; col < BoardConfig.cols; col++) {
        // Written either way rather than skipping the gaps: the clear lesson
        // leaves the top half of its O behind, and a leftover block sitting
        // in a gap would hand the rise a complete row to shatter.
        grid.set(
          row,
          col,
          _riseRigGaps[i].contains(col) ? null : Cell(BlockType.wood),
        );
      }
    }
  }

  /// Winds the rise up to something a player can actually watch.
  ///
  /// The rise has a 12-second grace period whose clock only advances while it
  /// is unfrozen, and a 22-second interval after that so simply letting it
  /// go would leave the player staring at a still board for half a minute.
  /// Skipping the grace and compressing the interval keeps the whole climb
  /// inside the caption's welcome.
  void _startRiseDemo() {
    final rise = game.engine.riseController;
    rise.elapsed = Difficulty.riseGracePeriod.inMicroseconds / 1e6 + 1;
    // From the bottom, not from 0.9 as this once did: the point of the step
    // is watching the row climb, and a row that starts nine tenths of the way
    // up has already arrived by the time the player looks down at it.
    rise.riseProgress = 0.0;
    rise.debugSpeedMultiplier = rise.riseInterval / _riseDemoSeconds;
  }

  void _end() {
    if (_finished) return;
    _finished = true;
    _releaseEngine();
    onFinished();
  }

  /// Hands the run back exactly as it was found. Idempotent, and reached from
  /// every exit finishing, skipping, and a game over underneath.
  void _releaseEngine() {
    _holdTimer?.cancel();
    _holdTimer = null;
    final engine = game.engine;
    engine.freezeGravity = false;
    engine.freezeRise = false;
    engine.pieceController.softDropActive = false;
    // `RiseController.reset` does not touch this, so the demo's compressed
    // clock would otherwise follow the player into their first real run.
    engine.riseController.debugSpeedMultiplier = 1.0;
  }

  // ----------------------------------------------------------------- events

  void _onEvent(GameEvent event) {
    if (_finished) return;

    if (event is PieceSpawnedEvent) {
      _showSpawnedPiece();
      return;
    }

    // A coached run should be unloseable, but the rise does run for two of the
    // steps. If it ever does end, get out of the way rather than stack a coach
    // card on top of the game-over overlay.
    if (event is GameOverEvent) {
      abandon();
      return;
    }

    // A step already showing its work is done listening: nothing the board
    // says during the beat can satisfy it a second time. This is also what
    // absorbs the stray `softDropStart` a hard-drop flick leaves behind.
    if (_phase == TutorialPhase.effect) return;

    switch (_step) {
      case TutorialStep.move:
        if (event is PlayerActionEvent &&
            (event.action == PlayerAction.moveLeft ||
                event.action == PlayerAction.moveRight)) {
          if (++_moveCount >= _movesToAdvance) {
            _satisfy(TutorialStep.rotate, _holdShort);
          }
        }
      case TutorialStep.rotate:
        if (event is PlayerActionEvent && event.action == PlayerAction.rotate) {
          _satisfy(TutorialStep.hardDrop, _holdShort);
        }
      case TutorialStep.hardDrop:
        // Not the action event, deliberately: the engine emits it *before*
        // running the drop (`game_engine.dart:258-259`), so a step hung off it
        // changed the card before the piece had moved a single row. The lock
        // that follows is the first moment there is a slam to have watched.
        if (event is PlayerActionEvent &&
            event.action == PlayerAction.hardDrop) {
          _dropSeen = true;
        } else if (_dropSeen && event is PieceLockedEvent) {
          _satisfy(TutorialStep.softDrop, _holdLand);
        }
      case TutorialStep.softDrop:
        if (event is PlayerActionEvent &&
            event.action == PlayerAction.softDrop) {
          _satisfy(TutorialStep.clearIntro, _holdSoftDrop);
        }
      case TutorialStep.clearRow:
        if (event is RowsClearedEvent) {
          _satisfy(TutorialStep.cascadeIntro, _holdClear);
        }
      case TutorialStep.cascadeRow:
        // The chain is the lesson, so this waits for the *second* clear. The
        // engine emits `ChainAdvancedEvent` once per resolve pass and only
        // increments between them, so a non-zero index is exactly "this clear
        // was caused by the last one" which is the thing being taught.
        if (event is ChainAdvancedEvent && event.chainIndex > 0) {
          _satisfy(TutorialStep.riseIntro, _holdChain);
        } else if (event is RowsClearedEvent) {
          // The first clear only arms a way out. The rig is deterministic and
          // the chain lands in about two seconds, but stranding a player on a
          // step whose exit can no longer happen is not a risk worth running.
          _armHold(TutorialStep.riseIntro, _cascadeFallback);
        }
      case TutorialStep.riseWatch:
        if (event is RiseCommittedEvent) {
          _satisfy(TutorialStep.done, _holdRise);
        }
      default:
        break;
    }
  }
}
