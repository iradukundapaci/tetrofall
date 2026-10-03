import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../theme/ui_scale.dart';

/// Which gesture animation plays over the board.
enum TutorialHint {
  none,
  swipeHorizontal,
  swipeLeft,
  swipeRight,
  tap,
  dragDown,
  flickDown,
}

/// The label plate: dark enough to read against lit wood, translucent enough
/// to see the board.
const _labelFill = Color(0xE0140C06);

/// How quickly one label gives way to the next.
const _labelFade = Duration(milliseconds: 180);

/// The looping "do this" prompt over the board: a fingertip with chevrons and
/// a label naming what the gesture does, driven by one [AnimationController].
class GestureHint extends StatefulWidget {
  const GestureHint({super.key, required this.hint, this.label, this.subLabel});

  final TutorialHint hint;

  /// One or two words naming what the gesture does, or null.
  final String? label;

  /// A dimmer line under [label] saying what the gesture does.
  final String? subLabel;

  @override
  State<GestureHint> createState() => _GestureHintState();
}

class _GestureHintState extends State<GestureHint>
    with SingleTickerProviderStateMixin {
  /// Resolved in [build] for the paint helpers, which have no `BuildContext`.
  late UiScale _ui;
  double get _fingerSize => _ui.px(Tokens.fingerHint);

  /// Each loop is one demonstration plus a beat of rest.
  static const _durations = {
    TutorialHint.swipeHorizontal: Duration(milliseconds: 1800),
    TutorialHint.swipeLeft: Duration(milliseconds: 1400),
    TutorialHint.swipeRight: Duration(milliseconds: 1400),
    TutorialHint.tap: Duration(milliseconds: 1300),
    TutorialHint.dragDown: Duration(milliseconds: 2400),
    TutorialHint.flickDown: Duration(milliseconds: 1500),
  };

  static Duration _durationFor(TutorialHint hint) =>
      _durations[hint] ?? const Duration(milliseconds: 1500);

  /// Built in [initState], not a lazy field: a [TutorialHint.none] step never
  /// reads it in [build], so a lazy initializer would first run in [dispose].
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
    _ui = context.scale;
    if (widget.hint == TutorialHint.none && widget.label == null) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.hint != TutorialHint.none)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => switch (widget.hint) {
                TutorialHint.swipeHorizontal => _buildSwipe(_controller.value),
                TutorialHint.swipeLeft => _buildOneWay(_controller.value, -1),
                TutorialHint.swipeRight => _buildOneWay(_controller.value, 1),
                TutorialHint.tap => _buildTap(_controller.value),
                TutorialHint.dragDown => _buildDrag(
                  _controller.value,
                  _ui.px(70),
                  0.12,
                  0.5,
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

  /// Cross-faded in place so the labels read as one prompt.
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
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
                  if (widget.subLabel != null)
                    Text(
                      widget.subLabel!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: Tokens.fontDisplay,
                        fontSize: _ui.fontSm * 0.85,
                        color: Tokens.colorText.withValues(alpha: 0.7),
                      ),
                    ),
                ],
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

  /// A swipe that only ever travels one way, with the chevrons ahead of the
  /// finger, so it can't be read as "either direction".
  Widget _buildOneWay(double t, int dir) {
    final travel = _ui.px(Tokens.fingerHint);
    final slide = Curves.easeInOut.transform(_seg(t, 0.1, 0.7));
    final opacity = _seg(t, 0, 0.1) * (1 - _seg(t, 0.8, 0.95));
    final angle = dir < 0 ? math.pi : 0.0;
    final chevrons = [_chevron(angle), _chevron(angle), _chevron(angle)];
    return Opacity(
      opacity: opacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dir < 0) ...chevrons,
          SizedBox(width: _ui.spaceSm),
          Transform.translate(
            offset: Offset(dir * (-travel * 0.6 + slide * travel * 1.2), 0),
            child: _finger(),
          ),
          SizedBox(width: _ui.spaceSm),
          if (dir > 0) ...chevrons,
        ],
      ),
    );
  }

  /// The fingertip's position in [AppIcons.handPoint] as a fraction of the box
  /// (24×24 viewBox); the tap ripple starts there, not at the hand's centre.
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
                  // The hand's outline colour: gold vanishes against lit wood.
                  border: Border.all(
                    color: const Color(0xFF2A1A0B),
                    width: _ui.borderThick,
                  ),
                ),
              ),
            ),
          ),
          // Scaled, never translated: a moving hand reads as the soft-drop
          // hint.
          Transform.scale(scale: 1 - press * 0.12, child: _finger()),
        ],
      ),
    );
  }

  /// Both downward gestures share a shape, differing in distance and speed.
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

  /// The hand, without a `colorFilter` (it carries its own palette). The shadow
  /// is a second copy underneath; a `BoxShadow` would shadow the square box.
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
