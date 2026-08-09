import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../engine/game_engine.dart';
import 'input_tuning.dart';

class GestureHandler {
  GestureHandler(this.engine, this.cellSizeProvider);

  final GameEngine engine;

  final double Function() cellSizeProvider;

  double _resolvedCellSize() {
    final size = cellSizeProvider();
    return size > 0 ? size : InputTuning.fallbackCellSize;
  }

  int? _pointer;
  Offset? _down;
  Offset? _last;
  DateTime? _downTime;
  DateTime? _lastMoveTime;
  bool _movedBeyondSlop = false;
  bool _softDropEngaged = false;

  /// Set once the gesture has committed to a hard drop.
  ///
  /// The pointer stays tracked until it actually lifts, so nothing further
  /// can be read out of it and no second finger can start a gesture
  /// underneath it. Clearing the pointer here instead — which is what the
  /// hard-drop path used to do — re-armed the handler mid-gesture, and the
  /// next touch-down it accepted could still be scored as a tap: hard drop,
  /// then a rotation the player never asked for.
  bool _consumed = false;

  /// Whether the downward travel that engaged the soft drop was fast enough
  /// to read as a flick. Only an armed gesture may hard drop, and arming
  /// happens exactly once, so a deliberate drag down can cross any distance
  /// without escalating into a slam.
  bool _hardDropArmed = false;

  bool _anyMoveFiredThisGesture = false;

  double _accumDx = 0;

  double _smoothDx = 0;
  double _smoothDy = 0;
  double _smoothSpeedY = 0;
  bool _hasSpeedSample = false;
  bool _sidewaysActive = false;

  DateTime? _lastHaptic;

  void onPointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    final pos = event.localPosition;
    final now = DateTime.now();
    _pointer = event.pointer;
    _down = pos;
    _last = pos;
    _downTime = now;
    _lastMoveTime = now;
    _movedBeyondSlop = false;
    _softDropEngaged = false;
    _consumed = false;
    _hardDropArmed = false;
    _anyMoveFiredThisGesture = false;
    _accumDx = 0;
    _smoothDx = 0;
    _smoothDy = 0;
    _smoothSpeedY = 0;
    _hasSpeedSample = false;
    _sidewaysActive = false;
  }

  void onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _consumed) return;
    _handleMove(event.localPosition);
  }

  void _handleMove(Offset pos) {
    final now = DateTime.now();
    final dx = pos.dx - _last!.dx;
    final dy = pos.dy - _last!.dy;
    final elapsed =
        now.difference(_lastMoveTime!).inMicroseconds /
        Duration.microsecondsPerSecond;
    _last = pos;
    _lastMoveTime = now;

    final totalMove = (pos - _down!).distance;
    if (totalMove > InputTuning.tapSlop) _movedBeyondSlop = true;

    final cellSize = _resolvedCellSize();
    final swipeColumnThreshold = InputTuning.swipeColumnThreshold(cellSize);
    final softDropDistance = InputTuning.softDropDistance(cellSize);
    final hardDropDistance = InputTuning.hardDropDistance(cellSize);
    final flickSpeed = InputTuning.flickSpeed(cellSize);

    final totalDx = pos.dx - _down!.dx;
    final totalDown = pos.dy - _down!.dy;

    // Seeded from the first sample rather than blended up from zero: the
    // flick/drag decision is made within an event or two of the finger
    // crossing the soft-drop distance, and a zero start would read every
    // flick as slow for exactly that long.
    if (elapsed > 0) {
      final speedY = dy / elapsed;
      _smoothSpeedY = _hasSpeedSample
          ? _smoothSpeedY * InputTuning.velocitySmoothing +
                speedY * (1 - InputTuning.velocitySmoothing)
          : speedY;
      _hasSpeedSample = true;
    }

    // Sideways intent is judged on a smoothed recent delta plus a two-
    // threshold latch, not on this event's raw delta or on the total
    // displacement since touch-down. Raw-per-event was tried first and was
    // too twitchy: real touch sensors don't jitter independently
    // sample-to-sample, so a short run of a few correlated noisy samples
    // during an otherwise straight drag could ride a single threshold long
    // enough to accumulate a full column shift, with the correction run
    // crossing it right back — the piece visibly jumping and snapping
    // back. Since-touch-down was the original bug: it never forgot a
    // downward arc, so sideways input died for the rest of the gesture
    // once a soft drop engaged.
    _smoothDx =
        _smoothDx * InputTuning.axisSmoothing +
        dx * (1 - InputTuning.axisSmoothing);
    _smoothDy =
        _smoothDy * InputTuning.axisSmoothing +
        dy * (1 - InputTuning.axisSmoothing);

    final axisRatio = _smoothDy.abs() < 1e-6
        ? double.infinity
        : _smoothDx.abs() / _smoothDy.abs();
    if (_sidewaysActive) {
      if (axisRatio < InputTuning.horizontalExitRatio) {
        _sidewaysActive = false;
      }
    } else if (axisRatio > InputTuning.horizontalEnterRatio) {
      _sidewaysActive = true;
    }

    if (_sidewaysActive) {
      if (_accumDx != 0 && dx != 0 && (_accumDx > 0) != (dx > 0)) {
        _accumDx = dx;
      } else {
        _accumDx += dx;
      }
      while (_accumDx.abs() >= swipeColumnThreshold) {
        final dir = _accumDx > 0 ? 1 : -1;
        _applyMove(dir);
        _accumDx -= dir * swipeColumnThreshold;
      }
    }

    // Hard drop stays a deliberate, mostly-vertical gesture, so it is still
    // measured against the whole gesture rather than one event.
    final isVertical =
        totalDown > InputTuning.hardDropVerticalityRatio * totalDx.abs();

    if (!_softDropEngaged &&
        totalDown >= softDropDistance &&
        totalDown > totalDx.abs()) {
      // The one moment the vertical gesture is classified. Distance decides
      // *that* the piece drops faster; speed decides whether this stroke is
      // ever allowed to become a slam. A drag that starts slow is a soft
      // drop for the rest of the gesture no matter how far it travels.
      _softDropEngaged = true;
      _hardDropArmed = isVertical && _smoothSpeedY >= flickSpeed;
      engine.enqueueIntent(GameIntentType.softDropStart);
    } else if (_hardDropArmed && _smoothSpeedY < flickSpeed) {
      // A flick does not stall halfway down. Once the finger settles into a
      // drag — or stops to hold the soft drop and steer — the gesture has
      // shown it is not a flick, and disarming is permanent.
      _hardDropArmed = false;
    }

    if (_hardDropArmed && totalDown >= hardDropDistance && isVertical) {
      _consumed = true;
      if (_softDropEngaged) engine.enqueueIntent(GameIntentType.softDropEnd);
      engine.enqueueIntent(GameIntentType.hardDrop);
    }
  }

  void onPointerUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _finish();
  }

  void onPointerCancel(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _endSoftDrop();
    _clearGesture();
  }

  void _finish() {
    // A gesture resolves to exactly one action. A hard drop has already
    // spent it; a soft drop only needs releasing; a rotation is what is left
    // when the finger never dragged, never shifted a column and never
    // lingered.
    if (!_consumed) {
      final duration = DateTime.now().difference(_downTime!);
      if (_softDropEngaged) {
        engine.enqueueIntent(GameIntentType.softDropEnd);
      } else if (!_anyMoveFiredThisGesture &&
          !_movedBeyondSlop &&
          duration <= InputTuning.tapMaxDuration) {
        engine.enqueueIntent(GameIntentType.rotateCW);
        HapticFeedback.selectionClick();
      }
    }
    _clearGesture();
  }

  void _endSoftDrop() {
    if (_softDropEngaged && !_consumed) {
      engine.enqueueIntent(GameIntentType.softDropEnd);
    }
  }

  void _clearGesture() {
    _pointer = null;
    _softDropEngaged = false;
    _consumed = false;
    _hardDropArmed = false;
    _anyMoveFiredThisGesture = false;
    _accumDx = 0;
    _hasSpeedSample = false;
    _smoothSpeedY = 0;
  }

  /// Abandons any gesture in flight — used when the run is paused, restarted
  /// or continued, where the pointer-up that would normally end it is
  /// swallowed before it reaches this handler.
  void reset() {
    _endSoftDrop();
    _clearGesture();
  }

  void _applyMove(int dir) {
    _anyMoveFiredThisGesture = true;
    engine.enqueueIntent(
      dir > 0 ? GameIntentType.moveRight : GameIntentType.moveLeft,
    );

    // A fast swipe can cross several columns inside one pointer event, and
    // each click is a platform-channel round trip on the UI thread.
    final now = DateTime.now();
    final last = _lastHaptic;
    if (last == null || now.difference(last) >= InputTuning.hapticMinInterval) {
      _lastHaptic = now;
      HapticFeedback.selectionClick();
    }
  }
}
