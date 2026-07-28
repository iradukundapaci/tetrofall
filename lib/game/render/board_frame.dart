import 'dart:math' as math;
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

  /// Set by [BoardComponent] when the stack top has reached the warning
  /// row (§2.1). Pulses the top edge red at 1Hz while true.
  bool warning = false;
  double _warnClock = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _warnClock = warning ? _warnClock + dt : 0;
  }

  @override
  void render(Canvas canvas) {
    final frameThickness = cellSize * 0.35;
    final wellRect = Rect.fromLTWH(0, 0, size.x, size.y);
    final outerRect = wellRect.inflate(frameThickness / 2);

    // 5. Outer drop shadow.
    canvas.drawRect(
      outerRect.shift(Tokens.shadowSoft.offset),
      Paint()
        ..color = Tokens.shadowSoft.color
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          Tokens.shadowSoft.blurRadius,
        ),
    );

    // 1. Outer frame — rect stroke, two-tone bevel.
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = frameThickness
      ..shader = ui.Gradient.linear(outerRect.topLeft, outerRect.bottomRight, [
        theme.frameLight,
        theme.frameDark,
      ]);
    canvas.drawRect(outerRect.deflate(frameThickness / 2), framePaint);

    // 2. Well interior — slightly darker than the page background so the
    // board reads as recessed.
    canvas.drawRect(wellRect, Paint()..color = theme.boardBg);

    // 3. Inner shadow — sells the depth an image version would have baked in.
    canvas.save();
    canvas.clipRect(wellRect);
    canvas.drawRect(
      wellRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 8),
    );
    canvas.restore();

    // 4. Grid lines — subtle enough that an empty board looks calm, present
    // enough to judge column alignment while a piece is falling.
    final gridPaint = Paint()
      ..color = theme.gridLine.withValues(alpha: 0.08)
      ..strokeWidth = cellSize * 0.03;
    for (var c = 1; c < cols; c++) {
      final x = c * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), gridPaint);
    }
    for (var r = 1; r < rows; r++) {
      final y = r * cellSize;
      canvas.drawLine(Offset(0, y), Offset(size.x, y), gridPaint);
    }

    // Warning pulse: the top edge glows red at 1Hz once the stack reaches
    // the warning row (§2.1).
    if (warning) {
      final pulse = (math.sin(2 * math.pi * _warnClock) + 1) / 2; // 0..1
      final alpha = 0.25 + 0.35 * pulse;
      canvas.drawRect(
        outerRect.deflate(frameThickness / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = frameThickness
          ..color = Tokens.colorRed.withValues(alpha: alpha),
      );
    }
  }
}
