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

  static const _defaults = <String, Object>{
    directorEnabledKey: true,
    directorV2Key: true,
    gentleFirstRunsKey: true,
    reviewPromptEnabledKey: true,
    feedbackEnabledKey: true,
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

  /// Off turns the Director into a [NullDirector]: the A/B control arm.
  static bool get directorEnabled => _flag(directorEnabledKey);

  /// Off leaves only the Director's rescue behaviour.
  static bool get directorV2 => _flag(directorV2Key);

  static bool get gentleFirstRuns => _flag(gentleFirstRunsKey);
  static bool get reviewPromptEnabled => _flag(reviewPromptEnabledKey);
  static bool get feedbackEnabled => _flag(feedbackEnabledKey);
}
