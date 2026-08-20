import 'package:flutter/material.dart';

abstract final class Tokens {
  static const colorWoodDark = Color(0xFF4A2F1C);
  static const colorWoodMid = Color(0xFF7A5230);
  static const colorWoodLight = Color(0xFFC89B6A);
  static const colorBg = Color(0xFF2B1C12);
  static const colorPanel = Color(0x0FFFFFFF);
  static const colorPanelBorder = Color(0x1AFFFFFF);
  static const colorGold = Color(0xFFF2B632);
  static const colorRed = Color(0xFFD9432E);
  static const colorBlue = Color(0xFF3AA0D9);
  static const colorPurple = Color(0xFF9B5CD6);
  static const colorGreen = Color(0xFF4CAF6B);
  static const colorText = Color(0xFFF5EAD9);
  static const colorTextMuted = Color(0xFFB9A889);

  static const fontDisplay = 'Baloo 2';
  static const fontBody = 'Nunito';

  static const fontSizeXs = 12.0;
  static const fontSizeSm = 14.0;
  static const fontSizeMd = 16.0;
  static const fontSizeLg = 20.0;
  static const fontSizeXl = 28.0;
  static const fontSizeXxl = 40.0;

  /// The game-over score numeral — the one type size larger than a heading.
  static const fontSizeHero = 56.0;

  static const shadowSoft = BoxShadow(
    color: Color(0x59000000),
    offset: Offset(0, 4),
    blurRadius: 12,
  );
  static const shadowLift = BoxShadow(
    color: Color(0x73000000),
    offset: Offset(0, 8),
    blurRadius: 20,
  );

  static const radiusSm = 10.0;
  static const radiusMd = 16.0;
  static const radiusLg = 24.0;
  static const radiusPill = 999.0;

  static const spaceXs = 4.0;
  static const spaceSm = 8.0;
  static const spaceMd = 16.0;
  static const spaceLg = 24.0;
  static const spaceXl = 32.0;
  static const spaceXxl = 48.0;

  // Iconography. Four sizes were in use with no token between them — 18 for
  // chevrons and inline glyphs, 20 for row icons, Material's implicit 24, and
  // a one-off 22 in the counter pill.
  static const iconSm = 18.0;
  static const iconMd = 20.0;
  static const iconLg = 24.0;
  static const iconCounter = 22.0;

  /// The circular icon button, and every other minimum touch target.
  static const tapTarget = 48.0;

  /// The tutorial's drawn fingertip.
  static const fingerHint = 44.0;

  /// The gameplay HUD's content row, excluding the top safe inset. Fixed
  /// rather than intrinsic so the board's vertical budget can be computed
  /// before layout — see `_GameplayBody`.
  static const hudHeight = 56.0;

  static const borderThick = 2.0;
  static const borderBoard = 3.0;
  static const boardInset = 4.0;

  /// Reference width for every centred modal, unifying what used to be 280
  /// (pause, game over), 300 (confirm quit) and 300 (tutorial).
  static const panelWidth = 300.0;

  static const buttonPadYLg = 14.0;
  static const buttonPadYMd = 12.0;
  static const progressBarHeight = 12.0;
  static const sliderTrackHeight = 8.0;
  static const menuPlayWidth = 160.0;

  static const logoCell = 40.0;
  static const logoWordFont = 32.0;
  static const splashDropDistance = 260.0;
  static const splashLoaderWidth = 220.0;

  static const bgWoodGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [colorWoodDark, colorBg],
  );
}
