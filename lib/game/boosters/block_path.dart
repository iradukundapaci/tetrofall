import '../engine/cell.dart';

/// Every cell one block visits, in order, start first (`boosters.md` §6.0).
///
/// [BlockFallEvent] only carries a column and two rows, so it can describe a
/// drop and nothing else. Slide and Tilt move blocks sideways, so they need a
/// shape that can turn a corner.
class BlockPath {
  const BlockPath(this.cells, this.type);

  final List<(int row, int col)> cells;
  final BlockType type;

  (int, int) get from => cells.first;
  (int, int) get to => cells.last;
}
