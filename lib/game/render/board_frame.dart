import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../../ui/theme/tokens.dart';

/// The play-area backdrop: the `bg_wood` pine texture (cover-cropped so its
/// vertical grain never stretches) with a dark vertical groove at every
/// column boundary — the planks are exactly one cell wide. Blocks sit
/// directly on top of this. The border and margin around the play area are
/// Flutter-side (see app.dart); this component only fills its own rect.
///
/// Keeps the name `BoardFrame` so the board plumbing (`cellSize` drives
/// `size`) stays untouched.
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

  /// Set by [BoardComponent] when the stack top has reached the warning
  /// row (§2.1). Pulses the top edge red at 1Hz while true.
  bool warning = false;
  double _warnClock = 0;

  ui.Image? _woodTexture;

  static const _grooveColor = Color(0xFF8A6844);

  /// Fallback fill for the single frame before the texture finishes
  /// decoding, matching the texture's average tone so there's no flash.
  static const _pineFallback = Color(0xFFEBC078);

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
      canvas.drawRect(rect, Paint()..color = _pineFallback);
    } else {
      // Cover-crop: scale uniformly to fill, cropping the overflow, so the
      // vertical grain keeps its natural proportions on the tall board.
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
      canvas.drawImageRect(
        texture,
        src,
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    // The signature vertical plank grooves — one per column boundary,
    // spanning the full height (the background is striped at exactly the
    // cell pitch).
    final groovePaint = Paint()
      ..color = _grooveColor.withValues(alpha: 0.55)
      ..strokeWidth = math.max(1, cellSize * 0.035);
    for (var c = 1; c < cols; c++) {
      final x = c * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), groovePaint);
    }

    // Warning pulse: the top edge glows red at 1Hz once the stack reaches
    // the warning row (§2.1).
    if (warning) {
      final pulse = (math.sin(2 * math.pi * _warnClock) + 1) / 2; // 0..1
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
