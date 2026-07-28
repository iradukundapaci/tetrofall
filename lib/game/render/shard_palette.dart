import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../../ui/theme/tokens.dart';
import '../engine/cell.dart';

/// Per-block-type shard color for the shatter animation (§2.3). Plain wood
/// reads the active theme's tint so a theme swap recolors its shards for
/// free; every special block instead bursts in its own fixed color,
/// independent of theme, so the same threat always reads the same way
/// (stone grey, diamond blue, gold amber...). Wired in Phase 5, exercised
/// by real special blocks starting Phase 7.
abstract final class ShardPalette {
  static Color colorFor(BlockType type, ThemeDefinition theme) {
    switch (type) {
      case BlockType.wood:
        return theme.blockTint;
      case BlockType.stone:
        return const Color(0xFF9A9A9A);
      case BlockType.ice:
      case BlockType.iceCracked:
        return const Color(0xFFBEE3F5);
      case BlockType.bomb:
        return Tokens.colorRed;
      case BlockType.gold:
        return Tokens.colorGold;
      case BlockType.diamond:
        return Tokens.colorBlue;
      case BlockType.treasure:
        return const Color(0xFFCD9B3A);
      case BlockType.locked:
        return const Color(0xFF5A5A5A);
      case BlockType.rainbow:
        return Tokens.colorPurple;
      case BlockType.key:
        return Tokens.colorGold;
    }
  }
}
