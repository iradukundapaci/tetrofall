import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart' show logAnalyticsFailure;
import 'firebase_bootstrap.dart';

/// Crashlytics, plus the one bit of crash state the rest of the app needs.
///
/// The hooks are installed whether or not Firebase is up, because
/// [crashedThisSession] is what stops the rating prompt from asking someone
/// who has just watched the game fall over; only the *reporting* depends on
/// Crashlytics being ready.
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
      // Debug builds keep the console trace; release swallows it, as the
      // framework would have crashed the isolate otherwise.
      return !kDebugMode;
    };

    await FirebaseBootstrap.init();
    if (!FirebaseBootstrap.isReady) return;
    try {
      // Off in debug so development noise never reaches the dashboard.
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
    } catch (error) {
      logAnalyticsFailure('enabling Crashlytics', error);
    }
  }

  /// A handled failure worth knowing about, without crashing anything.
  static void nonFatal(Object error, StackTrace stack, {String? reason}) {
    _record(
      () => FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
      ),
    );
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
