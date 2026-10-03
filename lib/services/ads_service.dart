import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_unit_ids.dart';
import 'analytics_service.dart';
import 'connectivity_service.dart';
import 'firebase_analytics_service.dart';
import 'remote_flags.dart';
import 'storage_service.dart';

class _AdRetry {
  static const _first = Duration(seconds: 4);
  static const _max = Duration(minutes: 5);

  /// Consecutive no-fills a dry slot retries on its own before going quiet.
  /// Past this, only a real demand event (run start, resume, network
  /// return) asks again — see `ad_request_waste_plan.md` Cause 1.
  static const _maxAttempts = 4;

  Timer? _timer;
  Duration _delay = _first;
  int _attempts = 0;

  /// Whether a retry is currently counting down; callers that aren't new
  /// information (see [AdsService._loadRewarded]'s `force`) check this
  /// before requesting on top of it.
  bool get isPending => _timer != null;

  void schedule(void Function() run) {
    if (_timer != null) return;
    if (_attempts >= _maxAttempts) return;
    _attempts++;
    final delay = _delay;
    _delay = delay * 2 > _max ? _max : delay * 2;
    _timer = Timer(delay, () {
      _timer = null;
      run();
    });
  }

  /// Drops any pending retry, the accumulated wait and the attempt count.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _delay = _first;
    _attempts = 0;
  }

  /// Drops the pending retry but keeps the wait and attempt count; for the
  /// background, where it would only fail.
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

  /// Owed-break arming only, not the cadence's play-seconds cap (that one is
  /// `RemoteFlags.interstitialPlaySecondsCap`): how long backgrounded before a
  /// return owes the next natural break an interstitial, and the floor
  /// between two such breaks (see [_maybeArmOwedBreak]).
  static const _owedBreakMinBackground = Duration(seconds: 30);

  /// Guardrail on top of [RemoteFlags.interstitialsPerSessionCap]: interstitial
  /// shows per calendar day, regardless of session.
  static const _interstitialDailyCap = 8;

  static const _fullScreenAdGap = Duration(seconds: 60);
  static const _interstitialTtl = Duration(minutes: 55);
  static const _rewardedTtl = Duration(minutes: 55);
  static const _adClickGrace = Duration(seconds: 10);
  static const _testDeviceIds = <String>[];

  final StorageService _storage;
  final ConnectivityService? _connectivity;

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;
  DateTime? _rewardedLoadedAt;
  DateTime? _interstitialLoadedAt;
  DateTime? _lastFullScreenAdEndedAt;
  DateTime? _lastAdClickAt;

  bool _canRequestAds = false;
  bool _justWatchedRewardedContinue = false;
  DateTime? _backgroundedAt;

  /// Set on an app return that qualifies for a break (see
  /// [_maybeArmOwedBreak]) and consumed by the next [notifyRunEnded] as a
  /// third "due" condition, alongside the run and play-seconds caps. Replaces
  /// the app-open ad: same moment, but it waits for the next natural break
  /// instead of showing on resume, and it shows the better-paid interstitial.
  bool _breakOwed = false;

  /// In-memory only: resets every cold start, which is the point of a
  /// *session* cap. The daily cap in [StorageService] is the one that
  /// survives a restart.
  int _interstitialsShownThisSession = 0;

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

  /// Disposes any ad past its TTL. [refill] re-requests the dropped slot —
  /// pass it from a real demand moment (about to show, or a run just ended);
  /// leave it false from a plain resume, where nothing is about to consume
  /// the ad and a re-request would only be speculative (see
  /// `ad_request_waste_plan.md` Cause 5).
  void dropExpiredAds({bool refill = false}) {
    if (_isExpired(_rewardedLoadedAt, _rewardedTtl)) {
      _rewardedAd?.dispose();
      _rewarded = null;
      if (refill) _loadRewarded();
    }
    if (_isExpired(_interstitialLoadedAt, _interstitialTtl)) {
      _interstitialAd?.dispose();
      _interstitialAd = null;
      _interstitialLoadedAt = null;
      if (refill) _loadInterstitial();
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
  /// consent form), so cached ads fetched under the old answer get dropped.
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

  Future<void>? _readyFuture;

  /// Completes once the first startup attempt has been made, not once it
  /// succeeded; blocking until ads work would hang Settings and the game-over
  /// screen while offline. The retry paths take over from there.
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

    // Settings and the game-over screen can't observe late consent themselves.
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

  /// Idempotent. The SDK starts once but caches are refilled on every call
  /// after the first, so a player who withdraws then re-grants consent isn't
  /// left with empty slots, and a resume or network return that finds a slot
  /// empty refills it.
  ///
  /// The *first* successful call never prefetches: that would request before
  /// any surface needs an ad (there is nothing to show at the home screen
  /// since the banner and app-open removal). [notifyRunStarted] covers the
  /// first real demand moment instead — see `ad_request_waste_plan.md`
  /// Cause 4.
  Future<void> _startAdsIfAllowed() async {
    if (!_canRequestAds) return;

    final isFirstStart = !_adsStarted;
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
    if (isFirstStart) return;

    _loadRewarded(force: true);
    _loadInterstitial(force: true);
  }

  /// Prefetches the two ads a run might end on: the rewarded continue
  /// (offered at every game over) and the interstitial (shown on cadence or
  /// an owed break). Both no-op if already held, in flight, or mid-backoff
  /// (a run start is a hint, not new information about fill — see
  /// `ad_request_waste_plan.md` Cause 2); called at run start on top of the
  /// dismiss-triggered reloads so a quick run doesn't reach game over before
  /// the previous show's reload has finished. This is also the first fetch
  /// of a session: [_startAdsIfAllowed] deliberately doesn't prefetch at app
  /// start.
  void notifyRunStarted() {
    _loadRewarded();
    _loadInterstitial();
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
      return;
    }
    _retryNow();
  }

  /// Floor between two backoff resets from this method, so a flapping
  /// connection or rapid resume/pause doesn't restart the ad retry ladder
  /// from 4 s on every blip (`ad_request_waste_plan.md` Cause 3). Consent and
  /// startup retries below are *not* gated by this — a network return still
  /// needs to keep asking UMP until it gets an answer.
  static const _adRetryResetGap = Duration(seconds: 60);
  DateTime? _lastAdRetryResetAt;

  /// Conditions improved: retry startup if it never completed, refill empty
  /// slots, and — no more often than [_adRetryResetGap] apart — reset the ad
  /// retry backoff.
  void _retryNow() {
    final now = DateTime.now();
    final last = _lastAdRetryResetAt;
    if (last == null || now.difference(last) >= _adRetryResetGap) {
      _lastAdRetryResetAt = now;
      _rewardedRetry.reset();
      _interstitialRetry.reset();
    }
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
    _loadRewarded();
    _loadInterstitial();
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
  }

  /// Whether an ad requested at [revision] may still be shown: consent must
  /// still permit ads and nothing may have changed what a request means.
  bool _isCurrent(int revision) =>
      _canRequestAds && revision == _adConfigRevision.value;

  final _rewardedRetry = _AdRetry();

  /// Non-null while a load is in flight, holding its revision; also guards
  /// against an overlapping load stranding an undisposed ad.
  int? _rewardedLoadRevision;

  /// [force] skips the "a retry is already counting down" guard — only
  /// warranted when something changed since the ladder was last scheduled
  /// (consent, network, a fresh app start). A routine demand hint like
  /// [notifyRunStarted] leaves it false, so it doesn't request on top of a
  /// backoff that's still waiting out the last no-fill.
  void _loadRewarded({bool force = false}) {
    // Reachable from dismiss callbacks and consent paths, so re-check consent.
    if (!_canRequestAds ||
        _rewardedAd != null ||
        _rewardedLoadRevision != null ||
        (!force && _rewardedRetry.isPending)) {
      return;
    }
    final revision = _adConfigRevision.value;
    _rewardedLoadRevision = revision;

    FirebaseAnalyticsService.logEvent('ad_requested', {
      'placement': AdPlacements.rewardedContinue,
    });
    RewardedAd.load(
      adUnitId: AdUnitIds.rewardedContinue,
      request: adRequest,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoadRevision = null;
          _rewardedRetry.reset();
          FirebaseAnalyticsService.logEvent('ad_loaded', {
            'placement': AdPlacements.rewardedContinue,
          });
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
    dropExpiredAds(refill: true);
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

  /// [force]: see [_loadRewarded]. Unlike the retry-pending guard, the
  /// session/day cap check below applies even when forced — a request that
  /// cannot be shown this session is never worth making.
  void _loadInterstitial({bool force = false}) {
    if (!_canRequestAds ||
        _interstitialAd != null ||
        _interstitialLoadRevision != null ||
        (!force && _interstitialRetry.isPending) ||
        !_underInterstitialCap) {
      return;
    }
    final revision = _adConfigRevision.value;
    _interstitialLoadRevision = revision;

    FirebaseAnalyticsService.logEvent('ad_requested', {
      'placement': AdPlacements.interstitial,
    });
    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: adRequest,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoadRevision = null;
          _interstitialRetry.reset();
          FirebaseAnalyticsService.logEvent('ad_loaded', {
            'placement': AdPlacements.interstitial,
          });
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

  /// Whether the session/day guardrail caps allow one more interstitial,
  /// independent of cadence due-ness. Checked only at show time, not at arm
  /// time, so an owed break or a due cadence that's capped simply waits.
  bool get _underInterstitialCap =>
      _interstitialsShownThisSession < RemoteFlags.interstitialsPerSessionCap &&
      _storage.interstitialsShownToday < _interstitialDailyCap;

  /// Shows the cached interstitial, returning a future that completes when it
  /// leaves the screen, or null if there is no ad, one ran too recently, or a
  /// guardrail cap is reached.
  Future<void>? _showInterstitial() {
    dropExpiredAds(refill: true);
    final ad = _interstitialAd;
    if (ad == null || _tooSoonAfterFullScreenAd || !_underInterstitialCap) {
      return null;
    }
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
    _interstitialsShownThisSession++;
    unawaited(_storage.saveInterstitialShownNow());
    AnalyticsService.ad(
      outcome: AdOutcome.shown,
      kind: AdKind.interstitial,
      placement: AdPlacements.interstitial,
    );
    ad.show();
    return closed.future;
  }

  /// Counts a finished run toward the interstitial cadence and shows one when
  /// due — by the cadence caps or an owed break (see [_maybeArmOwedBreak]) —
  /// completing once it is dismissed so a new run doesn't tick behind it.
  /// Counters reset only when an ad is shown, so a due cadence with nothing
  /// loaded (or capped, see [_underInterstitialCap]) stays due. They persist
  /// across cold starts; the one exception is straight after a rewarded
  /// continue.
  Future<void> notifyRunEnded(Duration runDuration) async {
    final skipThisOne = _justWatchedRewardedContinue;
    _justWatchedRewardedContinue = false;

    final runs = _storage.runsSinceLastInterstitial + 1;
    final seconds =
        _storage.playSecondsSinceLastInterstitial + runDuration.inSeconds;

    final due =
        runs >= _interstitialRunCap ||
        seconds >= RemoteFlags.interstitialPlaySecondsCap ||
        _breakOwed;
    final shown = !skipThisOne && due ? _showInterstitial() : null;
    if (shown != null) {
      await _storage.saveRunsSinceLastInterstitial(0);
      await _storage.savePlaySecondsSinceLastInterstitial(0);
      if (_breakOwed) {
        _breakOwed = false;
        await _storage.saveLastOwedBreakShownAt(DateTime.now());
      }
      await shown;
      return;
    }

    await _storage.saveRunsSinceLastInterstitial(runs);
    await _storage.savePlaySecondsSinceLastInterstitial(seconds);
  }

  void _onAppLifecycleStateChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // On Android a full-screen ad (or a tap out to the browser) backgrounds
      // the app like leaving does; counting that would follow every rewarded
      // video with an owed break.
      final lastClick = _lastAdClickAt;
      final leftForAd =
          _fullScreenAdShowing.value ||
          (lastClick != null &&
              DateTime.now().difference(lastClick) < _adClickGrace);
      _backgroundedAt = leftForAd ? null : DateTime.now();
      // Nothing requested from the background can be shown.
      _rewardedRetry.pause();
      _interstitialRetry.pause();
    } else if (state == AppLifecycleState.resumed) {
      // No refill: nothing here is about to consume an ad. The next run
      // start or show does the real fetch (Cause 5).
      dropExpiredAds();
      _maybeArmOwedBreak();
      _backgroundedAt = null;
      // The likeliest moment for the network to have changed, and a chance to
      // recover if the connectivity stream missed it.
      _connectivity?.refresh();
      _retryNow();
    }
  }

  /// Arms [_breakOwed] on a qualifying return from background: the app-open
  /// moment, without the app-open format. Nothing shows here — the next
  /// natural break (game over or quit, in [notifyRunEnded]) picks it up as a
  /// third "due" condition, so returning from background is never itself
  /// interrupted by an ad.
  void _maybeArmOwedBreak() {
    if (!RemoteFlags.owedBreakEnabled) return;
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt == null) return;
    // An early break is most likely to lose a first-session player.
    if (!_storage.tutorialSeen) return;
    if (DateTime.now().difference(backgroundedAt) < _owedBreakMinBackground) {
      return;
    }

    final lastShown = _storage.lastOwedBreakShownAt;
    if (lastShown != null &&
        DateTime.now().difference(lastShown) <
            RemoteFlags.owedBreakMinInterval) {
      return;
    }

    _breakOwed = true;
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
