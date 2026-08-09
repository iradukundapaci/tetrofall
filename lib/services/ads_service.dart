import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_unit_ids.dart';
import 'storage_service.dart';

class AdsService {
  AdsService(this._storage);

  static const _interstitialRunCap = 4;
  static const _interstitialPlaySecondsCap = 6 * 60;
  static const _appOpenMinBackgroundDuration = Duration(minutes: 5);
  static const _appOpenMinInterval = Duration(hours: 1);

  final StorageService _storage;

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;
  AppOpenAd? _appOpenAd;

  bool _canRequestAds = false;
  bool _hasEndedARunThisSession = false;
  bool _justWatchedRewardedContinue = false;
  DateTime? _backgroundedAt;

  bool get isRewardedContinueReady => _rewardedAd != null;

  bool get canRequestAds => _canRequestAds;

  /// Height the banner slot falls back to when this device has never
  /// measured an adaptive banner. Sized at the large-anchored ceiling so a
  /// later measurement can only shrink the slot, never overflow it.
  static const fallbackBannerHeight = 100.0;

  AdSize? _bannerSize;
  int? _bannerSizeWidth;
  Future<AdSize?>? _bannerSizeFuture;

  /// Height gameplay reserves at the bottom of the screen for the banner,
  /// whether or not an ad is (or ever will be) loaded there — so the play
  /// area's size doesn't depend on ad fill. Prefers the size measured this
  /// session, then the one this device measured previously.
  double reservedBannerHeight(int width) {
    final measured = _bannerSizeWidth == width ? _bannerSize : null;
    return measured?.height.toDouble() ??
        _storage.bannerAdHeightForWidth(width)?.toDouble() ??
        fallbackBannerHeight;
  }

  /// Measures the anchored-adaptive banner size for a screen [width] in
  /// logical pixels, once per width, and remembers the height for future
  /// cold starts. Safe to call before consent resolves — measuring a size
  /// doesn't request an ad.
  Future<AdSize?> resolveBannerSize(int width) {
    if (_bannerSizeWidth != width) {
      _bannerSizeWidth = width;
      _bannerSizeFuture = _resolveBannerSize(width);
    }
    return _bannerSizeFuture!;
  }

  Future<AdSize?> _resolveBannerSize(int width) async {
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null) return null;
    _bannerSize = size;
    await _storage.saveBannerAdSize(width: width, height: size.height);
    return size;
  }

  Future<void>? _readyFuture;

  Future<void> init() => _readyFuture ??= _init();

  Future<void> _init() async {
    await _requestConsent();
    if (!_canRequestAds) return;

    await MobileAds.instance.initialize();
    _loadRewarded();
    _loadInterstitial();
    _loadAppOpen();
    AppLifecycleListener(onStateChange: _onAppLifecycleStateChange);
  }

  Future<void> _requestConsent() async {
    final completer = Completer<void>();
    void proceed() {
      if (!completer.isCompleted) completer.complete();
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) => proceed()),
      (_) => proceed(),
    );
    await completer.future;
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: AdUnitIds.rewardedContinue,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (_) => _rewardedAd = null,
      ),
    );
  }

  Future<bool> showRewardedContinue() async {
    final ad = _rewardedAd;
    if (ad == null) return false;
    _rewardedAd = null;

    final result = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!result.isCompleted) result.complete(false);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadRewarded();
        if (!result.isCompleted) result.complete(false);
      },
    );
    ad.show(
      onUserEarnedReward: (_, _) {
        _justWatchedRewardedContinue = true;
        if (!result.isCompleted) result.complete(true);
      },
    );
    return result.future;
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (_) => _interstitialAd = null,
      ),
    );
  }
  void _showInterstitial() {
    final ad = _interstitialAd;
    if (ad == null) return;
    _interstitialAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    ad.show();
  }

  Future<void> notifyRunEnded(Duration runDuration) async {
    final skipThisOne =
        !_hasEndedARunThisSession || _justWatchedRewardedContinue;
    _hasEndedARunThisSession = true;
    _justWatchedRewardedContinue = false;

    final runs = _storage.runsSinceLastInterstitial + 1;
    final seconds =
        _storage.playSecondsSinceLastInterstitial + runDuration.inSeconds;

    if (!skipThisOne &&
        (runs >= _interstitialRunCap ||
            seconds >= _interstitialPlaySecondsCap)) {
      _showInterstitial();
      await _storage.saveRunsSinceLastInterstitial(0);
      await _storage.savePlaySecondsSinceLastInterstitial(0);
      return;
    }

    await _storage.saveRunsSinceLastInterstitial(runs);
    await _storage.savePlaySecondsSinceLastInterstitial(seconds);
  }

  void _loadAppOpen() {
    AppOpenAd.load(
      adUnitId: AdUnitIds.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) => _appOpenAd = ad,
        onAdFailedToLoad: (_) => _appOpenAd = null,
      ),
    );
  }
  void _onAppLifecycleStateChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _maybeShowAppOpenAd();
    }
  }
  void _maybeShowAppOpenAd() {
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt == null) return;
    if (DateTime.now().difference(backgroundedAt) <
        _appOpenMinBackgroundDuration) {
      return;
    }

    final lastShown = _storage.lastAppOpenAdShownAt;
    if (lastShown != null &&
        DateTime.now().difference(lastShown) < _appOpenMinInterval) {
      return;
    }

    final ad = _appOpenAd;
    if (ad == null) return;
    _appOpenAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadAppOpen();
      },
    );
    ad.show();
    _storage.saveLastAppOpenAdShownAt(DateTime.now());
  }
}
