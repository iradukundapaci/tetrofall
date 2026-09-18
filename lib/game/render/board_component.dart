import 'dart:math' as math;

import 'package:flame/components.dart';

import '../../models/theme_definition.dart';
import '../boosters/booster_run_state.dart';
import '../boosters/booster_type.dart';
import '../config/board_config.dart';
import '../config/motion.dart';
import '../engine/events.dart';
import '../engine/game_engine.dart';
import 'board_blocks_component.dart';
import 'board_frame.dart';
import 'booster_preview_layer.dart';
import 'fall_animator.dart';
import 'pending_row_component.dart';
import 'piece_component.dart';
import 'shatter_layer.dart';
import 'tile_cache.dart';

class BoardComponent extends PositionComponent with HasGameReference {
  BoardComponent({
    required this.engine,
    required this.boosters,
    this.theme = ThemeDefinition.classicWood,
  });

  final GameEngine engine;
  final BoosterRunState boosters;
  final ThemeDefinition theme;

  late final BoardFrame frame;
  late final ClipComponent _clip;
  late final PositionComponent _contentLayer;
  late final PieceComponent pieceComponent;
  late final FallAnimator fallAnimator;
  late final PendingRowComponent pendingRowComponent;
  late final ShatterLayer shatterLayer;
  late final BoardBlocksComponent blocksComponent;
  late final BoosterPreviewLayer boosterPreviewLayer;

  double get cellSize => frame.cellSize;

  (int, int)? cellFromScreen(Vector2 screenPos) {
    if (cellSize <= 0) return null;
    final rise = engine.riseController;
    final localX = screenPos.x - position.x;
    final localY = screenPos.y - position.y + rise.riseProgress * cellSize;
    final col = (localX / cellSize).floor();
    final row = (localY / cellSize).floor();
    final grid = engine.grid;
    if (row < 0 || row > grid.maxRow || col < 0 || col >= grid.cols) {
      return null;
    }
    return (row, col);
  }

  @override
  Future<void> onLoad() async {
    frame = BoardFrame(
      cols: BoardConfig.cols,
      rows: BoardConfig.rows,
      cellSize: 1,
      theme: theme,
    );
    await add(frame);

    _clip = ClipComponent.rectangle(size: frame.size);
    await add(_clip);

    _contentLayer = PositionComponent();
    await _clip.add(_contentLayer);

    fallAnimator = FallAnimator(theme: theme);

    blocksComponent = BoardBlocksComponent(
      engine: engine,
      theme: theme,
      fallAnimator: fallAnimator,
    );
    await _contentLayer.add(blocksComponent);

    pieceComponent = PieceComponent(engine: engine, theme: theme);
    await _contentLayer.add(pieceComponent);

    await _contentLayer.add(fallAnimator);

    pendingRowComponent = PendingRowComponent(theme: theme);
    await _contentLayer.add(pendingRowComponent);

    shatterLayer = ShatterLayer(theme: theme);
    await _contentLayer.add(shatterLayer);

    boosterPreviewLayer = BoosterPreviewLayer(state: boosters, theme: theme);
    await _contentLayer.add(boosterPreviewLayer);

    engine.addEventListener(_onEngineEvent);

    _layout(game.size);
  }

  void resetForRestart() {
    // The roll overlay can close on the very first frame, before Flame has
    // run `onLoad` and built the layers — and a board with no layers has
    // nothing to reset.
    if (!isLoaded) return;
    fallAnimator.reset();
    shatterLayer.reset();
  }

  void _onEngineEvent(GameEvent event) {
    if (event is BlocksFellEvent) {
      fallAnimator.addFalls(event.falls);
    } else if (event is BlocksMovedEvent) {
      fallAnimator.addPaths(event.paths);
    } else if (event is RowsClearedEvent) {
      shatterLayer.addClear(
        event.cells,
        BoardConfig.cols,
        linesCleared: event.rows.length,
        timeScale: event.timeScale,
      );
    } else if (event is BoosterFiredEvent) {
      _playBoosterEffect(event);
    }
  }

  /// A booster's cells coming apart (`boosters.md` §6). The shards, the pool
  /// and the budget are the ones a line clear already uses; what changes per
  /// booster is the order the cells break in and where they are thrown.
  void _playBoosterEffect(BoosterFiredEvent event) {
    final removed = event.result.removed;
    if (removed.isEmpty) return;

    final scale = engine.resolveTimeScale;
    switch (event.type) {
      case BoosterType.bomb:
        // Ring by ring, out from the centre, shards biased away from it.
        shatterLayer.addBoosterBurst(
          removed,
          BoardConfig.cols,
          origin: (event.target.row ?? 0, event.target.col ?? 0),
          stepSeconds: Motion.boosterBombRing.inMilliseconds / 1000,
          leadSeconds: Motion.boosterBombFuse.inMilliseconds / 1000,
          timeScale: scale,
        );
      case BoosterType.drill:
        // In sweep order, from the edge the bit entered by — the nearer one.
        final row = event.target.row ?? 0;
        final entry = (event.target.col ?? 0) < BoardConfig.cols / 2
            ? 0
            : BoardConfig.cols - 1;
        shatterLayer.addBoosterBurst(
          removed,
          BoardConfig.cols,
          origin: (row, entry),
          spread: BurstSpread.sweep,
          stepSeconds: Motion.boosterDrillCellStep.inMilliseconds / 1000,
          timeScale: scale,
        );
      case BoosterType.sweep:
        // The gust crosses left to right and cells go as it reaches them.
        shatterLayer.addBoosterBurst(
          removed,
          BoardConfig.cols,
          origin: (removed.first.row, 0),
          spread: BurstSpread.sweep,
          stepSeconds:
              Motion.boosterSweep.inMilliseconds / 1000 / BoardConfig.cols,
          timeScale: scale,
        );
      case BoosterType.wildfire:
        // Outward from the cell the fire was started in, one layer at a time.
        shatterLayer.addBoosterBurst(
          removed,
          BoardConfig.cols,
          origin: (event.target.row ?? 0, event.target.col ?? 0),
          stepSeconds: Motion.boosterFireLayer.inMilliseconds / 1000,
          timeScale: scale,
        );
      case BoosterType.hammer:
        shatterLayer.addBoosterBurst(
          removed,
          BoardConfig.cols,
          origin: (event.target.row ?? 0, event.target.col ?? 0),
          leadSeconds: Motion.boosterHammerSwing.inMilliseconds / 1000,
          timeScale: scale,
        );
      case _:
        shatterLayer.addBoosterBurst(
          removed,
          BoardConfig.cols,
          timeScale: scale,
        );
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!isLoaded) return;
    _layout(size);
  }

  void _layout(Vector2 gameSize) {
    final widthCellSize = gameSize.x / BoardConfig.cols;
    final heightCellSize = gameSize.y / BoardConfig.rows;

    final newCellSize = math.min(widthCellSize, heightCellSize);

    // Rebake the tinted tile for the new cell size before anything renders
    // at it, so the flat-fill fallback is never visible on a resize.
    TileCache.ensure(theme, newCellSize);

    frame.cellSize = newCellSize;
    _clip.size = frame.size;

    position = Vector2(
      (gameSize.x - frame.size.x) / 2,
      (gameSize.y - frame.size.y) / 2,
    );
    pieceComponent.cellSize = newCellSize;
    fallAnimator.cellSize = newCellSize;
    pendingRowComponent.updateLayout(newCellSize);
    shatterLayer.cellSize = newCellSize;
    blocksComponent.cellSize = newCellSize;
    boosterPreviewLayer.cellSize = newCellSize;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final grid = engine.grid;
    final rise = engine.riseController;

    _contentLayer.position = Vector2(0, -rise.riseProgress * cellSize);

    pendingRowComponent.row = rise.pendingRow;
    pendingRowComponent.riseProgress = rise.riseProgress;

    var warn = false;
    for (var r = 0; r <= Motion.riseWarnRow; r++) {
      if (grid.rowHasAnyBlock(r)) {
        warn = true;
        break;
      }
    }
    frame.warning = warn;
  }
}
