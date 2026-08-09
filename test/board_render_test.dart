import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/engine/cell.dart';
import 'package:tetrofall/game/engine/events.dart';
import 'package:tetrofall/game/engine/game_engine.dart';
import 'package:tetrofall/models/theme_definition.dart';
import 'package:tetrofall/game/render/board_blocks_component.dart';
import 'package:tetrofall/game/render/fall_animator.dart';
import 'package:tetrofall/game/render/shatter_layer.dart';
import 'package:tetrofall/game/render/tile_cache.dart';

/// Smoke tests for the batched render paths. Neither the `drawRawAtlas` board
/// nor the pre-baked tile can be exercised by the engine tests, and a bad
/// buffer length or source rect there fails at raster time on a device rather
/// than at analysis time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = ThemeDefinition.classicWood;
  const cellSize = 20.0;

  ui.Picture record(void Function(Canvas) draw) {
    final recorder = ui.PictureRecorder();
    draw(Canvas(recorder));
    return recorder.endRecording();
  }

  test('a full board renders through the atlas path', () async {
    final engine = GameEngine(random: Random(4));
    engine.start();
    for (var r = 0; r <= engine.grid.maxRow; r++) {
      engine.grid.fillRow(r);
    }

    final fallAnimator = FallAnimator(theme: theme)..cellSize = cellSize;
    final blocks = BoardBlocksComponent(
      engine: engine,
      theme: theme,
      fallAnimator: fallAnimator,
    )..cellSize = cellSize;

    // Before the tile is baked, the flat fallback has to hold the fort.
    expect(TileCache.tile(theme, cellSize), isNull);
    record(blocks.render).dispose();

    await Flame.images.load('blocks/tile_classic_wood.png');
    TileCache.ensure(theme, cellSize);
    expect(TileCache.tile(theme, cellSize), isNotNull);

    record(blocks.render).dispose();
  });

  test('a shatter renders through the atlas path', () async {
    final layer = ShatterLayer(theme: theme)..cellSize = cellSize;
    await layer.onLoad();

    // Nothing live yet: the render must be a clean no-op.
    record(layer.render).dispose();

    layer.addClear([
      for (var c = 0; c < 18; c++)
        ClearedCell(row: 10, col: c, type: BlockType.wood),
    ], 18);

    // Past the crack hold, so shards are in flight rather than delayed.
    for (var i = 0; i < 40; i++) {
      layer.update(1 / 60);
    }
    record(layer.render).dispose();

    layer.reset();
    record(layer.render).dispose();
  });
}
