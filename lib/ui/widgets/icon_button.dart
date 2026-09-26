import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// The circular icon button, sized from [UiScale.tap] (never below 44pt).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final size = context.scale.tap;
    final button = GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Tokens.colorPanel,
          shape: BoxShape.circle,
          border: Border.all(color: Tokens.colorPanelBorder),
          boxShadow: const [Tokens.shadowSoft],
        ),
        child: Center(child: icon),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
