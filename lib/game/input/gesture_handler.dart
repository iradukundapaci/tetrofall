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

  int? _primaryPointer;
  Offset? _primaryDown;
  Offset? _primaryLast;
  DateTime? _primaryDownTime;
  bool _primaryMovedBeyondSlop = false;

  int _dasDirection = 0;
  double _dasTimer = 0;
  bool _dasFired = false;
  bool _softDropEngaged = false;

  /// Horizontal drag accumulated since the last emitted column move — lets
  /// a slow/medium drag move multiple columns instead of only fast flicks
  /// registering (I2-2).
  double _accumDx = 0;

  /// Recent (position, time) samples for the current gesture, used to
  /// estimate downward velocity for the fast-flick hard-drop trigger
  /// (I2-4). Capped to a short rolling window.
  final List<_PointerSample> _velocitySamples = [];

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
      _accumDx = 0;
      _velocitySamples
        ..clear()
        ..add(_PointerSample(pos, _primaryDownTime!));
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
    final now = DateTime.now();
    final dx = pos.dx - _primaryLast!.dx;
    _primaryLast = pos;
    _pushVelocitySample(pos, now);

    final totalMove = (pos - _primaryDown!).distance;
    if (totalMove > InputTuning.tapSlop) _primaryMovedBeyondSlop = true;

    final cellSize = _resolvedCellSize();
    final swipeColumnThreshold = InputTuning.swipeColumnThreshold(cellSize);
    final softDropDistance = InputTuning.softDropDistance(cellSize);
    final hardDropDistance = InputTuning.hardDropDistance(cellSize);

    // Horizontal moves accumulate drag distance since the last emitted
    // move rather than comparing a single event's delta, so slow/medium
    // drags register — not just fast flicks (I2-2) — and a multi-column
    // drag can emit more than one move. Allowed even while soft-dropping
    // (I2-3): only the gesture's initial predominant direction decides
    // whether soft drop engages, not whether horizontal input is honored
    // afterward.
    if (_accumDx != 0 && dx != 0 && (_accumDx > 0) != (dx > 0)) {
      _accumDx = dx; // direction reversed — start the accumulator fresh
    } else {
      _accumDx += dx;
    }
    while (_accumDx.abs() >= swipeColumnThreshold) {
      final dir = _accumDx > 0 ? 1 : -1;
      _applyMove(dir);
      _accumDx -= dir * swipeColumnThreshold;
      _dasDirection = dir;
      _dasTimer = 0;
      _dasFired = false;
    }

    final totalDx = pos.dx - _primaryDown!.dx;
    final totalDown = pos.dy - _primaryDown!.dy;
    final downVelocity = _currentDownVelocity();

    if (totalDown >= hardDropDistance || downVelocity >= InputTuning.hardDropVelocity) {
      if (_softDropEngaged) engine.enqueueIntent(GameIntentType.softDropEnd);
      engine.enqueueIntent(GameIntentType.hardDrop);
      _resetPrimary();
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

  void _pushVelocitySample(Offset pos, DateTime time) {
    _velocitySamples.add(_PointerSample(pos, time));
    while (_velocitySamples.length > 6) {
      _velocitySamples.removeAt(0);
    }
  }

  /// Downward velocity in px/s over the last few pointer-move events
  /// (I2-4), positive when moving down. Using a short window instead of a
  /// single frame's delta smooths out uneven event spacing.
  double _currentDownVelocity() {
    if (_velocitySamples.length < 2) return 0;
    final first = _velocitySamples.first;
    final last = _velocitySamples.last;
    final dtSeconds = last.time.difference(first.time).inMicroseconds / 1e6;
    if (dtSeconds <= 0) return 0;
    return (last.pos.dy - first.pos.dy) / dtSeconds;
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
    _accumDx = 0;
    _velocitySamples.clear();
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

class _PointerSample {
  const _PointerSample(this.pos, this.time);
  final Offset pos;
  final DateTime time;
}
