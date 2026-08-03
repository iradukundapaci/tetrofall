import 'package:flutter/material.dart';

import '../../game/engine/events.dart';
import '../theme/tokens.dart';
import '../widgets/icon_button.dart';
import '../widgets/primary_button.dart';

class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({
    super.key,
    required this.reason,
    required this.score,
    required this.best,
    required this.onRestart,
    required this.onHome,
    required this.canContinueWithAd,
    required this.onContinueWithAd,
  });

  final GameOverReason reason;
  final int score;
  final int best;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  final bool canContinueWithAd;
  final VoidCallback onContinueWithAd;

  bool get _isNewBest => score > best;

  String get _reasonLabel => switch (reason) {
    GameOverReason.topOut => 'The rising floor reached the top.',
    GameOverReason.blockOut => 'No room left to spawn the next piece.',
  };

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isNewBest) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Tokens.colorGold, Color(0xFFD99A1F)],
                      ),
                      boxShadow: const [Tokens.shadowSoft],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 13, color: Tokens.colorWoodDark),
                        SizedBox(width: 6),
                        Text(
                          'NEW BEST!',
                          style: TextStyle(
                            fontFamily: Tokens.fontDisplay,
                            fontSize: Tokens.fontSizeXs,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: Tokens.colorWoodDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Tokens.spaceXs),
                ],
                Text(
                  'GAME OVER',
                  style: const TextStyle(
                    fontFamily: Tokens.fontDisplay,
                    fontSize: Tokens.fontSizeSm,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: Tokens.colorTextMuted,
                  ),
                ),
                const SizedBox(height: Tokens.spaceXs),
                Text(
                  _reasonLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: Tokens.fontSizeSm,
                    color: Tokens.colorTextMuted,
                  ),
                ),
                const SizedBox(height: Tokens.spaceMd),
                const Text(
                  'SCORE',
                  style: TextStyle(
                    fontSize: Tokens.fontSizeSm,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: Tokens.colorTextMuted,
                  ),
                ),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFE9B0),
                      Tokens.colorGold,
                      Color(0xFFC9821A),
                    ],
                    stops: [0, 0.55, 1],
                  ).createShader(bounds),
                  child: Text(
                    '$score',
                    style: const TextStyle(
                      fontFamily: Tokens.fontDisplay,
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    text: 'Previous best: ',
                    style: const TextStyle(
                      fontSize: Tokens.fontSizeSm,
                      color: Tokens.colorTextMuted,
                    ),
                    children: [
                      TextSpan(
                        text: '$best',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Tokens.colorText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Tokens.spaceXl),
                SizedBox(
                  width: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canContinueWithAd) ...[
                        SecondaryButton(
                          label: 'Watch Ad to Continue',
                          icon: const Icon(
                            Icons.smart_display_outlined,
                            size: 18,
                            color: Tokens.colorText,
                          ),
                          onPressed: onContinueWithAd,
                        ),
                        const SizedBox(height: Tokens.spaceMd),
                      ],
                      PrimaryButton(label: 'Play Again', onPressed: onRestart),
                      const SizedBox(height: Tokens.spaceMd),
                      Center(
                        child: CircleIconButton(
                          tooltip: 'Home',
                          icon: const Icon(
                            Icons.home_outlined,
                            color: Tokens.colorText,
                          ),
                          onPressed: onHome,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
