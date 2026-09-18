import '../config/board_config.dart';
import 'cell.dart';

class Grid {
  Grid({
    this.cols = BoardConfig.cols,
    this.visibleRows = BoardConfig.rows,
    this.spawnRows = BoardConfig.spawnRows,
  }) : _cells = List.generate(
         visibleRows + spawnRows,
         (_) => List<Cell?>.filled(cols, null),
       );

  final int cols;
  final int visibleRows;
  final int spawnRows;

  final List<List<Cell?>> _cells;

  int get minRow => -spawnRows;
  int get maxRow => visibleRows - 1;

  bool inBounds(int row, int col) =>
      col >= 0 && col < cols && row >= minRow && row <= maxRow;

  Cell? at(int row, int col) {
    if (!inBounds(row, col)) return null;
    return _cells[row + spawnRows][col];
  }

  void set(int row, int col, Cell? cell) {
    assert(inBounds(row, col), 'set out of bounds: ($row,$col)');
    _cells[row + spawnRows][col] = cell;
  }

  bool isOccupied(int row, int col) => at(row, col) != null;

  bool isRowFull(int row) {
    for (var c = 0; c < cols; c++) {
      if (at(row, c) == null) return false;
    }
    return true;
  }

  bool rowHasAnyBlock(int row) {
    for (var c = 0; c < cols; c++) {
      if (at(row, c) != null) return true;
    }
    return false;
  }

  void clearAll() {
    for (var r = minRow; r <= maxRow; r++) {
      for (var c = 0; c < cols; c++) {
        set(r, c, null);
      }
    }
  }

  /// Fills every empty cell in a single visible [row] — used one row at a
  /// time, bottom-to-top, by the Watch-Ad-To-Continue fill animation.
  void fillRow(int row) {
    for (var c = 0; c < cols; c++) {
      if (at(row, c) == null) {
        set(row, c, Cell(BlockType.wood));
      }
    }
  }

  /// A copy of one visible row, left to right. Slide rebuilds a row from
  /// this rather than reading cell by cell (`boosters.md` §5.5).
  List<Cell?> rowCells(int row) => [for (var c = 0; c < cols; c++) at(row, c)];

  /// Carries one cell from one coordinate to another, emptying the source.
  /// The mover boosters settle the board themselves, so they need this rather
  /// than the column-at-a-time repacking the cascades do.
  void move((int, int) from, (int, int) to) {
    final cell = at(from.$1, from.$2);
    set(from.$1, from.$2, null);
    set(to.$1, to.$2, cell);
  }

  /// Empties the spawn buffer above the board. It isn't rendered, so
  /// unlike a visible-row clear it needs no animation — just a direct
  /// wipe so nothing left over there can block the next spawn after a
  /// Watch-Ad-To-Continue.
  void clearSpawnRows() {
    for (var r = minRow; r < 0; r++) {
      for (var c = 0; c < cols; c++) {
        set(r, c, null);
      }
    }
  }
}
