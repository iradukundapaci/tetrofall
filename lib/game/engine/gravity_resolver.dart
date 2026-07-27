import 'grid.dart';

/// One block's move during cascade resolution, for the render layer's fall
/// animation (§2.2). The grid already holds the final state by the time
/// this is produced — logic commits instantly, render catches up (§3.1).
class BlockFall {
  const BlockFall({required this.col, required this.fromRow, required this.toRow});

  final int col;
  final int fromRow;
  final int toRow;
}

/// Resolves what happens to settled blocks after row(s) clear (§1.6).
/// Swappable behind a debug flag so [ColumnCascade] (the shipping default)
/// and `StickyGroup` can both be play-tested.
abstract class GravityResolver {
  /// Mutates [grid] in place to its final resting state and returns every
  /// block that moved.
  List<BlockFall> resolve(Grid grid);
}
