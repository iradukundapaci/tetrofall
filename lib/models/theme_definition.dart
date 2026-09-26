import 'package:flutter/material.dart';

import '../ui/theme/tokens.dart';

class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.boardBg,
    required this.frameLight,
    required this.frameDark,
    required this.blockTint,
    required this.text,
    required this.baseTileAsset,
  });

  final String id;
  final Color boardBg;
  final Color frameLight;
  final Color frameDark;
  final Color blockTint;
  final Color text;

  final String baseTileAsset;

  static const classicWood = ThemeDefinition(
    id: 'classic_wood',
    boardBg: Color(0xFF1F140C),
    frameLight: Tokens.colorWoodLight,
    frameDark: Tokens.colorWoodDark,
    blockTint: Tokens.colorWoodMid,
    text: Tokens.colorText,
    baseTileAsset: 'assets/images/blocks/tile_classic_wood.png',
  );
}
