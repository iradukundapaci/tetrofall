import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../../ui/theme/tokens.dart';

/// Canvas-drawn board frame: outer bevel, recessed well, inner shadow, grid
/// lines, outer drop shadow. No image asset — resolution-independent,
/// recolors from [ThemeDefinition] for free. See game.md P.4.
///
/// Frame thickness and radius are derived from [cellSize], never a fixed
/// pixel value, so the frame reads the same on phone and tablet.
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

  @override
  void render(Canvas canvas) {
    final frameThickness = cellSize * 0.35;
    final wellRect = Rect.fromLTWH(0, 0, size.x, size.y);
    final outerRect = wellRect.inflate(frameThickness / 2);
    final outerRRect = RRect.fromRectAndRadius(
      outerRect,
      const Radius.circular(Tokens.radiusLg),
    );
    final wellRadius = (Tokens.radiusLg - frameThickness / 2).clamp(
      0.0,
      Tokens.radiusLg,
    );
    final wellRRect = RRect.fromRectAndRadius(
      wellRect,
      Radius.circular(wellRadius),
    );

    // 5. Outer drop shadow.
    canvas.drawRRect(
      outerRRect.shift(Tokens.shadowSoft.offset),
      Paint()
        ..color = Tokens.shadowSoft.color
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          Tokens.shadowSoft.blurRadius,
        ),
    );

    // 1. Outer frame — rounded rect stroke, two-tone bevel.
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = frameThickness
      ..shader = ui.Gradient.linear(outerRect.topLeft, outerRect.bottomRight, [
        theme.frameLight,
        theme.frameDark,
      ]);
    canvas.drawRRect(outerRRect.deflate(frameThickness / 2), framePaint);

    // 2. Well interior — slightly darker than the page background so the
    // board reads as recessed.
    canvas.drawRRect(wellRRect, Paint()..color = theme.boardBg);

    // 3. Inner shadow — sells the depth an image version would have baked in.
    canvas.save();
    canvas.clipRRect(wellRRect);
    canvas.drawRRect(
      wellRRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 8),
    );
    canvas.restore();

    // 4. Grid lines — subtle enough that an empty board looks calm, present
    // enough to judge column alignment while a piece is falling.
    final gridPaint = Paint()
      ..color = theme.gridLine.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var c = 1; c < cols; c++) {
      final x = c * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), gridPaint);
    }
    for (var r = 1; r < rows; r++) {
      final y = r * cellSize;
      canvas.drawLine(Offset(0, y), Offset(size.x, y), gridPaint);
    }
  }
}
