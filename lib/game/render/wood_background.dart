import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Full-bleed pale-pine backing behind the board, matching the reference
/// footage's light wooden background — so any letterboxed sliver around
/// the full-bleed board blends into the same material instead of showing
/// a dark surface.
class WoodBackground extends PositionComponent with HasGameReference {
  static const _pineLight = Color(0xFFEBD5A8);
  static const _pineMid = Color(0xFFDDC08E);

  @override
  int get priority => -1;

  @override
  Future<void> onLoad() async {
    size = game.size;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
          _pineLight,
          _pineMid,
        ]),
    );
  }
}
