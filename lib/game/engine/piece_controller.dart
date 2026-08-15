import '../config/motion.dart';
import 'cell.dart';
import 'grid.dart';
import 'tetromino.dart';

class ActivePiece {
  ActivePiece({
    required this.type,
    required this.anchorRow,
    required this.anchorCol,
  }) : rotation = RotationState.spawn;

  final TetrominoType type;
  RotationState rotation;
  int anchorRow;
  int anchorCol;

  List<GridOffset> get cells => Tetromino.cellsFor(type, rotation);

  List<GridOffset> absoluteCells() => [
    for (final c in cells) GridOffset(anchorRow + c.row, anchorCol + c.col),
  ];
}

enum PieceTickResult { continues, locked }

class PieceController {
  PieceController(this.grid);

  final Grid grid;

  ActivePiece? _piece;
  ActivePiece? get piece => _piece;

  bool _grounded = false;
  double _gravityTimer = 0;
  double _lockTimer = 0;
  int _resetCount = 0;

  Duration dropInterval = const Duration(milliseconds: 800);
  bool softDropActive = false;

  bool spawn(TetrominoType type) {
    final anchorCol = Tetromino.spawnColumn[type]!;
    final anchorRow = grid.minRow;
    final candidate = ActivePiece(
      type: type,
      anchorRow: anchorRow,
      anchorCol: anchorCol,
    );
    _piece = candidate;
    _grounded = false;
    _gravityTimer = 0;
    _lockTimer = 0;
    _resetCount = 0;
    if (_collides(candidate.cells, anchorRow, anchorCol)) {
      return false;
    }
    _updateGrounded();
    return true;
  }

  bool _collides(List<GridOffset> cells, int anchorRow, int anchorCol) {
    for (final c in cells) {
      final row = anchorRow + c.row;
      final col = anchorCol + c.col;
      if (!grid.inBounds(row, col)) return true;
      if (grid.isOccupied(row, col)) return true;
    }
    return false;
  }

  bool collidesAt(int anchorRow, int anchorCol) {
    final p = _piece;
    if (p == null) return false;
    return _collides(p.cells, anchorRow, anchorCol);
  }

  void _updateGrounded() {
    final p = _piece;
    if (p == null) return;
    final below = _collides(p.cells, p.anchorRow + 1, p.anchorCol);
    // Landing on a fresh surface restarts the lock delay, but only out of
    // the same budget a move or rotation spends. Refreshing it for free let
    // a piece be walked off a ledge and back on forever.
    if (below && !_grounded && _resetCount < Motion.lockResetLimit) {
      _lockTimer = 0;
    }
    _grounded = below;
  }

  void _onSuccessfulAction() {
    if (!_grounded) return;
    if (_resetCount < Motion.lockResetLimit) {
      _lockTimer = 0;
      _resetCount++;
    }
  }

  bool moveLeft() => _playerShift(0, -1);
  bool moveRight() => _playerShift(0, 1);

  bool _playerShift(int dRow, int dCol) {
    final moved = _attemptShift(dRow, dCol);
    if (moved) _onSuccessfulAction();
    return moved;
  }

  bool _attemptShift(int dRow, int dCol) {
    final p = _piece;
    if (p == null) return false;
    final newRow = p.anchorRow + dRow;
    final newCol = p.anchorCol + dCol;
    if (_collides(p.cells, newRow, newCol)) return false;
    p.anchorRow = newRow;
    p.anchorCol = newCol;
    _updateGrounded();
    return true;
  }

  /// Slides the piece straight down towards [targetRow], stopping early if
  /// anything is in the way. Returns the row it came to rest on.
  ///
  /// Pieces spawn at `grid.minRow`, entirely inside the hidden spawn buffer,
  /// and only ordinary gravity carries them into view. The tutorial freezes
  /// gravity, so without this its very first coached step would ask the
  /// player to steer a piece they cannot see.
  int lowerTo(int targetRow) {
    final p = _piece;
    if (p == null) return 0;
    while (p.anchorRow < targetRow &&
        !_collides(p.cells, p.anchorRow + 1, p.anchorCol)) {
      p.anchorRow++;
    }
    _updateGrounded();
    return p.anchorRow;
  }

  bool rotateCW() => _rotate(clockwise: true);
  bool rotateCCW() => _rotate(clockwise: false);

  bool _rotate({required bool clockwise}) {
    final p = _piece;
    if (p == null) return false;
    final target = clockwise ? p.rotation.rotatedCW() : p.rotation.rotatedCCW();
    final targetCells = Tetromino.cellsFor(p.type, target);
    for (final kick in Tetromino.kicksFor(p.type, p.rotation, target)) {
      final row = p.anchorRow + kick.row;
      final col = p.anchorCol + kick.col;
      if (!_collides(targetCells, row, col)) {
        p.rotation = target;
        p.anchorRow = row;
        p.anchorCol = col;
        _updateGrounded();
        _onSuccessfulAction();
        return true;
      }
    }
    return false;
  }

  void hardDrop() {
    while (_attemptShift(1, 0)) {}
  }

  int? ghostLandingRow() {
    final p = _piece;
    if (p == null) return null;
    var row = p.anchorRow;
    while (!_collides(p.cells, row + 1, p.anchorCol)) {
      row++;
    }
    return row;
  }

  void lockPiece() {
    final p = _piece;
    if (p == null) return;
    for (final c in p.absoluteCells()) {
      grid.set(c.row, c.col, Cell(BlockType.wood));
    }
    _piece = null;
  }

  PieceTickResult tick(double dt) {
    final p = _piece;
    if (p == null) return PieceTickResult.continues;

    final intervalMs = softDropActive
        ? dropInterval.inMilliseconds / Motion.softDropDivisor
        : dropInterval.inMilliseconds.toDouble();
    final intervalSeconds = intervalMs / 1000;

    _gravityTimer += dt;
    if (_gravityTimer >= intervalSeconds) {
      _gravityTimer -= intervalSeconds;
      _attemptShift(1, 0);
    }
    _updateGrounded();

    if (_grounded) {
      _lockTimer += dt;
      // Only the delay running out locks a piece. Exhausting the reset
      // budget used to lock it on the spot, so the fifteenth nudge along a
      // row snapped the piece down under the player's finger instead of
      // simply being the last nudge that bought more time.
      if (_lockTimer * 1000 >= Motion.lockDelay.inMilliseconds) {
        return PieceTickResult.locked;
      }
    }
    return PieceTickResult.continues;
  }
}
