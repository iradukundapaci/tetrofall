import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_unit_ids.dart';
import 'connectivity_service.dart';
import 'storage_service.dart';

/// One retriable slot: the timer that will try a failed load again, and how
/// long it will wait before doing so.
///
/// Backoff rather than a fixed interval because most failures are one of two
/// things — no network, which can last minutes, or no fill, which is the ad
/// server saying "not right now" and should not be asked again immediately.
/// [reset] is the counterweight: the moment something changes that makes a
/// retry likely to succeed (the network returns, the app is resumed) the wait
/// collapses back to the first step instead of sitting out a full minute.
class _AdRetry {
  static const _first = Duration(seconds: 4);
  static const _max = Duration(seconds: 60);

  Timer? _timer;
  Duration _delay = _first;

  /// No-ops while a retry is already pending, so several failures in a row
  /// can't stack up into several timers racing to reload the same slot.
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

  static const _interstitialRunCap = 4;
  static const _interstitialPlaySecondsCap = 6 * 60;
  static const _appOpenMinBackgroundDuration = Duration(minutes: 5);
  static const _appOpenMinInterval = Duration(hours: 1);

  final StorageService _storage;
  final ConnectivityService? _connectivity;

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;
  AppOpenAd? _appOpenAd;

  bool _canRequestAds = false;
  bool _hasEndedARunThisSession = false;
  bool _justWatchedRewardedContinue = false;
  DateTime? _backgroundedAt;

  bool get isRewardedContinueReady => _rewardedAd != null;

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
  }

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
        await MobileAds.instance.initialize();
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
    _rewardedAd = null;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _appOpenAd?.dispose();
    _appOpenAd = null;
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
          _rewardedAd = ad;
        },
        onAdFailedToLoad: (_) {
          _rewardedLoadRevision = null;
          _rewardedAd = null;
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
    final ad = _rewardedAd;
    if (ad == null) return false;
    _rewardedAd = null;

    var earned = false;
    final closed = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!closed.isCompleted) closed.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadRewarded();
        if (!closed.isCompleted) closed.complete(false);
      },
    );
    ad.show(
      onUserEarnedReward: (_, _) {
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
        },
        onAdFailedToLoad: (_) {
          _interstitialLoadRevision = null;
          _interstitialAd = null;
          _interstitialRetry.schedule(_loadInterstitial);
        },
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
        },
        onAdFailedToLoad: (_) {
          _appOpenLoadRevision = null;
          _appOpenAd = null;
          _appOpenRetry.schedule(_loadAppOpen);
        },
      ),
    );
  }

  void _onAppLifecycleStateChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      // Nothing requested from the background can be shown, and the network
      // may well be asleep with the device.
      _rewardedRetry.pause();
      _interstitialRetry.pause();
      _appOpenRetry.pause();
    } else if (state == AppLifecycleState.resumed) {
      _maybeShowAppOpenAd();
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
  }
}
