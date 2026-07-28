/// All nine block types from game.md §1.8, plus [key] — the un-named
/// pairing block that §1.8's Locked entry requires ("Keys spawn in the
/// same row") but that P.3's asset list never gave its own tile, so it
/// renders as a code-drawn glyph instead of a sprite (see
/// `BlockComponent`). Falling tetrominoes are always [wood] — specials
/// arrive only inside rising rows, starting Phase 7.
enum BlockType {
  wood,
  stone,
  ice,
  iceCracked,
  bomb,
  gold,
  diamond,
  treasure,
  locked,
  rainbow,
  key,
}

/// One settled block. `null` in a [Grid] cell means empty.
class Cell {
  Cell(this.type, {int? hp}) : hp = hp ?? (type == BlockType.ice ? 2 : 1);

  BlockType type;

  /// Hits remaining before this cell is removed. Only [BlockType.ice]
  /// starts above 1 — see §1.8: first completion cracks it, second clears.
  int hp;

  /// Whether a row containing this cell can complete at all. Only Stone
  /// blocks completion outright — Locked *can* be part of a completing
  /// row, it just survives the clear unless a Key clears in the same
  /// resolve; that pairing logic lives in `SpecialBlocks` (§1.8, Phase 7).
  bool get blocksLineClear => type == BlockType.stone;

  Cell copyWith({BlockType? type, int? hp}) =>
      Cell(type ?? this.type, hp: hp ?? this.hp);
}
