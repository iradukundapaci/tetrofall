import 'package:flutter/material.dart';

import '../../game/tetrofall_game.dart';
import '../../services/storage_service.dart';
import '../theme/tokens.dart';
import '../widgets/panel.dart';
import '../widgets/primary_button.dart';
import 'settings_screen.dart';

/// 1:1 port of pause.html's modal: Resume, Restart, Settings, Quit.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.storage,
    required this.liveGame,
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
  });

  final StorageService storage;
  final TetrofallGame liveGame;
  final VoidCallback onResume;
  final VoidCallback onRestart;

  /// Asks the host screen to confirm before abandoning the run.
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: SizedBox(
            width: 280,
            child: AppPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'PAUSED',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: Tokens.fontDisplay,
                      fontSize: Tokens.fontSizeXxl,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: Tokens.colorText,
                    ),
                  ),
                  const SizedBox(height: Tokens.spaceMd),
                  PrimaryButton(
                    label: 'Resume',
                    fontSize: Tokens.fontSizeMd,
                    onPressed: onResume,
                  ),
                  const SizedBox(height: Tokens.spaceMd),
                  SecondaryButton(label: 'Restart', onPressed: onRestart),
                  const SizedBox(height: Tokens.spaceMd),
                  SecondaryButton(
                    label: 'Settings',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          storage: storage,
                          liveGame: liveGame,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Tokens.spaceMd),
                  TextButton(
                    onPressed: onQuit,
                    child: const Text(
                      'Quit',
                      style: TextStyle(
                        fontFamily: Tokens.fontDisplay,
                        fontSize: Tokens.fontSizeMd,
                        fontWeight: FontWeight.w700,
                        color: Tokens.colorTextMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
