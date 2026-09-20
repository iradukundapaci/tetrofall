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

  /// Drops any pending retry and forgets the accumulated wait. Called on a
  /// successful load and whenever conditions change for the better.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _delay = _first;
  }

  /// Drops the pending retry but keeps the accumulated wait — for going into
  /// the background, where the retry would only fail again.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }
}

class AdsService {
  /// [connectivity] is optional so tests can build a service that never
  /// touches a platform channel; when it is absent the network is assumed to
  /// be up and this class behaves as it did before it was connectivity-aware.
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

  /// Whether ads may be personalised, as the player last left it in Settings.
  /// Read straight from storage so it is right on the very first request of a
  /// cold start, before [init] has finished talking to UMP.
  bool get personalizedAds => _personalizedAds;
  late bool _personalizedAds = _storage.personalizedAdsEnabled;

  /// The request every format goes out with, so one switch covers all four.
  ///
  /// Off sends `npa=1`, which forces non-personalised ads no matter what else
  /// the SDK knows. On leaves the field *null* rather than false — false is
  /// not "personalise this", it is only the absence of the restriction, and
  /// leaving it unset is what keeps the UMP consent answer authoritative in
  /// the regions that have one.
  AdRequest get adRequest =>
      AdRequest(nonPersonalizedAds: _personalizedAds ? null : true);

  /// Bumped whenever what an ad request *means* changes — the personalisation
  /// switch, or a trip through the consent form. The banner is the one format
  /// that can already be on screen when that happens, so it listens here and
  /// replaces itself; the rest are re-fetched from cache before they're shown.
  ValueListenable<int> get adConfigRevision => _adConfigRevision;
  final ValueNotifier<int> _adConfigRevision = ValueNotifier(0);

  /// Bumped whenever something changes that makes a *previously failed* load
  /// worth attempting again — the network coming back, the app being resumed,
  /// consent finally resolving after a start with no internet.
  ///
  /// Deliberately separate from [adConfigRevision]: that one means "drop what
  /// you are holding, it is stale", this one means "try again if you are
  /// holding nothing". A slot that already has an ad ignores this.
  ValueListenable<int> get adRetryPulse => _adRetryPulse;
  final ValueNotifier<int> _adRetryPulse = ValueNotifier(0);

  /// Whether UMP says this user must be given a way back to their consent
  /// choice — true in the EEA/UK, and in US states whose messages you have
  /// published. Settings shows its Privacy row only when this is true, because
  /// outside those jurisdictions there is no form to present and the row would
  /// be a button that does nothing.
  bool get privacyOptionsRequired => _privacyOptionsRequired;
  bool _privacyOptionsRequired = false;

  /// Guards the SDK handshake, which must happen exactly once, from the paths
  /// that reach startup again later — consent or personalisation changing from
  /// Settings, or a retry after a start with no network.
  bool _adsStarted = false;

  /// Whether UMP has actually *answered*, as opposed to having been asked and
  /// failed. Without this a network error is indistinguishable from a refusal,
  /// which is what used to strand a cold start made offline: consent looked
  /// settled and denied, so nothing ever asked again.
  bool _consentResolved = false;

  AppLifecycleListener? _lifecycle;

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
  /// Height an anchored adaptive banner takes on a device that has never
  /// measured one, following AdMob's own anchored rule — 32 / 50 / 90 by
  /// screen height, capped at 15% of it.
  ///
  /// Worth having rather than reserving a flat [fallbackBannerHeight]
  /// everywhere: on a 360x640 phone the real banner is 50pt, so the flat 100
  /// over-reserved by half a slot, and that 50pt came straight off the
  /// board's height — and, through its 9:16 aspect, off its width.
  static double estimateBannerHeight(double screenHeight) {
    final tier = screenHeight <= 400
        ? 32.0
        : screenHeight <= 720
        ? 50.0
        : 90.0;
    return math.min(tier, screenHeight * 0.15);
  }

  double reservedBannerHeight(int width, {double? screenHeight}) {
    final measured = _bannerSizeWidth == width ? _bannerSize : null;
    return measured?.height.toDouble() ??
        _storage.bannerAdHeightForWidth(width)?.toDouble() ??
        (screenHeight == null
            ? fallbackBannerHeight
            : estimateBannerHeight(screenHeight));
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
    if (size == null) {
      // Not cached: a null here is a failure to measure, not an answer, and
      // caching it would leave the banner permanently unable to size itself
      // for this width no matter how many times the slot retried.
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

  /// Completes once the first startup attempt has been *made* — not once it
  /// has succeeded. Callers await this to know that consent has been asked
  /// about; an attempt made with no network completes here having resolved
  /// nothing, and the retry paths take it from there. Blocking until ads
  /// actually work would hang the banner and Settings for the whole time a
  /// player is offline.
  Future<void> init() => _readyFuture ??= _init();

  Future<void> _init() async {
    // Registered unconditionally and before the first attempt: this used to
    // live behind the consent gate, so the one start that most needed a second
    // chance — the one where consent never resolved — was also the one with no
    // lifecycle hook to trigger it.
    _lifecycle = AppLifecycleListener(onStateChange: _onAppLifecycleStateChange);
    _connectivity?.isOnline.addListener(_onOnlineChanged);
    await _attemptStart();
  }

  bool get _isOnline => _connectivity?.isOnline.value ?? true;

  /// True while a startup attempt is running, so the three things that can
  /// trigger one — boot, the network returning, a resume — can't overlap into
  /// two consent requests at once.
  bool _starting = false;

  /// The single entry point for "get ads going, from wherever we are".
  ///
  /// Idempotent and safe to call repeatedly: consent is only re-requested if
  /// it never resolved, the SDK is only started once, and the loaders no-op
  /// on formats that are already stocked or already in flight.
  Future<void> _attemptStart() async {
    if (_starting) return;
    // Nothing here can succeed without a network, and failing now would only
    // burn a request. The [_onOnlineChanged] listener calls back the moment
    // that changes.
    if (!_isOnline) return;

    _starting = true;
    try {
      if (!_consentResolved) await _requestConsent();
      await _startAdsIfAllowed();
    } finally {
      _starting = false;
    }
  }

  /// Device IDs that UMP should treat as if they were in [_debugGeography].
  ///
  /// Without this the consent form only appears to someone physically in a
  /// regulated region, so the accept path — and the withdraw path behind
  /// Settings → Privacy Settings — cannot be exercised from anywhere else.
  /// Run the app once and copy the hashed ID the UMP SDK logs
  /// ("Use new ConsentDebugSettings.Builder().addTestDeviceHashedId(...)")
  /// in here. Empty means debug settings are inert, which is why this is safe
  /// to leave as it ships; it is compiled out of release builds regardless.
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
      // Only the success branch counts as an answer. A form that then fails to
      // load is a separate, non-fatal problem: the consent *information* is in
      // hand either way, which is what the rest of this class needs.
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

    // Consent arriving late is the one moment Settings and the banner cannot
    // observe for themselves — Settings has already drawn its Privacy rows
    // from the old answer, and the banner has already given up.
    if (_canRequestAds != wasAllowed) _adRetryPulse.value++;

    _publishConsent();
  }

  /// Hands the answer UMP just gave to GA4 consent mode.
  ///
  /// Firebase defaults every ad signal to denied (see the
  /// `google_analytics_default_allow_*` entries in AndroidManifest.xml and
  /// Info.plist), so this is the only thing that ever grants them — which
  /// makes it, in turn, what lets a Google Ads App campaign attribute an
  /// install. Called from both places the answer can change: here, and from
  /// [setPersonalizedAds].
  ///
  /// Unawaited on purpose. Nothing in the ad path waits on analytics, and
  /// [FirebaseAnalyticsService.setConsent] swallows its own failures.
  void _publishConsent() => unawaited(
    FirebaseAnalyticsService.setConsent(
      adsAllowed: _canRequestAds,
      personalized: _personalizedAds,
    ),
  );

  /// Idempotent: safe to call at boot and again after a consent change.
  ///
  /// The SDK is only started once, but the caches are refilled every time —
  /// a player who withdraws consent and then grants it again in the same
  /// session had every cached ad dropped in between, and would otherwise sit
  /// out the rest of the session with empty slots. The loaders below no-op
  /// on the formats that are already stocked.
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
        // Deliberately leaves [_adsStarted] false. This flag used to be set
        // before the await, so a handshake that failed could never be tried
        // again; the retry paths now come back to it.
        return;
      }
      _adsStarted = true;
    }

    _loadRewarded();
    _loadInterstitial();
    _loadAppOpen();
  }

  /// Prints each mediation adapter's state after the SDK handshake. A
  /// `notReady` here is almost always a wrong placement ID in the AdMob
  /// console or an adapter missing from `android/app/build.gradle.kts`, and
  /// this is the first place to look when a network never serves.
  static void _logAdapterStatuses(InitializationStatus status) {
    if (kReleaseMode) return;
    status.adapterStatuses.forEach((name, adapter) {
      debugPrint(
        '[Ads] $name: ${adapter.state.name}'
        '${adapter.description.isEmpty ? '' : ' — ${adapter.description}'}',
      );
    });
  }

  /// The network came back, or went away.
  void _onOnlineChanged() {
    if (!_isOnline) {
      // Every pending retry would fail. Hold them rather than spend them.
      _rewardedRetry.pause();
      _interstitialRetry.pause();
      _appOpenRetry.pause();
      return;
    }
    _retryNow();
  }

  /// Conditions just improved: forget the accumulated backoff, try startup
  /// again if it never completed, refill anything empty, and tell the slots
  /// that own their own loads (the banner) to do the same.
  void _retryNow() {
    _rewardedRetry.reset();
    _interstitialRetry.reset();
    _appOpenRetry.reset();
    _adRetryPulse.value++;
    unawaited(_attemptStart());
  }

  /// Re-presents the UMP privacy options form so a user can change or withdraw
  /// the consent they gave at first launch — a requirement under GDPR and
  /// several US state laws, and the reason Settings has a Privacy row.
  ///
  /// Whatever the player does in there, the ads in hand were fetched under the
  /// answer they just replaced, so they are dropped either way. If consent is
  /// granted here by someone who declined at boot, ads start for the first
  /// time this session; if it is withdrawn, `canRequestAds` flips false and
  /// every load path stops until it is granted again.
  Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((_) {});
    await _refreshConsentState();

    // Bumped unconditionally, and before the reload: the form can change
    // *which* purposes are consented to without changing whether ads may be
    // requested at all, and that still makes every ad in hand — and every one
    // mid-flight — one fetched under the old answer.
    _adConfigRevision.value++;
    _discardCachedAds();
    if (_canRequestAds) await _startAdsIfAllowed();
  }

  /// Turns ad personalisation on or off, from the Settings switch.
  ///
  /// This is the control that exists everywhere. In the regions UMP covers it
  /// sits *behind* the consent form and can only narrow what that form
  /// allowed; everywhere else it is the only say the player gets, which is
  /// why it isn't hidden outside the EEA the way the Privacy row is.
  Future<void> setPersonalizedAds(bool value) async {
    if (value == _personalizedAds) return;
    _personalizedAds = value;
    await _storage.savePersonalizedAdsEnabled(value);
    _publishConsent();

    // Every cached ad was fetched under the previous answer, so showing one
    // now would be a personalised ad served after the switch went off. Bump
    // first — that invalidates the loads already in flight as well — then drop
    // what's cached and refill under the new request.
    _adConfigRevision.value++;
    _discardCachedAds();
    _rewardedRetry.reset();
    _interstitialRetry.reset();
    _appOpenRetry.reset();
    _loadRewarded();
    _loadInterstitial();
    _loadAppOpen();
  }

  /// Drops every ad in hand, because the answer it was fetched under is no
  /// longer the current one — consent withdrawn, consent re-stated, or the
  /// personalisation switch flipped. Callers bump [adConfigRevision] alongside
  /// this, which is what stops an in-flight load from refilling the slots with
  /// ads from the same stale answer, and what tells the banner to replace the
  /// one it is already showing.
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

  /// Whether an ad requested at [revision] is still one this app is allowed to
  /// show: consent must still permit ads, and nothing may have changed what a
  /// request means since it went out. A load that fails this was fetched under
  /// an answer the player has since replaced, so it is dropped rather than
  /// cached — the whole point of the personalisation switch is that it applies
  /// to the next ad, not the one after the queue drains.
  bool _isCurrent(int revision) =>
      _canRequestAds && revision == _adConfigRevision.value;

  final _rewardedRetry = _AdRetry();

  /// Non-null while a load is in flight, holding the revision it went out
  /// under. Doubles as the guard against a second overlapping load, which
  /// would strand the first ad undisposed when the later one overwrote it.
  int? _rewardedLoadRevision;

  void _loadRewarded() {
    // Reachable from the ad-dismissed callbacks and from both consent paths,
    // so it has to re-check consent rather than assume the boot-time answer
    // still holds.
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
            // The change that stranded this one found the slot in flight and
            // couldn't refill it, so that job lands here.
            _loadRewarded();
            return;
          }
          _rewarded = ad;
        },
        onAdFailedToLoad: (error) {
          _reportNoFill(AdPlacements.rewardedContinue, AdKind.rewardedVideo, error);
          _rewardedLoadRevision = null;
          _rewarded = null;
          // Without this the slot is dead for the session: the only other
          // path back into this method is a dismissal callback, and there is
          // no ad to dismiss.
          _rewardedRetry.schedule(_loadRewarded);
        },
      ),
    );
  }

  /// Shows the continue ad and reports whether the reward was earned, but
  /// only once the ad has actually left the screen. The reward callback
  /// fires while the ad is still up (often several seconds before the user
  /// can close it), and the caller resumes the run on this future — so
  /// completing early would play the board wipe behind the ad.
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
    // Reachable from the ad-dismissed callbacks too, so it has to
    // re-check consent rather than assume the boot-time answer holds.
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
          _reportNoFill(AdPlacements.interstitial, AdKind.interstitial, error);
          _interstitialLoadRevision = null;
          _interstitialAd = null;
          _interstitialRetry.schedule(_loadInterstitial);
        },
      ),
    );
  }

  /// Shows the cached interstitial, returning a future that completes once it
  /// has left the screen — or null, having shown nothing, when there is no
  /// ad in hand or one was on screen too recently.
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

  /// Counts a finished run toward the interstitial cadence, and shows one
  /// when the cadence is due. Completes once any interstitial it showed has
  /// been dismissed, so a caller about to start a new run can wait for it —
  /// otherwise the run would start ticking behind the ad.
  ///
  /// The counters reset only when an ad is actually shown. A cadence that
  /// comes due with nothing loaded stays due, and the next run-end gets it.
  ///
  /// There is no per-session grace run: the counters persist across cold
  /// starts, so a player coming back with the cap nearly reached is shown one
  /// on their first run-end, as they would have been had they never left. The
  /// one exception is straight after a rewarded continue — an interstitial on
  /// the heels of an ad the player chose to watch is the fastest way to teach
  /// them not to.
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
    // Reachable from the ad-dismissed callbacks too, so it has to
    // re-check consent rather than assume the boot-time answer holds.
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
          _reportNoFill(AdPlacements.appOpen, AdKind.interstitial, error);
          _appOpenLoadRevision = null;
          _appOpenAd = null;
          _appOpenRetry.schedule(_loadAppOpen);
        },
      ),
    );
  }

  void _onAppLifecycleStateChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // On Android a full-screen ad is its own activity, so showing one — or
      // following a tap on one out to the browser — backgrounds the app just
      // as leaving does. Neither is the player leaving, and counting them
      // would greet the end of every rewarded video with an app-open ad.
      final lastClick = _lastAdClickAt;
      final leftForAd =
          _fullScreenAdShowing.value ||
          (lastClick != null &&
              DateTime.now().difference(lastClick) < _adClickGrace);
      _backgroundedAt = leftForAd ? null : DateTime.now();
      // Nothing requested from the background can be shown, and the network
      // may well be asleep with the device.
      _rewardedRetry.pause();
      _interstitialRetry.pause();
      _appOpenRetry.pause();
    } else if (state == AppLifecycleState.resumed) {
      dropExpiredAds();
      _maybeShowAppOpenAd();
      _backgroundedAt = null;
      // The likeliest moment for the network to have changed while nothing
      // was watching — and the one chance to recover a session that started
      // with no internet if the connectivity stream missed the transition.
      _connectivity?.refresh();
      _retryNow();
    }
  }

  void _maybeShowAppOpenAd() {
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt == null) return;
    // A player still in their first session — tutorial not yet finished — is
    // exactly the one an early ad is most likely to lose.
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
      // GameAnalytics has no app-open type; Interstitial is the closest fit,
      // and the placement keeps the two apart on the dashboard.
      kind: AdKind.interstitial,
      placement: AdPlacements.appOpen,
    );
    ad.show();
    _storage.saveLastAppOpenAdShownAt(DateTime.now());
  }

  /// Whether ad diagnostics are printed: debug and profile builds only.
  static const _diagnostics = !kReleaseMode;

  /// Prints why a load failed, network by network.
  ///
  /// The top-level error only says "no fill". The reason lives in the
  /// response info: one entry per ad source AdMob tried, each with the
  /// adapter's own error code and message — for Meta, 101-111 are the
  /// adapter's (bad placement ID, SDK failed to initialise, ...) and
  /// 1000-9999 are Meta's own (see Meta's error checklist). Used by the
  /// banner slot too, which owns its own load.
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

  /// Reports a failed load as a GameAnalytics `FailedShow` with a reason, so
  /// no-fill (an inventory problem) is separable from being offline (not one).
  ///
  /// AdMob's numeric codes are not documented as a stable enum, so this maps
  /// only the two that change what you would do about them and lets the rest
  /// fall through to `unknown` rather than guessing.
  static void _reportNoFill(String placement, AdKind kind, LoadAdError error) {
    logLoadFailure(placement, error);
    AnalyticsService.ad(
      outcome: AdOutcome.failed,
      kind: kind,
      placement: placement,
      reason: switch (error.code) {
        2 => AdFailure.internalError,
        3 => AdFailure.noFill,
        _ => AdFailure.unknown,
      },
    );
  }

  /// The app holds one of these for its whole life, so this exists for tests —
  /// which would otherwise leave retry timers running past the end of a case.
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
