import 'grid.dart';

/// Full-row detection (§1.5). A dedicated class rather than a Grid method
/// so future rules (chain rescans, per-column resolvers in Phase 3) can
/// call it without coupling to Grid's storage.
abstract final class ClearDetector {
  static List<int> findFullRows(Grid grid) => [
    for (var r = 0; r < grid.visibleRows; r++)
      if (grid.isRowFull(r)) r,
  ];
}
