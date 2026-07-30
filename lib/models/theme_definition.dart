import 'package:flutter/material.dart';

import '../ui/theme/tokens.dart';

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

  final String baseTileAsset;

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
