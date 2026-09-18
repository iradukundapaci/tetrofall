import 'package:flame/components.dart' show Vector2;
import 'package:flutter/gestures.dart';

import '../boosters/booster_run_state.dart';
import '../boosters/booster_type.dart';
import '../render/board_component.dart';

/// Pointer events while a booster is armed (`boosters.md` §4.4).
///
/// [GestureHandler] is bypassed entirely for the duration: a swipe aims, it
/// does not move or rotate the piece. Releasing on a valid target fires;
/// releasing anywhere else shakes the preview and leaves the booster armed,
/// so a miss never costs a charge.
class BoosterAimHandler {
  BoosterAimHandler({required this.state, required this.boardProvider});

  final BoosterRunState state;
  final BoardComponent? Function() boardProvider;

  int? _pointer;
  Offset? _down;
  (int, int)? _cell;

  bool get isAiming => state.armedIndex != null;

  void onPointerDown(PointerDownEvent event) {
    if (!isAiming || _pointer != null) return;
    _pointer = event.pointer;
    _down = event.localPosition;
    _update(event.localPosition);
  }

  void onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _update(event.localPosition);
  }

  void onPointerUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _update(event.localPosition);
    state.releaseAim();
    _clear();
  }

  void onPointerCancel(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _clear();
  }

  void reset() => _clear();

  void _update(Offset position) {
    final board = boardProvider();
    if (board == null) return;

    final cell =
        board.cellFromScreen(Vector2(position.dx, position.dy)) ?? _cell;
    if (cell == null) return;
    _cell = cell;

    // Swipe distance in cells, which is what Slide and Tilt lock their
    // direction on (BoosterTuning.slideMinDragCells).
    final cellSize = board.cellSize;
    final down = _down;
    final dragCells = down == null || cellSize <= 0
        ? 0.0
        : (position.dx - down.dx) / cellSize;

    state.updateAim(cell.$1, cell.$2, dragCells: dragCells);
  }

  void _clear() {
    _pointer = null;
    _down = null;
    _cell = null;
  }

  /// Tilt can be swiped on the board *or* on its own slot, so the bar needs a
  /// way in as well (§5.11).
  void fireSwipeOnly(double dragCells) {
    final type = state.armedType;
    if (type != BoosterType.tilt) return;
    state.updateAim(0, 0, dragCells: dragCells);
    state.releaseAim();
  }
}
