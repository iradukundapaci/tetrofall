import 'package:flutter/material.dart';

import '../theme/tokens.dart';
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
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: SizedBox(
            width: 300,
            child: AppPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'QUIT GAME?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: Tokens.fontDisplay,
                      fontSize: Tokens.fontSizeXxl,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: Tokens.colorText,
                    ),
                  ),
                  const SizedBox(height: Tokens.spaceSm),
                  Text(
                    'Your run will be lost.\nScore so far: $score',
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
                    label: 'Keep Playing',
                    fontSize: Tokens.fontSizeMd,
                    onPressed: onContinue,
                  ),
                  const SizedBox(height: Tokens.spaceMd),
                  SecondaryButton(label: 'Quit', onPressed: onQuit),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
