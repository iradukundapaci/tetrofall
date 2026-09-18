import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/theme_definition.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/economy.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/coin_balance_pill.dart';
import '../widgets/purchase_prompt.dart';

/// Port of `screens/themes.html`: every theme, and what it takes to wear it.
///
/// A card is Equipped, Owned (tap to equip), or priced in Coins (tap to buy,
/// then it equips). The mockup's other themes — Space, Neon and the rest —
/// arrive once they have art; the registry is [ThemeDefinition.all].
class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key, required this.ads, required this.economy});

  final AdsService ads;
  final Economy economy;

  Future<void> _tap(BuildContext context, ThemeDefinition theme) async {
    final wallet = economy.wallet;
    if (!wallet.ownsTheme(theme)) {
      final ok = await confirmPurchase(
        context,
        title: '${theme.displayName} theme',
        message: 'Yours for good, and equipped straight away.',
        price: theme.price,
        wallet: wallet,
        ads: ads,
      );
      if (!ok || !await wallet.buyTheme(theme)) return;
      AnalyticsService.design('shop:theme:${theme.id}');
    }
    await wallet.equipTheme(theme);
  }

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
                  Text(
                    'Themes',
                    style: TextStyle(
                      fontFamily: Tokens.fontDisplay,
                      fontSize: ui.fontLg,
                      fontWeight: FontWeight.w700,
                      color: Tokens.colorText,
                    ),
                  ),
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
                builder: (context, _) => GridView.count(
                  crossAxisCount: 2,
                  padding: EdgeInsets.all(ui.spaceLg),
                  mainAxisSpacing: ui.spaceMd,
                  crossAxisSpacing: ui.spaceMd,
                  childAspectRatio: 0.8,
                  children: [
                    for (final theme in ThemeDefinition.all)
                      _ThemeCard(
                        theme: theme,
                        owned: economy.wallet.ownsTheme(theme),
                        equipped: economy.wallet.equippedTheme.id == theme.id,
                        onTap: () => _tap(context, theme),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.owned,
    required this.equipped,
    required this.onTap,
  });

  final ThemeDefinition theme;
  final bool owned;
  final bool equipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final label = Text(
      equipped ? 'Equipped' : (owned ? 'Equip' : '${theme.price}'),
      style: TextStyle(
        fontFamily: Tokens.fontBody,
        fontSize: ui.fontSm,
        fontWeight: FontWeight.w700,
        color: equipped ? Tokens.colorGold : Tokens.colorText,
      ),
    );
    return Semantics(
      button: true,
      label: '${theme.displayName} theme',
      child: GestureDetector(
        onTap: equipped ? null : onTap,
        child: Container(
          padding: EdgeInsets.all(ui.spaceSm),
          decoration: BoxDecoration(
            color: Tokens.colorPanel,
            borderRadius: BorderRadius.circular(ui.radiusMd),
            border: Border.all(
              color: equipped ? Tokens.colorGold : Tokens.colorPanelBorder,
              width: equipped ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Expanded(child: _Swatch(theme: theme)),
              SizedBox(height: ui.spaceSm),
              Text(
                theme.displayName,
                style: TextStyle(
                  fontFamily: Tokens.fontDisplay,
                  fontSize: ui.fontMd,
                  fontWeight: FontWeight.w700,
                  color: Tokens.colorText,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!owned) ...[
                    SvgPicture.asset(
                      AppIcons.coin,
                      width: ui.iconSm,
                      height: ui.iconSm,
                      colorFilter: const ColorFilter.mode(
                        Tokens.colorGold,
                        BlendMode.srcIn,
                      ),
                    ),
                    SizedBox(width: ui.spaceXs),
                  ],
                  label,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Six blocks on the theme's board, tinted exactly the way `TileCache` tints
/// them — `BlendMode.color` over the tile — so the preview is the real look.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.theme});

  final ThemeDefinition theme;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Container(
      padding: EdgeInsets.all(ui.spaceXs),
      decoration: BoxDecoration(
        color: theme.boardBg,
        borderRadius: BorderRadius.circular(ui.radiusSm),
        border: Border.all(color: theme.frameLight, width: 2),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (var i = 0; i < 6; i++)
            // Clipped first, as `TileCache` does: `BlendMode.color` is
            // non-separable and would otherwise paint the tint into the
            // tile's transparent corners.
            ClipRRect(
              borderRadius: BorderRadius.circular(ui.radiusSm / 2),
              child: Image.asset(
                theme.baseTileAsset,
                color: theme.blockTint,
                colorBlendMode: BlendMode.color,
              ),
            ),
        ],
      ),
    );
  }
}
