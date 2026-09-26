import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/modal_overlay.dart';
import '../widgets/panel.dart';
import '../widgets/primary_button.dart';

/// Guards against losing a run by accident (back gesture or pause-menu Quit).
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
            // The one heading that may not fit: shrink rather than wrap.
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
