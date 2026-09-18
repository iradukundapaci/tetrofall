import 'package:flutter/material.dart';

import '../ui/theme/tokens.dart';

class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.displayName,
    required this.price,
    required this.background,
    required this.boardBg,
    required this.frameLight,
    required this.frameDark,
    required this.gridLine,
    required this.blockTint,
    required this.text,
    required this.accent,
    required this.boosterFace,
    required this.boosterRim,
    required this.boosterGlyph,
    required this.boosterGlyphMuted,
    required this.effectHot,
    required this.effectEmber,
    required this.baseTileAsset,
  });

  final String id;

  /// What the themes screen calls it.
  final String displayName;

  /// Coins to unlock. Zero means free and always owned.
  final int price;

  final Color background;
  final Color boardBg;
  final Color frameLight;
  final Color frameDark;
  final Color gridLine;
  final Color blockTint;
  final Color text;
  final Color accent;

  /// The six fields every booster visual reads (`boosters.md` §9.2). Nothing
  /// under the booster UI or its effects may reach past these into [Tokens] —
  /// a second theme redefines these and recolors all twelve with no code
  /// change. No blue, purple or green is allowed here (§9.1), and red is
  /// reserved for Wildfire's dying ember, never a UI state.
  final Color boosterFace;
  final Color boosterRim;
  final Color boosterGlyph;
  final Color boosterGlyphMuted;
  final Color effectHot;
  final Color effectEmber;

  final String baseTileAsset;

  static const classicWood = ThemeDefinition(
    id: 'classic_wood',
    displayName: 'Classic Wood',
    price: 0,
    background: Tokens.colorBg,
    boardBg: Color(0xFF1F140C),
    frameLight: Tokens.colorWoodLight,
    frameDark: Tokens.colorWoodDark,
    gridLine: Tokens.colorText,
    blockTint: Tokens.colorWoodMid,
    text: Tokens.colorText,
    accent: Tokens.colorGold,
    boosterFace: Tokens.colorPanel,
    boosterRim: Color(0x99C89B6A), // colorWoodLight at 60%
    boosterGlyph: Tokens.colorGold,
    boosterGlyphMuted: Tokens.colorTextMuted,
    effectHot: Color(0xFFFFE6A8), // pale gold, lighter than colorGold
    effectEmber: Tokens.colorRed,
    baseTileAsset: 'assets/images/blocks/tile_classic_wood.png',
  );

  // The three Coin-shop themes. Prices are `screens/themes.html`'s, and the
  // block palettes come from its `.pal-*` swatches. Their tiles are generated
  // placeholders (`tools/themes/make_tiles.py`) until proper art is drawn.
  //
  // Booster colours stay inside §9.1 on every theme — gold, cream and white,
  // never blue, purple or green, even on Snow — because the booster visuals
  // must read as the same twelve objects whatever board they sit on.

  static const marble = ThemeDefinition(
    id: 'marble',
    displayName: 'Marble',
    price: 300,
    background: Color(0xFF26272C),
    boardBg: Color(0xFF1A1B1F),
    frameLight: Color(0xFFC9C9CF),
    frameDark: Color(0xFF55565E),
    gridLine: Color(0xFFF2F2F2),
    blockTint: Color(0xFFB8B9C2),
    text: Color(0xFFF2F2F2),
    accent: Tokens.colorGold,
    boosterFace: Tokens.colorPanel,
    boosterRim: Color(0x99C9C9CF),
    boosterGlyph: Tokens.colorGold,
    boosterGlyphMuted: Color(0xFFA8A8B0),
    effectHot: Color(0xFFFFF4D6),
    effectEmber: Tokens.colorRed,
    baseTileAsset: 'assets/images/blocks/tile_marble.png',
  );

  static const snow = ThemeDefinition(
    id: 'snow',
    displayName: 'Snow',
    price: 350,
    background: Color(0xFF14222E),
    boardBg: Color(0xFF0E1822),
    frameLight: Color(0xFFBFE3F5),
    frameDark: Color(0xFF3F6782),
    gridLine: Color(0xFFF2FBFF),
    blockTint: Color(0xFF9CCFEA),
    text: Color(0xFFF2FBFF),
    accent: Tokens.colorGold,
    boosterFace: Tokens.colorPanel,
    boosterRim: Color(0x99F2FBFF),
    boosterGlyph: Color(0xFFFFFFFF),
    boosterGlyphMuted: Color(0xFFB9C4CC),
    effectHot: Color(0xFFFFFFFF),
    effectEmber: Tokens.colorRed,
    baseTileAsset: 'assets/images/blocks/tile_snow.png',
  );

  static const candy = ThemeDefinition(
    id: 'candy',
    displayName: 'Candy',
    price: 450,
    background: Color(0xFF2A1020),
    boardBg: Color(0xFF1E0B17),
    frameLight: Color(0xFFFFC4E0),
    frameDark: Color(0xFFC72368),
    gridLine: Color(0xFFFFE8F2),
    blockTint: Color(0xFFF05C9C),
    text: Color(0xFFFFF0F6),
    accent: Tokens.colorGold,
    boosterFace: Tokens.colorPanel,
    boosterRim: Color(0x99FFC4E0),
    boosterGlyph: Tokens.colorGold,
    boosterGlyphMuted: Color(0xFFD9B3C4),
    effectHot: Color(0xFFFFF1C2),
    effectEmber: Tokens.colorRed,
    baseTileAsset: 'assets/images/blocks/tile_candy.png',
  );

  /// Every theme, in shop order. The first is the free default.
  static const all = <ThemeDefinition>[classicWood, marble, snow, candy];

  static ThemeDefinition byId(String? id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return classicWood;
  }
}
