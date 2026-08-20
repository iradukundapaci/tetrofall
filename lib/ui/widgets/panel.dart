import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// Port of `.panel` — the modal/panel container used by pause and
/// other overlays.
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Container(
      padding: padding ?? EdgeInsets.all(ui.spaceLg),
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
