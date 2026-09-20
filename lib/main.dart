import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/ads_service.dart';
import 'services/analytics_service.dart';
import 'services/audio_service.dart';
import 'services/connectivity_service.dart';
import 'services/firebase_analytics_service.dart';
import 'services/music_service.dart';
import 'services/storage_service.dart';

/// The width Android itself draws the phone / large-screen line at.
const _largeScreenDp = 600;

/// Phones stay portrait; large screens are left free to rotate.
///
/// This used to be `android:screenOrientation="portrait"` in the manifest, and
/// Play flags that on its own: a manifest lock is ignored on large screens from
/// Android 16 anyway (`targetSdk` 36), so a tablet or foldable was going to
/// rotate whatever we said — and a lock we cannot enforce is worse than none,
/// because it is the reason nobody checked that landscape lays out. It does:
/// the board is aspect-ratio bound and simply centres, narrower, when there is
/// more width than it can use.
///
/// The lock stays for phones because the game is played one-handed in portrait
/// and a sideways board would be a much worse game, not a different layout.
Future<void> _applyOrientationPolicy() {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  // No view, or one that has not reported a size yet, is treated as a phone:
  // the restrictive answer is the one that matches every shipped release.
  final shortestDp = view == null || view.physicalSize.isEmpty
      ? 0.0
      : view.physicalSize.shortestSide / view.devicePixelRatio;
  return SystemChrome.setPreferredOrientations(
    shortestDp >= _largeScreenDp
        ? DeviceOrientation.values
        : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _applyOrientationPolicy();
  final storage = await StorageService.load();
  await FirebaseAnalyticsService.init();
  final ads = AdsService(storage, connectivity: ConnectivityService());
  unawaited(ads.init());
  unawaited(
    AnalyticsService.init().then((_) {
      AnalyticsService.setAdaptiveDimension(storage.adaptiveStartSpeedEnabled);
      AnalyticsService.setTutorialDimension(storage.tutorialSeen);
    }),
  );
  unawaited(AudioService.warmUp());
  unawaited(MusicService.warmUp());
  runApp(TetrofallApp(storage: storage, ads: ads));
}
