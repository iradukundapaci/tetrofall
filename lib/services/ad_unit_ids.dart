import 'package:flutter/foundation.dart';

abstract final class AdUnitIds {
  static const rewardedContinue = kReleaseMode
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
