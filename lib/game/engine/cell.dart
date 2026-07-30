enum BlockType { wood }

class Cell {
  Cell(this.type);

  BlockType type;

  Cell copyWith({BlockType? type}) => Cell(type ?? this.type);
}
