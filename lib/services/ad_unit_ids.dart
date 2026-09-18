import 'package:flutter/foundation.dart';

abstract final class AdUnitIds {
  /// The Coin faucet — the only rewarded placement. There used to be a
  /// second one for continuing after a loss; the continue is bought with Coins
  /// now, so this unit (the one that placement used) pays for everything.
  static const rewardedCoins = kReleaseMode
      ? 'ca-app-pub-5422471961828877/1955998895'
      : 'ca-app-pub-3940256099942544/5224354917';

  static const interstitial = kReleaseMode
      ? 'ca-app-pub-5422471961828877/8521407244'
      : 'ca-app-pub-3940256099942544/1033173712';

  static const appOpen = kReleaseMode
      ? 'ca-app-pub-5422471961828877/5088714688'
      : 'ca-app-pub-3940256099942544/9257395921';

  static const banner = kReleaseMode
      ? 'ca-app-pub-5422471961828877/7786196060'
      : 'ca-app-pub-3940256099942544/6300978111';
}

/// Stable names for the ad slots, reported to GameAnalytics instead of
/// the unit ids above.
///
/// Kept separate from [AdUnitIds] on purpose: a unit can be replaced, split
/// for an experiment, or swapped between test and release — and if the
/// dashboard were keyed on the id, that would silently start a brand new
/// series rather than continuing the old one.
abstract final class AdPlacements {
  static const rewardedCoins = 'rewarded_coins';
  static const interstitial = 'interstitial';
  static const appOpen = 'app_open';
  static const banner = 'banner';
}
