import 'cell.dart';

sealed class GameEvent {
  const GameEvent();
}

class PieceSpawnedEvent extends GameEvent {
  const PieceSpawnedEvent();
}

class PieceLockedEvent extends GameEvent {
  const PieceLockedEvent();
}

class ClearedCell {
  const ClearedCell({required this.row, required this.col, required this.type});
  final int row;
  final int col;
  final BlockType type;
}

class RowsClearedEvent extends GameEvent {
  const RowsClearedEvent(this.rows, this.cells);
  final List<int> rows;
  final List<ClearedCell> cells;
}

class ContinueRevealEvent extends GameEvent {
  const ContinueRevealEvent(this.cells);
  final List<ClearedCell> cells;
}

class BlockFallEvent {
  const BlockFallEvent({
    required this.fromRow,
    required this.toRow,
    required this.col,
    required this.type,
  });
  final int fromRow;
  final int toRow;
  final int col;
  final BlockType type;
}

class BlocksFellEvent extends GameEvent {
  const BlocksFellEvent(this.falls);
  final List<BlockFallEvent> falls;
}

class ChainAdvancedEvent extends GameEvent {
  const ChainAdvancedEvent(this.chainIndex);
  final int chainIndex;
}

enum GameOverReason { topOut, blockOut }

class GameOverEvent extends GameEvent {
  const GameOverEvent(this.reason);
  final GameOverReason reason;
}

class RiseCommittedEvent extends GameEvent {
  const RiseCommittedEvent();
}
