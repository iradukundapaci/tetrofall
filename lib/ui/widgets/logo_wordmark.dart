import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The gradient "TETROFALL" text, ported from splash.html's
/// `.splash-logo-word`. A vertical gold gradient clipped to the text,
/// with a hard drop shadow plus a soft one for depth.
class LogoWordmark extends StatelessWidget {
  const LogoWordmark({super.key, this.fontSize = 32});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: Tokens.fontDisplay,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: fontSize * 0.03,
      shadows: const [
        Shadow(color: Color(0x59000000), offset: Offset(0, 3)),
        Shadow(color: Color(0x73000000), offset: Offset(0, 4), blurRadius: 8),
      ],
    );

    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE9B0), Tokens.colorGold, Color(0xFFC9821A)],
        stops: [0, 0.55, 1],
      ).createShader(bounds),
      child: Text('TETROFALL', style: style),
    );
  }
}
