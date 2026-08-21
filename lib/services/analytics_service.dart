import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gameanalytics_sdk/gameanalytics.dart';

import 'analytics_keys.dart';

/// Reports what an analytics call could not do, without ever letting it reach
/// the player. Mirrors `logAudioFailure` — deliberately not a bare `catch (_)`,
/// so a channel that has started throwing on every event is visible in debug
/// instead of silently reporting nothing for a whole release.
void logAnalyticsFailure(String what, Object error) {
  if (kDebugMode) {
    debugPrint('[analytics] $what failed: $error');
  }
}

/// GameAnalytics, wrapped so the rest of the app never touches the SDK.
///
/// Static rather than an injected instance, for the same reason [AudioService]
/// and [MusicService] are: there is exactly one analytics stream per process,
/// and the call sites that need it — a Flame render component, a pure-Dart
/// tracker, an ad callback buried in a listener closure — have no constructor
/// to thread a handle through.
///
/// Every method is a no-op until [init] has resolved, and every one of them
/// swallows its own failures. Nothing in here is allowed to change what the
/// game does; analytics that crashes the app it is measuring is worse than no
/// analytics at all.
abstract final class AnalyticsService {
  static Future<void>? _initFuture;
  static bool _ready = false;

  /// Whether events are actually going anywhere. False in tests, on desktop,
  /// and in any build where [AnalyticsKeys] were left blank.
  static bool get isReady => _ready;

  /// Safe to call more than once; only the first call does anything.
  ///
  /// Completes when the initialisation *attempt* is over, not when the SDK has
  /// reached the network — the same contract as [AdsService.init].
  static Future<void> init() => _initFuture ??= _init();

  static Future<void> _init() async {
    if (!AnalyticsKeys.configured) return;
    // The plugin only registers a method channel on Android and iOS. Under
    // `flutter test` there is no channel at all, and every call would throw
    // MissingPluginException — so don't make them.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await GameAnalytics.setEnabledInfoLog(kDebugMode);
      // Both dimension vocabularies must be declared before `initialize`;
      // GameAnalytics drops any value that isn't in the list it was given.
      await GameAnalytics.configureAvailableCustomDimensions01(const [
        adaptiveOn,
        adaptiveOff,
      ]);
      await GameAnalytics.configureAvailableCustomDimensions02(const [
        tutorialNew,
        tutorialSeen,
      ]);
      await GameAnalytics.configureBuild(AnalyticsKeys.build);
      await GameAnalytics.initialize(
        AnalyticsKeys.gameKey,
        AnalyticsKeys.secretKey,
      );
      _ready = true;
    } catch (error) {
      logAnalyticsFailure('initialising', error);
    }
  }

  // ---------------------------------------------------------------- events

  /// A design event. [eventId] is a `a:b:c` hierarchy of at most five parts.
  ///
  /// Ids must come from a fixed vocabulary — never interpolate a score, a
  /// duration or anything else player-derived into one. GameAnalytics indexes
  /// on the id, and an unbounded set of them makes the dashboard useless.
  /// Numbers go in [value].
  static void design(String eventId, {double? value}) {
    if (!_ready) return;
    try {
      unawaited(
        GameAnalytics.addDesignEvent({
          'eventId': eventId,
          'value': ?value,
        }),
      );
    } catch (error) {
      logAnalyticsFailure('design event $eventId', error);
    }
  }

  /// The run's progression funnel. Tetrofall is endless and has no win state,
  /// so every run is a [GAProgressionStatus.Start] followed by a
  /// [GAProgressionStatus.Fail] — quitting mid-run included. There is
  /// deliberately only one progression level: with adaptive start speed a run
  /// can begin partway up the difficulty curve, and putting the tier in
  /// `progression02` would pair starts and fails that GameAnalytics then
  /// counts as separate funnels.
  static const _progression = 'endless';

  static void progressionStart() {
    if (!_ready) return;
    try {
      unawaited(
        GameAnalytics.addProgressionEvent({
          'progressionStatus': GAProgressionStatus.Start,
          'progression01': _progression,
        }),
      );
    } catch (error) {
      logAnalyticsFailure('progression start', error);
    }
  }

  static void progressionFail({required int score}) {
    if (!_ready) return;
    try {
      unawaited(
        GameAnalytics.addProgressionEvent({
          'progressionStatus': GAProgressionStatus.Fail,
          'progression01': _progression,
          'score': score,
        }),
      );
    } catch (error) {
      logAnalyticsFailure('progression fail', error);
    }
  }

  static void error(String message, {int severity = GAErrorSeverity.Error}) {
    if (!_ready) return;
    try {
      unawaited(
        GameAnalytics.addErrorEvent({
          'severity': severity,
          'message': message,
        }),
      );
    } catch (failure) {
      logAnalyticsFailure('error event', failure);
    }
  }

  /// An ad impression, reward or failure. [placement] is a stable friendly
  /// name (`rewarded_continue`, `banner`, …) rather than the AdMob unit id, so
  /// the dashboard survives a unit being swapped out.
  ///
  /// [reason] only means anything alongside [AdOutcome.failed].
  static void ad({
    required AdOutcome outcome,
    required AdKind kind,
    required String placement,
    AdFailure? reason,
  }) {
    if (!_ready) return;
    try {
      unawaited(
        GameAnalytics.addAdEvent({
          'adAction': outcome._ga,
          'adType': kind._ga,
          'adSdkName': 'admob',
          'adPlacement': placement,
          'noAdReason': ?reason?._ga,
        }),
      );
    } catch (error) {
      logAnalyticsFailure('ad event $placement', error);
    }
  }

  // ------------------------------------------------------ custom dimensions

  static const adaptiveOn = 'adaptive_on';
  static const adaptiveOff = 'adaptive_off';
  static const tutorialNew = 'tutorial_new';
  static const tutorialSeen = 'tutorial_seen';

  /// Segments every subsequent event by whether the player starts runs partway
  /// up the difficulty curve — without it, adaptive-start runs drag the
  /// run-length distribution down and look like a difficulty problem.
  static void setAdaptiveDimension(bool enabled) =>
      _setDimension01(enabled ? adaptiveOn : adaptiveOff);

  static void setTutorialDimension(bool seen) =>
      _setDimension02(seen ? tutorialSeen : tutorialNew);

  static void _setDimension01(String value) {
    if (!_ready) return;
    try {
      unawaited(GameAnalytics.setCustomDimension01(value));
    } catch (error) {
      logAnalyticsFailure('custom dimension 01', error);
    }
  }

  static void _setDimension02(String value) {
    if (!_ready) return;
    try {
      unawaited(GameAnalytics.setCustomDimension02(value));
    } catch (error) {
      logAnalyticsFailure('custom dimension 02', error);
    }
  }
}

/// What happened to an ad. Named for what the app knows rather than for
/// GameAnalytics' vocabulary, so [AdsService] never has to import the SDK.
enum AdOutcome {
  shown(GAAdAction.Show),
  clicked(GAAdAction.Clicked),
  rewarded(GAAdAction.RewardReceived),
  failed(GAAdAction.FailedShow);

  const AdOutcome(this._ga);
  final int _ga;
}

/// GameAnalytics has no app-open format; it is reported as an interstitial and
/// told apart by its placement.
enum AdKind {
  rewardedVideo(GAAdType.RewardedVideo),
  interstitial(GAAdType.Interstitial),
  banner(GAAdType.Banner);

  const AdKind(this._ga);
  final int _ga;
}

/// GameAnalytics' `no_ad_reason` vocabulary. The Flutter wrapper forwards the
/// raw int to the native SDK without exposing an enum for it, so the values
/// are spelled out here.
enum AdFailure {
  unknown(1),
  offline(2),
  noFill(3),
  internalError(4),
  invalidRequest(5),
  unableToPrecache(6);

  const AdFailure(this._ga);
  final int _ga;
}
