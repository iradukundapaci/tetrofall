import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/panel.dart';
import '../../widgets/primary_button.dart';
import 'gesture_hint.dart';
import 'tutorial_controller.dart';

/// The first-run tutorial's chrome. Two very different looks share one widget
/// because they are two halves of the same sequence:
///
/// * **Modal steps** match the pause and quit prompts exactly — scrim, centred
///   [AppPanel], a button. The board is already dimmed behind them by
///   gameplay's own `dimmed` treatment.
/// * **Coach steps** draw no scrim at all and confine themselves to the
///   board's own rect, so every touch outside the caption still reaches the
///   board — and so nothing is ever painted over the banner ad below it.
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
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: SizedBox(
          width: 300,
          child: AppPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: Tokens.fontDisplay,
                    fontSize: Tokens.fontSizeXl,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: Tokens.colorText,
                  ),
                ),
                const SizedBox(height: Tokens.spaceMd),
                Text(
                  c.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: Tokens.fontSizeSm,
                    fontWeight: FontWeight.w600,
                    color: Tokens.colorTextMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: Tokens.spaceLg),
                PrimaryButton(
                  label: c.buttonLabel ?? 'Continue',
                  fontSize: Tokens.fontSizeMd,
                  onPressed: c.advance,
                ),
                // Nothing left to skip on the closing card — its own button
                // already does exactly what Skip would.
                if (c.step != TutorialStep.done) ...[
                  const SizedBox(height: Tokens.spaceSm),
                  _SkipButton(onPressed: c.skip),
                ],
              ],
            ),
          ),
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
    final card = Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: _CoachCard(text: c.body, onSkip: c.skip),
    );

    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: Stack(
            children: [
              // Up near the spawn rows, where the piece the player is being
              // asked to steer actually is.
              Align(
                alignment: const Alignment(0, -0.35),
                child: GestureHint(hint: c.hint),
              ),
              if (c.captionAtTop)
                Positioned(top: 0, left: 0, right: 0, child: card)
              else
                Positioned(bottom: 0, left: 0, right: 0, child: card),
            ],
          ),
        ),
      ],
    );
  }
}

/// The caption on a coach step. Deliberately narrower and lighter than
/// [AppPanel] — it sits *on* the live board, not in front of it.
class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.text, required this.onSkip});

  final String text;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            Tokens.spaceMd,
            Tokens.spaceMd,
            Tokens.spaceMd,
            Tokens.spaceSm,
          ),
          decoration: BoxDecoration(
            color: const Color(0xE0140C06),
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
            border: Border.all(color: Tokens.colorPanelBorder),
            boxShadow: const [Tokens.shadowSoft],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: Tokens.fontDisplay,
                  fontSize: Tokens.fontSizeMd,
                  fontWeight: FontWeight.w700,
                  color: Tokens.colorText,
                  height: 1.35,
                ),
              ),
              _SkipButton(onPressed: onSkip),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: const Text(
        'Skip',
        style: TextStyle(
          fontFamily: Tokens.fontDisplay,
          fontSize: Tokens.fontSizeSm,
          fontWeight: FontWeight.w700,
          color: Tokens.colorTextMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
