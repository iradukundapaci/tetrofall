/// Board geometry constants. See game.md §1.1.
abstract final class BoardConfig {
  static const cols = 10;
  static const rows = 20;

  /// Hidden buffer above row 0, used only for piece spawn.
  static const spawnRows = 2;

  /// Total rows in the backing grid, visible + hidden buffer.
  static const totalRows = rows + spawnRows;
}
