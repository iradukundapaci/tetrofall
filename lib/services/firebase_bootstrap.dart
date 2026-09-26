import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

import 'analytics_service.dart' show logAnalyticsFailure;

/// The one place Firebase is initialised. Analytics, Crashlytics, Remote
/// Config, Auth and Firestore all wait on it, so there is a single answer to
/// "is Firebase up?" and a single failure to swallow.
///
/// Inert off Android and iOS — under `flutter test` and on desktop there is no
/// native config to read and no plugin channel to call.
abstract final class FirebaseBootstrap {
  static Future<void>? _initFuture;
  static bool _ready = false;

  static bool get isReady => _ready;

  static Future<void> init() => _initFuture ??= _init();

  static Future<void> _init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (error) {
      logAnalyticsFailure('initialising Firebase', error);
    }
  }
}
