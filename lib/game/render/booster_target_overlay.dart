import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../ui/theme/tokens.dart';

/// Highlights the cells a booster would destroy, before the player commits
/// (§1.9: "highlight the affected cells before commit"). Lives in the
/// rise-scrolled content layer so the highlight tracks the same cells
/// visually, not fixed screen positions.
class BoosterTargetOverlay extends PositionComponent {
  double cellSize = 1;
  List<(int, int)> _cells = const [];

  void show(List<(int, int)> cells) => _cells = cells;
  void hide() => _cells = const [];

  @override
  void render(Canvas canvas) {
    if (_cells.isEmpty || cellSize <= 0) return;
    final fillPaint = Paint()..color = Tokens.colorGold.withValues(alpha: 0.28);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Tokens.colorGold.withValues(alpha: 0.9);
    for (final (row, col) in _cells) {
      final rect = Rect.fromLTWH(
        col * cellSize,
        row * cellSize,
        cellSize,
        cellSize,
      );
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);
    }
  }
}
