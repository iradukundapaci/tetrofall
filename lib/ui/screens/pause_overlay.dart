import 'package:flutter/material.dart';

import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/storage_service.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/modal_overlay.dart';
import '../widgets/panel.dart';
import '../widgets/primary_button.dart';
import 'settings_screen.dart';

/// 1:1 port of pause.html's modal: Resume, Restart, Settings, Quit.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.storage,
    required this.ads,
    required this.liveGame,
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
  });

  final StorageService storage;

  /// Passed straight through to [SettingsScreen] for its Privacy row.
  final AdsService ads;
  final TetrofallGame liveGame;
  final VoidCallback onResume;
  final VoidCallback onRestart;

  /// Asks the host screen to confirm before abandoning the run.
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return ModalOverlay(
      child: AppPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PAUSED',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Tokens.fontDisplay,
                fontSize: ui.fontXxl,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: Tokens.colorText,
              ),
            ),
            SizedBox(height: ui.spaceMd),
            PrimaryButton(
              label: 'Resume',
              fontSize: ui.fontMd,
              onPressed: onResume,
            ),
            SizedBox(height: ui.spaceMd),
            SecondaryButton(label: 'Restart', onPressed: onRestart),
            SizedBox(height: ui.spaceMd),
            SecondaryButton(
              label: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    storage: storage,
                    ads: ads,
                    liveGame: liveGame,
                  ),
                ),
              ),
            ),
            SizedBox(height: ui.spaceMd),
            TextButton(
              onPressed: onQuit,
              child: Text(
                'Quit',
                style: TextStyle(
                  fontFamily: Tokens.fontDisplay,
                  fontSize: ui.fontMd,
                  fontWeight: FontWeight.w700,
                  color: Tokens.colorTextMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
