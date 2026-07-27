import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../engine/cell.dart';

/// One block, theme-aware. Renders the active theme's base tile for plain
/// [BlockType.wood] cells; specials get their own tiles in Phase 7. A
/// [ghost] instance draws a translucent outline instead (§1.2 ghost piece).
class BlockComponent extends PositionComponent with HasGameReference {
  BlockComponent({required this.theme, this.ghost = false});

  final ThemeDefinition theme;
  final bool ghost;

  bool blockVisible = false;
  BlockType blockType = BlockType.wood;

  /// Impact squash-and-stretch (§2.2): 1.0 = normal, <1.0 = squashed
  /// vertically (and stretched horizontally to preserve volume).
  double squashY = 1.0;

  ui.Image? _tile;

  @override
  Future<void> onLoad() async {
    if (ghost) return;
    _tile = await game.images.load(_stripImagesPrefix(theme.baseTileAsset));
  }

  static String _stripImagesPrefix(String path) {
    const prefix = 'assets/images/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  void setLayout({required double cellSize, required int row, required int col}) {
    size = Vector2.all(cellSize);
    position = Vector2(col * cellSize, row * cellSize);
  }

  @override
  void render(Canvas canvas) {
    if (!blockVisible || size.x <= 0) return;

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

    final inset = size.x * 0.04;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.x - inset * 2,
      size.y - inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.x * 0.12));

    if (ghost) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = theme.text.withValues(alpha: 0.5),
      );
    } else {
      final tile = _tile;
      if (tile == null) {
        canvas.drawRRect(rrect, Paint()..color = theme.blockTint);
      } else {
        canvas.save();
        canvas.clipRRect(rrect);
        canvas.drawImageRect(
          tile,
          Rect.fromLTWH(0, 0, tile.width.toDouble(), tile.height.toDouble()),
          rect,
          Paint(),
        );
        canvas.restore();
      }
    }

    if (needsSquash) canvas.restore();
  }
}
