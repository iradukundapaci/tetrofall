import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../../ui/theme/tokens.dart';

class BoardFrame extends PositionComponent {
  BoardFrame({
    required this.cols,
    required this.rows,
    required double cellSize,
    this.theme = ThemeDefinition.classicWood,
  }) : _cellSize = cellSize,
       super(size: Vector2(cols * cellSize, rows * cellSize));

  final int cols;
  final int rows;
  final ThemeDefinition theme;

  double _cellSize;
  double get cellSize => _cellSize;
  set cellSize(double value) {
    _cellSize = value;
    size = Vector2(cols * value, rows * value);
  }

  bool warning = false;
  double _warnClock = 0;

  ui.Image? _woodTexture;

  @override
  Future<void> onLoad() async {
    _woodTexture = await Flame.images.load('textures/bg_wood.png');
  }

  @override
  void update(double dt) {
    super.update(dt);
    _warnClock = warning ? _warnClock + dt : 0;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    final texture = _woodTexture;
    if (texture == null) {
      canvas.drawRect(rect, Paint()..color = theme.boardBg);
    } else {
      final imgW = texture.width.toDouble();
      final imgH = texture.height.toDouble();
      final scale = math.max(size.x / imgW, size.y / imgH);
      final srcW = size.x / scale;
      final srcH = size.y / scale;
      final src = Rect.fromLTWH(
        (imgW - srcW) / 2,
        (imgH - srcH) / 2,
        srcW,
        srcH,
      );
      // Colorize (hue + saturation from the theme, luminance from the
      // photo) rather than swap the asset per theme — classic_wood's
      // frameLight is already this same warm tan, so this is a no-op
      // for the shipping look, but it means a new theme only needs a
      // palette entry, never a new frame texture.
      canvas.drawImageRect(
        texture,
        src,
        rect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.mode(theme.frameLight, BlendMode.color),
      );
    }

    final groovePaint = Paint()
      ..color = theme.frameDark.withValues(alpha: 0.55)
      ..strokeWidth = math.max(1, cellSize * 0.035);
    for (var c = 1; c < cols; c++) {
      final x = c * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), groovePaint);
    }

    if (warning) {
      final pulse = (math.sin(2 * math.pi * _warnClock) + 1) / 2;
      final alpha = 0.12 + 0.22 * pulse;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, cellSize * 2),
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            Offset(rect.center.dx, cellSize * 2),
            [
              Tokens.colorRed.withValues(alpha: alpha),
              Tokens.colorRed.withValues(alpha: 0),
            ],
          ),
      );
    }
  }
}
