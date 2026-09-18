import 'dart:math';

import '../game/boosters/booster_type.dart';
import '../game/config/economy_tuning.dart';
import '../models/theme_definition.dart';
import 'storage_service.dart';
import 'wallet_service.dart';

/// What one chest paid out. Exactly one of the three is set.
class ChestReward {
  const ChestReward.coins(int this.coins)
    : charge = null,
      chargeCount = 0,
      theme = null;
  const ChestReward.charges(BoosterType this.charge, this.chargeCount)
    : coins = null,
      theme = null;
  const ChestReward.theme(ThemeDefinition this.theme)
    : coins = null,
      charge = null,
      chargeCount = 0;

  final int? coins;
  final BoosterType? charge;
  final int chargeCount;
  final ThemeDefinition? theme;

  String get label {
    if (coins != null) return '$coins Coins';
    if (theme != null) return '${theme!.displayName} theme';
    return '${charge!.displayName} x$chargeCount';
  }
}

/// The Mystery Chest (the loot box): bought in the shop, or free on day 7 of
/// the login calendar.
///
/// Two rules keep it from feeling like a scam. It never rolls a theme the
/// player already owns — that outcome becomes Coins instead. And every
/// [EconomyTuning.chestPityEvery]th chest is guaranteed to be something other
/// than Coins, so it can never degrade into a slower way of buying Coins.
class MysteryChest {
  MysteryChest(this._storage, this._wallet, {Random? random})
    : _random = random ?? Random();

  final StorageService _storage;
  final WalletService _wallet;
  final Random _random;

  /// Weights out of 100. Themes are rare on purpose: a theme is worth more
  /// than the chest costs, so it has to be the jackpot, not the expectation.
  static const _coinWeight = 55;
  static const _chargeWeight = 40;
  // Remaining 5: an unowned theme.

  /// Pays for and opens a chest, or returns null if the player cannot afford
  /// one.
  Future<ChestReward?> buyAndOpen() async {
    if (!await _wallet.trySpend(EconomyTuning.mysteryChestPrice)) return null;
    return open();
  }

  /// Opens a chest that has already been paid for (or was given free).
  Future<ChestReward> open() async {
    final since = _storage.chestsSinceBonus + 1;
    final pity = since >= EconomyTuning.chestPityEvery;

    var roll = _random.nextInt(100);
    if (pity && roll < _coinWeight) {
      // Re-roll into the non-Coin part of the table.
      roll = _coinWeight + _random.nextInt(100 - _coinWeight);
    }

    final ChestReward reward;
    if (roll < _coinWeight) {
      reward = ChestReward.coins(_coinRoll());
    } else if (roll < _coinWeight + _chargeWeight) {
      reward = _chargeRoll();
    } else {
      final unowned = ThemeDefinition.all
          .where((t) => !_wallet.ownsTheme(t))
          .toList();
      reward = unowned.isEmpty
          // Nothing left to win — pay the top of the Coin range instead of a
          // duplicate.
          ? const ChestReward.coins(EconomyTuning.chestCoinsMax)
          : ChestReward.theme(unowned[_random.nextInt(unowned.length)]);
    }

    await _grant(reward);
    await _storage.setChestsSinceBonus(reward.coins == null ? 0 : since);
    return reward;
  }

  int _coinRoll() {
    const step = 50;
    const min = EconomyTuning.chestCoinsMin ~/ step;
    const max = EconomyTuning.chestCoinsMax ~/ step;
    return (min + _random.nextInt(max - min + 1)) * step;
  }

  ChestReward _chargeRoll() {
    final type = BoosterType.values[_random.nextInt(BoosterType.values.length)];
    // Bigger boosters come in smaller numbers, so a chest's value stays
    // roughly level whatever it lands on.
    final count = switch (type.slot) {
      BoosterSlot.small => 3,
      BoosterSlot.line => 2,
      BoosterSlot.area => 2,
      BoosterSlot.board => 1,
    };
    return ChestReward.charges(type, count);
  }

  Future<void> _grant(ChestReward reward) async {
    if (reward.coins != null) return _wallet.earn(reward.coins!);
    if (reward.theme != null) return _wallet.grantTheme(reward.theme!);
    return _wallet.grantCharges(reward.charge!, count: reward.chargeCount);
  }
}
