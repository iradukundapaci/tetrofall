import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/config/economy_tuning.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/wallet_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/coin_balance_pill.dart';
import '../widgets/primary_button.dart';

/// Where attention becomes Coins.
///
/// This screen is the whole faucet, so its only job is to make a *second*
/// view as cheap as the first. The loop is deliberately flat: watch, see the
/// balance move, tap again — with the next ad already preloaded by
/// [AdsService] and the button armed before the player has finished reading
/// the reward. Bouncing back to a menu between views is what kills multi-view
/// sittings, so nothing here navigates on its own.
class CoinVaultScreen extends StatefulWidget {
  const CoinVaultScreen({super.key, required this.ads, required this.wallet});

  final AdsService ads;
  final WalletService wallet;

  @override
  State<CoinVaultScreen> createState() => _CoinVaultScreenState();
}

class _CoinVaultScreenState extends State<CoinVaultScreen> {
  bool _watching = false;

  /// What the last view paid, shown until the next one starts.
  int? _lastReward;

  @override
  void dispose() {
    // The streak rewards one sitting, not a view they come back for hours
    // later.
    widget.wallet.resetViewStreak();
    super.dispose();
  }

  Future<void> _watch() async {
    if (_watching) return;
    setState(() {
      _watching = true;
      _lastReward = null;
    });
    AnalyticsService.design('coins:watch');

    final earned = await widget.ads.showRewardedCoins();
    if (!mounted) return;

    if (!earned) {
      // Dismissed early, or failed to show. Nothing is credited and nothing
      // is said about it beyond re-arming the button.
      AnalyticsService.design('coins:abandoned');
      setState(() => _watching = false);
      return;
    }

    final reward = await widget.wallet.creditAdView();
    if (!mounted) return;
    AnalyticsService.design('coins:earned');
    setState(() {
      _watching = false;
      _lastReward = reward;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(ui.spaceLg),
          child: Column(
            children: [
              _header(ui),
              Expanded(
                child: Center(
                  // Listens to both the wallet and ad readiness, so the
                  // reward on the button and whether it is drawn at all stay
                  // true without polling.
                  child: AnimatedBuilder(
                    animation: widget.wallet,
                    builder: (context, _) => ValueListenableBuilder<int>(
                      valueListenable: widget.ads.rewardedCoinsReady,
                      builder: (context, ready, _) => _body(ui, ready),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(UiScale ui) => Row(
    children: [
      IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back, color: Tokens.colorText),
      ),
      const Spacer(),
      CoinBalancePill(wallet: widget.wallet),
    ],
  );

  Widget _body(UiScale ui, int ready) {
    final wallet = widget.wallet;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          AppIcons.coin,
          width: ui.iconLg * 2.5,
          height: ui.iconLg * 2.5,
          colorFilter: const ColorFilter.mode(
            Tokens.colorGold,
            BlendMode.srcIn,
          ),
        ),
        SizedBox(height: ui.spaceMd),
        Text(
          _lastReward == null ? 'Coin Vault' : '+${_lastReward!}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: Tokens.fontDisplay,
            fontSize: ui.fontXl,
            fontWeight: FontWeight.w700,
            color: _lastReward == null ? Tokens.colorText : Tokens.colorGold,
          ),
        ),
        SizedBox(height: ui.spaceSm),
        Text(
          _subtitle(ready),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: Tokens.fontBody,
            fontSize: ui.fontSm,
            color: Tokens.colorTextMuted,
          ),
        ),
        SizedBox(height: ui.spaceXl),
        // Rule 4 of `boosters.md` §4.9, applied to the faucet: with nothing
        // in hand there is no button, because an armed button that cannot
        // deliver is worse than an honest empty state.
        if (ready > 0 && !_watching)
          PrimaryButton(
            label: _lastReward == null
                ? 'Watch  +${wallet.nextAdReward}'
                : 'Watch next  +${wallet.nextAdReward}',
            onPressed: _watch,
          )
        else if (_watching)
          Text(
            'Opening…',
            style: TextStyle(
              fontFamily: Tokens.fontBody,
              fontSize: ui.fontSm,
              color: Tokens.colorTextMuted,
            ),
          ),
      ],
    );
  }

  String _subtitle(int ready) {
    if (ready == 0) {
      return 'No videos available right now.\n'
          'Daily challenges and the login streak still pay Coins.';
    }
    if (widget.wallet.nextAdHasStreakBonus) {
      return 'Next one lands a +${EconomyTuning.streakBonus} streak bonus.';
    }
    return 'Watch a short video, keep the Coins.\n'
        'Every ${EconomyTuning.streakBonusEvery} in a row pays a bonus.';
  }
}
