import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';

/// One wooden block, theme-aware — the only block type in the game.
/// Renders the active theme's base tile edge-to-edge with just a hairline
/// seam and near-square corners, matching the reference footage's tight
/// wooden grid. A [ghost] instance draws a translucent outline instead
/// (§1.2).
class BlockComponent extends PositionComponent with HasGameReference {
  BlockComponent({required this.theme, this.ghost = false});

  final ThemeDefinition theme;
  final bool ghost;

  bool blockVisible = false;

  /// Impact squash-and-stretch (§2.2): 1.0 = normal, <1.0 = squashed
  /// vertically (and stretched horizontally to preserve volume).
  double squashY = 1.0;

  /// 0..1 — used by the emerging pending row's fade-in (§2.1).
  double opacity = 1.0;

  ui.Image? _tile;
  bool _loading = false;

  @override
  Future<void> onLoad() async {
    if (ghost) return;
    unawaited(_ensureTileLoaded());
  }

  static String _stripImagesPrefix(String path) {
    const prefix = 'assets/images/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  Future<void> _ensureTileLoaded() async {
    if (ghost || _tile != null || _loading) return;
    _loading = true;
    final path = theme.spriteOverrides['wood'] ?? theme.baseTileAsset;
    _tile = await game.images.load(_stripImagesPrefix(path));
    _loading = false;
  }

  void setLayout({required double cellSize, required int row, required int col}) {
    size = Vector2.all(cellSize);
    position = Vector2(col * cellSize, row * cellSize);
  }

  @override
  void render(Canvas canvas) {
    if (!blockVisible || size.x <= 0 || opacity <= 0) return;

    final needsOpacity = opacity < 1.0;
    if (needsOpacity) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }

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

    // Reference look: blocks nearly touch — only a hairline dark seam and
    // a tiny corner round separate neighbours.
    final inset = size.x * 0.015;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.x - inset * 2,
      size.y - inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.x * 0.06));

    if (ghost) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.x * 0.05
          ..color = theme.text.withValues(alpha: 0.5),
      );
    } else {
      final tile = _tile;
      if (tile == null) {
        canvas.drawRRect(rrect, Paint()..color = theme.blockTint);
      } else {
        canvas.save();
        canvas.clipRRect(rrect);
        // Backstop against any tile asset that bakes in a background
        // margin (R2): sample a slightly inset source rect so a stray
        // border can't leak into the cell even if the asset isn't clean.
        final srcInset = tile.width * 0.03;
        canvas.drawImageRect(
          tile,
          Rect.fromLTWH(
            srcInset,
            srcInset,
            tile.width - srcInset * 2,
            tile.height - srcInset * 2,
          ),
          rect,
          Paint(),
        );
        canvas.restore();
      }
    }

    if (needsSquash) canvas.restore();
    if (needsOpacity) canvas.restore();
  }
}
