import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/ui_scale.dart';
import '../../widgets/modal_overlay.dart';
import '../../widgets/panel.dart';
import '../../widgets/primary_button.dart';
import 'gesture_hint.dart';
import 'tutorial_controller.dart';

/// The first-run tutorial's chrome. Two very different looks share one widget
/// because they are two halves of the same sequence:
///
/// * **Modal steps** match the pause and quit prompts exactly scrim, centred
///   [AppPanel], a button. The board is already dimmed behind them by
///   gameplay's own `dimmed` treatment.
/// * **Coach steps** draw no scrim at all and confine themselves to the
///   board's own rect, so every touch outside the caption still reaches the
///   board and so nothing is ever painted over the banner ad below it.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.controller,
    required this.boardKey,
  });

  final TutorialController controller;

  /// Key on gameplay's board container. The coach layer needs the board's real
  /// laid-out rect, which depends on the HUD above it and on the banner ad's
  /// measured height below it, so it is read back from layout rather than
  /// guessed at.
  final GlobalKey boardKey;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

/// How quickly the coach chrome gets out of the way, and how quickly the
/// caption changes ends when the action does.
const _fadeDuration = Duration(milliseconds: 180);
const _slideDuration = Duration(milliseconds: 280);

/// The caption's plate. Dark enough to read white display type against the
/// board's lit wood, translucent enough to see the board through.
const _cardFill = Color(0xE0140C06);

/// What the caption dims to under a finger. Not zero: the player should still
/// be able to see that the instruction is there and unchanged, just not have
/// it standing between them and the board.
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
    // lives here and everything below is plain layout inside this overlay's
    // own full-screen box.
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => widget.controller.mode == TutorialMode.modal
            ? _buildModal()
            : _buildCoach(),
      ),
    );
  }

  // ------------------------------------------------------------------ modal

  Widget _buildModal() {
    final c = widget.controller;
    final ui = context.scale;
    // The body rather than [ModalOverlay] itself: `build` already owns this
    // overlay's `Positioned.fill`, and the coach branch needs to keep it.
    return ModalOverlayBody(
      scrimOpacity: 0.55,
      child: AppPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Tokens.fontDisplay,
                fontSize: ui.fontXl,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: Tokens.colorText,
              ),
            ),
            SizedBox(height: ui.spaceMd),
            Text(
              c.body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ui.fontSm,
                fontWeight: FontWeight.w600,
                color: Tokens.colorTextMuted,
                height: 1.4,
              ),
            ),
            SizedBox(height: ui.spaceLg),
            PrimaryButton(
              label: c.buttonLabel ?? 'Continue',
              fontSize: ui.fontMd,
              onPressed: c.advance,
            ),
            // Nothing left to skip on the closing card its own button
            // already does exactly what Skip would.
            if (c.step != TutorialStep.done) ...[
              SizedBox(height: ui.spaceSm),
              _SkipButton(onPressed: c.skip),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ coach

  Widget _buildCoach() {
    final rect = _boardRect;
    // Before the first post-frame measurement there is nowhere to put the
    // caption. The board is live and unobstructed for that one frame.
    if (rect == null) return const SizedBox.shrink();

    final c = widget.controller;
    final ui = context.scale;
    // Mid-gesture the player is watching the board, not reading about it. The
    // caption, the hint and Skip all stand down until the finger comes off.
    final faded = c.boardTouched;

    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: Stack(
            children: [
              // Over the piece the player is being asked to steer, rather than
              // at a fixed height that happened to look about right.
              AnimatedOpacity(
                opacity: faded ? 0.0 : 1.0,
                duration: _fadeDuration,
                child: Align(
                  alignment: Alignment(0, c.hintAlignY),
                  child: GestureHint(hint: c.hint),
                ),
              ),
              // Whichever end of the board the action is not at. It slides
              // rather than teleports, because on the drop steps it changes
              // ends the instant the piece sets off and a jump there would
              // read as a second thing happening.
              //
              // Skip travels with it rather than sitting in the opposite
              // corner: the caption is at the far end precisely because the
              // action is at *this* one, so the corner it would leave free is
              // the one the player has been told to watch.
              AnimatedAlign(
                alignment: c.captionAtTop
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                duration: _slideDuration,
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: faded ? _touchedOpacity : 1.0,
                  duration: _fadeDuration,
                  child: Padding(
                    padding: EdgeInsets.all(ui.spaceSm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      // Sizes the column to the card and hangs Skip off its
                      // right edge, so the card still reads as centred.
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final w
                            in c.captionAtTop
                                ? [_CoachCard(text: c.body), _skip(c)]
                                : [_skip(c), _CoachCard(text: c.body)])
                          w,
                      ],
                    ),
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

/// Skip, as it appears alongside a coach caption.
Widget _skip(TutorialController c) =>
    _SkipButton(onPressed: c.skip, onBoard: true);

/// The caption on a coach step. Deliberately narrow, short and lighter than
/// [AppPanel] it sits *on* the live board, not in front of it, and every
/// row of it is a row of board the player cannot see.
class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: ui.px(300)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ui.spaceMd,
          vertical: ui.spaceSm,
        ),
        decoration: BoxDecoration(
          color: _cardFill,
          borderRadius: BorderRadius.circular(ui.radiusMd),
          border: Border.all(color: Tokens.colorPanelBorder),
          boxShadow: const [Tokens.shadowSoft],
        ),
        // Cross-faded so that a step being satisfied reads as the card
        // answering, rather than as the text being swapped out from under it.
        child: AnimatedSwitcher(
          duration: _fadeDuration,
          child: Text(
            text,
            key: ValueKey(text),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: ui.fontSm,
              fontWeight: FontWeight.w700,
              color: Tokens.colorText,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed, this.onBoard = false});

  final VoidCallback onPressed;

  /// Whether this one sits on the bare board rather than on a panel.
  ///
  /// Muted text is right on [AppPanel]'s near-black; on lit wood it all but
  /// disappears, and Skip is the one control that has to stay findable from
  /// any step. On the board it gets the caption's own plate behind it.
  final bool onBoard;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final label = Text(
      'Skip',
      style: TextStyle(
        fontFamily: Tokens.fontDisplay,
        fontSize: ui.fontSm,
        fontWeight: FontWeight.w700,
        color: onBoard ? Tokens.colorText : Tokens.colorTextMuted,
        letterSpacing: 0.5,
      ),
    );

    if (!onBoard) return TextButton(onPressed: onPressed, child: label);

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: ui.spaceMd,
          vertical: ui.spaceXs,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: _cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ui.radiusMd),
          side: const BorderSide(color: Tokens.colorPanelBorder),
        ),
      ),
      child: label,
    );
  }
}
