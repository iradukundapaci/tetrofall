import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart' show logAnalyticsFailure;
import 'firebase_bootstrap.dart';

/// Crashlytics, plus [crashedThisSession], which keeps the rating prompt away
/// from someone who just saw the game crash. Hooks are installed whether or
/// not Firebase is up; only reporting depends on it.
abstract final class CrashReporting {
  /// True once anything has gone uncaught this session.
  static bool crashedThisSession = false;

  /// Call once, before `runApp`.
  static Future<void> install() async {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      crashedThisSession = true;
      _record(
        () => FirebaseCrashlytics.instance.recordFlutterFatalError(details),
      );
      previousFlutterHandler?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      crashedThisSession = true;
      _record(
        () =>
            FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
      );
      // Release swallows the error; debug keeps the console trace.
      return !kDebugMode;
    };

    await FirebaseBootstrap.init();
    if (!FirebaseBootstrap.isReady) return;
    try {
      // Off in debug so dev noise stays off the dashboard.
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
    } catch (error) {
      logAnalyticsFailure('enabling Crashlytics', error);
    }
  }

  static void _record(Future<void> Function() report) {
    if (!FirebaseBootstrap.isReady) return;
    try {
      report().catchError((Object e) => logAnalyticsFailure('Crashlytics', e));
    } catch (error) {
      logAnalyticsFailure('Crashlytics', error);
    }
  }
}
