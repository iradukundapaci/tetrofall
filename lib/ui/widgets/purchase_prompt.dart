import 'package:flutter/material.dart';

import '../../services/ads_service.dart';
import '../../services/wallet_service.dart';
import '../screens/coin_vault_screen.dart';
import 'booster_coin_sheet.dart';

/// Opens the earn screen and comes back.
Future<void> openCoinVault(
  BuildContext context, {
  required AdsService ads,
  required WalletService wallet,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CoinVaultScreen(ads: ads, wallet: wallet),
  ),
);

/// Asks before spending, using the same sheet as the in-run booster
/// purchases so every checkout in the game looks and behaves the same.
///
/// Returns true when the player confirmed *and* can afford [price] — the
/// caller does the spending. When they are short, the sheet's primary button
/// becomes "Earn Coins"; the sheet stays open underneath the earn screen and
/// redraws against the new balance when they come back, so a player can top
/// up and finish the purchase without starting it over.
Future<bool> confirmPurchase(
  BuildContext context, {
  required String title,
  required String message,
  required int price,
  required WalletService wallet,
  required AdsService ads,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    pageBuilder: (dialogContext, _, _) => AnimatedBuilder(
      animation: wallet,
      builder: (_, _) => Stack(
        children: [
          BoosterCoinSheet(
            title: title,
            message: message,
            price: price,
            balance: wallet.coins,
            onSpend: () => Navigator.of(dialogContext).pop(true),
            onEarn: () =>
                openCoinVault(dialogContext, ads: ads, wallet: wallet),
            onDecline: () => Navigator.of(dialogContext).pop(false),
          ),
        ],
      ),
    ),
  );
  return (result ?? false) && wallet.canAfford(price);
}
