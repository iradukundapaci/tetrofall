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

enum PlayerAction { moveLeft, moveRight, rotate, softDrop, hardDrop }

/// A player intent that actually took effect; a swipe into a wall emits
/// nothing.
class PlayerActionEvent extends GameEvent {
  const PlayerActionEvent(this.action);
  final PlayerAction action;
}

class ClearedCell {
  const ClearedCell({required this.row, required this.col, required this.type});
  final int row;
  final int col;
  final BlockType type;
}

class RowsClearedEvent extends GameEvent {
  const RowsClearedEvent(
    this.rows,
    this.cells, {
    this.timeScale = 1.0,
    this.forced = false,
  });
  final List<int> rows;
  final List<ClearedCell> cells;

  /// How much the engine compressed this shatter; the crack sequence runs at
  /// the same speed.
  final double timeScale;

  /// True for the board-clearing sweep a rewarded continue pays for. It
  /// shatters like a clear but is not something the player did, so anything
  /// counting achievements must skip it.
  final bool forced;
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

  /// Flight time the engine budgeted; the animator must use this rather than
  /// re-deriving it.
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
