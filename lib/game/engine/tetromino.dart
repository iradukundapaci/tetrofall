import 'dart:math';

/// An integer (row, col) offset. Row grows downward, matching [Grid].
class GridOffset {
  const GridOffset(this.row, this.col);

  final int row;
  final int col;

  GridOffset operator +(GridOffset other) =>
      GridOffset(row + other.row, col + other.col);

  @override
  String toString() => '($row,$col)';
}

enum TetrominoType { I, O, T, S, Z, J, L }

/// Rotation states in SRS order: 0 (spawn), R (clockwise), 2 (180°),
/// L (counter-clockwise).
enum RotationState { spawn, right, flip, left }

extension on RotationState {
  RotationState clockwise() =>
      RotationState.values[(index + 1) % RotationState.values.length];
  RotationState counterClockwise() =>
      RotationState.values[(index + 3) % RotationState.values.length];
}

/// Standard 7 tetrominoes: shapes, spawn position, and SRS wall kicks.
/// See game.md §1.2.
abstract final class Tetromino {
  /// Cell offsets for each rotation state, within each piece's bounding box.
  static const Map<TetrominoType, List<List<GridOffset>>> _shapes = {
    TetrominoType.I: [
      [GridOffset(1, 0), GridOffset(1, 1), GridOffset(1, 2), GridOffset(1, 3)],
      [GridOffset(0, 2), GridOffset(1, 2), GridOffset(2, 2), GridOffset(3, 2)],
      [GridOffset(2, 0), GridOffset(2, 1), GridOffset(2, 2), GridOffset(2, 3)],
      [GridOffset(0, 1), GridOffset(1, 1), GridOffset(2, 1), GridOffset(3, 1)],
    ],
    TetrominoType.O: [
      [GridOffset(0, 0), GridOffset(0, 1), GridOffset(1, 0), GridOffset(1, 1)],
      [GridOffset(0, 0), GridOffset(0, 1), GridOffset(1, 0), GridOffset(1, 1)],
      [GridOffset(0, 0), GridOffset(0, 1), GridOffset(1, 0), GridOffset(1, 1)],
      [GridOffset(0, 0), GridOffset(0, 1), GridOffset(1, 0), GridOffset(1, 1)],
    ],
    TetrominoType.T: [
      [GridOffset(0, 1), GridOffset(1, 0), GridOffset(1, 1), GridOffset(1, 2)],
      [GridOffset(0, 1), GridOffset(1, 1), GridOffset(1, 2), GridOffset(2, 1)],
      [GridOffset(1, 0), GridOffset(1, 1), GridOffset(1, 2), GridOffset(2, 1)],
      [GridOffset(0, 1), GridOffset(1, 0), GridOffset(1, 1), GridOffset(2, 1)],
    ],
    TetrominoType.S: [
      [GridOffset(0, 1), GridOffset(0, 2), GridOffset(1, 0), GridOffset(1, 1)],
      [GridOffset(0, 1), GridOffset(1, 1), GridOffset(1, 2), GridOffset(2, 2)],
      [GridOffset(1, 1), GridOffset(1, 2), GridOffset(2, 0), GridOffset(2, 1)],
      [GridOffset(0, 0), GridOffset(1, 0), GridOffset(1, 1), GridOffset(2, 1)],
    ],
    TetrominoType.Z: [
      [GridOffset(0, 0), GridOffset(0, 1), GridOffset(1, 1), GridOffset(1, 2)],
      [GridOffset(0, 2), GridOffset(1, 1), GridOffset(1, 2), GridOffset(2, 1)],
      [GridOffset(1, 0), GridOffset(1, 1), GridOffset(2, 1), GridOffset(2, 2)],
      [GridOffset(0, 1), GridOffset(1, 0), GridOffset(1, 1), GridOffset(2, 0)],
    ],
    TetrominoType.J: [
      [GridOffset(0, 0), GridOffset(1, 0), GridOffset(1, 1), GridOffset(1, 2)],
      [GridOffset(0, 1), GridOffset(0, 2), GridOffset(1, 1), GridOffset(2, 1)],
      [GridOffset(1, 0), GridOffset(1, 1), GridOffset(1, 2), GridOffset(2, 2)],
      [GridOffset(0, 1), GridOffset(1, 1), GridOffset(2, 0), GridOffset(2, 1)],
    ],
    TetrominoType.L: [
      [GridOffset(0, 2), GridOffset(1, 0), GridOffset(1, 1), GridOffset(1, 2)],
      [GridOffset(0, 1), GridOffset(1, 1), GridOffset(2, 1), GridOffset(2, 2)],
      [GridOffset(1, 0), GridOffset(1, 1), GridOffset(1, 2), GridOffset(2, 0)],
      [GridOffset(0, 0), GridOffset(0, 1), GridOffset(1, 1), GridOffset(2, 1)],
    ],
  };

  /// Column of the bounding box's top-left corner at spawn, centering the
  /// piece on a `BoardConfig.cols == 10` board.
  static const Map<TetrominoType, int> spawnColumn = {
    TetrominoType.I: 3,
    TetrominoType.O: 4,
    TetrominoType.T: 3,
    TetrominoType.S: 3,
    TetrominoType.Z: 3,
    TetrominoType.J: 3,
    TetrominoType.L: 3,
  };

  static List<GridOffset> cellsFor(TetrominoType type, RotationState state) =>
      _shapes[type]![state.index];

  /// SRS wall kicks for JLSTZ pieces, keyed by (from, to) rotation state.
  static final Map<(RotationState, RotationState), List<GridOffset>>
  _jlstzKicks = {
    (RotationState.spawn, RotationState.right): _k([
      (0, 0),
      (-1, 0),
      (-1, -1),
      (0, 2),
      (-1, 2),
    ]),
    (RotationState.right, RotationState.spawn): _k([
      (0, 0),
      (1, 0),
      (1, 1),
      (0, -2),
      (1, -2),
    ]),
    (RotationState.right, RotationState.flip): _k([
      (0, 0),
      (1, 0),
      (1, 1),
      (0, -2),
      (1, -2),
    ]),
    (RotationState.flip, RotationState.right): _k([
      (0, 0),
      (-1, 0),
      (-1, -1),
      (0, 2),
      (-1, 2),
    ]),
    (RotationState.flip, RotationState.left): _k([
      (0, 0),
      (1, 0),
      (1, -1),
      (0, 2),
      (1, 2),
    ]),
    (RotationState.left, RotationState.flip): _k([
      (0, 0),
      (-1, 0),
      (-1, 1),
      (0, -2),
      (-1, -2),
    ]),
    (RotationState.left, RotationState.spawn): _k([
      (0, 0),
      (-1, 0),
      (-1, 1),
      (0, -2),
      (-1, -2),
    ]),
    (RotationState.spawn, RotationState.left): _k([
      (0, 0),
      (1, 0),
      (1, -1),
      (0, 2),
      (1, 2),
    ]),
  };

  /// SRS wall kicks for the I piece — a separate table per the guideline.
  static final Map<(RotationState, RotationState), List<GridOffset>>
  _iKicks = {
    (RotationState.spawn, RotationState.right): _k([
      (0, 0),
      (-2, 0),
      (1, 0),
      (-2, 1),
      (1, -2),
    ]),
    (RotationState.right, RotationState.spawn): _k([
      (0, 0),
      (2, 0),
      (-1, 0),
      (2, -1),
      (-1, 2),
    ]),
    (RotationState.right, RotationState.flip): _k([
      (0, 0),
      (-1, 0),
      (2, 0),
      (-1, -2),
      (2, 1),
    ]),
    (RotationState.flip, RotationState.right): _k([
      (0, 0),
      (1, 0),
      (-2, 0),
      (1, 2),
      (-2, -1),
    ]),
    (RotationState.flip, RotationState.left): _k([
      (0, 0),
      (2, 0),
      (-1, 0),
      (2, -1),
      (-1, 2),
    ]),
    (RotationState.left, RotationState.flip): _k([
      (0, 0),
      (-2, 0),
      (1, 0),
      (-2, 1),
      (1, -2),
    ]),
    (RotationState.left, RotationState.spawn): _k([
      (0, 0),
      (1, 0),
      (-2, 0),
      (1, 2),
      (-2, -1),
    ]),
    (RotationState.spawn, RotationState.left): _k([
      (0, 0),
      (-1, 0),
      (2, 0),
      (-1, -2),
      (2, 1),
    ]),
  };

  /// `(dCol, dRow)` pairs, matching this codebase's row-down convention —
  /// converted once here from the guideline's row-up `(x, y)` kick tables.
  static List<GridOffset> _k(List<(int, int)> dColDRow) =>
      [for (final (dCol, dRow) in dColDRow) GridOffset(dRow, dCol)];

  /// Wall-kick candidate offsets to try, in order, for a rotation attempt.
  /// `O` has none — it does not rotate.
  static List<GridOffset> kicksFor(
    TetrominoType type,
    RotationState from,
    RotationState to,
  ) {
    if (type == TetrominoType.O) return const [GridOffset(0, 0)];
    final table = type == TetrominoType.I ? _iKicks : _jlstzKicks;
    return table[(from, to)] ?? const [GridOffset(0, 0)];
  }
}

/// A piece's live rotation, tracking transitions for kick lookups.
extension RotationStateTransitions on RotationState {
  RotationState rotatedCW() => clockwise();
  RotationState rotatedCCW() => counterClockwise();
}

/// 7-bag randomizer (§1.2): shuffle all seven, deal, reshuffle. Takes an
/// injectable [Random] so runs are seed-reproducible (see game.md §5).
class SevenBag {
  SevenBag(this._random);

  final Random _random;
  final List<TetrominoType> _queue = [];

  /// Current queue contents, for the debug bag readout. Does not mutate
  /// the bag.
  List<TetrominoType> peekAll() => List.unmodifiable(_queue);

  TetrominoType next() {
    if (_queue.isEmpty) _refill();
    return _queue.removeAt(0);
  }

  void _refill() {
    _queue.addAll(TetrominoType.values);
    _queue.shuffle(_random);
  }
}
