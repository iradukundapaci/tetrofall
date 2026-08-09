import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';

/// Bakes the expensive parts of a block's look — the rounded-corner clip and
/// the theme tint, which uses the non-separable [BlendMode.color] — into a
/// ready-to-blit [ui.Image], once per (theme, cell size).
///
/// Doing that work per cell per frame made frame cost scale with how full the
/// board was: an 18x32 board near capacity issued ~576 clips plus ~576
/// advanced-blend subpasses every frame, which is what made a filling board
/// go laggy. Paying it once here turns each block into a plain image blit, so
/// the whole board can go out in a single `drawRawAtlas` call.
abstract final class TileCache {
  static const _minPx = 8;
  static const _maxPx = 256;

  static final Map<String, ui.Image> _tiles = {};
  static final Set<String> _loading = {};

  static String _stripImagesPrefix(String path) {
    const prefix = 'assets/images/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  static String _key(ThemeDefinition theme, int px) => '${theme.id}@$px';

  static double get _devicePixelRatio =>
      ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;

  /// Rasterize at physical-pixel resolution so the blit lands ~1:1 on screen.
  static int _pixelsFor(double cellSize) =>
      (cellSize * _devicePixelRatio).round().clamp(_minPx, _maxPx);

  /// Builds — or reuses — the tile for [theme] at [cellSize] logical pixels.
  /// Cheap to call on every layout pass; only a new size does real work.
  static void ensure(ThemeDefinition theme, double cellSize) {
    if (cellSize <= 0) return;
    final px = _pixelsFor(cellSize);
    final key = _key(theme, px);
    if (_tiles.containsKey(key) || _loading.contains(key)) return;

    final asset = _stripImagesPrefix(theme.baseTileAsset);
    if (!Flame.images.containsKey(asset)) {
      _loading.add(key);
      Flame.images.load(asset).then((_) {
        _loading.remove(key);
        ensure(theme, cellSize);
      });
      return;
    }
    _tiles[key] = _bake(theme, Flame.images.fromCache(asset), px);
  }

  /// The baked tile, or null while the source asset is still decoding —
  /// callers fall back to a flat fill for those few frames.
  static ui.Image? tile(ThemeDefinition theme, double cellSize) {
    if (cellSize <= 0) return null;
    return _tiles[_key(theme, _pixelsFor(cellSize))];
  }

  static ui.Image _bake(ThemeDefinition theme, ui.Image source, int px) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = px.toDouble();

    // Same geometry the per-frame renderer used to compute: a 1.5% inset and
    // a 6% corner radius, expressed against the cell.
    final inset = size * 0.015;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size - inset * 2,
      size - inset * 2,
    );
    canvas.clipRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size * 0.06)),
    );

    final srcInset = source.width * 0.03;
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(
        srcInset,
        srcInset,
        source.width - srcInset * 2,
        source.height - srcInset * 2,
      ),
      rect,
      Paint()
        ..filterQuality = FilterQuality.medium
        // Colorize with theme.blockTint (hue/saturation from the theme,
        // luminance from the tile) so the one bundled tile asset reskins per
        // theme instead of needing a new PNG.
        ..colorFilter = ColorFilter.mode(theme.blockTint, BlendMode.color),
    );

    final picture = recorder.endRecording();
    final image = picture.toImageSync(px, px);
    picture.dispose();
    return image;
  }

  /// Frees every baked tile. Only needed if themes become swappable at
  /// runtime; the cache is otherwise bounded by the handful of cell sizes a
  /// device can produce.
  static void clear() {
    for (final image in _tiles.values) {
      image.dispose();
    }
    _tiles.clear();
  }
}
