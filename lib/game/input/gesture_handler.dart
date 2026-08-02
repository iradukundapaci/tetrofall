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

    final isVertical =
        totalDown > InputTuning.hardDropVerticalityRatio * totalDx.abs();

    if (!isVertical) {
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
    HapticFeedback.selectionClick();
  }
}
