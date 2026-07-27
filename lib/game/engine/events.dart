/// Domain events the engine emits after committing a state change. The
/// render layer reads engine state and turns these into animation — see
/// game.md §3.1. Grows across phases: this file starts with what Phase 1-3
/// need; `RiseCommitted`, booster events etc. join in later phases.
sealed class GameEvent {
  const GameEvent();
}

class PieceSpawnedEvent extends GameEvent {
  const PieceSpawnedEvent();
}

class PieceLockedEvent extends GameEvent {
  const PieceLockedEvent();
}

class RowsClearedEvent extends GameEvent {
  const RowsClearedEvent(this.rows);
  final List<int> rows;
}

/// One block's fall during cascade resolution (§1.6, §2.2). Phase 3.
class BlockFallEvent {
  const BlockFallEvent({
    required this.fromRow,
    required this.toRow,
    required this.col,
  });
  final int fromRow;
  final int toRow;
  final int col;
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
