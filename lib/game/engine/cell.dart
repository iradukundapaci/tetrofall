/// All nine block types (game.md §1.8). Falling tetrominoes are always
/// [wood] — specials arrive only inside rising rows, starting Phase 7.
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
}

/// One settled block. `null` in a [Grid] cell means empty.
class Cell {
  Cell(this.type, {int? hp}) : hp = hp ?? (type == BlockType.ice ? 2 : 1);

  BlockType type;

  /// Hits remaining before this cell is removed. Only [BlockType.ice]
  /// starts above 1 — see §1.8: first completion cracks it, second clears.
  int hp;

  /// Whether a completed line containing this cell can actually clear it.
  /// Stone never can; Locked needs a paired Key cleared in the same
  /// resolve (§1.8), which is engine logic added in Phase 7 — until then
  /// this getter is the full rule.
  bool get blocksLineClear => type == BlockType.stone;

  Cell copyWith({BlockType? type, int? hp}) =>
      Cell(type ?? this.type, hp: hp ?? this.hp);
}
