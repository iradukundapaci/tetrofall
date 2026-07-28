import 'cell.dart';
import 'events.dart';
import 'grid.dart';

/// What one resolve pass actually destroyed, after special-block rules
/// (§1.8) are applied — used for scoring, the combo banner, and the
/// shatter animation.
class SpecialResolution {
  const SpecialResolution({
    required this.removedCells,
    required this.goldCleared,
    required this.diamondCleared,
    required this.treasureCleared,
  });

  final List<ClearedCell> removedCells;
  final int goldCleared;
  final int diamondCleared;
  final int treasureCleared;
}

/// Resolves special-block behaviour (§1.8) for the rows [ClearDetector]
/// found full. Mutates [grid] directly: cells that survive this pass
/// (cracked ice, un-keyed locked blocks) are left in place — with any
/// state change (ice's `hp`) applied — while everything else is nulled.
/// Bomb and Rainbow additionally destroy cells *outside* the completed
/// rows entirely, which is why this takes the whole grid rather than just
/// the row contents.
abstract final class SpecialBlocks {
  static const _bombRadius = 1; // 3x3 neighbourhood
  static const _rainbowRadius = 2;

  static SpecialResolution resolve(Grid grid, List<int> fullRows) {
    final rowCells = <(int, int)>[
      for (final r in fullRows) for (var c = 0; c < grid.cols; c++) (r, c),
    ];

    final hasKey = rowCells.any(
      (rc) => grid.at(rc.$1, rc.$2)?.type == BlockType.key,
    );

    final toRemove = <(int, int)>{};
    final blastQueue = <(int, int)>[];

    for (final rc in rowCells) {
      final cell = grid.at(rc.$1, rc.$2);
      if (cell == null) continue; // the row was full; shouldn't happen
      switch (cell.type) {
        case BlockType.ice:
          // First completion cracks it and clears the rest of the row;
          // second completion clears it (§1.8) — modeled by `hp`, which
          // Cell already starts at 2 for ice.
          cell.hp -= 1;
          if (cell.hp <= 0) {
            toRemove.add(rc);
          } else {
            cell.type = BlockType.iceCracked;
          }
        case BlockType.locked:
          if (hasKey) toRemove.add(rc);
        case BlockType.stone:
          // Unreachable in practice: Stone sets Cell.blocksLineClear, so
          // ClearDetector never counts its row as full to begin with.
          break;
        default:
          toRemove.add(rc);
          if (cell.type == BlockType.bomb || cell.type == BlockType.rainbow) {
            blastQueue.add(rc);
          }
      }
    }

    // Bomb (3x3) / Rainbow (radius 2) blasts, including bomb chain
    // reactions when a blast catches another bomb. Blasts bypass every
    // normal resistance — ice, locked, even Stone — by design (§1.8:
    // Rainbow explicitly destroys "regardless of type, including Stone").
    final blastOrigins = <(int, int)>{};
    while (blastQueue.isNotEmpty) {
      final origin = blastQueue.removeLast();
      if (!blastOrigins.add(origin)) continue;
      final originCell = grid.at(origin.$1, origin.$2);
      final radius = originCell?.type == BlockType.rainbow
          ? _rainbowRadius
          : _bombRadius;
      for (var dr = -radius; dr <= radius; dr++) {
        for (var dc = -radius; dc <= radius; dc++) {
          final nr = origin.$1 + dr;
          final nc = origin.$2 + dc;
          if (!grid.inBounds(nr, nc)) continue;
          final neighbor = grid.at(nr, nc);
          if (neighbor == null) continue;
          final key = (nr, nc);
          final newlyMarked = toRemove.add(key);
          if (neighbor.type == BlockType.bomb && newlyMarked) {
            blastQueue.add(key); // chain reaction
          }
        }
      }
    }

    var gold = 0;
    var diamond = 0;
    var treasure = 0;
    final removedCells = <ClearedCell>[];
    for (final rc in toRemove) {
      final cell = grid.at(rc.$1, rc.$2);
      if (cell == null) continue;
      removedCells.add(ClearedCell(row: rc.$1, col: rc.$2, type: cell.type));
      switch (cell.type) {
        case BlockType.gold:
          gold++;
        case BlockType.diamond:
          diamond++;
        case BlockType.treasure:
          treasure++;
        default:
          break;
      }
      grid.set(rc.$1, rc.$2, null);
    }

    return SpecialResolution(
      removedCells: removedCells,
      goldCleared: gold,
      diamondCleared: diamond,
      treasureCleared: treasure,
    );
  }
}
