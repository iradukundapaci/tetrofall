/// Board geometry constants. See game.md §1.1.
///
/// 18×32 keeps the reference footage's near-square cells but at a larger
/// size: 18 columns across the play-area width (rows scaled down
/// proportionally from the original 21×37) so the board still fills a
/// phone-shaped play area edge-to-edge inside its frame.
abstract final class BoardConfig {
  static const cols = 18;
  static const rows = 32;

  /// Hidden buffer above row 0, used only for piece spawn.
  static const spawnRows = 2;

  /// Total rows in the backing grid, visible + hidden buffer.
  static const totalRows = rows + spawnRows;
}
