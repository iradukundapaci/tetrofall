import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import 'tile_cache.dart';

/// A single drawn block. Used for the bounded, moving cases — the active
/// piece, its ghost, blocks mid-fall and the pending rise row. The settled
/// board is drawn in one batch by `BoardBlocksComponent` instead.
class BlockComponent extends PositionComponent {
  BlockComponent({required this.theme, this.ghost = false});

  final ThemeDefinition theme;
  final bool ghost;

  bool blockVisible = false;

  double squashY = 1.0;

  double opacity = 1.0;

  // Reused across frames: this used to allocate a Paint and a ColorFilter on
  // every render call, for every block.
  final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  @override
  void render(Canvas canvas) {
    if (!blockVisible || size.x <= 0 || opacity <= 0) return;

    final needsSquash = squashY != 1.0;
    if (needsSquash) {
      canvas.save();
      final cx = size.x / 2;
      final cy = size.y / 2;
      final scaleX = 1 + (1 - squashY) * 0.5;
      canvas.translate(cx, cy);
      canvas.scale(scaleX, squashY);
      canvas.translate(-cx, -cy);
    }

    final ui.Image? tile = ghost ? null : TileCache.tile(theme, size.x);
    if (tile != null) {
      // Opacity rides on the paint's alpha rather than a saveLayer. The
      // pending row fades every frame, and an offscreen layer per block is
      // not a price worth paying for a cross-fade.
      _paint
        ..style = PaintingStyle.fill
        ..color = opacity >= 1.0
            ? const Color(0xFFFFFFFF)
            : const Color(0xFFFFFFFF).withValues(alpha: opacity);
      canvas.drawImageRect(
        tile,
        Rect.fromLTWH(0, 0, tile.width.toDouble(), tile.height.toDouble()),
        Rect.fromLTWH(0, 0, size.x, size.y),
        _paint,
      );
    } else {
      _renderVector(canvas);
    }

    if (needsSquash) canvas.restore();
  }

  /// The ghost outline, and the flat fallback fill for the few frames before
  /// the baked tile is ready.
  void _renderVector(Canvas canvas) {
    final inset = size.x * 0.015;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.x - inset * 2,
      size.y - inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.x * 0.06));

    if (ghost) {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.x * 0.05
        ..color = theme.text.withValues(alpha: 0.5 * opacity);
    } else {
      _paint
        ..style = PaintingStyle.fill
        ..color = theme.blockTint.withValues(alpha: opacity);
    }
    canvas.drawRRect(rrect, _paint);
  }

  void setLayout({
    required double cellSize,
    required int row,
    required int col,
  }) {
    size = Vector2.all(cellSize);
    position = Vector2(col * cellSize, row * cellSize);
  }
}
