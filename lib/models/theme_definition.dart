import 'package:flutter/material.dart';

import '../ui/theme/tokens.dart';

/// Palette + block sprite set for one visual theme. The render layer reads
/// every color it draws from the active [ThemeDefinition] — never from
/// [Tokens] directly — so a future theme (Phase 11) costs one palette and
/// one base tile, no code. See game.md P.8.
class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.background,
    required this.boardBg,
    required this.frameLight,
    required this.frameDark,
    required this.gridLine,
    required this.blockTint,
    required this.text,
    required this.accent,
    required this.baseTileAsset,
    this.spriteOverrides = const {},
  });

  final String id;
  final Color background;
  final Color boardBg;
  final Color frameLight;
  final Color frameDark;
  final Color gridLine;
  final Color blockTint;
  final Color text;
  final Color accent;

  /// This theme's base block tile (P.3), used for plain/wood blocks.
  final String baseTileAsset;

  /// Per-block-type sprite override, empty by default. Keyed by block-type
  /// name (e.g. `'bomb'`) rather than the engine's `BlockType` enum so this
  /// model file — which needs `Color` — never has to import the pure-Dart
  /// engine. A future theme supplies one entry; everything else falls back
  /// to the shared special-block tiles.
  final Map<String, String> spriteOverrides;

  static const classicWood = ThemeDefinition(
    id: 'classic_wood',
    background: Tokens.colorBg,
    boardBg: Color(0xFF1F140C),
    frameLight: Tokens.colorWoodLight,
    frameDark: Tokens.colorWoodDark,
    gridLine: Tokens.colorText,
    blockTint: Tokens.colorWoodMid,
    text: Tokens.colorText,
    accent: Tokens.colorGold,
    baseTileAsset: 'assets/images/blocks/tile_classic_wood.png',
  );
}
