import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

import 'analytics_service.dart' show logAnalyticsFailure;

/// The one place Firebase is initialised; everything Firebase-backed waits on
/// it. Inert off Android and iOS (tests, desktop).
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
