import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// Back button and centred title for full-screen pages.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Tokens.colorText),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: ui.fontXl,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Tokens.colorText,
            ),
          ),
        ),
        // Mirrors the back button so the title stays centred.
        SizedBox(width: ui.tap),
      ],
    );
  }
}
