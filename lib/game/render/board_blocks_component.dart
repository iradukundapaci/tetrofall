import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../config/board_config.dart';
import '../engine/game_engine.dart';
import 'fall_animator.dart';
import 'tile_cache.dart';

/// Draws every settled block on the board in a single `drawRawAtlas` call.
///
/// The board used to be 576 individual `BlockComponent`s, so a nearly-full
/// board meant 576 component-tree walks and 576 draws per frame — frame cost
/// climbed as the player stacked up, which is exactly when they could least
/// afford it. One atlas call keeps the cost flat no matter how full it gets.
class BoardBlocksComponent extends PositionComponent {
  BoardBlocksComponent({
    required this.engine,
    required this.theme,
    required this.fallAnimator,
  });

  final GameEngine engine;
  final ThemeDefinition theme;
  final FallAnimator fallAnimator;

  double cellSize = 1;

  static const _capacity = BoardConfig.rows * BoardConfig.cols;

  // Preallocated to the board's maximum, so a frame never allocates: four
  // floats per sprite (scaled cos, scaled sin, translate x, translate y) for
  // the transforms, and left/top/right/bottom for the source rects.
  final Float32List _transforms = Float32List(_capacity * 4);
  final Float32List _rects = Float32List(_capacity * 4);

  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.low;
  late final Paint _fallbackPaint = Paint()..color = theme.blockTint;

  @override
  void render(Canvas canvas) {
    if (cellSize <= 0) return;

    final tile = TileCache.tile(theme, cellSize);
    if (tile == null) {
      _renderFallback(canvas);
      return;
    }

    final grid = engine.grid;
    final animating = fallAnimator.isAnimating;
    final scale = cellSize / tile.width;
    final srcRight = tile.width.toDouble();
    final srcBottom = tile.height.toDouble();

    var count = 0;
    for (var r = 0; r < BoardConfig.rows; r++) {
      for (var c = 0; c < BoardConfig.cols; c++) {
        if (grid.at(r, c) == null) continue;
        // A cell a block is still falling into is drawn by FallAnimator
        // until it settles, so it must not be drawn twice.
        if (animating && fallAnimator.isFallTarget(r, c)) continue;

        final i = count * 4;
        _transforms[i] = scale;
        _transforms[i + 1] = 0;
        _transforms[i + 2] = c * cellSize;
        _transforms[i + 3] = r * cellSize;
        _rects[i] = 0;
        _rects[i + 1] = 0;
        _rects[i + 2] = srcRight;
        _rects[i + 3] = srcBottom;
        count++;
      }
    }
    if (count == 0) return;

    final used = count * 4;
    canvas.drawRawAtlas(
      tile,
      Float32List.view(_transforms.buffer, 0, used),
      Float32List.view(_rects.buffer, 0, used),
      null,
      null,
      null,
      _atlasPaint,
    );
  }

  /// Flat fill for the few frames before the baked tile is ready.
  void _renderFallback(Canvas canvas) {
    final grid = engine.grid;
    final animating = fallAnimator.isAnimating;
    final inset = cellSize * 0.015;
    final radius = Radius.circular(cellSize * 0.06);

    for (var r = 0; r < BoardConfig.rows; r++) {
      for (var c = 0; c < BoardConfig.cols; c++) {
        if (grid.at(r, c) == null) continue;
        if (animating && fallAnimator.isFallTarget(r, c)) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              c * cellSize + inset,
              r * cellSize + inset,
              cellSize - inset * 2,
              cellSize - inset * 2,
            ),
            radius,
          ),
          _fallbackPaint,
        );
      }
    }
  }
}
