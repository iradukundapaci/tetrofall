import 'dart:async';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

import 'analytics_service.dart' show logAnalyticsFailure;

abstract final class FirebaseAnalyticsService {
  static Future<void>? _initFuture;
  static FirebaseAnalytics? _analytics;
  static bool get isReady => _analytics != null;
  static Future<void> init() => _initFuture ??= _init();

  static Future<void> _init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
    } catch (error) {
      logAnalyticsFailure('initialising Firebase', error);
    }
  }

  static Future<void> setConsent({
    required bool adsAllowed,
    required bool personalized,
  }) async {
    await init();
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.setConsent(
        analyticsStorageConsentGranted: true,
        adStorageConsentGranted: adsAllowed,
        adUserDataConsentGranted: adsAllowed,
        adPersonalizationSignalsConsentGranted: adsAllowed && personalized,
      );
    } catch (error) {
      logAnalyticsFailure('firebase consent', error);
    }
  }

  static const _level = 'endless';

  static void logLevelStart() {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      unawaited(analytics.logLevelStart(levelName: _level));
    } catch (error) {
      logAnalyticsFailure('level_start', error);
    }
  }

  static void logLevelEnd({required int score, required int tier}) {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      unawaited(analytics.logLevelEnd(levelName: _level, success: 0));
      unawaited(analytics.logPostScore(score: score, level: tier));
    } catch (error) {
      logAnalyticsFailure('level_end', error);
    }
  }

  static void logTutorialBegin() {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      unawaited(analytics.logTutorialBegin());
    } catch (error) {
      logAnalyticsFailure('tutorial_begin', error);
    }
  }

  static void logTutorialComplete() {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      unawaited(analytics.logTutorialComplete());
    } catch (error) {
      logAnalyticsFailure('tutorial_complete', error);
    }
  }
}
