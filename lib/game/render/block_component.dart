import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../../ui/theme/tokens.dart';
import '../engine/cell.dart';

/// Asset-file name for each special block's complete tile (P.3) — every
/// theme shares these, so they're keyed by type alone, not by theme. [key]
/// has no entry: P.3's asset list never planned a Key tile (game.md §6's
/// "gap" pattern, like the missing Stopwatch icon), so it renders as a
/// code-drawn glyph instead — see [_renderKeyGlyph].
const _specialAssetNames = <BlockType, String>{
  BlockType.stone: 'stone',
  BlockType.ice: 'ice',
  BlockType.iceCracked: 'ice_cracked',
  BlockType.bomb: 'bomb',
  BlockType.gold: 'gold',
  BlockType.diamond: 'diamond',
  BlockType.treasure: 'treasure',
  BlockType.locked: 'locked',
  BlockType.rainbow: 'rainbow',
};

/// One block, theme-aware. Renders the active theme's base tile for plain
/// [BlockType.wood] cells, and each special's own complete tile (P.3) for
/// everything else — one sprite lookup per cell, no compositing (Phase 7).
/// A [ghost] instance draws a translucent outline instead (§1.2).
class BlockComponent extends PositionComponent with HasGameReference {
  BlockComponent({required this.theme, this.ghost = false});

  final ThemeDefinition theme;
  final bool ghost;

  bool blockVisible = false;
  BlockType blockType = BlockType.wood;

  /// Impact squash-and-stretch (§2.2): 1.0 = normal, <1.0 = squashed
  /// vertically (and stretched horizontally to preserve volume).
  double squashY = 1.0;

  /// 0..1 — used by the emerging pending row's fade-in (§2.1).
  double opacity = 1.0;

  final Map<BlockType, ui.Image> _tiles = {};
  final Set<BlockType> _loadingTiles = {};

  @override
  Future<void> onLoad() async {
    if (ghost) return;
    await _ensureTileLoaded(BlockType.wood);
  }

  static String _stripImagesPrefix(String path) {
    const prefix = 'assets/images/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  /// Resolves and caches the tile for [type], honoring
  /// `ThemeDefinition.spriteOverrides` before falling back to the shared
  /// special-block tile (or the theme's own base tile for wood). No-ops
  /// for [BlockType.key] (no asset exists) and while already in flight.
  Future<void> _ensureTileLoaded(BlockType type) async {
    if (ghost || _tiles.containsKey(type) || _loadingTiles.contains(type)) {
      return;
    }
    if (type == BlockType.key) return; // code-drawn, no tile to load

    final overrideKey = type == BlockType.wood ? 'wood' : type.name;
    final path =
        theme.spriteOverrides[overrideKey] ??
        (type == BlockType.wood
            ? theme.baseTileAsset
            : 'assets/images/blocks/block_${_specialAssetNames[type]}.png');

    _loadingTiles.add(type);
    final image = await game.images.load(_stripImagesPrefix(path));
    _loadingTiles.remove(type);
    _tiles[type] = image;
  }

  void setLayout({required double cellSize, required int row, required int col}) {
    size = Vector2.all(cellSize);
    position = Vector2(col * cellSize, row * cellSize);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!ghost && blockVisible) {
      // Fire-and-forget: draws the placeholder tint this frame, the real
      // tile once `game.images.load` resolves (cached after the first hit).
      unawaited(_ensureTileLoaded(blockType));
    }
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
    } else if (blockType == BlockType.key) {
      _renderKeyGlyph(canvas, rect, rrect);
    } else {
      final tile = _tiles[blockType];
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
    if (needsOpacity) canvas.restore();
  }

  /// A code-drawn key glyph — no image asset exists for [BlockType.key]
  /// (see the class doc). Distinguishable by shape, not just tint, per the
  /// accessibility rule: a bow-and-shaft silhouette on a dark plate.
  void _renderKeyGlyph(Canvas canvas, Rect rect, RRect rrect) {
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF3B2A1A));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.x * 0.05
        ..color = Tokens.colorGold.withValues(alpha: 0.6),
    );

    final gold = Paint()..color = Tokens.colorGold;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final bowRadius = size.x * 0.16;
    final bowCenter = Offset(cx - size.x * 0.1, cy);

    canvas.drawCircle(bowCenter, bowRadius, gold);
    canvas.drawCircle(
      bowCenter,
      bowRadius * 0.45,
      Paint()..color = const Color(0xFF3B2A1A),
    );

    final shaftLeft = bowCenter.dx + bowRadius * 0.7;
    final shaftRect = Rect.fromLTWH(
      shaftLeft,
      cy - size.x * 0.045,
      rect.right - shaftLeft - size.x * 0.06,
      size.x * 0.09,
    );
    canvas.drawRect(shaftRect, gold);
    canvas.drawRect(
      Rect.fromLTWH(
        shaftRect.right - size.x * 0.1,
        shaftRect.bottom,
        size.x * 0.05,
        size.x * 0.07,
      ),
      gold,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        shaftRect.right - size.x * 0.02,
        shaftRect.bottom,
        size.x * 0.05,
        size.x * 0.1,
      ),
      gold,
    );
  }
}
