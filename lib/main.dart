import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'game/director/skill_model.dart';
import 'services/ads_service.dart';
import 'services/analytics_service.dart';
import 'services/audio_service.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';
import 'services/crash_reporting.dart';
import 'services/firebase_analytics_service.dart';
import 'services/music_service.dart';
import 'services/remote_flags.dart';
import 'services/session_tracker.dart';
import 'services/storage_service.dart';
import 'services/telemetry.dart';

/// The width Android itself draws the phone / large-screen line at.
const _largeScreenDp = 600;

/// Phones stay portrait; large screens rotate freely. A manifest lock is
/// ignored on large screens from Android 16 anyway, and the aspect-bound board
/// simply centres in landscape.
Future<void> _applyOrientationPolicy() {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  // No view yet counts as a phone.
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
  await storage.ensureInstallDate();
  // Hooks first so nothing after can crash unseen; also brings Firebase up.
  await CrashReporting.install();
  await FirebaseAnalyticsService.init();
  // None of these may hold up the first frame.
  unawaited(AuthService.ensureAnonymous());
  unawaited(
    RemoteFlags.init().then(
      (_) => Telemetry.setExperiment(
        RemoteFlags.directorEnabled ? 'director_on' : 'director_off',
      ),
    ),
  );
  unawaited(SessionTracker.begin(storage));
  final ads = AdsService(storage, connectivity: ConnectivityService());
  unawaited(ads.init());
  unawaited(
    AnalyticsService.init().then((_) {
      AnalyticsService.setAdaptiveDimension(storage.adaptiveStartSpeedEnabled);
      AnalyticsService.setTutorialDimension(storage.tutorialSeen);
      Telemetry.setSkillBucket(SkillModel.bucketOf(storage.directorSkill));
    }),
  );
  unawaited(AudioService.warmUp());
  unawaited(MusicService.warmUp());
  runApp(TetrofallApp(storage: storage, ads: ads));
}
