import 'dart:math' as math;

import 'package:flame/components.dart';

import '../../models/theme_definition.dart';
import '../config/board_config.dart';
import '../config/motion.dart';
import '../engine/events.dart';
import '../engine/game_engine.dart';
import 'block_component.dart';
import 'board_frame.dart';
import 'combo_banner.dart';
import 'fall_animator.dart';
import 'pending_row_component.dart';
import 'piece_component.dart';
import 'shatter_layer.dart';

/// Owns board layout: derives [cellSize] from the available viewport rect
/// at layout time (never hardcoded, see game.md §1.1) and keeps the frame
/// centered as the game resizes. Also owns the settled-block render pool
/// (synced from [GameEngine.grid] every frame), the active piece, the
/// cascade fall animation, and the rise mechanic's continuous scroll
/// (§2.1) — everything that scrolls with the rise lives in [_contentLayer],
/// clipped to the frame's bounds so the emerging pending row is hidden
/// until it slides into view. The frame itself stays fixed.
class BoardComponent extends PositionComponent with HasGameReference {
  BoardComponent({required this.engine, this.theme = ThemeDefinition.classicWood});

  final GameEngine engine;
  final ThemeDefinition theme;

  late final BoardFrame frame;
  late final ClipComponent _clip;
  late final PositionComponent _contentLayer;
  late final PieceComponent pieceComponent;
  late final FallAnimator fallAnimator;
  late final PendingRowComponent pendingRowComponent;
  late final ShatterLayer shatterLayer;
  late final ComboBanner comboBanner;

  /// One [BlockComponent] per visible cell, indexed `[row][col]`. Rebuilt
  /// from `engine.grid` every frame — Phase 1's placeholder clear (instant
  /// row removal) and Phase 3's cascade both just become "the grid changed
  /// since last frame" from this pool's point of view. Cells currently
  /// mid-flight in [fallAnimator] are hidden here so the block doesn't
  /// appear twice — once teleported, once animating.
  final List<List<BlockComponent>> _blocks = [];

  double get cellSize => frame.cellSize;

  /// Converts a screen-space position to a visible grid cell, accounting
  /// for the board's centering offset and the rise's continuous scroll
  /// (§2.1) so the tapped cell matches what's on screen. Returns null
  /// outside the visible board.
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

    for (var r = 0; r < BoardConfig.rows; r++) {
      final row = <BlockComponent>[];
      for (var c = 0; c < BoardConfig.cols; c++) {
        final block = BlockComponent(theme: theme);
        row.add(block);
        await _contentLayer.add(block);
      }
      _blocks.add(row);
    }

    pieceComponent = PieceComponent(engine: engine, theme: theme);
    await _contentLayer.add(pieceComponent);

    fallAnimator = FallAnimator(theme: theme);
    await _contentLayer.add(fallAnimator);

    pendingRowComponent = PendingRowComponent(theme: theme);
    await _contentLayer.add(pendingRowComponent);

    shatterLayer = ShatterLayer(theme: theme);
    await _contentLayer.add(shatterLayer);

    // Outside the clip/content layer on purpose: the banner overlays the
    // top of the full-bleed board and must not scroll with the rise.
    comboBanner = ComboBanner();
    await add(comboBanner);

    engine.addEventListener(_onEngineEvent);

    _layout(game.size);
  }

  /// Clears every render-only animation carryover from the run that just
  /// ended — shatter shards, an in-flight cascade fall, and the combo
  /// banner — before [GameEngine.start] spawns the first piece of a new
  /// run (§4). The logical grid itself is already cleared by
  /// `GameEngine.start`; this only concerns state `_onEngineEvent`
  /// wouldn't otherwise reset, since those animations are designed to
  /// outlive a single resolve.
  void resetForRestart() {
    fallAnimator.reset();
    shatterLayer.reset();
    comboBanner.reset();
  }

  void _onEngineEvent(GameEvent event) {
    if (event is BlocksFellEvent) {
      fallAnimator.addFalls(event.falls);
    } else if (event is RowsClearedEvent) {
      shatterLayer.addClear(event.cells, BoardConfig.cols);
    } else if (event is ComboBannerEvent) {
      comboBanner.trigger(event.tier);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!isLoaded) return;
    _layout(size);
  }

  /// Full-bleed layout, matching the reference footage: the board fills
  /// the entire box the Flutter `Expanded` region hands it — no side
  /// margins, no reserved strips. `cellSize` is whichever of width/21 or
  /// height/37 fits; on typical phones that's edge-to-edge. The combo
  /// banner overlays the top of the board instead of reserving space.
  void _layout(Vector2 gameSize) {
    final widthCellSize = gameSize.x / BoardConfig.cols;
    final heightCellSize = gameSize.y / BoardConfig.rows;

    final newCellSize = math.min(widthCellSize, heightCellSize);
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

    final bannerHeight = newCellSize * 2.4;
    comboBanner
      ..size = Vector2(frame.size.x, bannerHeight)
      ..position = Vector2(0, newCellSize * 1.2);
    for (var r = 0; r < BoardConfig.rows; r++) {
      for (var c = 0; c < BoardConfig.cols; c++) {
        _blocks[r][c].setLayout(cellSize: newCellSize, row: r, col: c);
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    final grid = engine.grid;
    final rise = engine.riseController;

    // The whole content layer drifts up continuously with the rise —
    // nothing snaps (§2.1).
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

    for (var r = 0; r < BoardConfig.rows; r++) {
      for (var c = 0; c < BoardConfig.cols; c++) {
        final block = _blocks[r][c];
        if (fallAnimator.activeTargets.contains((r, c))) {
          block.blockVisible = false;
          continue;
        }
        block.blockVisible = grid.at(r, c) != null;
      }
    }
  }
}
