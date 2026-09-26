import 'dart:math' as math;

import 'grid.dart';

/// A read-only summary of the stack, computed on demand. Pure functions over
/// [Grid]: the Director reads it to judge how much trouble the player is in,
/// and to find the column they are keeping open.
class BoardMetrics {
  BoardMetrics._({
    required this.rows,
    required this.heights,
    required this.tallest,
    required this.coveredHoles,
    required this.bumpiness,
    required this.wellColumn,
  });

  /// Visible rows, i.e. the most a column can hold.
  final int rows;

  /// Per-column stack height, in rows.
  final List<int> heights;

  final int tallest;

  /// Empty cells with a block somewhere above them in the same column.
  final int coveredHoles;

  /// Sum of height differences between neighbouring columns.
  final int bumpiness;

  /// The column the player is keeping open, or null when there isn't one: a
  /// column at least [minWellDepth] rows below every neighbour it has. The
  /// deepest wins.
  final int? wellColumn;

  static const minWellDepth = 3;

  double get tallestFraction => tallest / rows;

  factory BoardMetrics.of(Grid grid) {
    final rows = grid.maxRow + 1;
    final cols = grid.cols;
    final heights = List<int>.filled(cols, 0);
    var holes = 0;

    for (var c = 0; c < cols; c++) {
      var seenBlock = false;
      for (var r = 0; r < rows; r++) {
        if (grid.isOccupied(r, c)) {
          if (!seenBlock) heights[c] = rows - r;
          seenBlock = true;
        } else if (seenBlock) {
          holes++;
        }
      }
    }

    var bump = 0;
    for (var c = 1; c < cols; c++) {
      bump += (heights[c] - heights[c - 1]).abs();
    }

    int? well;
    var wellDepth = 0;
    for (var c = 0; c < cols; c++) {
      final left = c > 0 ? heights[c - 1] : null;
      final right = c < cols - 1 ? heights[c + 1] : null;
      final neighbours = [?left, ?right];
      final lowestNeighbour = neighbours.reduce(math.min);
      final depth = lowestNeighbour - heights[c];
      // Every neighbour must stand above it, not just one: a step on a
      // staircase is not a well.
      final isWell = neighbours.every((n) => n - heights[c] >= minWellDepth);
      if (isWell && depth > wellDepth) {
        wellDepth = depth;
        well = c;
      }
    }

    return BoardMetrics._(
      rows: rows,
      heights: heights,
      tallest: heights.reduce(math.max),
      coveredHoles: holes,
      bumpiness: bump,
      wellColumn: well,
    );
  }
}
