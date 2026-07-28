import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../engine/game_engine.dart';
import 'input_tuning.dart';

/// Raw-pointer gesture recognizer implementing §1.12's control scheme —
/// deliberately just four inputs: drag left/right to move (each column
/// costs a fixed drag distance — no auto-repeat, so speed always tracks
/// the finger 1:1), drag down to soft/hard drop, and tap to rotate. No
/// other gesture is recognized.
///
/// Deliberately built on raw pointer events rather than a high-level
/// `GestureDetector` — the drag-distance accounting below needs direct
/// access to every intermediate move sample, not just a resolved swipe.
class GestureHandler {
  GestureHandler(this.engine, this.cellSizeProvider);

  final GameEngine engine;

  /// Reports the board's current on-screen cell size so thresholds stay
  /// cell-relative (see `InputTuning`). May return 0 before the board has
  /// completed its first layout pass.
  final double Function() cellSizeProvider;

  double _resolvedCellSize() {
    final size = cellSizeProvider();
    return size > 0 ? size : InputTuning.fallbackCellSize;
  }

  int? _pointer;
  Offset? _down;
  Offset? _last;
  DateTime? _downTime;
  bool _movedBeyondSlop = false;
  bool _softDropEngaged = false;

  /// Whether any column move has fired yet this gesture — used only to
  /// tell a tap (rotate) apart from a drag that happened to end up back
  /// near its start column.
  bool _anyMoveFiredThisGesture = false;

  /// Horizontal drag accumulated since the last emitted column move — lets
  /// a slow/medium drag move multiple columns instead of only fast flicks
  /// registering (I2-2). Movement speed is purely a function of how far
  /// the finger has actually travelled — there is deliberately no
  /// auto-repeat-while-held: holding a finger still, or dragging it only
  /// slowly, must never move the piece faster than the finger itself is
  /// moving (§1: reported "moving left/right is too fast, not realistic").
  double _accumDx = 0;

  /// Only one pointer is ever tracked — everything else (a second finger
  /// touching down, additional simultaneous touches) is ignored outright.
  /// The control scheme is exactly four inputs: drag left, drag right,
  /// drag down, tap.
  void onPointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    final pos = event.localPosition;
    _pointer = event.pointer;
    _down = pos;
    _last = pos;
    _downTime = DateTime.now();
    _movedBeyondSlop = false;
    _softDropEngaged = false;
    _anyMoveFiredThisGesture = false;
    _accumDx = 0;
  }

  void onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _handleMove(event.localPosition);
  }

  void _handleMove(Offset pos) {
    final dx = pos.dx - _last!.dx;
    _last = pos;

    final totalMove = (pos - _down!).distance;
    if (totalMove > InputTuning.tapSlop) _movedBeyondSlop = true;

    final cellSize = _resolvedCellSize();
    final swipeColumnThreshold = InputTuning.swipeColumnThreshold(cellSize);
    final softDropDistance = InputTuning.softDropDistance(cellSize);
    final hardDropDistance = InputTuning.hardDropDistance(cellSize);

    final totalDx = pos.dx - _down!.dx;
    final totalDown = pos.dy - _down!.dy;

    // "Predominantly vertical" by the cumulative distance from the finger's
    // down point — shared by the horizontal-drift guard below and the
    // hard-drop trigger further down, so both agree on the same bar.
    final isVertical =
        totalDown > InputTuning.hardDropVerticalityRatio * totalDx.abs();

    // While the gesture stays predominantly vertical, stop honoring
    // incidental horizontal drift. A thumb swiping straight down almost
    // always wobbles sideways by a few px; without this, that wobble could
    // cross `swipeColumnThreshold` mid-swipe and shift the piece a column
    // before the hard drop actually fires, landing it somewhere the player
    // never meant to drop it. A genuinely deliberate sideways drag — enough
    // to pull the *cumulative* ratio back below the vertical bar — still
    // un-suppresses this normally, so nudging mid-soft-drop (I2-3) keeps
    // working; only small jitter that never threatens the vertical reading
    // gets ignored.
    if (!isVertical) {
      // Horizontal moves accumulate drag distance since the last emitted
      // move rather than comparing a single event's delta, so slow/medium
      // drags register — not just fast flicks (I2-2) — and a multi-column
      // drag can emit more than one move, but only ever as many columns as
      // the finger has actually travelled: no timer-driven repeat.
      if (_accumDx != 0 && dx != 0 && (_accumDx > 0) != (dx > 0)) {
        _accumDx = dx; // direction reversed — start the accumulator fresh
      } else {
        _accumDx += dx;
      }
      while (_accumDx.abs() >= swipeColumnThreshold) {
        final dir = _accumDx > 0 ? 1 : -1;
        _applyMove(dir);
        _accumDx -= dir * swipeColumnThreshold;
      }
    }

    // Hard drop requires an actual sustained downward swipe — a real drag
    // covering `hardDropDistance`, not a quick flick — so it only ever
    // fires on a deliberate swipe-down motion (§1.3).
    if (totalDown >= hardDropDistance && isVertical) {
      if (_softDropEngaged) engine.enqueueIntent(GameIntentType.softDropEnd);
      engine.enqueueIntent(GameIntentType.hardDrop);
      _reset();
      return;
    }
    // Engage soft drop only once, and only when the gesture is
    // predominantly vertical (I2-3) — otherwise 24px of downward drift
    // during a horizontal swipe used to engage it by accident.
    if (!_softDropEngaged &&
        totalDown >= softDropDistance &&
        totalDown > totalDx.abs()) {
      _softDropEngaged = true;
      engine.enqueueIntent(GameIntentType.softDropStart);
    }
  }

  void onPointerUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _finish();
  }

  void onPointerCancel(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (_softDropEngaged) engine.enqueueIntent(GameIntentType.softDropEnd);
    _reset();
  }

  void _finish() {
    final duration = DateTime.now().difference(_downTime!);
    if (_softDropEngaged) {
      engine.enqueueIntent(GameIntentType.softDropEnd);
    } else if (!_anyMoveFiredThisGesture &&
        !_movedBeyondSlop &&
        duration <= InputTuning.tapMaxDuration) {
      engine.enqueueIntent(GameIntentType.rotateCW);
      // Light tactile confirmation on rotate (§6.6) — the control most in
      // need of it, since a tap gives no visual feedback until the piece
      // actually turns.
      HapticFeedback.selectionClick();
    }
    _reset();
  }

  void _reset() {
    _pointer = null;
    _softDropEngaged = false;
    _anyMoveFiredThisGesture = false;
    _accumDx = 0;
  }

  /// Fully resets all pointer state, ending any in-progress soft drop.
  /// Used when something outside the normal down/move/up flow takes over
  /// mid-gesture — pausing (§6.1), or a booster getting armed from the HUD
  /// while a board swipe is still active (§6.2) — so the next touch isn't
  /// misread as a stale continuation of the old gesture.
  void reset() {
    if (_softDropEngaged) engine.enqueueIntent(GameIntentType.softDropEnd);
    _reset();
  }

  void _applyMove(int dir) {
    _anyMoveFiredThisGesture = true;
    engine.enqueueIntent(
      dir > 0 ? GameIntentType.moveRight : GameIntentType.moveLeft,
    );
    // Light tactile confirmation per column move (§6.6) — this is the
    // control the sensitivity complaints (§1) were mostly about, so it
    // benefits most from feeling deliberate.
    HapticFeedback.selectionClick();
  }
}
