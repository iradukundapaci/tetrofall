import 'cell.dart';
import 'combo_tier.dart';

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

/// One cell that was part of a clear, captured just before it's removed
/// from the grid — the shatter layer (§2.3) needs the type to pick the
/// shard color (plain wood -> theme tint, specials -> their own palette).
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

/// One block's fall during cascade resolution (§1.6, §2.2). Phase 3;
/// [type] joined in Phase 7 so specials keep their sprite mid-flight.
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

/// A pending row finished sliding in and was committed into the grid
/// (§1.4). Phase 4.
class RiseCommittedEvent extends GameEvent {
  const RiseCommittedEvent();
}

/// A blocks-destroyed banner threshold was newly crossed within the
/// current resolve (§1.7). Phase 6.
class ComboBannerEvent extends GameEvent {
  const ComboBannerEvent(this.tier);
  final ComboTier tier;
}
