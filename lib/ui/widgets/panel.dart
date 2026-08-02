import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Port of `.panel` — the modal/panel container used by pause and
/// other overlays.
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(Tokens.spaceLg),
      decoration: BoxDecoration(
        color: const Color(0xE0140C06),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: Tokens.colorPanelBorder),
        boxShadow: const [Tokens.shadowLift],
      ),
      child: child,
    );
  }
}
