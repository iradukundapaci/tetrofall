import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart' show logAnalyticsFailure;
import 'firebase_bootstrap.dart';

/// Feature flags and the A/B experiment, from Firebase Remote Config. Every
/// flag has an in-code default, and values are read when needed so a fetch
/// mid-session takes effect on the next run.
abstract final class RemoteFlags {
  static const directorEnabledKey = 'director_enabled';
  static const directorV2Key = 'director_v2';
  static const gentleFirstRunsKey = 'gentle_first_runs';
  static const reviewPromptEnabledKey = 'review_prompt_enabled';
  static const feedbackEnabledKey = 'feedback_enabled';

  /// Master switch for `AdsService`'s owed-break interstitial (the app-open
  /// replacement, see `ads_slimdown_plan.md`).
  static const owedBreakEnabledKey = 'owed_break_enabled';

  /// How often a backgrounded return can arm an owed break, in seconds.
  static const owedBreakMinIntervalSKey = 'owed_break_min_interval_s';

  /// Cumulative play seconds that make an interstitial due, on top of the
  /// run-count cap.
  static const interstitialPlaySecondsCapKey = 'interstitial_play_seconds_cap';

  /// Guardrail: interstitials shown per app session, regardless of cadence.
  static const interstitialsPerSessionCapKey = 'interstitials_per_session_cap';

  static const _defaults = <String, Object>{
    directorEnabledKey: true,
    directorV2Key: true,
    gentleFirstRunsKey: true,
    reviewPromptEnabledKey: true,
    feedbackEnabledKey: true,
    owedBreakEnabledKey: true,
    owedBreakMinIntervalSKey: 900,
    interstitialPlaySecondsCapKey: 180,
    interstitialsPerSessionCapKey: 4,
  };

  static FirebaseRemoteConfig? _config;
  static Future<void>? _initFuture;

  /// Completes when the fetch attempt is over. Never throws.
  static Future<void> init() => _initFuture ??= _init();

  static Future<void> _init() async {
    await FirebaseBootstrap.init();
    if (!FirebaseBootstrap.isReady) return;
    try {
      final config = FirebaseRemoteConfig.instance;
      await config.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(hours: 12),
        ),
      );
      await config.setDefaults(_defaults);
      _config = config;
      await config.fetchAndActivate();
    } catch (error) {
      logAnalyticsFailure('fetching Remote Config', error);
    }
  }

  static bool _flag(String key) {
    final config = _config;
    if (config == null) return _defaults[key]! as bool;
    try {
      return config.getBool(key);
    } catch (error) {
      logAnalyticsFailure('reading flag $key', error);
      return _defaults[key]! as bool;
    }
  }

  static int _intFlag(String key) {
    final config = _config;
    if (config == null) return _defaults[key]! as int;
    try {
      return config.getInt(key);
    } catch (error) {
      logAnalyticsFailure('reading flag $key', error);
      return _defaults[key]! as int;
    }
  }

  /// Off turns the Director into a [NullDirector]: the A/B control arm.
  static bool get directorEnabled => _flag(directorEnabledKey);

  /// Off leaves only the Director's rescue behaviour.
  static bool get directorV2 => _flag(directorV2Key);

  static bool get gentleFirstRuns => _flag(gentleFirstRunsKey);
  static bool get reviewPromptEnabled => _flag(reviewPromptEnabledKey);
  static bool get feedbackEnabled => _flag(feedbackEnabledKey);

  static bool get owedBreakEnabled => _flag(owedBreakEnabledKey);

  static Duration get owedBreakMinInterval =>
      Duration(seconds: _intFlag(owedBreakMinIntervalSKey));

  static int get interstitialPlaySecondsCap =>
      _intFlag(interstitialPlaySecondsCapKey);

  static int get interstitialsPerSessionCap =>
      _intFlag(interstitialsPerSessionCapKey);
}
