import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// Port of `.btn-primary` — the one bright, high-emphasis action on a
/// screen (PLAY, Play Again, Resume).
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

  /// Null means "the scaled default" — callers only pass this to pick a
  /// different step on the type scale, not to opt out of scaling.
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
            // Shrinks to fit rather than overflowing. A long label inside a
            // panel-width column on a 320pt screen — "Watch Ad to Continue"
            // is the worst case — has nowhere else to go.
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

/// Port of `.btn-secondary` — outline/panel-toned button (Restart, Quit's
/// louder sibling, Settings-from-pause, Watch Ad to Continue).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.highlighted = false,
    this.fontSize,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// Null means "the scaled default". Matches [PrimaryButton] — without it,
  /// game-over's "Watch Ad to Continue" had no way to shrink on a narrow
  /// screen while the button beside it did.
  final double? fontSize;

  /// Gold "active/confirmed" tint — e.g. main-menu.html's `.is-purchased`
  /// state — distinct from the disabled (null onPressed) dim.
  final bool highlighted;

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
          color: highlighted
              ? const Color(0x2EF2B632)
              : pressed
              ? const Color(0x1AFFFFFF)
              : Tokens.colorPanel,
          borderRadius: BorderRadius.circular(ui.radiusLg),
          border: Border.all(
            color: highlighted ? Tokens.colorGold : Tokens.colorPanelBorder,
            width: ui.borderThick,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, SizedBox(width: ui.spaceSm)],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: Tokens.fontDisplay,
                    fontSize: fontSize ?? ui.fontMd,
                    fontWeight: FontWeight.w600,
                    color: highlighted ? Tokens.colorGold : Tokens.colorText,
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

/// Shared press feedback: scale to 0.96 on tap-down, matching
/// `:active { transform: scale(0.96) }` from components.css.
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
