import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/boosters/booster_type.dart';
import '../../game/config/economy_tuning.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/economy.dart';
import '../../services/mystery_chest.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/coin_balance_pill.dart';
import '../widgets/panel.dart';
import '../widgets/primary_button.dart';
import '../widgets/purchase_prompt.dart';
import 'themes_screen.dart';

/// Port of `screens/shop.html`, rebased from dollars to Coins.
///
/// Everything here is bought with Coins and Coins come only from rewarded
/// video, so the mockup's coin packs, Starter Pack and $2.99 Remove Ads are
/// gone. In their place: a way to *earn* at the top, and Clear Skies — timed
/// ad-free play — where Remove Ads used to be.
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, required this.ads, required this.economy});

  final AdsService ads;
  final Economy economy;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(ui.spaceMd),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Tokens.colorText),
                  ),
                  Text('Shop', style: _title(ui)),
                  const Spacer(),
                  CoinBalancePill(
                    wallet: economy.wallet,
                    onTap: () => openCoinVault(
                      context,
                      ads: ads,
                      wallet: economy.wallet,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: economy.wallet,
                builder: (context, _) => ListView(
                  padding: EdgeInsets.fromLTRB(
                    ui.spaceLg,
                    0,
                    ui.spaceLg,
                    ui.spaceXl,
                  ),
                  children: [
                    _EarnCard(ads: ads, economy: economy),
                    _section(ui, 'Clear Skies'),
                    _ClearSkiesCard(ads: ads, economy: economy),
                    _section(ui, 'Boosters'),
                    for (final slot in BoosterSlot.values) ...[
                      for (final type in BoosterType.pool(slot))
                        _BoosterRow(type: type, ads: ads, economy: economy),
                    ],
                    _section(ui, 'Mystery Chest'),
                    _ChestCard(ads: ads, economy: economy),
                    _section(ui, 'Themes'),
                    _ThemesLink(ads: ads, economy: economy),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _section(UiScale ui, String text) => Padding(
    padding: EdgeInsets.only(top: ui.spaceLg, bottom: ui.spaceSm),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: Tokens.fontBody,
        fontSize: ui.fontXs,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Tokens.colorTextMuted,
      ),
    ),
  );
}

TextStyle _title(UiScale ui) => TextStyle(
  fontFamily: Tokens.fontDisplay,
  fontSize: ui.fontLg,
  fontWeight: FontWeight.w700,
  color: Tokens.colorText,
);

TextStyle _body(UiScale ui, {bool muted = false}) => TextStyle(
  fontFamily: Tokens.fontBody,
  fontSize: ui.fontSm,
  color: muted ? Tokens.colorTextMuted : Tokens.colorText,
);

Widget _coinIcon(double size) => SvgPicture.asset(
  AppIcons.coin,
  width: size,
  height: size,
  colorFilter: const ColorFilter.mode(Tokens.colorGold, BlendMode.srcIn),
);

/// A small gold "price" button.
class _PriceButton extends StatelessWidget {
  const _PriceButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: _coinIcon(ui.iconSm),
      label: Text(
        label,
        style: _body(ui).copyWith(fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Tokens.colorGold),
        padding: EdgeInsets.symmetric(horizontal: ui.spaceSm),
        minimumSize: Size(0, ui.tap),
      ),
    );
  }
}

class _EarnCard extends StatelessWidget {
  const _EarnCard({required this.ads, required this.economy});

  final AdsService ads;
  final Economy economy;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return AppPanel(
      child: Column(
        children: [
          _coinIcon(ui.iconLg * 2),
          SizedBox(height: ui.spaceSm),
          Text('Get Coins', style: _title(ui)),
          SizedBox(height: ui.spaceXs),
          Text(
            'Watch short videos — '
            '${EconomyTuning.coinsPerAdFullRate} Coins each. '
            'Everything in the game is free to earn.',
            textAlign: TextAlign.center,
            style: _body(ui, muted: true),
          ),
          SizedBox(height: ui.spaceMd),
          PrimaryButton(
            label: 'Earn Coins',
            onPressed: () =>
                openCoinVault(context, ads: ads, wallet: economy.wallet),
          ),
        ],
      ),
    );
  }
}

class _ClearSkiesCard extends StatelessWidget {
  const _ClearSkiesCard({required this.ads, required this.economy});

  final AdsService ads;
  final Economy economy;

  static String _span(Duration d) =>
      d.inHours >= 1 ? '${d.inHours} h' : '${d.inMinutes} min';

  static String _left(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  Future<void> _buy(BuildContext context, ClearSkiesTier tier) async {
    final ok = await confirmPurchase(
      context,
      title: 'Clear Skies — ${_span(tier.gameTime)}',
      message:
          'No interruptions between runs for ${_span(tier.gameTime)} of '
          'play. The clock only runs while you are playing.',
      price: tier.price,
      wallet: economy.wallet,
      ads: ads,
    );
    if (!ok || !await economy.wallet.trySpend(tier.price)) return;
    await economy.clearSkies.grant(tier.gameTime);
    AnalyticsService.design('shop:clear_skies:${tier.gameTime.inMinutes}');
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                AppIcons.soundOff,
                width: ui.iconMd,
                height: ui.iconMd,
                colorFilter: const ColorFilter.mode(
                  Tokens.colorText,
                  BlendMode.srcIn,
                ),
              ),
              SizedBox(width: ui.spaceSm),
              Expanded(
                child: ValueListenableBuilder<Duration>(
                  valueListenable: economy.clearSkies.remaining,
                  builder: (context, left, _) => Text(
                    left > Duration.zero
                        ? 'Active — ${_left(left)} of play left'
                        : 'No ads between runs',
                    style: _body(ui).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ui.spaceXs),
          // Said plainly, because the thing it does not do is the thing that
          // keeps the whole economy running.
          Text(
            'Only counts down while a run is live. Videos for Coins stay '
            'available whenever you want them.',
            style: _body(ui, muted: true),
          ),
          SizedBox(height: ui.spaceMd),
          Wrap(
            spacing: ui.spaceSm,
            runSpacing: ui.spaceSm,
            children: [
              for (final tier in EconomyTuning.clearSkiesTiers)
                _PriceButton(
                  label: '${_span(tier.gameTime)} · ${tier.price}',
                  onTap: () => _buy(context, tier),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoosterRow extends StatelessWidget {
  const _BoosterRow({
    required this.type,
    required this.ads,
    required this.economy,
  });

  final BoosterType type;
  final AdsService ads;
  final Economy economy;

  Future<void> _buy(BuildContext context, int count) async {
    final bundle = count == EconomyTuning.chargeBundleSize;
    final price = bundle
        ? EconomyTuning.chargeBundlePrice(type.slot)
        : EconomyTuning.chargePrice(type.slot);
    final ok = await confirmPurchase(
      context,
      title: '${type.displayName} x$count',
      message:
          'Recharges a spent ${type.displayName} mid-run, whenever it rolls '
          'into your loadout.',
      price: price,
      wallet: economy.wallet,
      ads: ads,
    );
    if (!ok) return;
    if (await economy.wallet.buyCharges(type, count: count)) {
      AnalyticsService.design('shop:booster:${type.name}:$count');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final held = economy.wallet.chargesOf(type);
    return Padding(
      padding: EdgeInsets.only(bottom: ui.spaceSm),
      child: AppPanel(
        padding: EdgeInsets.all(ui.spaceSm),
        child: Row(
          children: [
            SvgPicture.asset(
              type.icon,
              width: ui.iconLg,
              height: ui.iconLg,
              colorFilter: const ColorFilter.mode(
                Tokens.colorGold,
                BlendMode.srcIn,
              ),
            ),
            SizedBox(width: ui.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.displayName,
                    style: _body(ui).copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    held > 0 ? '$held held' : type.tip,
                    style: _body(ui, muted: true).copyWith(fontSize: ui.fontXs),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _PriceButton(
              label: '${EconomyTuning.chargePrice(type.slot)}',
              onTap: () => _buy(context, 1),
            ),
            SizedBox(width: ui.spaceXs),
            _PriceButton(
              label:
                  'x${EconomyTuning.chargeBundleSize} '
                  '${EconomyTuning.chargeBundlePrice(type.slot)}',
              onTap: () => _buy(context, EconomyTuning.chargeBundleSize),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChestCard extends StatelessWidget {
  const _ChestCard({required this.ads, required this.economy});

  final AdsService ads;
  final Economy economy;

  Future<void> _open(BuildContext context) async {
    final ok = await confirmPurchase(
      context,
      title: 'Mystery Chest',
      message:
          'Coins, booster charges, or — rarely — a theme you do not own yet. '
          'Every ${EconomyTuning.chestPityEvery}th chest is never just Coins.',
      price: EconomyTuning.mysteryChestPrice,
      wallet: economy.wallet,
      ads: ads,
    );
    if (!ok) return;
    final reward = await economy.chest.buyAndOpen();
    if (reward == null || !context.mounted) return;
    AnalyticsService.design('shop:chest');
    await showChestReward(context, reward);
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return AppPanel(
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: Tokens.colorGold,
            size: ui.iconLg * 1.5,
          ),
          SizedBox(width: ui.spaceMd),
          Expanded(
            child: Text(
              'Coins, charges or a theme',
              style: _body(ui, muted: true),
            ),
          ),
          _PriceButton(
            label: '${EconomyTuning.mysteryChestPrice}',
            onTap: () => _open(context),
          ),
        ],
      ),
    );
  }
}

/// The reveal after a chest opens, shared with the day-7 login reward.
Future<void> showChestReward(BuildContext context, ChestReward reward) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final ui = context.scale;
        return AlertDialog(
          backgroundColor: Tokens.colorBg,
          title: Text(
            'Mystery Chest',
            style: _title(ui),
            textAlign: TextAlign.center,
          ),
          content: Text(
            reward.label,
            textAlign: TextAlign.center,
            style: _title(ui).copyWith(color: Tokens.colorGold),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Nice', style: _body(ui)),
            ),
          ],
        );
      },
    );

class _ThemesLink extends StatelessWidget {
  const _ThemesLink({required this.ads, required this.economy});

  final AdsService ads;
  final Economy economy;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ThemesScreen(ads: ads, economy: economy),
        ),
      ),
      child: AppPanel(
        child: Row(
          children: [
            SvgPicture.asset(
              AppIcons.palette,
              width: ui.iconLg,
              height: ui.iconLg,
              colorFilter: const ColorFilter.mode(
                Tokens.colorText,
                BlendMode.srcIn,
              ),
            ),
            SizedBox(width: ui.spaceSm),
            Expanded(child: Text('Browse all themes', style: _body(ui))),
            SvgPicture.asset(
              AppIcons.chevronRight,
              width: ui.iconSm,
              height: ui.iconSm,
              colorFilter: const ColorFilter.mode(
                Tokens.colorTextMuted,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
