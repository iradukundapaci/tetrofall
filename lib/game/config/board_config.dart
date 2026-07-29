/// Board geometry constants. See game.md §1.1.
///
/// 21×37 matches the reference footage 1:1 — measured from the source
/// screenshots: 21 columns across the full screen width (cell ≈ 60.5px at
/// 1272px wide) and ≈37 visible rows filling the height edge-to-edge.
abstract final class BoardConfig {
  static const cols = 21;
  static const rows = 37;

  /// Hidden buffer above row 0, used only for piece spawn.
  static const spawnRows = 2;

  /// Total rows in the backing grid, visible + hidden buffer.
  static const totalRows = rows + spawnRows;
}
