import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../ui/theme/tokens.dart';

final _identityMatrix4 = Float64List.fromList([
  1, 0, 0, 0, //
  0, 1, 0, 0,
  0, 0, 1, 0,
  0, 0, 0, 1,
]);

/// Full-bleed seamless wood texture (`bg_wood.png`, P.4). Falls back to a
/// vertical gradient approximation of `--bg-wood-texture` while the image
/// is still loading.
class WoodBackground extends PositionComponent with HasGameReference {
  ui.Image? _texture;

  @override
  int get priority => -1;

  @override
  Future<void> onLoad() async {
    size = game.size;
    _texture = await game.images.load('textures/bg_wood.png');
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final texture = _texture;
    if (texture == null) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
            Tokens.colorWoodDark,
            Tokens.colorBg,
          ]),
      );
      return;
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ImageShader(
          texture,
          TileMode.repeated,
          TileMode.repeated,
          _identityMatrix4,
        ),
    );
  }
}
