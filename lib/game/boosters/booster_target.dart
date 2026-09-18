/// Which way a board-wide mover leans.
enum BoosterDirection { left, right }

/// Everything a booster can be aimed at, in one shape.
///
/// Instant boosters fire with [BoosterTarget.instant], which carries nothing —
/// the effect reads the whole board instead (`boosters.md` §5.7–§5.10).
class BoosterTarget {
  const BoosterTarget({this.row, this.col, this.direction});

  const BoosterTarget.cell(int row, int col) : this(row: row, col: col);
  const BoosterTarget.row(int row) : this(row: row);
  const BoosterTarget.column(int col) : this(col: col);
  const BoosterTarget.rowSwipe(int row, BoosterDirection direction)
    : this(row: row, direction: direction);
  const BoosterTarget.swipe(BoosterDirection direction)
    : this(direction: direction);
  const BoosterTarget.instant() : this();

  final int? row;
  final int? col;
  final BoosterDirection? direction;

  int get dirSign => direction == BoosterDirection.left ? -1 : 1;

  @override
  String toString() => 'BoosterTarget(row: $row, col: $col, dir: $direction)';
}
