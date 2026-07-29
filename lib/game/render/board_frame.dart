import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../../ui/theme/tokens.dart';

/// Full-bleed light-pine backdrop, 1:1 with the reference footage: no
/// frame, no bevel, no recessed well — just pale planked wood with a dark
/// vertical groove at every column boundary (the planks are exactly one
/// cell wide) and faint horizontal grain streaks. Blocks sit directly on
/// top of this. Canvas-drawn — resolution-independent, no asset.
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

  // Reference palette, sampled from the source footage's empty area:
  // pale pine planks with slightly darker grooves between them.
  static const _pineLight = Color(0xFFEBD5A8);
  static const _pineMid = Color(0xFFE0C494);
  static const _grooveColor = Color(0xFF8A6844);

  @override
  void update(double dt) {
    super.update(dt);
    _warnClock = warning ? _warnClock + dt : 0;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Pale pine base with a soft vertical light falloff.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
          _pineLight,
          _pineMid,
        ]),
    );

    // Faint horizontal grain streaks, deterministic per layout so they
    // don't shimmer frame to frame.
    final grainPaint = Paint()
      ..color = _grooveColor.withValues(alpha: 0.06)
      ..strokeWidth = math.max(1, cellSize * 0.03);
    final rng = math.Random(7);
    final streaks = (rows * 1.5).round();
    for (var i = 0; i < streaks; i++) {
      final y = rng.nextDouble() * size.y;
      final xStart = rng.nextDouble() * size.x * 0.6;
      final length = size.x * (0.15 + rng.nextDouble() * 0.35);
      canvas.drawLine(
        Offset(xStart, y),
        Offset(math.min(xStart + length, size.x), y),
        grainPaint,
      );
    }

    // The signature vertical plank grooves — one per column boundary,
    // spanning the full height (the reference background is striped at
    // exactly the cell pitch).
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
