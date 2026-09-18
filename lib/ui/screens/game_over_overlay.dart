import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/engine/events.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/icon_button.dart';
import '../widgets/modal_overlay.dart';
import '../widgets/primary_button.dart';

class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({
    super.key,
    required this.reason,
    required this.score,
    required this.best,
    required this.onRestart,
    required this.onHome,
    required this.canContinue,
    required this.continuePrice,
    required this.coinBalance,
    required this.onContinue,
  });

  final GameOverReason reason;
  final int score;
  final int best;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  /// Whether a continue is still on the table at all — one per run, whatever
  /// it is paid with.
  final bool canContinue;

  /// Coins the continue costs. Shown on the button, so the price is never a
  /// surprise revealed after the tap.
  final int continuePrice;

  final int coinBalance;

  /// Spends the Coins, or opens the earn screen first when the wallet is
  /// short. Either way the player does not lose this board by going to get
  /// what they need.
  final VoidCallback onContinue;

  bool get _isNewBest => score > best;

  String get _reasonLabel => switch (reason) {
    GameOverReason.topOut => 'The rising floor reached the top.',
    GameOverReason.blockOut => 'No room left to spawn the next piece.',
  };

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return ModalOverlay(
      scrimOpacity: 0.72,
      // The caption and the score numeral want the full viewport width; only
      // the button column below is panel-width.
      constrainWidth: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: ui.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isNewBest) ...[
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ui.px(14),
                  vertical: ui.px(5),
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(UiScale.radiusPill),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Tokens.colorGold, Color(0xFFD99A1F)],
                  ),
                  boxShadow: const [Tokens.shadowSoft],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      size: ui.px(13),
                      color: Tokens.colorWoodDark,
                    ),
                    SizedBox(width: ui.px(6)),
                    Text(
                      'NEW BEST!',
                      style: TextStyle(
                        fontFamily: Tokens.fontDisplay,
                        fontSize: ui.fontXs,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: Tokens.colorWoodDark,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: ui.spaceXs),
            ],
            Text(
              'GAME OVER',
              style: TextStyle(
                fontFamily: Tokens.fontDisplay,
                fontSize: ui.fontSm,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: Tokens.colorTextMuted,
              ),
            ),
            SizedBox(height: ui.spaceXs),
            Text(
              _reasonLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ui.fontSm,
                color: Tokens.colorTextMuted,
              ),
            ),
            SizedBox(height: ui.spaceMd),
            Text(
              'SCORE',
              style: TextStyle(
                fontSize: ui.fontSm,
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
                style: TextStyle(
                  fontFamily: Tokens.fontDisplay,
                  fontSize: ui.fontHero,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
            ),
            Text.rich(
              TextSpan(
                text: 'Previous best: ',
                style: TextStyle(
                  fontSize: ui.fontSm,
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
            SizedBox(height: ui.spaceXl),
            SizedBox(
              width: ui.panelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canContinue) ...[
                    SecondaryButton(
                      label: coinBalance >= continuePrice
                          ? 'Continue  $continuePrice'
                          : 'Continue  $continuePrice  (earn Coins)',
                      icon: SvgPicture.asset(
                        AppIcons.coin,
                        width: ui.iconSm,
                        height: ui.iconSm,
                        colorFilter: const ColorFilter.mode(
                          Tokens.colorGold,
                          BlendMode.srcIn,
                        ),
                      ),
                      onPressed: onContinue,
                    ),
                    SizedBox(height: ui.spaceMd),
                  ],
                  PrimaryButton(label: 'Play Again', onPressed: onRestart),
                  SizedBox(height: ui.spaceMd),
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
    );
  }
}
