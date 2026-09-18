import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/boosters/booster_run_state.dart';
import '../../game/boosters/booster_type.dart';
import '../../models/theme_definition.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// One booster in the bar: a disc, a glyph, and one badge on its rim
/// (`boosters.md` §9.3).
///
/// Round and small is deliberate. A disc reads as a control rather than as a
/// second frame under the board, the row fits in a 58pt strip, and on a tablet
/// it stays 50pt instead of growing into a slab — 50 still clears the 48pt
/// touch target.
///
/// **One badge corner.** Bottom-right carries the whole story: a number means
/// the booster is loaded, a play triangle means a video brings it back, and
/// nothing means it is done for the run.
class BoosterSlotButton extends StatelessWidget {
  const BoosterSlotButton({
    super.key,
    required this.type,
    required this.state,
    required this.charges,
    required this.aimProgress,
    required this.theme,
    required this.onTap,
  });

  final BoosterType type;
  final BoosterSlotState state;
  final int charges;

  /// 1 at the moment of arming, 0 when the aim window runs out (§4.4).
  final double aimProgress;

  final ThemeDefinition theme;
  final VoidCallback onTap;

  bool get _spent =>
      state == BoosterSlotState.spent || state == BoosterSlotState.exhausted;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final size = ui.px(Tokens.boosterSlot);

    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _spent
            ? theme.boardBg.withValues(alpha: 0.3)
            : theme.boosterFace,
        border: Border.all(color: _rimColor, width: ui.px(1.5)),
        boxShadow: _spent ? null : const [Tokens.shadowSoft],
      ),
      child: Center(
        child: SvgPicture.asset(
          type.icon,
          width: ui.px(Tokens.boosterGlyphSize),
          height: ui.px(Tokens.boosterGlyphSize),
          colorFilter: ColorFilter.mode(_glyphColor, BlendMode.srcIn),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: type.displayName,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: state == BoosterSlotState.busy ? 0.6 : 1.0,
          child: SizedBox(
            width: size + ui.px(4),
            height: size + ui.px(4),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                disc,
                if (state == BoosterSlotState.armed)
                  // The aim window, draining around the rim.
                  SizedBox(
                    width: size,
                    height: size,
                    child: CustomPaint(
                      painter: _AimRingPainter(
                        progress: aimProgress,
                        color: theme.accent,
                        strokeWidth: ui.px(2.5),
                      ),
                    ),
                  ),
                Positioned(right: 0, bottom: 0, child: _badge(ui)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(UiScale ui) {
    // Nothing at all once a booster is done for the run: no number to show,
    // and no video to sell.
    if (state == BoosterSlotState.exhausted) return const SizedBox.shrink();

    if (state == BoosterSlotState.spent) {
      final badge = ui.px(Tokens.boosterBadge);
      return _BadgePulse(
        child: Container(
          width: badge,
          height: badge,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.boardBg,
          ),
          child: Center(
            child: SvgPicture.asset(
              AppIcons.circlePlay,
              width: badge - ui.px(2),
              height: badge - ui.px(2),
              colorFilter: ColorFilter.mode(theme.accent, BlendMode.srcIn),
            ),
          ),
        ),
      );
    }

    // The charge count. It stays bright even on a "no target" slot: the
    // charge is still there, the board just has nothing to spend it on.
    return Container(
      constraints: BoxConstraints(minWidth: ui.px(16)),
      height: ui.px(16),
      padding: EdgeInsets.symmetric(horizontal: ui.px(4)),
      decoration: BoxDecoration(
        color: theme.boardBg,
        borderRadius: BorderRadius.circular(UiScale.radiusPill),
      ),
      child: Center(
        child: Text(
          '$charges',
          style: TextStyle(
            fontFamily: Tokens.fontDisplay,
            fontSize: ui.fontXs,
            fontWeight: FontWeight.w700,
            color: theme.text,
            height: 1,
          ),
        ),
      ),
    );
  }

  Color get _rimColor => switch (state) {
    BoosterSlotState.armed => theme.accent,
    BoosterSlotState.noTarget => theme.boosterRim.withValues(alpha: 0.3),
    BoosterSlotState.spent ||
    BoosterSlotState.exhausted => Colors.white.withValues(alpha: 0.08),
    _ => theme.boosterRim,
  };

  Color get _glyphColor => switch (state) {
    BoosterSlotState.armed => theme.text,
    BoosterSlotState.noTarget => theme.boosterGlyph.withValues(alpha: 0.4),
    BoosterSlotState.spent || BoosterSlotState.exhausted =>
      theme.boosterGlyphMuted.withValues(alpha: 0.45),
    _ => theme.boosterGlyph,
  };
}

/// Scale 1 → 1.18 → 1 every 2.4s: enough to read as an offer without nagging
/// (§9.3).
class _BadgePulse extends StatefulWidget {
  const _BadgePulse({required this.child});

  final Widget child;

  @override
  State<_BadgePulse> createState() => _BadgePulseState();
}

class _BadgePulseState extends State<_BadgePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      // One short pulse per cycle, then a long rest.
      final t = _controller.value;
      final pulse = t < 0.25 ? math.sin(t / 0.25 * math.pi) : 0.0;
      return Transform.scale(scale: 1 + 0.18 * pulse, child: child);
    },
    child: widget.child,
  );
}

class _AimRingPainter extends CustomPainter {
  const _AimRingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Offset.zero & size,
      -math.pi / 2,
      -2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_AimRingPainter old) => old.progress != progress;
}
