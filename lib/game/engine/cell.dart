/// Only plain wooden blocks exist — the game is rising rows + falling
/// tetrominoes, nothing else. The enum survives (rather than deleting the
/// type entirely) so grid/fall/clear plumbing keeps a stable `type` field.
enum BlockType { wood }

/// One settled block. `null` in a [Grid] cell means empty.
class Cell {
  Cell(this.type);

  BlockType type;

  Cell copyWith({BlockType? type}) => Cell(type ?? this.type);
}
