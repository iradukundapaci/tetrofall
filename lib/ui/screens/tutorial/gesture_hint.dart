import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../theme/ui_scale.dart';
import 'tutorial_controller.dart';

/// The looping "do this" animation that floats over the board on a coach step:
/// a translucent fingertip, plus chevrons pointing the way it travels.
///
/// Hand-rolled from one [AnimationController] in the same idiom as the splash
/// sequence (`splash_screen.dart`) — explicit millisecond constants and
/// hand-cut segments — rather than pulling in an animation package for four
/// short loops.
class GestureHint extends StatefulWidget {
  const GestureHint({super.key, required this.hint});

  final TutorialHint hint;

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
      child: AnimatedBuilder(
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

  Widget _buildTap(double t) {
    final press = _seg(t, 0, 0.16) * (1 - _seg(t, 0.16, 0.34));
    final ring = Curves.easeOut.transform(_seg(t, 0.1, 0.62));
    final opacity = 1 - _seg(t, 0.7, 0.9);
    return Opacity(
      opacity: opacity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: (1 - ring) * 0.7,
            child: Container(
              width: _fingerSize + ring * _ui.px(46),
              height: _fingerSize + ring * _ui.px(46),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Tokens.colorGold,
                  width: _ui.borderThick,
                ),
              ),
            ),
          ),
          Transform.scale(scale: 1 - press * 0.18, child: _finger()),
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

  Widget _finger() => Container(
    width: _fingerSize,
    height: _fingerSize,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0x33F5EAD9),
      border: Border.all(color: Tokens.colorGold, width: _ui.borderThick),
      boxShadow: const [Tokens.shadowSoft],
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
