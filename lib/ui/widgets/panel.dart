import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// The container for modals and panels.
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Container(
      padding: EdgeInsets.all(ui.spaceLg),
      decoration: BoxDecoration(
        color: const Color(0xE0140C06),
        borderRadius: BorderRadius.circular(ui.radiusLg),
        border: Border.all(color: Tokens.colorPanelBorder),
        boxShadow: const [Tokens.shadowLift],
      ),
      child: child,
    );
  }
}
