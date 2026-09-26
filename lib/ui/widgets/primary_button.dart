import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// The one bright, high-emphasis action on a screen.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fontSize,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// Null means the scaled default; pass to pick a different type-scale step.
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return _JuiceButton(
      onPressed: onPressed,
      builder: (pressed) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: ui.spaceXl,
          vertical: ui.px(Tokens.buttonPadYLg),
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Tokens.colorGold, Color(0xFFD99A1F)],
          ),
          borderRadius: BorderRadius.circular(ui.radiusLg),
          boxShadow: pressed ? const [] : const [Tokens.shadowSoft],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, SizedBox(width: ui.spaceSm)],
            // Shrinks to fit; "Watch Ad to Continue" on a 320pt screen has
            // nowhere else to go.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: Tokens.fontDisplay,
                    fontSize: fontSize ?? ui.fontLg,
                    fontWeight: FontWeight.w700,
                    color: Tokens.colorWoodDark,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Outline/panel-toned button for secondary actions.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return _JuiceButton(
      onPressed: onPressed,
      builder: (pressed) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: ui.spaceLg,
          vertical: ui.px(Tokens.buttonPadYMd),
        ),
        decoration: BoxDecoration(
          color: pressed ? const Color(0x1AFFFFFF) : Tokens.colorPanel,
          borderRadius: BorderRadius.circular(ui.radiusLg),
          border: Border.all(
            color: Tokens.colorPanelBorder,
            width: ui.borderThick,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: Tokens.fontDisplay,
                    fontSize: ui.fontMd,
                    fontWeight: FontWeight.w600,
                    color: Tokens.colorText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared press feedback: scale to 0.96 on tap-down.
class _JuiceButton extends StatefulWidget {
  const _JuiceButton({required this.onPressed, required this.builder});

  final VoidCallback? onPressed;
  final Widget Function(bool pressed) builder;

  @override
  State<_JuiceButton> createState() => _JuiceButtonState();
}

class _JuiceButtonState extends State<_JuiceButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Opacity(
          opacity: widget.onPressed == null ? 0.5 : 1.0,
          child: widget.builder(_pressed),
        ),
      ),
    );
  }
}
