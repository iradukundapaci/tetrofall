import 'cell.dart';
import 'grid.dart';

class BlockFall {
  const BlockFall({
    required this.col,
    required this.fromRow,
    required this.toRow,
    required this.type,
  });

  final int col;
  final int fromRow;
  final int toRow;

  final BlockType type;
}

abstract class GravityResolver {
  List<BlockFall> resolve(Grid grid);
}
