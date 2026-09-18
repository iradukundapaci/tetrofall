import 'dart:math' as math;

import '../config/booster_tuning.dart';
import '../engine/cell.dart';
import '../engine/events.dart';
import '../engine/grid.dart';
import 'block_path.dart';
import 'booster_target.dart';
import 'booster_type.dart';
import 'tilt_cascade.dart';

/// What one booster did to the grid, handed to the engine so it can run the
/// shared resolve and to the render layer so it can animate it.
class BoosterResult {
  BoosterResult({
    this.removed = const [],
    this.added = const [],
    this.moved = const [],
    this.lowestChangedRow,
    this.fullBoardSettle = false,
  });

  /// Cells the booster emptied, for the shatter.
  final List<ClearedCell> removed;

  /// Cells the booster filled.
  final List<(int row, int col)> added;

  /// Blocks the booster carried somewhere else, with the route they took.
  final List<BlockPath> moved;

  /// Where the gravity wave is allowed to start from (§4.6 rule 1). Null for
  /// builders: nothing needs to fall unless a row clears.
  final int? lowestChangedRow;

  /// Set by Earthquake and Tilt, which settle the whole board themselves —
  /// the one deliberate exception to `game.md` §1.6 (§5.10, §5.11).
  final bool fullBoardSettle;
}

/// `isValid` and `apply` for all twelve boosters (`boosters.md` §5).
///
/// Every effect edits the grid and stops. Gravity, clears and chains are the
/// engine's existing machinery — one pipeline, twelve small functions.
abstract final class BoosterEffects {
  /// Whether firing [type] at [target] would do anything at all. Instant
  /// boosters are asked this every frame to drive the "no target" look
  /// (§4.2), so every scan here is a straight walk over the grid.
  static bool isValid(
    BoosterType type,
    Grid grid,
    BoosterTarget target,
    Set<(int, int)> solid,
  ) {
    switch (type) {
      case BoosterType.hammer:
        final (r, c) = _cell(target);
        return _inBoard(grid, r, c) &&
            grid.at(r, c) != null &&
            !solid.contains((r, c));

      case BoosterType.bomb:
        final (r, c) = _cell(target);
        if (!_inBoard(grid, r, c)) return false;
        for (final (br, bc) in _blastCells(grid, r, c)) {
          if (grid.at(br, bc) != null) return true;
        }
        return false;

      case BoosterType.patch:
        final (r, c) = _cell(target);
        if (!_inBoard(grid, r, c)) return false;
        if (grid.at(r, c) != null || solid.contains((r, c))) return false;
        // No blocks in open air: it has to touch something.
        if (r == grid.maxRow) return true;
        for (final (nr, nc) in [
          (r - 1, c),
          (r + 1, c),
          (r, c - 1),
          (r, c + 1),
        ]) {
          if (_inBoard(grid, nr, nc) && grid.at(nr, nc) != null) return true;
        }
        return false;

      case BoosterType.drill:
        final r = target.row;
        return r != null && _inRows(grid, r) && grid.rowHasAnyBlock(r);

      case BoosterType.slide:
        final r = target.row;
        if (r == null || !_inRows(grid, r)) return false;
        if (!grid.rowHasAnyBlock(r)) return false;
        var hasGap = false;
        for (var c = 0; c < grid.cols; c++) {
          if (grid.at(r, c) == null) hasGap = true;
        }
        if (!hasGap) return false;
        // Direction only arrives once the swipe locks; before that the row
        // itself is the whole answer.
        if (target.direction == null) return true;
        return _slideCells(grid, r, target.dirSign, solid) != null;

      case BoosterType.pillar:
        final c = target.col;
        if (c == null || c < 0 || c >= grid.cols) return false;
        return _columnHoles(grid, c, solid).isNotEmpty;

      case BoosterType.sweep:
        return _sweepRows(grid).isNotEmpty;

      case BoosterType.lightning:
        return _lightningStrikes(grid, solid).isNotEmpty;

      case BoosterType.mortar:
        return _mortarHoles(grid, solid).isNotEmpty;

      case BoosterType.earthquake:
        for (var r = 0; r < grid.maxRow; r++) {
          for (var c = 0; c < grid.cols; c++) {
            if (grid.at(r, c) != null &&
                grid.at(r + 1, c) == null &&
                !solid.contains((r + 1, c))) {
              return true;
            }
          }
        }
        return false;

      case BoosterType.tilt:
        final dir = target.direction == null ? null : target.dirSign;
        for (var r = grid.maxRow; r >= 0; r--) {
          for (var c = 0; c < grid.cols; c++) {
            if (grid.at(r, c) == null) continue;
            if (_free(grid, solid, r + 1, c)) return true;
            if (dir != null && _free(grid, solid, r, c + dir)) return true;
            if (dir == null &&
                (_free(grid, solid, r, c - 1) ||
                    _free(grid, solid, r, c + 1))) {
              return true;
            }
          }
        }
        return false;

      case BoosterType.wildfire:
        final (r, c) = _cell(target);
        return _inBoard(grid, r, c) &&
            grid.at(r, c) != null &&
            !solid.contains((r, c));
    }
  }

  /// Exactly the cells the booster would touch, for the aim preview (§4.4).
  /// Same scans as [apply], so the preview can never promise something the
  /// effect does not deliver.
  static List<(int, int)> preview(
    BoosterType type,
    Grid grid,
    BoosterTarget target,
    Set<(int, int)> solid,
  ) {
    switch (type) {
      case BoosterType.hammer:
      case BoosterType.patch:
        final (r, c) = _cell(target);
        return _inBoard(grid, r, c) ? [(r, c)] : const [];

      case BoosterType.bomb:
        final (r, c) = _cell(target);
        return _inBoard(grid, r, c) ? _blastCells(grid, r, c) : const [];

      case BoosterType.drill:
        final r = target.row;
        if (r == null || !_inRows(grid, r)) return const [];
        return [for (var c = 0; c < grid.cols; c++) (r, c)];

      case BoosterType.slide:
        final r = target.row;
        if (r == null || !_inRows(grid, r)) return const [];
        return [for (var c = 0; c < grid.cols; c++) (r, c)];

      case BoosterType.pillar:
        final c = target.col;
        if (c == null || c < 0 || c >= grid.cols) return const [];
        return _columnHoles(grid, c, solid);

      case BoosterType.sweep:
        return [
          for (final r in _sweepRows(grid))
            for (var c = 0; c < grid.cols; c++)
              if (grid.at(r, c) != null) (r, c),
        ];

      case BoosterType.lightning:
        return _lightningStrikes(grid, solid);

      case BoosterType.mortar:
        return _mortarHoles(grid, solid);

      case BoosterType.wildfire:
        final (r, c) = _cell(target);
        if (!_inBoard(grid, r, c) || grid.at(r, c) == null) return const [];
        return _burnLayers(grid, r, c).expand((l) => l).toList();

      // Board movers depend on the whole settle, so there is nothing
      // per-cell to outline (§5.11 Preview).
      case BoosterType.earthquake:
      case BoosterType.tilt:
        return const [];
    }
  }

  /// Edits the grid and reports what changed. Callers must have checked
  /// [isValid] first — the engine does.
  static BoosterResult apply(
    BoosterType type,
    Grid grid,
    BoosterTarget target,
    Set<(int, int)> solid,
  ) {
    switch (type) {
      case BoosterType.hammer:
        final (r, c) = _cell(target);
        return _remove(grid, [(r, c)]);

      case BoosterType.bomb:
        final (r, c) = _cell(target);
        return _remove(grid, _blastCells(grid, r, c));

      case BoosterType.patch:
        final (r, c) = _cell(target);
        grid.set(r, c, Cell(BlockType.wood));
        // No floor: a plug stays where it is placed, the same way an
        // overhang does (§5.3).
        return BoosterResult(added: [(r, c)]);

      case BoosterType.drill:
        final r = target.row!;
        return _remove(grid, [for (var c = 0; c < grid.cols; c++) (r, c)]);

      case BoosterType.slide:
        final r = target.row!;
        final shifted = _slideCells(grid, r, target.dirSign, solid)!;
        final paths = <BlockPath>[];
        for (var c = 0; c < grid.cols; c++) {
          final cell = grid.at(r, c);
          if (cell == null) continue;
          final to = _wrap(c + target.dirSign, grid.cols);
          paths.add(BlockPath([(r, c), (r, to)], cell.type));
        }
        for (var c = 0; c < grid.cols; c++) {
          grid.set(r, c, shifted[c]);
        }
        // Floor sits one row below, so the wave releases row r itself: a
        // block now standing over a hole has to fall into it (§5.5).
        return BoosterResult(
          moved: paths,
          lowestChangedRow: math.min(r + 1, grid.maxRow),
        );

      case BoosterType.pillar:
        final holes = _columnHoles(grid, target.col!, solid);
        for (final (hr, hc) in holes) {
          grid.set(hr, hc, Cell(BlockType.wood));
        }
        return BoosterResult(added: holes);

      case BoosterType.sweep:
        final rows = _sweepRows(grid);
        return _remove(grid, [
          for (final r in rows)
            for (var c = 0; c < grid.cols; c++) (r, c),
        ]);

      case BoosterType.lightning:
        final strikes = _lightningStrikes(grid, solid);
        for (final (sr, sc) in strikes) {
          grid.set(sr, sc, Cell(BlockType.wood));
        }
        return BoosterResult(added: strikes);

      case BoosterType.mortar:
        final holes = _mortarHoles(grid, solid);
        for (final (hr, hc) in holes) {
          grid.set(hr, hc, Cell(BlockType.wood));
        }
        return BoosterResult(added: holes);

      case BoosterType.earthquake:
        // ColumnCascade is already the reference resolver; it just has to be
        // told the active piece is solid, which it learns by being run over a
        // grid that has the piece stamped into it and then lifted back out.
        final paths = _settleWholeBoard(grid, solid);
        return BoosterResult(moved: paths, fullBoardSettle: true);

      case BoosterType.tilt:
        final paths = TiltCascade.run(grid, target.dirSign, solid);
        return BoosterResult(moved: paths, fullBoardSettle: true);

      case BoosterType.wildfire:
        final (r, c) = _cell(target);
        final burned = _burnLayers(grid, r, c).expand((l) => l).toList();
        return _remove(grid, burned);
    }
  }

  // --- shared scans -------------------------------------------------------

  static (int, int) _cell(BoosterTarget t) => (t.row ?? -1, t.col ?? -1);

  static bool _inBoard(Grid grid, int row, int col) =>
      row >= 0 && row <= grid.maxRow && col >= 0 && col < grid.cols;

  static bool _inRows(Grid grid, int row) => row >= 0 && row <= grid.maxRow;

  static bool _free(Grid grid, Set<(int, int)> solid, int row, int col) =>
      _inBoard(grid, row, col) &&
      grid.at(row, col) == null &&
      !solid.contains((row, col));

  static int _wrap(int col, int cols) => (col + cols) % cols;

  /// Empties [cells], reporting what was actually there and how low it went.
  static BoosterResult _remove(Grid grid, List<(int, int)> cells) {
    final removed = <ClearedCell>[];
    int? lowest;
    for (final (r, c) in cells) {
      final cell = grid.at(r, c);
      if (cell == null) continue;
      removed.add(ClearedCell(row: r, col: c, type: cell.type));
      grid.set(r, c, null);
      if (lowest == null || r > lowest) lowest = r;
    }
    return BoosterResult(removed: removed, lowestChangedRow: lowest);
  }

  static List<(int, int)> _blastCells(Grid grid, int row, int col) {
    const rad = BoosterTuning.bombRadius;
    return [
      for (var r = row - rad; r <= row + rad; r++)
        for (var c = col - rad; c <= col + rad; c++)
          if (_inBoard(grid, r, c)) (r, c),
    ];
  }

  /// The row after a one-column wrapping shift, or null if a block would be
  /// pushed into the active piece (§5.5).
  static List<Cell?>? _slideCells(
    Grid grid,
    int row,
    int dir,
    Set<(int, int)> solid,
  ) {
    final source = grid.rowCells(row);
    final shifted = List<Cell?>.filled(grid.cols, null);
    for (var c = 0; c < grid.cols; c++) {
      if (source[c] == null) continue;
      final to = _wrap(c + dir, grid.cols);
      if (solid.contains((row, to))) return null;
      shifted[to] = source[c];
    }
    return shifted;
  }

  /// Empty cells in a column with a block somewhere above them (§5.6).
  static List<(int, int)> _columnHoles(
    Grid grid,
    int col,
    Set<(int, int)> solid,
  ) {
    var top = -1;
    for (var r = 0; r <= grid.maxRow; r++) {
      if (grid.at(r, col) != null) {
        top = r;
        break;
      }
    }
    if (top < 0) return const [];
    return [
      for (var r = top; r <= grid.maxRow; r++)
        if (grid.at(r, col) == null && !solid.contains((r, col))) (r, col),
    ];
  }

  /// The top [BoosterTuning.sweepRows] rows that hold anything. They do not
  /// have to be next to each other (§5.7).
  static List<int> _sweepRows(Grid grid) {
    final rows = <int>[];
    for (
      var r = 0;
      r <= grid.maxRow && rows.length < BoosterTuning.sweepRows;
      r++
    ) {
      if (grid.rowHasAnyBlock(r)) rows.add(r);
    }
    return rows;
  }

  /// Where the bolts land: fullest rows first, lower row on a tie, and each
  /// row's gaps taken from the middle outward, so the same board always gives
  /// the same strikes (§5.8).
  static List<(int, int)> _lightningStrikes(Grid grid, Set<(int, int)> solid) {
    final candidates = <({int row, List<int> gaps})>[];
    for (var r = 0; r <= grid.maxRow; r++) {
      if (!grid.rowHasAnyBlock(r)) continue;
      final gaps = [
        for (var c = 0; c < grid.cols; c++)
          if (grid.at(r, c) == null && !solid.contains((r, c))) c,
      ];
      if (gaps.isEmpty) continue;
      candidates.add((row: r, gaps: gaps));
    }
    candidates.sort(
      (a, b) => a.gaps.length != b.gaps.length
          ? a.gaps.length.compareTo(b.gaps.length)
          : b.row.compareTo(a.row),
    );

    final strikes = <(int, int)>[];
    for (final c in candidates) {
      for (final col in _centreOut(c.gaps, grid.cols)) {
        if (strikes.length == BoosterTuning.lightningBolts) return strikes;
        strikes.add((c.row, col));
      }
    }
    return strikes;
  }

  static List<int> _centreOut(List<int> cols, int width) {
    final centre = (width - 1) / 2.0;
    final sorted = List.of(cols)
      ..sort((a, b) => (a - centre).abs().compareTo((b - centre).abs()));
    return sorted;
  }

  /// Empty cells with a block above and a block (or the floor) below. Side
  /// neighbours do not matter, and the scan runs once, before any filling, so
  /// a cell filled in this pass cannot create a new one (§5.9).
  static List<(int, int)> _mortarHoles(Grid grid, Set<(int, int)> solid) {
    final holes = <(int, int)>[];
    for (var r = 0; r <= grid.maxRow; r++) {
      for (var c = 0; c < grid.cols; c++) {
        if (grid.at(r, c) != null || solid.contains((r, c))) continue;
        final above = r - 1 >= 0 && grid.at(r - 1, c) != null;
        if (!above) continue;
        final below = r == grid.maxRow || grid.at(r + 1, c) != null;
        if (!below) continue;
        holes.add((r, c));
      }
    }
    return holes;
  }

  /// Every block that settles, and the route it takes, when gravity is let
  /// off its leash over the whole board (§5.10).
  ///
  /// [ColumnCascade] is the reference resolver for exactly this, but it has
  /// no notion of an obstacle: it compacts every column to the floor. The
  /// active piece is not a grid cell and must not move, yet a block above it
  /// in the same column has to stop on top of it (§4.5 rule 1) — so the walk
  /// is done here, with the piece's rows treated as a floor of their own.
  static List<BlockPath> _settleWholeBoard(Grid grid, Set<(int, int)> solid) {
    final paths = <BlockPath>[];
    for (var col = 0; col < grid.cols; col++) {
      // The lowest free row in this column, walking up from the floor.
      var write = grid.maxRow;
      for (var r = grid.maxRow; r >= 0; r--) {
        if (solid.contains((r, col))) {
          // Everything above the piece stacks on top of it.
          write = r - 1;
          continue;
        }
        final cell = grid.at(r, col);
        if (cell == null) continue;
        if (r != write) {
          grid.set(r, col, null);
          grid.set(write, col, cell);
          paths.add(
            BlockPath([for (var p = r; p <= write; p++) (p, col)], cell.type),
          );
        }
        write--;
      }
    }
    return paths;
  }

  /// Breadth-first spread through connected blocks, neighbours taken up,
  /// left, right, down so the fire climbs, capped at [wildfireCap]. One list
  /// per layer, which is what drives the burn animation (§5.12).
  static List<List<(int, int)>> _burnLayers(Grid grid, int row, int col) {
    final layers = <List<(int, int)>>[];
    final burned = <(int, int)>{};
    var frontier = <(int, int)>[(row, col)];
    final seen = <(int, int)>{(row, col)};

    while (frontier.isNotEmpty && burned.length < BoosterTuning.wildfireCap) {
      final layer = <(int, int)>[];
      final next = <(int, int)>[];
      for (final (r, c) in frontier) {
        if (burned.length == BoosterTuning.wildfireCap) break;
        burned.add((r, c));
        layer.add((r, c));
        for (final n in [(r - 1, c), (r, c - 1), (r, c + 1), (r + 1, c)]) {
          if (_inBoard(grid, n.$1, n.$2) &&
              grid.at(n.$1, n.$2) != null &&
              seen.add(n)) {
            next.add(n);
          }
        }
      }
      if (layer.isNotEmpty) layers.add(layer);
      frontier = next;
    }
    return layers;
  }

  /// The layer breakdown, for the burn animation.
  static List<List<(int, int)>> burnLayers(Grid grid, int row, int col) =>
      _burnLayers(grid, row, col);
}
