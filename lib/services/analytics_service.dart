import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gameanalytics_sdk/gameanalytics.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'analytics_keys.dart';

/// Logs (debug only) what an analytics call couldn't do, instead of a bare
/// `catch (_)`, so a channel that starts throwing is visible.
void logAnalyticsFailure(String what, Object error) {
  if (kDebugMode) {
    debugPrint('[analytics] $what failed: $error');
  }
}

/// GameAnalytics, wrapped so the rest of the app never touches the SDK.
/// Static because call sites (render components, trackers, ad callbacks) have
/// no constructor to thread a handle through. Every method is a no-op until
/// [init] resolves and swallows its own failures.
abstract final class AnalyticsService {
  static Future<void>? _initFuture;
  static bool _ready = false;

  /// False in tests, on desktop, and when [AnalyticsKeys] are blank.
  static bool get isReady => _ready;

  /// Only the first call does anything. Completes when the attempt is over,
  /// not when the SDK has reached the network.
  static Future<void> init() => _initFuture ??= _init();

  static Future<void> _init() async {
    if (!AnalyticsKeys.configured) return;
    // No method channel exists off Android/iOS; calls would throw.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await GameAnalytics.setEnabledInfoLog(kDebugMode);
      // Dimension vocabularies must be declared before `initialize`.
      await GameAnalytics.configureAvailableCustomDimensions01(const [
        adaptiveOn,
        adaptiveOff,
      ]);
      await GameAnalytics.configureAvailableCustomDimensions02(const [
        tutorialNew,
        tutorialSeen,
      ]);
      await GameAnalytics.configureAvailableCustomDimensions03(const [
        skillLow,
        skillMid,
        skillHigh,
      ]);
      await GameAnalytics.configureBuild(await _buildVersion());
      await GameAnalytics.initialize(
        AnalyticsKeys.gameKey,
        AnalyticsKeys.secretKey,
      );
      _ready = true;
    } catch (error) {
      logAnalyticsFailure('initialising', error);
    }
  }

  /// The installed version, so events carry the build that sent them.
  static Future<String> _buildVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return AnalyticsKeys.build;
    }
  }

  /// A design event. [eventId] is an `a:b:c` hierarchy of at most five parts
  /// from a fixed vocabulary; never put player-derived values in it, use
  /// [value].
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

  /// Every run is a Start followed by a Fail (there is no win state). One
  /// progression level only: with adaptive start, a tier in `progression02`
  /// would split start/fail pairs into separate funnels.
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

  /// An ad impression, reward or failure. [placement] is an [AdPlacements]
  /// name; [reason] only matters with [AdOutcome.failed].
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

  static const adaptiveOn = 'adaptive_on';
  static const adaptiveOff = 'adaptive_off';
  static const tutorialNew = 'tutorial_new';
  static const tutorialSeen = 'tutorial_seen';

  /// Segments events by adaptive start, which otherwise drags run lengths down
  /// and looks like a difficulty problem.
  static void setAdaptiveDimension(bool enabled) =>
      _setDimension01(enabled ? adaptiveOn : adaptiveOff);

  static void setTutorialDimension(bool seen) =>
      _setDimension02(seen ? tutorialSeen : tutorialNew);

  static const skillLow = 'low';
  static const skillMid = 'mid';
  static const skillHigh = 'high';

  /// Segments events by the Director's skill estimate.
  static void setSkillBucketDimension(String bucket) {
    if (!_ready) return;
    if (bucket != skillLow && bucket != skillMid && bucket != skillHigh) return;
    try {
      unawaited(GameAnalytics.setCustomDimension03(bucket));
    } catch (error) {
      logAnalyticsFailure('custom dimension 03', error);
    }
  }

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

/// What happened to an ad, so [AdsService] never imports the SDK.
enum AdOutcome {
  shown(GAAdAction.Show),
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

/// GameAnalytics' `no_ad_reason` values; the Flutter wrapper doesn't expose
/// them.
enum AdFailure {
  unknown(1),
  offline(2),
  noFill(3),
  internalError(4);

  const AdFailure(this._ga);
  final int _ga;
}
