import 'package:flutter/gestures.dart';

import '../engine/game_engine.dart';
import 'input_tuning.dart';

/// Raw-pointer gesture recognizer implementing §1.12's control scheme:
/// swipe left/right to move (hold for DAS/ARR auto-repeat), tap to rotate
/// CW, two-finger tap to rotate CCW, short downward swipe to soft drop,
/// long/fast downward swipe to hard drop.
///
/// Deliberately built on raw pointer events rather than a high-level
/// `GestureDetector` — DAS/ARR auto-repeat needs a per-frame timer, which
/// [update] provides, driven from `TetrofallGame.update`.
class GestureHandler {
  GestureHandler(this.engine);

  final GameEngine engine;

  int? _primaryPointer;
  Offset? _primaryDown;
  Offset? _primaryLast;
  DateTime? _primaryDownTime;
  bool _primaryMovedBeyondSlop = false;

  int _dasDirection = 0;
  double _dasTimer = 0;
  bool _dasFired = false;
  bool _softDropEngaged = false;

  int? _secondaryPointer;
  Offset? _secondaryDown;
  bool _secondaryMovedBeyondSlop = false;
  bool _hadCleanSecondaryTap = false;

  void onPointerDown(PointerDownEvent event) {
    final pos = event.localPosition;
    if (_primaryPointer == null) {
      _primaryPointer = event.pointer;
      _primaryDown = pos;
      _primaryLast = pos;
      _primaryDownTime = DateTime.now();
      _primaryMovedBeyondSlop = false;
      _dasDirection = 0;
      _dasTimer = 0;
      _dasFired = false;
      _softDropEngaged = false;
    } else if (_secondaryPointer == null && !_primaryMovedBeyondSlop) {
      _secondaryPointer = event.pointer;
      _secondaryDown = pos;
      _secondaryMovedBeyondSlop = false;
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    if (event.pointer == _primaryPointer) {
      _handlePrimaryMove(event.localPosition);
    } else if (event.pointer == _secondaryPointer) {
      final moved = (event.localPosition - _secondaryDown!).distance;
      if (moved > InputTuning.tapSlop) _secondaryMovedBeyondSlop = true;
    }
  }

  void _handlePrimaryMove(Offset pos) {
    final dx = pos.dx - _primaryLast!.dx;
    _primaryLast = pos;

    final totalMove = (pos - _primaryDown!).distance;
    if (totalMove > InputTuning.tapSlop) _primaryMovedBeyondSlop = true;

    if (!_softDropEngaged && dx.abs() >= InputTuning.swipeColumnThreshold) {
      final dir = dx > 0 ? 1 : -1;
      _applyMove(dir);
      _dasDirection = dir;
      _dasTimer = 0;
      _dasFired = false;
    }

    final totalDown = pos.dy - _primaryDown!.dy;
    if (totalDown >= InputTuning.hardDropDistance) {
      engine.enqueueIntent(GameIntentType.hardDrop);
      _resetPrimary();
      return;
    }
    if (!_softDropEngaged && totalDown >= InputTuning.softDropDistance) {
      _softDropEngaged = true;
      engine.enqueueIntent(GameIntentType.softDropStart);
    }
  }

  void onPointerUp(PointerEvent event) {
    if (event.pointer == _secondaryPointer) {
      if (!_secondaryMovedBeyondSlop) _hadCleanSecondaryTap = true;
      _secondaryPointer = null;
      return;
    }
    if (event.pointer == _primaryPointer) {
      _finishPrimary();
    }
  }

  void onPointerCancel(PointerEvent event) {
    if (event.pointer == _secondaryPointer) {
      _secondaryPointer = null;
      return;
    }
    if (event.pointer == _primaryPointer) {
      if (_softDropEngaged) engine.enqueueIntent(GameIntentType.softDropEnd);
      _resetPrimary();
    }
  }

  void _finishPrimary() {
    final duration = DateTime.now().difference(_primaryDownTime!);
    if (_softDropEngaged) {
      engine.enqueueIntent(GameIntentType.softDropEnd);
    } else if (_dasDirection == 0 &&
        !_primaryMovedBeyondSlop &&
        duration <= InputTuning.tapMaxDuration) {
      final twoFingerTap = _hadCleanSecondaryTap;
      engine.enqueueIntent(
        twoFingerTap ? GameIntentType.rotateCCW : GameIntentType.rotateCW,
      );
    }
    _resetPrimary();
  }

  void _resetPrimary() {
    _primaryPointer = null;
    _dasDirection = 0;
    _dasTimer = 0;
    _dasFired = false;
    _softDropEngaged = false;
    _hadCleanSecondaryTap = false;
  }

  void _applyMove(int dir) {
    engine.enqueueIntent(
      dir > 0 ? GameIntentType.moveRight : GameIntentType.moveLeft,
    );
  }

  /// Advances the DAS/ARR auto-repeat timer. Call once per frame.
  void update(double dt) {
    if (_dasDirection == 0) return;
    _dasTimer += dt;
    if (!_dasFired) {
      if (_dasTimer * 1000 >= InputTuning.dasDelay.inMilliseconds) {
        _dasFired = true;
        _dasTimer = 0;
        _applyMove(_dasDirection);
      }
    } else {
      final arrSeconds = InputTuning.arr.inMilliseconds / 1000;
      while (_dasTimer >= arrSeconds) {
        _dasTimer -= arrSeconds;
        _applyMove(_dasDirection);
      }
    }
  }
}
