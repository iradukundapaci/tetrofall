import 'package:flame/components.dart';

import '../../models/theme_definition.dart';
import '../config/board_config.dart';
import '../engine/events.dart';
import '../engine/game_engine.dart';
import 'block_component.dart';
import 'board_frame.dart';
import 'fall_animator.dart';
import 'piece_component.dart';

/// Owns board layout: derives [cellSize] from the available viewport rect
/// at layout time (never hardcoded, see game.md §1.1) and keeps the frame
/// centered as the game resizes. Also owns the settled-block render pool
/// (synced from [GameEngine.grid] every frame), the active piece, and the
/// cascade fall animation.
class BoardComponent extends PositionComponent with HasGameReference {
  BoardComponent({required this.engine, this.theme = ThemeDefinition.classicWood});

  final GameEngine engine;
  final ThemeDefinition theme;

  late final BoardFrame frame;
  late final PieceComponent pieceComponent;
  late final FallAnimator fallAnimator;

  /// One [BlockComponent] per visible cell, indexed `[row][col]`. Rebuilt
  /// from `engine.grid` every frame — Phase 1's placeholder clear (instant
  /// row removal) and Phase 3's cascade both just become "the grid changed
  /// since last frame" from this pool's point of view. Cells currently
  /// mid-flight in [fallAnimator] are hidden here so the block doesn't
  /// appear twice — once teleported, once animating.
  final List<List<BlockComponent>> _blocks = [];

  double get cellSize => frame.cellSize;

  @override
  Future<void> onLoad() async {
    frame = BoardFrame(
      cols: BoardConfig.cols,
      rows: BoardConfig.rows,
      cellSize: 1,
      theme: theme,
    );
    await add(frame);

    for (var r = 0; r < BoardConfig.rows; r++) {
      final row = <BlockComponent>[];
      for (var c = 0; c < BoardConfig.cols; c++) {
        final block = BlockComponent(theme: theme);
        row.add(block);
        await add(block);
      }
      _blocks.add(row);
    }

    pieceComponent = PieceComponent(engine: engine, theme: theme);
    await add(pieceComponent);

    fallAnimator = FallAnimator(theme: theme);
    await add(fallAnimator);

    engine.addEventListener(_onEngineEvent);

    _layout(game.size);
  }

  void _onEngineEvent(GameEvent event) {
    if (event is BlocksFellEvent) {
      fallAnimator.addFalls(event.falls);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!isLoaded) return;
    _layout(size);
  }

  void _layout(Vector2 gameSize) {
    final availableWidth = gameSize.x * 0.9;
    final availableHeight = gameSize.y * 0.78;
    final newCellSize = (availableWidth / BoardConfig.cols).clamp(
      0.0,
      availableHeight / BoardConfig.rows,
    );
    frame.cellSize = newCellSize;
    position = (gameSize - frame.size) / 2;
    pieceComponent.cellSize = newCellSize;
    fallAnimator.cellSize = newCellSize;
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
    for (var r = 0; r < BoardConfig.rows; r++) {
      for (var c = 0; c < BoardConfig.cols; c++) {
        final block = _blocks[r][c];
        if (fallAnimator.activeTargets.contains((r, c))) {
          block.blockVisible = false;
          continue;
        }
        final cell = grid.at(r, c);
        block.blockVisible = cell != null;
        if (cell != null) block.blockType = cell.type;
      }
    }
  }
}
