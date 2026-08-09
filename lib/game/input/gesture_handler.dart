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
  bool _movedBeyondSlop = false;
  bool _softDropEngaged = false;

  bool _anyMoveFiredThisGesture = false;

  double _accumDx = 0;

  DateTime? _lastHaptic;

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
    final dy = pos.dy - _last!.dy;
    _last = pos;

    final totalMove = (pos - _down!).distance;
    if (totalMove > InputTuning.tapSlop) _movedBeyondSlop = true;

    final cellSize = _resolvedCellSize();
    final swipeColumnThreshold = InputTuning.swipeColumnThreshold(cellSize);
    final softDropDistance = InputTuning.softDropDistance(cellSize);
    final hardDropDistance = InputTuning.hardDropDistance(cellSize);

    final totalDx = pos.dx - _down!.dx;
    final totalDown = pos.dy - _down!.dy;

    // Sideways intent is judged on this event's own delta. It used to be
    // gated on `totalDown > 1.5 * totalDx.abs()` — both measured from the
    // touch-down point — so once the thumb had arced downward at all, and
    // permanently once a soft drop was engaged, horizontal moves stopped
    // registering for the rest of the gesture.
    if (dx.abs() > dy.abs() * InputTuning.horizontalAxisRatio) {
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

    // Hard drop stays a deliberate, mostly-vertical flick, so it is still
    // measured against the whole gesture rather than one event.
    final isVertical =
        totalDown > InputTuning.hardDropVerticalityRatio * totalDx.abs();

    if (totalDown >= hardDropDistance && isVertical) {
      if (_softDropEngaged) engine.enqueueIntent(GameIntentType.softDropEnd);
      engine.enqueueIntent(GameIntentType.hardDrop);
      _reset();
      return;
    }
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

  void reset() {
    if (_softDropEngaged) engine.enqueueIntent(GameIntentType.softDropEnd);
    _reset();
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
    if (last == null ||
        now.difference(last) >= InputTuning.hapticMinInterval) {
      _lastHaptic = now;
      HapticFeedback.selectionClick();
    }
  }
}
