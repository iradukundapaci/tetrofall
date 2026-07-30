import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Port of `.btn-icon` — the circular 48×48 icon button used for
/// settings, pause, and home affordances across every screen.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.tooltip,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? const Color(0x2EF2B632) : Tokens.colorPanel,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? Tokens.colorGold : Tokens.colorPanelBorder,
          ),
          boxShadow: const [Tokens.shadowSoft],
        ),
        child: Center(child: icon),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
