import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../theme/ui_scale.dart';

/// Which gesture animation plays over the board. Lives here rather than with
/// the controller because the widget below is the only thing that can draw one.
enum TutorialHint { none, swipeHorizontal, tap, dragDown, flickDown }

/// The plate the label sits on. Dark enough to read display type against the
/// board's lit wood, translucent enough to see the board through.
const _labelFill = Color(0xE0140C06);

/// How quickly one label gives way to the next.
const _labelFade = Duration(milliseconds: 180);

/// The looping "do this" prompt that floats over the board: a translucent
/// fingertip with chevrons pointing the way it travels, and a word or two
/// underneath naming what the gesture does.
///
/// Hand-rolled from one [AnimationController] in the same idiom as the splash
/// sequence (`splash_screen.dart`) — explicit millisecond constants and
/// hand-cut segments — rather than pulling in an animation package for four
/// short loops.
class GestureHint extends StatefulWidget {
  const GestureHint({super.key, required this.hint, this.label});

  final TutorialHint hint;

  /// One or two words under the animation, or null for none. The animation
  /// already says what the gesture *is*, so this names what it does.
  final String? label;

  @override
  State<GestureHint> createState() => _GestureHintState();
}

class _GestureHintState extends State<GestureHint>
    with SingleTickerProviderStateMixin {
  /// Resolved in [build] and read by the paint helpers below, which have no
  /// `BuildContext` of their own.
  late UiScale _ui;
  double get _fingerSize => _ui.px(Tokens.fingerHint);

  /// Each loop is one demonstration plus a beat of rest, so the gesture reads
  /// as a discrete action rather than a continuous wobble.
  static const _durations = {
    TutorialHint.swipeHorizontal: Duration(milliseconds: 1800),
    TutorialHint.tap: Duration(milliseconds: 1300),
    TutorialHint.dragDown: Duration(milliseconds: 2000),
    TutorialHint.flickDown: Duration(milliseconds: 1500),
  };

  static Duration _durationFor(TutorialHint hint) =>
      _durations[hint] ?? const Duration(milliseconds: 1500);

  /// Built here rather than in a `late` field initializer: a [TutorialHint.none]
  /// step never reads [_controller] from [build], so a lazy field would first
  /// run its initializer inside [dispose] — asking a defunct element for
  /// [TickerMode].
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.hint),
    )..repeat();
  }

  @override
  void didUpdateWidget(GestureHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hint != oldWidget.hint) {
      _controller
        ..duration = _durationFor(widget.hint)
        ..forward(from: 0)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Progress of [t] through the segment `[start, end]`, clamped outside it.
  static double _seg(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    if (widget.hint == TutorialHint.none) return const SizedBox.shrink();
    _ui = context.scale;
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => switch (widget.hint) {
              TutorialHint.swipeHorizontal => _buildSwipe(_controller.value),
              TutorialHint.tap => _buildTap(_controller.value),
              TutorialHint.dragDown => _buildDrag(
                _controller.value,
                _ui.px(70),
                0.12,
                0.6,
              ),
              TutorialHint.flickDown => _buildDrag(
                _controller.value,
                _ui.px(110),
                0.06,
                0.26,
              ),
              TutorialHint.none => const SizedBox.shrink(),
            },
          ),
          SizedBox(height: _ui.spaceSm),
          _buildLabel(),
        ],
      ),
    );
  }

  /// Cross-faded in place rather than swapped, so `Move → Rotate → Slam` reads
  /// as one prompt answering the player rather than three prompts arriving.
  Widget _buildLabel() {
    final label = widget.label;
    return AnimatedSwitcher(
      duration: _labelFade,
      child: label == null
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(label),
              padding: EdgeInsets.symmetric(
                horizontal: _ui.spaceMd,
                vertical: _ui.spaceXs,
              ),
              decoration: BoxDecoration(
                color: _labelFill,
                borderRadius: BorderRadius.circular(_ui.radiusMd),
                border: Border.all(color: Tokens.colorPanelBorder),
                boxShadow: const [Tokens.shadowSoft],
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Tokens.fontDisplay,
                  fontSize: _ui.fontSm,
                  fontWeight: FontWeight.w700,
                  color: Tokens.colorText,
                  letterSpacing: 0.5,
                ),
              ),
            ),
    );
  }

  Widget _buildSwipe(double t) {
    final travel = _ui.px(Tokens.fingerHint);
    final slide = Curves.easeInOut.transform(_seg(t, 0.15, 0.78));
    final opacity = _seg(t, 0, 0.12) * (1 - _seg(t, 0.82, 0.95));
    return Opacity(
      opacity: opacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chevron(math.pi),
          SizedBox(width: _ui.spaceSm),
          Transform.translate(
            offset: Offset(-travel + slide * travel * 2, 0),
            child: _finger(),
          ),
          SizedBox(width: _ui.spaceSm),
          _chevron(0),
        ],
      ),
    );
  }

  /// Where the fingertip sits inside [AppIcons.handPoint], as a fraction of the
  /// icon box, measured off the index finger's tip in its 24×24 viewBox.
  ///
  /// The ripple has to start there rather than at the middle of the icon: a
  /// ring centred on the whole hand reads as the hand glowing, not as the
  /// fingertip striking the board.
  static const _tipX = 10.5 / 24;
  static const _tipY = 4.5 / 24;

  Widget _buildTap(double t) {
    final press = _seg(t, 0, 0.16) * (1 - _seg(t, 0.16, 0.34));
    final ring = Curves.easeOut.transform(_seg(t, 0.1, 0.62));
    final opacity = 1 - _seg(t, 0.7, 0.9);
    return Opacity(
      opacity: opacity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(
              (_tipX - 0.5) * _fingerSize,
              (_tipY - 0.5) * _fingerSize,
            ),
            child: Opacity(
              opacity: (1 - ring) * 0.8,
              child: Container(
                width: _fingerSize * 0.5 + ring * _ui.px(46),
                height: _fingerSize * 0.5 + ring * _ui.px(46),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // The hand's own outline colour, not gold. Gold was legible
                  // around the old translucent disc, but this ring starts half
                  // that size against lit wood, and at low opacity it simply
                  // disappeared — the tap loop had no visible ripple at all.
                  border: Border.all(
                    color: const Color(0xFF2A1A0B),
                    width: _ui.borderThick,
                  ),
                ),
              ),
            ),
          ),
          // Scaled, never translated. A hand that travels downward — even 4px,
          // even on a loop — reads as a short drag, which is the soft-drop
          // hint, not this one. The ripple above is what says "tap"; the press
          // only has to keep the hand alive underneath it.
          Transform.scale(scale: 1 - press * 0.12, child: _finger()),
        ],
      ),
    );
  }

  /// Both downward gestures are the same shape — a fingertip travelling down
  /// with chevrons under it — separated only by how far and how fast it goes.
  Widget _buildDrag(double t, double travel, double start, double end) {
    final slide = Curves.easeInOut.transform(_seg(t, start, end));
    final opacity = _seg(t, 0, start) * (1 - _seg(t, end + 0.08, end + 0.28));
    return Opacity(
      opacity: opacity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: Offset(0, slide * travel),
            child: _finger(),
          ),
          SizedBox(height: _ui.spaceSm),
          _chevron(math.pi / 2),
        ],
      ),
    );
  }

  /// The hand doing the gesture.
  ///
  /// Drawn without a `colorFilter` — [AppIcons.handPoint] carries its own cream
  /// palm and dark outline, and flattening it to one colour would leave a
  /// silhouette that disappears into the board's lit wood.
  ///
  /// The drop shadow is a second copy underneath rather than a `BoxShadow`,
  /// which would shadow the widget's square box instead of the hand inside it.
  Widget _finger() => SizedBox(
    width: _fingerSize,
    height: _fingerSize,
    child: Stack(
      children: [
        Transform.translate(
          offset: Offset(_ui.px(1), _ui.px(2)),
          child: Opacity(
            opacity: 0.25,
            child: SvgPicture.asset(
              AppIcons.handPoint,
              width: _fingerSize,
              height: _fingerSize,
              colorFilter: const ColorFilter.mode(
                Color(0xFF140C06),
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        SvgPicture.asset(
          AppIcons.handPoint,
          width: _fingerSize,
          height: _fingerSize,
        ),
      ],
    ),
  );

  Widget _chevron(double radians) => Transform.rotate(
    angle: radians,
    child: SvgPicture.asset(
      AppIcons.chevronRight,
      width: _ui.iconSm,
      height: _ui.iconSm,
      colorFilter: const ColorFilter.mode(Tokens.colorGold, BlendMode.srcIn),
    ),
  );
}
