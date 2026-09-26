import 'package:flutter/gestures.dart';

import '../../services/haptics_service.dart';
import '../engine/game_engine.dart';
import 'input_tuning.dart';

class GestureHandler {
  GestureHandler(this.engine, this.cellSizeProvider, {this.haptics});

  final GameEngine engine;

  final double Function() cellSizeProvider;

  /// Null in tests and for the menu demo.
  final HapticsService? haptics;

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

  /// Set once the gesture has committed to a hard drop. The pointer stays
  /// tracked until it lifts so a second finger can't start a gesture (and be
  /// scored as a tap) underneath it.
  bool _consumed = false;

  /// Whether the downward travel that engaged the soft drop was a flick. Arming
  /// happens once, so a deliberate drag can cross any distance without
  /// escalating into a slam.
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

    // Seeded from the first sample: the flick/drag decision comes within an
    // event or two, and a zero start would read every flick as slow.
    if (elapsed > 0) {
      final speedY = dy / elapsed;
      _smoothSpeedY = _hasSpeedSample
          ? _smoothSpeedY * InputTuning.velocitySmoothing +
                speedY * (1 - InputTuning.velocitySmoothing)
          : speedY;
      _hasSpeedSample = true;
    }

    // Sideways intent uses a smoothed recent delta with a two-threshold latch.
    // Raw per-event deltas are too twitchy (correlated sensor noise can bank a
    // column and snap back), and displacement since touch-down never forgets
    // a downward arc, killing sideways input once a soft drop engages.
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

    // Hard drop is judged against the whole gesture, not one event.
    final isVertical =
        totalDown > InputTuning.hardDropVerticalityRatio * totalDx.abs();

    // Arming runs before the sideways block so an event that newly arms the
    // hard drop can't also bank a column shift under the stale pre-arm flag.
    if (!_softDropEngaged &&
        totalDown >= softDropDistance &&
        totalDown > totalDx.abs()) {
      // Distance decides that the piece drops faster; speed decides whether
      // the stroke may become a slam. A slow start stays a soft drop.
      _softDropEngaged = true;
      _hardDropArmed = isVertical && _smoothSpeedY >= flickSpeed;
      engine.enqueueIntent(GameIntentType.softDropStart);
    } else if (_hardDropArmed && _smoothSpeedY < flickSpeed) {
      // A flick doesn't stall halfway; once it slows, disarming is permanent.
      _hardDropArmed = false;
    }

    // A thumb arcs; sideways travel mid-flick must not bank a column shift,
    // or the slam lands one column off. Gated on speed alone, not
    // `isVertical`, which lacks history on a flick's first events.
    final holdSideways =
        _hardDropArmed ||
        _smoothSpeedY >= flickSpeed * InputTuning.flickSuppressionFraction;

    if (_sidewaysActive) {
      // Drift keeps accumulating while held so an aborted flick turns into a
      // steer immediately.
      if (_accumDx != 0 && dx != 0 && (_accumDx > 0) != (dx > 0)) {
        _accumDx = dx;
      } else {
        _accumDx += dx;
      }
      while (!holdSideways && _accumDx.abs() >= swipeColumnThreshold) {
        final dir = _accumDx > 0 ? 1 : -1;
        _applyMove(dir);
        _accumDx -= dir * swipeColumnThreshold;
      }
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
    // A gesture resolves to one action: a hard drop already spent it, a soft
    // drop only needs releasing, and a tap is what's left when the finger
    // never dragged, shifted or lingered.
    if (!_consumed) {
      final duration = DateTime.now().difference(_downTime!);
      if (_softDropEngaged) {
        engine.enqueueIntent(GameIntentType.softDropEnd);
      } else if (!_anyMoveFiredThisGesture &&
          !_movedBeyondSlop &&
          duration <= InputTuning.tapMaxDuration) {
        engine.enqueueIntent(GameIntentType.rotateCW);
        haptics?.selection();
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

  /// Abandons any gesture in flight (pause, restart, continue), where the
  /// pointer-up is swallowed before it reaches this handler.
  void reset() {
    _endSoftDrop();
    _clearGesture();
  }

  void _applyMove(int dir) {
    _anyMoveFiredThisGesture = true;
    engine.enqueueIntent(
      dir > 0 ? GameIntentType.moveRight : GameIntentType.moveLeft,
    );

    // A fast swipe can cross several columns in one event, and each click is
    // a platform-channel round trip.
    final now = DateTime.now();
    final last = _lastHaptic;
    if (last == null || now.difference(last) >= InputTuning.hapticMinInterval) {
      _lastHaptic = now;
      haptics?.selection();
    }
  }
}
