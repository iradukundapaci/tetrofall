import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

abstract final class AdUnitIds {
  static final _ios = Platform.isIOS;

  static final rewardedContinue = kReleaseMode
      ? (_ios
          ? 'ca-app-pub-5422471961828877/2158726568'
          : 'ca-app-pub-5422471961828877/1955998895')
      : (_ios
          ? 'ca-app-pub-3940256099942544/1712485313'
          : 'ca-app-pub-3940256099942544/5224354917');

  static final interstitial = kReleaseMode
      ? (_ios
          ? 'ca-app-pub-5422471961828877/2952933480'
          : 'ca-app-pub-5422471961828877/8521407244')
      : (_ios
          ? 'ca-app-pub-3940256099942544/4411468910'
          : 'ca-app-pub-3940256099942544/1033173712');
}

/// Stable slot names reported to GameAnalytics instead of unit ids, so
/// replacing a unit doesn't start a new dashboard series.
abstract final class AdPlacements {
  static const rewardedContinue = 'rewarded_continue';
  static const interstitial = 'interstitial';
}
