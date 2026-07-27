import '../config/motion.dart';
import 'cell.dart';
import 'grid.dart';
import 'tetromino.dart';

/// The active piece: type, rotation, and the (row, col) of its bounding
/// box's top-left corner.
class ActivePiece {
  ActivePiece({required this.type, required this.anchorRow, required this.anchorCol})
    : rotation = RotationState.spawn;

  final TetrominoType type;
  RotationState rotation;
  int anchorRow;
  int anchorCol;

  List<GridOffset> get cells => Tetromino.cellsFor(type, rotation);

  /// Absolute (row, col) of each occupied cell on the grid.
  List<GridOffset> absoluteCells() => [
    for (final c in cells) GridOffset(anchorRow + c.row, anchorCol + c.col),
  ];
}

enum PieceTickResult { continues, locked }

/// Move/rotate/lock, collision, hard/soft drop, lock delay with reset cap.
/// Pure Dart — see game.md §1.3, §1.12 and §3.1's layer-separation rule.
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

  /// Places a new piece at its spawn position. Returns false if the spawn
  /// cell collides with settled blocks — the block-out game-over condition
  /// (§1.11). The caller is responsible for acting on that.
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

  void _updateGrounded() {
    final p = _piece;
    if (p == null) return;
    final below = _collides(p.cells, p.anchorRow + 1, p.anchorCol);
    if (below && !_grounded) {
      _lockTimer = 0;
    }
    _grounded = below;
  }

  /// Registers a successful move/rotate against the lock-reset cap (§1.3):
  /// up to 15 resets, then the piece force-locks regardless of further
  /// input.
  void _onSuccessfulAction() {
    if (!_grounded) return;
    if (_resetCount < Motion.lockResetLimit) {
      _lockTimer = 0;
      _resetCount++;
    }
  }

  bool moveLeft() => _playerShift(0, -1);
  bool moveRight() => _playerShift(0, 1);

  /// Player-initiated shift: on success, counts against the lock-reset cap.
  bool _playerShift(int dRow, int dCol) {
    final moved = _attemptShift(dRow, dCol);
    if (moved) _onSuccessfulAction();
    return moved;
  }

  /// Raw shift with no lock-reset bookkeeping — used by gravity (which
  /// should never itself spend a reset credit) and by drop methods.
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

  /// Instant descent to the landing row; caller should lock immediately
  /// after (§1.3: hard drop "locks immediately"). Returns rows dropped.
  int hardDrop() {
    var rows = 0;
    while (_attemptShift(1, 0)) {
      rows++;
    }
    return rows;
  }

  /// Row the piece would land on if hard-dropped right now, without
  /// mutating state — feeds the ghost piece (Phase 2).
  int? ghostLandingRow() {
    final p = _piece;
    if (p == null) return null;
    var row = p.anchorRow;
    while (!_collides(p.cells, row + 1, p.anchorCol)) {
      row++;
    }
    return row;
  }

  /// Writes the active piece's cells into the grid and clears it. Call
  /// after a [PieceTickResult.locked] tick.
  void lockPiece() {
    final p = _piece;
    if (p == null) return;
    for (final c in p.absoluteCells()) {
      grid.set(c.row, c.col, Cell(BlockType.wood));
    }
    _piece = null;
  }

  /// Advances gravity and lock-delay timers by [dt] seconds. Returns
  /// [PieceTickResult.locked] when the piece should be locked this frame —
  /// on `RESOLVING`, the caller doesn't return here until spawning again.
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
      _attemptShift(1, 0); // if blocked, _updateGrounded still runs below
    }
    _updateGrounded();

    if (_grounded) {
      _lockTimer += dt;
      if (_lockTimer * 1000 >= Motion.lockDelay.inMilliseconds ||
          _resetCount >= Motion.lockResetLimit) {
        return PieceTickResult.locked;
      }
    }
    return PieceTickResult.continues;
  }
}
