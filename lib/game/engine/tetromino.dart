import 'dart:math';

import '../config/board_config.dart';

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

enum RotationState { spawn, right, flip, left }

extension on RotationState {
  RotationState clockwise() =>
      RotationState.values[(index + 1) % RotationState.values.length];
  RotationState counterClockwise() =>
      RotationState.values[(index + 3) % RotationState.values.length];
}

abstract final class Tetromino {
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

  static final Map<TetrominoType, int> spawnColumn = {
    TetrominoType.I: (BoardConfig.cols - 4) ~/ 2,
    TetrominoType.O: (BoardConfig.cols - 2) ~/ 2,
    TetrominoType.T: (BoardConfig.cols - 3) ~/ 2,
    TetrominoType.S: (BoardConfig.cols - 3) ~/ 2,
    TetrominoType.Z: (BoardConfig.cols - 3) ~/ 2,
    TetrominoType.J: (BoardConfig.cols - 3) ~/ 2,
    TetrominoType.L: (BoardConfig.cols - 3) ~/ 2,
  };

  static List<GridOffset> cellsFor(TetrominoType type, RotationState state) =>
      _shapes[type]![state.index];

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

  static final Map<(RotationState, RotationState), List<GridOffset>> _iKicks = {
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

  static List<GridOffset> _k(List<(int, int)> dColDRow) => [
    for (final (dCol, dRow) in dColDRow) GridOffset(dRow, dCol),
  ];

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

extension RotationStateTransitions on RotationState {
  RotationState rotatedCW() => clockwise();
  RotationState rotatedCCW() => counterClockwise();
}

class SevenBag {
  SevenBag(this._random);

  final Random _random;
  final List<TetrominoType> _queue = [];

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
