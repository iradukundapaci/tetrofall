import '../game/engine/cell.dart';
import '../game/engine/grid.dart';

/// Preset boards for triggering specific engine behaviour on demand,
/// instead of playing toward it. Phase 3's "Load Fixture" debug button
/// uses [loadCascadeTest] — see game.md Phase 3.
abstract final class DebugFixtures {
  /// A tall, holey stack with one almost-complete middle row (row 17,
  /// missing only column 9) and a scattered stack above it. Drop any piece
  /// with a cell over column 9 and hard-drop it: row 17 completes and
  /// clears, and everything above it should cascade down — independently
  /// per column, onto whatever's below or the floor. Column 1 has no floor
  /// block, so its scattered block should fall all the way to row 19: the
  /// clearest possible demonstration of "never rests above an empty cell."
  static void loadCascadeTest(Grid grid) {
    grid.clearAll();

    const middleRow = 17;
    const gapCol = 9;
    for (var c = 0; c < grid.cols; c++) {
      if (c == gapCol) continue;
      grid.set(middleRow, c, Cell(BlockType.wood));
    }

    grid.set(14, 2, Cell(BlockType.wood));
    grid.set(13, 1, Cell(BlockType.wood));
    grid.set(13, 2, Cell(BlockType.wood));
    grid.set(13, 3, Cell(BlockType.wood));
    grid.set(12, 2, Cell(BlockType.wood));

    // Jagged floor below the middle row — columns 1 and 4 are left open so
    // a falling block has somewhere dramatic to land.
    for (var c = 0; c < grid.cols; c++) {
      if (c == 1 || c == 4) continue;
      grid.set(18, c, Cell(BlockType.wood));
      grid.set(19, c, Cell(BlockType.wood));
    }
  }
}
