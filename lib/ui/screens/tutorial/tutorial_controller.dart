import 'package:flutter/foundation.dart';

import '../../../game/config/board_config.dart';
import '../../../game/config/difficulty.dart';
import '../../../game/engine/cell.dart';
import '../../../game/engine/events.dart';
import '../../../game/engine/tetromino.dart';
import '../../../game/tetrofall_game.dart';
import '../../../services/analytics_service.dart';
import '../../../services/storage_service.dart';

/// How a step presents itself.
enum TutorialMode {
  /// Board dimmed behind a centred panel the player reads and dismisses.
  /// Reuses gameplay's existing dim treatment, which also blocks board
  /// touches — correct here, since these steps ask for a button press.
  modal,

  /// Board live and fully touchable, with a caption and a looping hint
  /// floating over it. The player advances it by *doing* the thing.
  coach,
}

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
  riseIntro,
  riseWatch,
  done,
}

/// Where the tutorial's rigged row leaves its gap. Off-centre on purpose: an
/// `O` spawns over columns 8–9 of 18, so a gap here costs four swipes right
/// and puts the movement the player was just taught straight to work.
const _clearGapCol = 12;

/// Column moves needed to clear the `move` step. Two is enough to show the
/// piece tracking the finger without turning the step into a chore.
const _movesToAdvance = 2;

/// Where a coached piece is parked: far enough down to be plainly visible,
/// far enough up to leave the player somewhere to drop it.
const _coachRow = 4;

/// Drives the first-run coached tutorial — owns which step is showing,
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
    // through [_goTo] — without this the funnel would have no entry count to
    // measure the later steps against.
    AnalyticsService.design('tutorial:step:${_step.name}');
    _applyStep();
  }

  final TetrofallGame game;
  final StorageService storage;

  /// Called once, on completion or skip, after the engine has been released.
  /// The host screen uses it to hand off into a clean scored run.
  final VoidCallback onFinished;

  TutorialStep _step = TutorialStep.intro;
  TutorialStep get step => _step;

  int _moveCount = 0;
  bool _finished = false;

  /// Whether the tutorial has run its course, by any route.
  bool get isFinished => _finished;

  @override
  void dispose() {
    game.engine.removeEventListener(_onEvent);
    super.dispose();
  }

  // ---------------------------------------------------------------- content

  TutorialMode get mode => switch (_step) {
    TutorialStep.intro ||
    TutorialStep.clearIntro ||
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
    TutorialStep.riseIntro => 'THE RISE',
    TutorialStep.done => "YOU'RE READY",
    _ => '',
  };

  String get body => switch (_step) {
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
    TutorialStep.riseIntro =>
      'New rows push up from below, faster the longer you last.\n\n'
          'If the stack reaches the top, the run is over.',
    TutorialStep.riseWatch => 'Here it comes — clear rows to hold it back.',
    TutorialStep.done => 'Good luck.',
  };

  /// Null on coach steps, which have no button — the gesture is the button.
  String? get buttonLabel => switch (_step) {
    TutorialStep.intro => "Let's Go",
    TutorialStep.clearIntro || TutorialStep.riseIntro => 'Continue',
    TutorialStep.done => 'Play',
    _ => null,
  };

  /// Which end of the board the caption hides. It defaults to the bottom,
  /// where nothing is happening while the piece hovers up top — but the two
  /// steps that are *about* the bottom of the board (the rigged row, and the
  /// rise pushing in beneath it) move it out of the way.
  bool get captionAtTop =>
      _step == TutorialStep.clearRow || _step == TutorialStep.riseWatch;

  TutorialHint get hint => switch (_step) {
    TutorialStep.move => TutorialHint.swipeHorizontal,
    TutorialStep.rotate => TutorialHint.tap,
    TutorialStep.hardDrop => TutorialHint.flickDown,
    TutorialStep.softDrop => TutorialHint.dragDown,
    _ => TutorialHint.none,
  };

  // ------------------------------------------------------------ transitions

  /// Advances a modal step. Coach steps ignore it — they advance on events.
  void advance() {
    if (mode != TutorialMode.modal) return;
    if (_step == TutorialStep.done) {
      // The only genuine completion: tapping through the closing step. Every
      // other exit — Skip, or a top-out underneath the coach — also lands in
      // [_end] and then in the host screen's hand-off, so reporting from
      // there would score a skip as a completion and read 100% forever.
      AnalyticsService.design('tutorial:complete');
      _end();
      return;
    }
    _goTo(TutorialStep.values[_step.index + 1]);
  }

  void skip() {
    AnalyticsService.design('tutorial:skip:${_step.name}');
    _end();
  }

  /// Ends the tutorial without asking for a hand-off restart — used when the
  /// run has already ended underneath it and the game-over overlay owns the
  /// screen.
  void abandon() {
    if (_finished) return;
    AnalyticsService.design('tutorial:abandon:${_step.name}');
    _finished = true;
    _releaseEngine();
    notifyListeners();
  }

  void _goTo(TutorialStep next) {
    // The per-step drop-off funnel. [TutorialStep] is a closed enum, so this
    // is a fixed set of ids however the tutorial is navigated.
    AnalyticsService.design('tutorial:step:${next.name}');
    _step = next;
    _moveCount = 0;
    _applyStep();
    notifyListeners();
  }

  /// Everything a step needs done to the run on the way in.
  void _applyStep() {
    final engine = game.engine;

    // Soft drop is a no-op against frozen gravity — it only divides an
    // interval that is not being counted — so its step is the one that has to
    // let the clock run. The rigged clear and the rise demo need it too.
    engine.freezeGravity = switch (_step) {
      TutorialStep.softDrop ||
      TutorialStep.clearRow ||
      TutorialStep.riseWatch => false,
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
      case TutorialStep.riseWatch:
        _jumpRiseForward();
      default:
        break;
    }
  }

  /// Brings a just-spawned piece down out of the hidden spawn buffer.
  ///
  /// Pieces spawn at `grid.minRow` — two rows above the top of the board —
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

  /// The rise has a 12-second grace period, and its clock only advances while
  /// it is unfrozen — so simply letting it go would leave the player watching
  /// a still board for the whole of it. Wind it to just short of a commit so
  /// the row arrives while the caption is still on screen.
  void _jumpRiseForward() {
    final rise = game.engine.riseController;
    rise.elapsed = Difficulty.riseGracePeriod.inMicroseconds / 1e6 + 1;
    rise.riseProgress = 0.9;
  }

  void _end() {
    if (_finished) return;
    _finished = true;
    _releaseEngine();
    onFinished();
  }

  /// Hands the run back exactly as it was found. Idempotent, and reached from
  /// every exit — finishing, skipping, and a game over underneath.
  void _releaseEngine() {
    final engine = game.engine;
    engine.freezeGravity = false;
    engine.freezeRise = false;
    engine.pieceController.softDropActive = false;
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

    switch (_step) {
      case TutorialStep.move:
        if (event is PlayerActionEvent &&
            (event.action == PlayerAction.moveLeft ||
                event.action == PlayerAction.moveRight)) {
          if (++_moveCount >= _movesToAdvance) _goTo(TutorialStep.rotate);
        }
      case TutorialStep.rotate:
        if (event is PlayerActionEvent && event.action == PlayerAction.rotate) {
          _goTo(TutorialStep.hardDrop);
        }
      case TutorialStep.hardDrop:
        if (event is PlayerActionEvent &&
            event.action == PlayerAction.hardDrop) {
          _goTo(TutorialStep.softDrop);
        }
      case TutorialStep.softDrop:
        if (event is PlayerActionEvent &&
            event.action == PlayerAction.softDrop) {
          _goTo(TutorialStep.clearIntro);
        }
      case TutorialStep.clearRow:
        if (event is RowsClearedEvent) _goTo(TutorialStep.riseIntro);
      case TutorialStep.riseWatch:
        if (event is RiseCommittedEvent) _goTo(TutorialStep.done);
      default:
        break;
    }
  }
}
