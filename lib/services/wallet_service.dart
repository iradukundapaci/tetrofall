import 'package:flutter/foundation.dart';

import '../game/boosters/booster_type.dart';
import '../game/config/economy_tuning.dart';
import '../models/theme_definition.dart';
import 'storage_service.dart';

/// The player's Coins and booster-charge inventory.
///
/// Coins are the game's only currency and rewarded video is their only faucet
/// — there is no IAP. Everything buyable goes through [trySpend], and every
/// "watch an ad for X" prompt the game used to show has become "spend Coins on
/// X", with the ad moved out to [creditAdView] on the earn screen.
///
/// A [ChangeNotifier] because balance and inventory are read by widgets all
/// over the app (the same choice `BoosterRunState` makes); the codebase has no
/// DI framework, so this is built in `main()` and passed down.
class WalletService extends ChangeNotifier {
  WalletService(this._storage) {
    _coins = _storage.coinBalance;
    _charges = _decodeCharges(_storage.boosterCharges);
    _viewsToday = _storage.adViewsToday;
    _viewsDayEpoch = _storage.adViewsDayEpoch;
    _ownedThemes = {
      ...?_storage.ownedThemes?.split(',').where((id) => id.isNotEmpty),
    };
  }

  final StorageService _storage;

  late int _coins;
  late Map<BoosterType, int> _charges;
  late int _viewsToday;
  late int _viewsDayEpoch;
  late Set<String> _ownedThemes;

  /// Consecutive rewarded views in this sitting, for the streak bonus. Held in
  /// memory on purpose: a "sitting" ends when the app does, and persisting it
  /// would let someone bank four views today and collect the bonus tomorrow.
  int _viewStreak = 0;

  int get coins => _coins;

  int chargesOf(BoosterType type) => _charges[type] ?? 0;

  /// Total charges held across all boosters — what a shop badge shows.
  int get totalCharges => _charges.values.fold(0, (a, b) => a + b);

  // --- Earning ------------------------------------------------------------

  /// What the *next* rewarded view will pay, bonus included. Shown on the earn
  /// button so the offer is never a surprise.
  int get nextAdReward {
    final views = _viewsTodayAfterRollover;
    var reward = _rateFor(views);
    if ((_viewStreak + 1) % EconomyTuning.streakBonusEvery == 0) {
      reward += EconomyTuning.streakBonus;
    }
    return reward;
  }

  /// Whether the next view lands a streak bonus, so the button can say so.
  bool get nextAdHasStreakBonus =>
      (_viewStreak + 1) % EconomyTuning.streakBonusEvery == 0;

  /// Credits one completed rewarded view and returns what it paid.
  ///
  /// Call this only after the SDK has confirmed the reward — never on the
  /// attempt.
  Future<int> creditAdView() async {
    _rolloverIfNewDay();
    final reward = nextAdReward;
    _viewsToday += 1;
    _viewStreak += 1;
    _coins += reward;
    await _storage.setAdViewsToday(_viewsToday);
    await _storage.setCoinBalance(_coins);
    notifyListeners();
    return reward;
  }

  /// Breaks the consecutive-view run. Called when the player leaves the earn
  /// screen, so the bonus rewards a genuine sitting rather than a view they
  /// come back for hours later.
  void resetViewStreak() {
    _viewStreak = 0;
  }

  /// Coins from somewhere other than an ad — a daily challenge, the login
  /// calendar, a chest.
  Future<void> earn(int amount) async {
    if (amount <= 0) return;
    _coins += amount;
    await _storage.setCoinBalance(_coins);
    notifyListeners();
  }

  /// Pays the one-off first-launch grant, so a new player can open the shop
  /// and see what Coins are for before being asked to watch anything.
  Future<void> grantStarterIfNeeded() async {
    if (_storage.starterGrantGiven) return;
    await _storage.setStarterGrantGiven(true);
    await earn(EconomyTuning.starterGrant);
  }

  int get _viewsTodayAfterRollover =>
      _dayEpochNow() == _viewsDayEpoch ? _viewsToday : 0;

  int _rateFor(int viewsAlreadyToday) {
    if (viewsAlreadyToday < EconomyTuning.fullRateViewsPerDay) {
      return EconomyTuning.coinsPerAdFullRate;
    }
    if (viewsAlreadyToday < EconomyTuning.taperedViewsPerDay) {
      return EconomyTuning.coinsPerAdTaperedRate;
    }
    return EconomyTuning.coinsPerAdFloorRate;
  }

  void _rolloverIfNewDay() {
    final today = _dayEpochNow();
    if (today == _viewsDayEpoch) return;
    _viewsDayEpoch = today;
    _viewsToday = 0;
    _storage.setAdViewsDayEpoch(today);
    _storage.setAdViewsToday(0);
  }

  static int _dayEpochNow() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  // --- Spending -----------------------------------------------------------

  bool canAfford(int price) => _coins >= price;

  /// Deducts [price] if the player can afford it. Returns false and changes
  /// nothing otherwise, which is the caller's cue to offer the earn screen
  /// rather than a dead end.
  Future<bool> trySpend(int price) async {
    if (price <= 0 || _coins < price) return false;
    _coins -= price;
    await _storage.setCoinBalance(_coins);
    notifyListeners();
    return true;
  }

  /// Buys [count] charges of [type] at its slot's price.
  Future<bool> buyCharges(BoosterType type, {int count = 1}) async {
    final price = count == EconomyTuning.chargeBundleSize
        ? EconomyTuning.chargeBundlePrice(type.slot)
        : EconomyTuning.chargePrice(type.slot) * count;
    if (!await trySpend(price)) return false;
    await grantCharges(type, count: count);
    return true;
  }

  /// Adds charges without spending — daily rewards and chests.
  Future<void> grantCharges(BoosterType type, {int count = 1}) async {
    if (count <= 0) return;
    _charges[type] = chargesOf(type) + count;
    await _persistCharges();
    notifyListeners();
  }

  /// Spends one held charge of [type]. Returns false if the player has none.
  Future<bool> consumeCharge(BoosterType type) async {
    final held = chargesOf(type);
    if (held <= 0) return false;
    if (held == 1) {
      _charges.remove(type);
    } else {
      _charges[type] = held - 1;
    }
    await _persistCharges();
    notifyListeners();
    return true;
  }

  // --- Themes -------------------------------------------------------------

  bool ownsTheme(ThemeDefinition theme) =>
      theme.price == 0 || _ownedThemes.contains(theme.id);

  /// Unknown or unowned ids fall back to the free default, so a stale or
  /// hand-edited value can never leave the board unthemed.
  ThemeDefinition get equippedTheme {
    final theme = ThemeDefinition.byId(_storage.equippedTheme);
    return ownsTheme(theme) ? theme : ThemeDefinition.classicWood;
  }

  Future<bool> buyTheme(ThemeDefinition theme) async {
    if (ownsTheme(theme)) return true;
    if (!await trySpend(theme.price)) return false;
    await grantTheme(theme);
    return true;
  }

  /// Unlocks without spending — a chest roll.
  Future<void> grantTheme(ThemeDefinition theme) async {
    if (ownsTheme(theme)) return;
    _ownedThemes.add(theme.id);
    await _storage.setOwnedThemes(_ownedThemes.join(','));
    notifyListeners();
  }

  Future<void> equipTheme(ThemeDefinition theme) async {
    if (!ownsTheme(theme)) return;
    await _storage.setEquippedTheme(theme.id);
    notifyListeners();
  }

  Future<void> _persistCharges() =>
      _storage.setBoosterCharges(_encodeCharges(_charges));

  // --- Encoding -----------------------------------------------------------

  /// "hammer:2,drill:1" — the same comma style as the stored loadout. Unknown
  /// ids and unparseable counts are dropped rather than thrown on, so a
  /// corrupted value costs the player their charges but never a crash loop.
  static Map<BoosterType, int> _decodeCharges(String? encoded) {
    final out = <BoosterType, int>{};
    if (encoded == null || encoded.isEmpty) return out;
    for (final entry in encoded.split(',')) {
      final parts = entry.split(':');
      if (parts.length != 2) continue;
      final type = BoosterType.byId(parts[0]);
      final count = int.tryParse(parts[1]);
      if (type == null || count == null || count <= 0) continue;
      out[type] = count;
    }
    return out;
  }

  static String _encodeCharges(Map<BoosterType, int> charges) => charges.entries
      .where((e) => e.value > 0)
      .map((e) => '${e.key.name}:${e.value}')
      .join(',');
}
