import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Port of `.btn-primary` — the one bright, high-emphasis action on a
/// screen (PLAY, Play Again, Resume).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fontSize = Tokens.fontSizeLg,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return _JuiceButton(
      onPressed: onPressed,
      builder: (pressed) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.spaceXl,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Tokens.colorGold, Color(0xFFD99A1F)],
          ),
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          boxShadow: pressed ? const [] : const [Tokens.shadowSoft],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: Tokens.spaceSm)],
            Text(
              label,
              style: TextStyle(
                fontFamily: Tokens.fontDisplay,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: Tokens.colorWoodDark,
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
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// Gold "active/confirmed" tint — e.g. main-menu.html's `.is-purchased`
  /// state — distinct from the disabled (null onPressed) dim.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return _JuiceButton(
      onPressed: onPressed,
      builder: (pressed) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.spaceLg,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: highlighted
              ? const Color(0x2EF2B632)
              : pressed
              ? const Color(0x1AFFFFFF)
              : Tokens.colorPanel,
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          border: Border.all(
            color: highlighted ? Tokens.colorGold : Tokens.colorPanelBorder,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: Tokens.spaceSm)],
            Text(
              label,
              style: TextStyle(
                fontFamily: Tokens.fontDisplay,
                fontSize: Tokens.fontSizeMd,
                fontWeight: FontWeight.w600,
                color: highlighted ? Tokens.colorGold : Tokens.colorText,
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
