import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_unit_ids.dart';
import 'analytics_service.dart';
import 'connectivity_service.dart';
import 'firebase_analytics_service.dart';
import 'storage_service.dart';

class _AdRetry {
  static const _first = Duration(seconds: 4);
  static const _max = Duration(seconds: 60);

  Timer? _timer;
  Duration _delay = _first;

  void schedule(void Function() run) {
    if (_timer != null) return;
    final delay = _delay;
    _delay = delay * 2 > _max ? _max : delay * 2;
    _timer = Timer(delay, () {
      _timer = null;
      run();
    });
  }

  /// Drops any pending retry and the accumulated wait.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _delay = _first;
  }

  /// Drops the pending retry but keeps the wait; for the background, where it
  /// would only fail.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }
}

class AdsService {
  /// Without [connectivity] (tests) the network is assumed to be up.
  AdsService(this._storage, {ConnectivityService? connectivity})
    : _connectivity = connectivity;

  static const _interstitialRunCap = 2;
  static const _interstitialPlaySecondsCap = 3 * 60;
  static const _appOpenMinBackgroundDuration = Duration(seconds: 30);
  static const _appOpenMinInterval = Duration(minutes: 15);
  static const _fullScreenAdGap = Duration(seconds: 60);
  static const _interstitialTtl = Duration(minutes: 55);
  static const _rewardedTtl = Duration(minutes: 55);
  static const _appOpenTtl = Duration(hours: 3, minutes: 55);
  static const _adClickGrace = Duration(seconds: 10);
  static const _testDeviceIds = <String>[];

  final StorageService _storage;
  final ConnectivityService? _connectivity;

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;
  AppOpenAd? _appOpenAd;
  DateTime? _rewardedLoadedAt;
  DateTime? _interstitialLoadedAt;
  DateTime? _appOpenLoadedAt;
  DateTime? _lastFullScreenAdEndedAt;
  DateTime? _lastAdClickAt;

  bool _canRequestAds = false;
  bool _justWatchedRewardedContinue = false;
  DateTime? _backgroundedAt;

  bool get isRewardedContinueReady => _rewardedAd != null;
  ValueListenable<bool> get rewardedContinueReady => _rewardedContinueReady;
  final ValueNotifier<bool> _rewardedContinueReady = ValueNotifier(false);
  set _rewarded(RewardedAd? ad) {
    _rewardedAd = ad;
    _rewardedLoadedAt = ad == null ? null : DateTime.now();
    _rewardedContinueReady.value = ad != null;
  }

  ValueListenable<bool> get fullScreenAdShowing => _fullScreenAdShowing;
  final ValueNotifier<bool> _fullScreenAdShowing = ValueNotifier(false);

  void _fullScreenAdStarted() => _fullScreenAdShowing.value = true;

  void _fullScreenAdEnded() {
    _fullScreenAdShowing.value = false;
    _lastFullScreenAdEndedAt = DateTime.now();
  }

  bool get _tooSoonAfterFullScreenAd {
    if (_fullScreenAdShowing.value) return true;
    final last = _lastFullScreenAdEndedAt;
    return last != null && DateTime.now().difference(last) < _fullScreenAdGap;
  }

  void notifyAdClicked() => _lastAdClickAt = DateTime.now();

  static bool _isExpired(DateTime? loadedAt, Duration ttl) =>
      loadedAt != null && DateTime.now().difference(loadedAt) > ttl;
  void dropExpiredAds() {
    if (_isExpired(_rewardedLoadedAt, _rewardedTtl)) {
      _rewardedAd?.dispose();
      _rewarded = null;
      _loadRewarded();
    }
    if (_isExpired(_interstitialLoadedAt, _interstitialTtl)) {
      _interstitialAd?.dispose();
      _interstitialAd = null;
      _interstitialLoadedAt = null;
      _loadInterstitial();
    }
    if (_isExpired(_appOpenLoadedAt, _appOpenTtl)) {
      _appOpenAd?.dispose();
      _appOpenAd = null;
      _appOpenLoadedAt = null;
      _loadAppOpen();
    }
  }

  bool get canRequestAds => _canRequestAds;

  /// Whether ads may be personalised, read from storage so it's right before
  /// [init] finishes talking to UMP.
  bool get personalizedAds => _personalizedAds;
  late bool _personalizedAds = _storage.personalizedAdsEnabled;

  /// The request every format goes out with. Off sends `npa=1`; on leaves the
  /// field null (not false) so the UMP consent answer stays authoritative.
  AdRequest get adRequest =>
      AdRequest(nonPersonalizedAds: _personalizedAds ? null : true);

  /// Bumped when what an ad request means changes (personalisation switch,
  /// consent form). The banner listens and replaces itself.
  ValueListenable<int> get adConfigRevision => _adConfigRevision;
  final ValueNotifier<int> _adConfigRevision = ValueNotifier(0);

  /// Bumped when a failed load is worth retrying (network back, app resumed,
  /// consent resolved late). Unlike [adConfigRevision] ("drop what you hold")
  /// this means "try again if you hold nothing".
  ValueListenable<int> get adRetryPulse => _adRetryPulse;
  final ValueNotifier<int> _adRetryPulse = ValueNotifier(0);

  /// Whether UMP requires offering a way back to the consent choice (EEA/UK
  /// and some US states); Settings shows its Privacy row only then.
  bool get privacyOptionsRequired => _privacyOptionsRequired;
  bool _privacyOptionsRequired = false;

  /// Guards the SDK handshake, which must happen once, from paths that reach
  /// startup again.
  bool _adsStarted = false;

  /// Whether UMP actually answered, so a network error isn't mistaken for a
  /// refusal and never retried.
  bool _consentResolved = false;

  AppLifecycleListener? _lifecycle;

  /// Banner slot height when this device has never measured one: the
  /// large-anchored ceiling, so a measurement can only shrink it.
  static const fallbackBannerHeight = 100.0;

  AdSize? _bannerSize;
  int? _bannerSizeWidth;
  Future<AdSize?>? _bannerSizeFuture;

  /// AdMob's anchored banner rule for a device that has never measured one:
  /// 32 / 50 / 90 by screen height, capped at 15% of it. Beats a flat
  /// [fallbackBannerHeight], whose over-reserve comes straight off the board.
  static double estimateBannerHeight(double screenHeight) {
    final tier = screenHeight <= 400
        ? 32.0
        : screenHeight <= 720
        ? 50.0
        : 90.0;
    return math.min(tier, screenHeight * 0.15);
  }

  /// Height gameplay reserves for the banner whether or not an ad ever loads,
  /// so play-area size doesn't depend on fill: this session's measurement,
  /// then the stored one, then an estimate.
  double reservedBannerHeight(int width, {double? screenHeight}) {
    final measured = _bannerSizeWidth == width ? _bannerSize : null;
    return measured?.height.toDouble() ??
        _storage.bannerAdHeightForWidth(width)?.toDouble() ??
        (screenHeight == null
            ? fallbackBannerHeight
            : estimateBannerHeight(screenHeight));
  }

  /// Measures the adaptive banner size for a screen [width] once per width and
  /// stores the height for future cold starts. Safe before consent resolves.
  Future<AdSize?> resolveBannerSize(int width) {
    if (_bannerSizeWidth != width) {
      _bannerSizeWidth = width;
      _bannerSizeFuture = _resolveBannerSize(width);
    }
    return _bannerSizeFuture!;
  }

  Future<AdSize?> _resolveBannerSize(int width) async {
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null) {
      // A failure to measure, not an answer; don't cache it.
      if (_bannerSizeWidth == width) {
        _bannerSizeWidth = null;
        _bannerSizeFuture = null;
      }
      return null;
    }
    _bannerSize = size;
    await _storage.saveBannerAdSize(width: width, height: size.height);
    return size;
  }

  Future<void>? _readyFuture;

  /// Completes once the first startup attempt has been made, not once it
  /// succeeded; blocking until ads work would hang the banner and Settings
  /// while offline. The retry paths take over from there.
  Future<void> init() => _readyFuture ??= _init();

  Future<void> _init() async {
    // Registered before the first attempt so an unresolved start can retry.
    _lifecycle = AppLifecycleListener(onStateChange: _onAppLifecycleStateChange);
    _connectivity?.isOnline.addListener(_onOnlineChanged);
    await _attemptStart();
  }

  bool get _isOnline => _connectivity?.isOnline.value ?? true;

  /// True while a startup attempt runs, so boot, network-return and resume
  /// can't overlap into two consent requests.
  bool _starting = false;

  /// The single entry point for getting ads going. Idempotent: consent is only
  /// re-requested if unresolved, the SDK starts once, and loaders no-op on
  /// stocked or in-flight formats.
  Future<void> _attemptStart() async {
    if (_starting) return;
    // [_onOnlineChanged] calls back when the network returns.
    if (!_isOnline) return;

    _starting = true;
    try {
      if (!_consentResolved) await _requestConsent();
      await _startAdsIfAllowed();
    } finally {
      _starting = false;
    }
  }

  /// Device IDs UMP treats as being in [_debugGeography], to exercise the
  /// consent form outside a regulated region: copy the hashed ID the UMP SDK
  /// logs. Empty is inert, and release builds ignore it.
  static const _debugTestDeviceIds = <String>[];

  static const _debugGeography = DebugGeography.debugGeographyEea;

  ConsentDebugSettings? get _debugConsentSettings =>
      kReleaseMode || _debugTestDeviceIds.isEmpty
      ? null
      : ConsentDebugSettings(
          debugGeography: _debugGeography,
          testIdentifiers: _debugTestDeviceIds,
        );

  Future<void> _requestConsent() async {
    final completer = Completer<void>();
    void proceed({required bool resolved}) {
      // Only success counts as an answer; a form that fails to load is
      // non-fatal since the consent information is in hand.
      if (resolved) _consentResolved = true;
      if (!completer.isCompleted) completer.complete();
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(consentDebugSettings: _debugConsentSettings),
      () => ConsentForm.loadAndShowConsentFormIfRequired(
        (_) => proceed(resolved: true),
      ),
      (_) => proceed(resolved: false),
    );
    await completer.future;
    await _refreshConsentState();
  }

  Future<void> _refreshConsentState() async {
    final wasAllowed = _canRequestAds;
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    _privacyOptionsRequired =
        await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;

    // Settings and the banner can't observe late consent themselves.
    if (_canRequestAds != wasAllowed) _adRetryPulse.value++;

    _publishConsent();
  }

  /// Hands UMP's answer to GA4 consent mode. Firebase defaults every ad signal
  /// to denied (see `google_analytics_default_allow_*` in the manifest), so
  /// this is the only thing that grants them, which lets Google Ads attribute
  /// installs. Unawaited: nothing in the ad path waits on analytics.
  void _publishConsent() => unawaited(
    FirebaseAnalyticsService.setConsent(
      adsAllowed: _canRequestAds,
      personalized: _personalizedAds,
    ),
  );

  /// Idempotent. The SDK starts once but caches are refilled every time, so a
  /// player who withdraws then re-grants consent isn't left with empty slots.
  Future<void> _startAdsIfAllowed() async {
    if (!_canRequestAds) return;

    if (!_adsStarted) {
      try {
        if (_testDeviceIds.isNotEmpty) {
          await MobileAds.instance.updateRequestConfiguration(
            RequestConfiguration(testDeviceIds: _testDeviceIds),
          );
        }
        final status = await MobileAds.instance.initialize();
        _logAdapterStatuses(status);
      } catch (_) {
        // Leaves [_adsStarted] false so a retry can try again.
        return;
      }
      _adsStarted = true;
    }

    _loadRewarded();
    _loadInterstitial();
    _loadAppOpen();
  }

  /// Prints each mediation adapter's state after the handshake. `notReady` is
  /// usually a wrong placement ID or an adapter missing from
  /// `android/app/build.gradle.kts`.
  static void _logAdapterStatuses(InitializationStatus status) {
    if (kReleaseMode) return;
    status.adapterStatuses.forEach((name, adapter) {
      debugPrint(
        '[Ads] $name: ${adapter.state.name}'
        '${adapter.description.isEmpty ? '' : ' — ${adapter.description}'}',
      );
    });
  }

  void _onOnlineChanged() {
    if (!_isOnline) {
      // Pending retries would fail; hold them.
      _rewardedRetry.pause();
      _interstitialRetry.pause();
      _appOpenRetry.pause();
      return;
    }
    _retryNow();
  }

  /// Conditions improved: reset backoff, retry startup if it never completed,
  /// refill empty slots and tell the banner to do the same.
  void _retryNow() {
    _rewardedRetry.reset();
    _interstitialRetry.reset();
    _appOpenRetry.reset();
    _adRetryPulse.value++;
    unawaited(_attemptStart());
  }

  /// Re-presents the UMP privacy options form so consent can be changed or
  /// withdrawn (GDPR and US state law). Ads in hand were fetched under the old
  /// answer, so they are dropped either way; granting starts ads, withdrawing
  /// stops every load path.
  Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((_) {});
    await _refreshConsentState();

    // Bumped unconditionally and before the reload: the form can change which
    // purposes are consented to without changing whether ads may be requested.
    _adConfigRevision.value++;
    _discardCachedAds();
    if (_canRequestAds) await _startAdsIfAllowed();
  }

  /// Turns personalisation on or off from the Settings switch. Behind UMP's
  /// form it can only narrow it; elsewhere it is the player's only say.
  Future<void> setPersonalizedAds(bool value) async {
    if (value == _personalizedAds) return;
    _personalizedAds = value;
    await _storage.savePersonalizedAdsEnabled(value);
    _publishConsent();

    // Cached ads were fetched under the previous answer. Bump first to
    // invalidate loads in flight, then drop and refill.
    _adConfigRevision.value++;
    _discardCachedAds();
    _rewardedRetry.reset();
    _interstitialRetry.reset();
    _appOpenRetry.reset();
    _loadRewarded();
    _loadInterstitial();
    _loadAppOpen();
  }

  /// Drops every ad in hand because its consent/personalisation answer is
  /// stale. Callers bump [adConfigRevision] alongside, which also stops
  /// in-flight loads refilling the slots.
  void _discardCachedAds() {
    _rewardedAd?.dispose();
    _rewarded = null;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _interstitialLoadedAt = null;
    _appOpenAd?.dispose();
    _appOpenAd = null;
    _appOpenLoadedAt = null;
  }

  /// Whether an ad requested at [revision] may still be shown: consent must
  /// still permit ads and nothing may have changed what a request means.
  bool _isCurrent(int revision) =>
      _canRequestAds && revision == _adConfigRevision.value;

  final _rewardedRetry = _AdRetry();

  /// Non-null while a load is in flight, holding its revision; also guards
  /// against an overlapping load stranding an undisposed ad.
  int? _rewardedLoadRevision;

  void _loadRewarded() {
    // Reachable from dismiss callbacks and consent paths, so re-check consent.
    if (!_canRequestAds ||
        _rewardedAd != null ||
        _rewardedLoadRevision != null) {
      return;
    }
    final revision = _adConfigRevision.value;
    _rewardedLoadRevision = revision;

    RewardedAd.load(
      adUnitId: AdUnitIds.rewardedContinue,
      request: adRequest,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoadRevision = null;
          _rewardedRetry.reset();
          if (!_isCurrent(revision)) {
            ad.dispose();
            // The change that stranded this ad couldn't refill the in-flight
            // slot, so refill here.
            _loadRewarded();
            return;
          }
          _rewarded = ad;
        },
        onAdFailedToLoad: (error) {
          reportLoadFailure(
            AdPlacements.rewardedContinue,
            AdKind.rewardedVideo,
            error,
          );
          _rewardedLoadRevision = null;
          _rewarded = null;
          // Otherwise the slot is dead: only dismissal callbacks reload.
          _rewardedRetry.schedule(_loadRewarded);
        },
      ),
    );
  }

  /// Shows the continue ad and reports whether the reward was earned, only
  /// once the ad has left the screen (the reward fires while it is still up,
  /// and the caller resumes the run on this future).
  Future<bool> showRewardedContinue() async {
    dropExpiredAds();
    final ad = _rewardedAd;
    if (ad == null) return false;
    _rewarded = null;

    var earned = false;
    final closed = Completer<bool>();
    _fullScreenAdStarted();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdClicked: (_) => notifyAdClicked(),
      onAdDismissedFullScreenContent: (ad) {
        _fullScreenAdEnded();
        ad.dispose();
        _loadRewarded();
        if (!closed.isCompleted) closed.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _fullScreenAdEnded();
        AnalyticsService.ad(
          outcome: AdOutcome.failed,
          kind: AdKind.rewardedVideo,
          placement: AdPlacements.rewardedContinue,
        );
        ad.dispose();
        _loadRewarded();
        if (!closed.isCompleted) closed.complete(false);
      },
    );
    AnalyticsService.ad(
      outcome: AdOutcome.shown,
      kind: AdKind.rewardedVideo,
      placement: AdPlacements.rewardedContinue,
    );
    ad.show(
      onUserEarnedReward: (_, _) {
        AnalyticsService.ad(
          outcome: AdOutcome.rewarded,
          kind: AdKind.rewardedVideo,
          placement: AdPlacements.rewardedContinue,
        );
        earned = true;
        _justWatchedRewardedContinue = true;
      },
    );
    return closed.future;
  }

  final _interstitialRetry = _AdRetry();
  int? _interstitialLoadRevision;

  void _loadInterstitial() {
    if (!_canRequestAds ||
        _interstitialAd != null ||
        _interstitialLoadRevision != null) {
      return;
    }
    final revision = _adConfigRevision.value;
    _interstitialLoadRevision = revision;

    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: adRequest,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoadRevision = null;
          _interstitialRetry.reset();
          if (!_isCurrent(revision)) {
            ad.dispose();
            _loadInterstitial();
            return;
          }
          _interstitialAd = ad;
          _interstitialLoadedAt = DateTime.now();
        },
        onAdFailedToLoad: (error) {
          reportLoadFailure(
            AdPlacements.interstitial,
            AdKind.interstitial,
            error,
          );
          _interstitialLoadRevision = null;
          _interstitialAd = null;
          _interstitialRetry.schedule(_loadInterstitial);
        },
      ),
    );
  }

  /// Shows the cached interstitial, returning a future that completes when it
  /// leaves the screen, or null if there is no ad or one ran too recently.
  Future<void>? _showInterstitial() {
    dropExpiredAds();
    final ad = _interstitialAd;
    if (ad == null || _tooSoonAfterFullScreenAd) return null;
    _interstitialAd = null;
    _interstitialLoadedAt = null;

    final closed = Completer<void>();
    _fullScreenAdStarted();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdClicked: (_) => notifyAdClicked(),
      onAdDismissedFullScreenContent: (ad) {
        _fullScreenAdEnded();
        ad.dispose();
        _loadInterstitial();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _fullScreenAdEnded();
        if (!closed.isCompleted) closed.complete();
        AnalyticsService.ad(
          outcome: AdOutcome.failed,
          kind: AdKind.interstitial,
          placement: AdPlacements.interstitial,
        );
        ad.dispose();
        _loadInterstitial();
      },
    );
    AnalyticsService.ad(
      outcome: AdOutcome.shown,
      kind: AdKind.interstitial,
      placement: AdPlacements.interstitial,
    );
    ad.show();
    return closed.future;
  }

  /// Counts a finished run toward the interstitial cadence and shows one when
  /// due, completing once it is dismissed so a new run doesn't tick behind it.
  /// Counters reset only when an ad is shown, so a due cadence with nothing
  /// loaded stays due. They persist across cold starts; the one exception is
  /// straight after a rewarded continue.
  Future<void> notifyRunEnded(Duration runDuration) async {
    final skipThisOne = _justWatchedRewardedContinue;
    _justWatchedRewardedContinue = false;

    final runs = _storage.runsSinceLastInterstitial + 1;
    final seconds =
        _storage.playSecondsSinceLastInterstitial + runDuration.inSeconds;

    final due =
        runs >= _interstitialRunCap || seconds >= _interstitialPlaySecondsCap;
    final shown = !skipThisOne && due ? _showInterstitial() : null;
    if (shown != null) {
      await _storage.saveRunsSinceLastInterstitial(0);
      await _storage.savePlaySecondsSinceLastInterstitial(0);
      await shown;
      return;
    }

    await _storage.saveRunsSinceLastInterstitial(runs);
    await _storage.savePlaySecondsSinceLastInterstitial(seconds);
  }

  final _appOpenRetry = _AdRetry();
  int? _appOpenLoadRevision;

  void _loadAppOpen() {
    if (!_canRequestAds ||
        _appOpenAd != null ||
        _appOpenLoadRevision != null) {
      return;
    }
    final revision = _adConfigRevision.value;
    _appOpenLoadRevision = revision;

    AppOpenAd.load(
      adUnitId: AdUnitIds.appOpen,
      request: adRequest,
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenLoadRevision = null;
          _appOpenRetry.reset();
          if (!_isCurrent(revision)) {
            ad.dispose();
            _loadAppOpen();
            return;
          }
          _appOpenAd = ad;
          _appOpenLoadedAt = DateTime.now();
        },
        onAdFailedToLoad: (error) {
          reportLoadFailure(AdPlacements.appOpen, AdKind.interstitial, error);
          _appOpenLoadRevision = null;
          _appOpenAd = null;
          _appOpenRetry.schedule(_loadAppOpen);
        },
      ),
    );
  }

  void _onAppLifecycleStateChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // On Android a full-screen ad (or a tap out to the browser) backgrounds
      // the app like leaving does; counting that would follow every rewarded
      // video with an app-open ad.
      final lastClick = _lastAdClickAt;
      final leftForAd =
          _fullScreenAdShowing.value ||
          (lastClick != null &&
              DateTime.now().difference(lastClick) < _adClickGrace);
      _backgroundedAt = leftForAd ? null : DateTime.now();
      // Nothing requested from the background can be shown.
      _rewardedRetry.pause();
      _interstitialRetry.pause();
      _appOpenRetry.pause();
    } else if (state == AppLifecycleState.resumed) {
      dropExpiredAds();
      _maybeShowAppOpenAd();
      _backgroundedAt = null;
      // The likeliest moment for the network to have changed, and a chance to
      // recover if the connectivity stream missed it.
      _connectivity?.refresh();
      _retryNow();
    }
  }

  void _maybeShowAppOpenAd() {
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt == null) return;
    // An early ad is most likely to lose a first-session player.
    if (!_storage.tutorialSeen) return;
    if (_tooSoonAfterFullScreenAd) return;
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
    _appOpenLoadedAt = null;
    _fullScreenAdStarted();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdClicked: (_) => notifyAdClicked(),
      onAdDismissedFullScreenContent: (ad) {
        _fullScreenAdEnded();
        ad.dispose();
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _fullScreenAdEnded();
        AnalyticsService.ad(
          outcome: AdOutcome.failed,
          kind: AdKind.interstitial,
          placement: AdPlacements.appOpen,
        );
        ad.dispose();
        _loadAppOpen();
      },
    );
    AnalyticsService.ad(
      outcome: AdOutcome.shown,
      // GameAnalytics has no app-open type; the placement tells them apart.
      kind: AdKind.interstitial,
      placement: AdPlacements.appOpen,
    );
    ad.show();
    _storage.saveLastAppOpenAdShownAt(DateTime.now());
  }

  static const _diagnostics = !kReleaseMode;

  /// Prints why a load failed, network by network: the top-level error only
  /// says "no fill", the reason is in the per-adapter response info.
  static void logLoadFailure(String placement, LoadAdError error) {
    if (!_diagnostics) return;
    debugPrint(
      '[Ads] $placement failed: code ${error.code} (${error.domain}) '
      '${error.message}',
    );
    final responses = error.responseInfo?.adapterResponses;
    if (responses == null || responses.isEmpty) {
      debugPrint('[Ads] $placement: no adapter responses');
      return;
    }
    for (final r in responses) {
      final e = r.adError;
      debugPrint(
        '[Ads] $placement <- ${r.adSourceName} (${r.adapterClassName}) '
        '${r.latencyMillis}ms '
        '${e == null ? 'no error' : 'ERROR ${e.code} (${e.domain}): ${e.message}'} '
        'mapping=${r.adUnitMapping}',
      );
    }
  }

  /// Reports a failed load as a GameAnalytics `FailedShow`, keeping no-fill
  /// (inventory) apart from being offline. Maps only the AdMob codes that
  /// change what you'd do about them: 0 internal, 2 network, 3 no fill.
  static void reportLoadFailure(
    String placement,
    AdKind kind,
    LoadAdError error,
  ) {
    logLoadFailure(placement, error);
    AnalyticsService.ad(
      outcome: AdOutcome.failed,
      kind: kind,
      placement: placement,
      reason: switch (error.code) {
        0 => AdFailure.internalError,
        2 => AdFailure.offline,
        3 => AdFailure.noFill,
        _ => AdFailure.unknown,
      },
    );
  }

  /// For tests, to stop retry timers outliving a case.
  void dispose() {
    _rewardedRetry.pause();
    _interstitialRetry.pause();
    _appOpenRetry.pause();
    _connectivity?.isOnline.removeListener(_onOnlineChanged);
    _lifecycle?.dispose();
    _lifecycle = null;
    _discardCachedAds();
    _adConfigRevision.dispose();
    _adRetryPulse.dispose();
    _rewardedContinueReady.dispose();
    _fullScreenAdShowing.dispose();
  }
}
