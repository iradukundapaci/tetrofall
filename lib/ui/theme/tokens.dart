import 'package:flutter/material.dart';

/// 1:1 port of `screens/tokens.css`. Mechanical translation — no
/// reinterpretation. If a value isn't here, it doesn't belong on screen.
abstract final class Tokens {
  // Colors
  static const colorWoodDark = Color(0xFF4A2F1C);
  static const colorWoodMid = Color(0xFF7A5230);
  static const colorWoodLight = Color(0xFFC89B6A);
  static const colorBg = Color(0xFF2B1C12);
  static const colorPanel = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
  static const colorPanelBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.1)
  static const colorGold = Color(0xFFF2B632);
  static const colorRed = Color(0xFFD9432E);
  static const colorBlue = Color(0xFF3AA0D9);
  static const colorPurple = Color(0xFF9B5CD6);
  static const colorGreen = Color(0xFF4CAF6B);
  static const colorText = Color(0xFFF5EAD9);
  static const colorTextMuted = Color(0xFFB9A889);

  // Typography
  static const fontDisplay = 'Baloo 2';
  static const fontBody = 'Nunito';

  static const fontSizeXs = 12.0; // 0.75rem
  static const fontSizeSm = 14.0; // 0.875rem
  static const fontSizeMd = 16.0; // 1rem
  static const fontSizeLg = 20.0; // 1.25rem
  static const fontSizeXl = 28.0; // 1.75rem
  static const fontSizeXxl = 40.0; // 2.5rem

  // Shadows
  static const shadowSoft = BoxShadow(
    color: Color(0x59000000), // rgba(0,0,0,0.35)
    offset: Offset(0, 4),
    blurRadius: 12,
  );
  static const shadowLift = BoxShadow(
    color: Color(0x73000000), // rgba(0,0,0,0.45)
    offset: Offset(0, 8),
    blurRadius: 20,
  );
  // shadow-inset has no direct BoxShadow equivalent — see board_frame.dart,
  // which uses MaskFilter.blur(BlurStyle.inner, ...) instead (P.4).

  // Shape
  static const radiusSm = 10.0;
  static const radiusMd = 16.0;
  static const radiusLg = 24.0;
  static const radiusPill = 999.0;

  // Spacing scale
  static const spaceXs = 4.0;
  static const spaceSm = 8.0;
  static const spaceMd = 16.0;
  static const spaceLg = 24.0;
  static const spaceXl = 32.0;
  static const spaceXxl = 48.0;

  /// `--bg-wood-texture`'s solid-color half: a vertical gradient from
  /// wood-dark to bg. The repeating-stripe half is approximated by
  /// `bg_wood.png` (P.4) when available; this gradient is the fallback.
  static const bgWoodGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [colorWoodDark, colorBg],
  );
}
