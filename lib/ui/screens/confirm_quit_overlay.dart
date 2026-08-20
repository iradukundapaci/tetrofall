import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/modal_overlay.dart';
import '../widgets/panel.dart';
import '../widgets/primary_button.dart';

/// Guard against losing a run by accident — shown when the player hits the
/// system back gesture mid-game or taps Quit from the pause modal.
class ConfirmQuitOverlay extends StatelessWidget {
  const ConfirmQuitOverlay({
    super.key,
    required this.score,
    required this.onContinue,
    required this.onQuit,
  });

  final int score;
  final VoidCallback onContinue;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return ModalOverlay(
      scrimOpacity: 0.6,
      child: AppPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Nine display-font characters at the largest type size in the
            // app, in the narrowest container it has — the one heading that
            // cannot be trusted to fit, so it is allowed to shrink instead of
            // wrapping mid-word.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'QUIT GAME?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Tokens.fontDisplay,
                  fontSize: ui.fontXxl,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Tokens.colorText,
                ),
              ),
            ),
            SizedBox(height: ui.spaceSm),
            Text(
              'Your run will be lost.\nScore so far: $score',
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
              label: 'Keep Playing',
              fontSize: ui.fontMd,
              onPressed: onContinue,
            ),
            SizedBox(height: ui.spaceMd),
            SecondaryButton(label: 'Quit', onPressed: onQuit),
          ],
        ),
      ),
    );
  }
}
