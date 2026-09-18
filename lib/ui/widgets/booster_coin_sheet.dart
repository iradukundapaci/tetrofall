import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import 'modal_overlay.dart';
import 'panel.dart';
import 'primary_button.dart';

/// The one sheet both booster purchases use — a re-spin before the run
/// (`boosters.md` §3.5) and a booster brought back during it (§4.9).
///
/// They share a widget because they share a contract: the sheet names what it
/// costs **before** anything is spent, and declining costs nothing. Two
/// different-looking prompts would read as two different deals.
///
/// This used to play a rewarded video. It does not any more — Coins are the
/// price of everything and rewarded video is only ever the faucet, so an
/// empty wallet routes to the earn screen rather than putting an ad in front
/// of the player at the moment they are trying to get on with the game.
class BoosterCoinSheet extends StatelessWidget {
  const BoosterCoinSheet({
    super.key,
    required this.title,
    required this.message,
    required this.price,
    required this.balance,
    required this.onSpend,
    required this.onEarn,
    required this.onDecline,
  });

  /// Names the thing, e.g. "Recharge Hammer?" or "Re-spin the Line slot?".
  final String title;

  /// What it buys, and how many are left this run.
  final String message;

  final int price;
  final int balance;

  /// Called only when the player can afford [price].
  final VoidCallback onSpend;

  /// Called instead when they cannot — opens the earn screen.
  final VoidCallback onEarn;

  final VoidCallback onDecline;

  bool get _affordable => balance >= price;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return ModalOverlay(
      child: AppPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              _affordable ? AppIcons.coin : AppIcons.circlePlay,
              width: ui.iconLg,
              height: ui.iconLg,
              colorFilter: const ColorFilter.mode(
                Tokens.colorGold,
                BlendMode.srcIn,
              ),
            ),
            SizedBox(height: ui.spaceSm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Tokens.fontDisplay,
                fontSize: ui.fontLg,
                fontWeight: FontWeight.w700,
                color: Tokens.colorText,
              ),
            ),
            SizedBox(height: ui.spaceSm),
            Text(
              _affordable
                  ? message
                  // Never a scolding, and never a dead end: say what is short
                  // and point at the one screen that fixes it.
                  : '$message\n\nYou have $balance — $price needed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Tokens.fontBody,
                fontSize: ui.fontSm,
                color: Tokens.colorTextMuted,
              ),
            ),
            SizedBox(height: ui.spaceLg),
            PrimaryButton(
              label: _affordable ? 'Spend $price' : 'Earn Coins',
              onPressed: _affordable ? onSpend : onEarn,
            ),
            SizedBox(height: ui.spaceSm),
            // The decline is always one plain word, with no countdown and no
            // pre-selected primary (§4.9 Copy).
            TextButton(
              onPressed: onDecline,
              child: Text(
                'Not now',
                style: TextStyle(
                  fontFamily: Tokens.fontBody,
                  fontSize: ui.fontSm,
                  color: Tokens.colorTextMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
