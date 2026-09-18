import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/wallet_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'counter_pill.dart';

/// The Coin balance, live. Tapping it opens the earn screen wherever that
/// makes sense — the balance is the most natural place to ask "how do I get
/// more of these?".
class CoinBalancePill extends StatelessWidget {
  const CoinBalancePill({super.key, required this.wallet, this.onTap});

  final WalletService wallet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = AnimatedBuilder(
      animation: wallet,
      builder: (context, _) => CounterPill(
        icon: SvgPicture.asset(
          AppIcons.coin,
          colorFilter: const ColorFilter.mode(
            Tokens.colorGold,
            BlendMode.srcIn,
          ),
        ),
        value: '${wallet.coins}',
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: 'Coins: earn more',
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}
