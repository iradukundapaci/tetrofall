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
  const RowsClearedEvent(this.rows, this.cells, {this.timeScale = 1.0});
  final List<int> rows;
  final List<ClearedCell> cells;

  /// How much the engine compressed this shatter, so the crack sequence can
  /// run at the same speed the engine is waiting for.
  final double timeScale;
}

class BlockFallEvent {
  const BlockFallEvent({
    required this.fromRow,
    required this.toRow,
    required this.col,
    required this.type,
    required this.durationSeconds,
  });
  final int fromRow;
  final int toRow;
  final int col;
  final BlockType type;

  /// Flight time the engine budgeted for this block. The engine owns resolve
  /// timing, so the animator uses this rather than re-deriving it from
  /// [Motion.gravityCellsPerS2] and drifting out of sync.
  final double durationSeconds;
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
