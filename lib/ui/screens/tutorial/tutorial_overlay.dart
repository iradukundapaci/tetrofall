import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../theme/ui_scale.dart';
import 'gesture_hint.dart';
import 'tutorial_controller.dart';

/// The first-run tutorial's chrome: a looping gesture hint with a word or two
/// under it, and Skip.
///
/// It draws no scrim and confines itself to the board's own rect, so every
/// touch outside the Skip button still reaches the board, and nothing is ever
/// painted over the banner ad below it. There is no modal branch — the whole
/// tutorial is one live gameplay session, and a panel over the board would
/// both stop it and, through the dim treatment's `IgnorePointer`, swallow the
/// very gestures being taught.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.controller,
    required this.boardKey,
  });

  final TutorialController controller;

  /// Key on gameplay's board container. This layer needs the board's real
  /// laid-out rect, which depends on the HUD above it and on the banner ad's
  /// measured height below it, so it is read back from layout rather than
  /// guessed at.
  final GlobalKey boardKey;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

/// How quickly the chrome gets out of the way under a finger, and how quickly
/// a satisfied prompt disappears.
const _fadeDuration = Duration(milliseconds: 220);

/// The plate behind Skip, matching the prompt's own label plate.
const _skipFill = Color(0xE0140C06);

/// What Skip dims to under a finger. Not zero: the prompt itself can go, but
/// the one control that has to stay findable from any moment should not.
const _touchedOpacity = 0.15;

class _TutorialOverlayState extends State<TutorialOverlay> {
  Rect? _boardRect;

  /// Re-measured after every frame rather than once: the board resizes when
  /// the banner ad finally reports its height, which on a first launch happens
  /// while the tutorial is already up.
  ///
  /// Measured relative to this overlay rather than to the screen, so the rect
  /// arrives already in the coordinate space the `Positioned` below wants.
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
    // `Positioned` has to be a direct child of a `Stack`, so the positioning
    // lives here and everything below is plain layout inside the board's rect.
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => _build(),
      ),
    );
  }

  Widget _build() {
    final rect = _boardRect;
    // Before the first post-frame measurement there is nowhere to put the
    // prompt. The board is live and unobstructed for that one frame.
    if (rect == null) return const SizedBox.shrink();

    final c = widget.controller;
    final ui = context.scale;
    // Mid-gesture the player is watching the board, not reading over it. The
    // prompt and Skip both stand down until the finger comes off.
    final faded = c.boardTouched;

    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: Stack(
            children: [
              // Over the piece the player is being asked to steer, rather than
              // at a fixed height that happened to look about right. A
              // satisfied lesson leaves [TutorialController.hint] at `none`,
              // and the prompt fades out rather than being replaced — the live
              // board is the confirmation.
              AnimatedOpacity(
                opacity: faded ? 0.0 : 1.0,
                duration: _fadeDuration,
                child: Align(
                  alignment: Alignment(0, c.hintAlignY),
                  child: GestureHint(hint: c.hint, label: c.label),
                ),
              ),
              // The hole the rigged floor left. "Fill the row" is only
              // actionable once the player can see which row, and where.
              if (c.gapAlignX != null)
                AnimatedOpacity(
                  opacity: faded ? 0.0 : 1.0,
                  duration: _fadeDuration,
                  child: Align(
                    alignment: Alignment(c.gapAlignX!, 0.92),
                    child: const _GapMarker(),
                  ),
                ),
              // Pieces spawn top-centre and the prompt hangs below them, so
              // the top-right corner is the one piece of board that is never
              // the thing the player has been told to look at.
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

/// A pulsing chevron over the gap in the rigged floor.
///
/// Deliberately not the [GestureHint] hand: that says "do this with your
/// finger", and this is saying "put it *there*" — a different kind of
/// instruction, and the two are on screen together.
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
          // One nudge downward per loop, with a rest at the end, so it reads
          // as pointing rather than bouncing.
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

/// Skip, as it appears on the bare board.
///
/// Muted text is right on [AppPanel]'s near-black; on lit wood it all but
/// disappears, and Skip is the one control that has to stay findable from any
/// moment. So it gets the prompt's own plate behind it.
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
