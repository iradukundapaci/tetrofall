import '../boosters/block_path.dart';
import '../boosters/booster_effects.dart';
import '../boosters/booster_target.dart';
import '../boosters/booster_type.dart';
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

/// A player intent that actually took effect. Emitted only for input the
/// engine acted on — a swipe into a wall moves nothing and says nothing — so
/// the tutorial can tell "they tried" from "they did it".
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

  /// How much the engine compressed this shatter, so the crack sequence can
  /// run at the same speed the engine is waiting for.
  final double timeScale;

  /// Whether the engine wiped this row rather than the player completing it —
  /// the board-clearing sweep a rewarded continue pays for.
  ///
  /// It still shatters and still sounds like a clear, because that is the
  /// point of it. But it is not something the player did: [Scoring] already
  /// declines to award it, and anything counting what the player achieved
  /// must skip it too, or one continue reads as thirty-two line clears.
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

/// A booster committed its edit to the grid. The render layer plays the
/// effect from here; the engine has already moved on to the resolve.
///
/// Booster events live in this file rather than next to the boosters because
/// [GameEvent] is sealed: every event the engine can emit is declared here, so
/// a listener that switches over one is told when a new kind appears.
class BoosterFiredEvent extends GameEvent {
  const BoosterFiredEvent(this.type, this.target, this.result);

  final BoosterType type;
  final BoosterTarget target;
  final BoosterResult result;
}

/// One block's journey, with the flight time the engine budgeted for it.
class BlockPathEvent {
  const BlockPathEvent({required this.path, required this.durationSeconds});

  final BlockPath path;
  final double durationSeconds;
}

/// Blocks that travelled somewhere a [BlocksFellEvent] could not describe —
/// sideways, or around a corner (`boosters.md` §6.0).
class BlocksMovedEvent extends GameEvent {
  const BlocksMovedEvent(this.paths);

  final List<BlockPathEvent> paths;
}

/// A booster was armed, or the armed one was cancelled. Null means nothing is
/// armed any more.
class BoosterArmedEvent extends GameEvent {
  const BoosterArmedEvent(this.type);

  final BoosterType? type;
}
