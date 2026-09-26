import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../theme/ui_scale.dart';
import 'gesture_hint.dart';
import 'tutorial_controller.dart';

/// The tutorial's chrome: a looping gesture hint with a label, and Skip. No
/// scrim, and confined to the board's rect, so touches outside Skip still reach
/// the board and nothing paints over the banner ad.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.controller,
    required this.boardKey,
  });

  final TutorialController controller;

  /// Key on gameplay's board container, whose laid-out rect depends on the HUD
  /// and banner heights.
  final GlobalKey boardKey;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

/// How quickly the chrome fades under a finger or when a prompt is satisfied.
const _fadeDuration = Duration(milliseconds: 220);

/// The plate behind Skip, matching the prompt's own label plate.
const _skipFill = Color(0xE0140C06);

/// What Skip dims to under a finger; not zero, so it stays findable.
const _touchedOpacity = 0.15;

class _TutorialOverlayState extends State<TutorialOverlay> {
  Rect? _boardRect;

  /// Re-measured after every frame (the board resizes when the banner reports
  /// its height), relative to this overlay so it fits the `Positioned` below.
  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final self = context.findRenderObject();
      final board = widget.boardKey.currentContext?.findRenderObject();
      if (self is! RenderBox || board is! RenderBox) return;
      if (!self.hasSize || !board.hasSize) return;
      final rect =
          board.localToGlobal(Offset.zero, ancestor: self) & board.size;
      if (rect != _boardRect) setState(() => _boardRect = rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    // `Positioned` must be a direct child of the `Stack`.
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => _build(),
      ),
    );
  }

  Widget _build() {
    final rect = _boardRect;
    // Nowhere to put the prompt before the first measurement.
    if (rect == null) return const SizedBox.shrink();

    final c = widget.controller;
    final ui = context.scale;
    // Mid-gesture the player watches the board; the chrome stands down.
    final faded = c.boardTouched;

    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: Stack(
            children: [
              // Over the piece being steered. A satisfied lesson leaves the
              // hint at `none` and the prompt fades out; the board confirms.
              AnimatedOpacity(
                opacity: faded ? 0.0 : 1.0,
                duration: _fadeDuration,
                child: Align(
                  alignment: Alignment(0, c.hintAlignY),
                  child: GestureHint(hint: c.hint, label: c.label),
                ),
              ),
              // The hole the rigged floor left.
              if (c.gapAlignX != null)
                AnimatedOpacity(
                  opacity: faded ? 0.0 : 1.0,
                  duration: _fadeDuration,
                  child: Align(
                    alignment: Alignment(c.gapAlignX!, 0.92),
                    child: const _GapMarker(),
                  ),
                ),
              // The top-right corner is never what the player is told to look
              // at.
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(ui.spaceSm),
                  child: AnimatedOpacity(
                    opacity: faded ? _touchedOpacity : 1.0,
                    duration: _fadeDuration,
                    child: _SkipButton(onPressed: c.skip),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A pulsing chevron over the gap in the rigged floor. Not the [GestureHint]
/// hand, which says "do this"; this says "put it there".
class _GapMarker extends StatefulWidget {
  const _GapMarker();

  @override
  State<_GapMarker> createState() => _GapMarkerState();
}

class _GapMarkerState extends State<_GapMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // One nudge per loop with a rest, so it reads as pointing.
          final t = Curves.easeInOut.transform(
            (_controller.value / 0.55).clamp(0.0, 1.0),
          );
          final bob = (t < 0.5 ? t : 1 - t) * 2;
          return Transform.translate(
            offset: Offset(0, bob * ui.px(6)),
            child: Opacity(
              opacity: 0.55 + bob * 0.45,
              child: Transform.rotate(
                angle: math.pi / 2,
                child: SvgPicture.asset(
                  AppIcons.chevronRight,
                  width: ui.iconMd,
                  height: ui.iconMd,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF2A1A0B),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Skip on the bare board: muted text vanishes on lit wood, so it gets the
/// prompt's own plate.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: ui.spaceMd,
          vertical: ui.spaceXs,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: _skipFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ui.radiusMd),
          side: const BorderSide(color: Tokens.colorPanelBorder),
        ),
      ),
      child: Text(
        'Skip',
        style: TextStyle(
          fontFamily: Tokens.fontDisplay,
          fontSize: ui.fontSm,
          fontWeight: FontWeight.w700,
          color: Tokens.colorText,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
