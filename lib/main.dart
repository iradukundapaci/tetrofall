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
import 'services/economy.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final storage = await StorageService.load();
  await FirebaseAnalyticsService.init();
  // Built before the ad service, which has to consult Clear Skies before
  // showing an interstitial or an app-open ad.
  final economy = Economy(storage);
  unawaited(economy.wallet.grantStarterIfNeeded());
  final ads = AdsService(
    storage,
    connectivity: ConnectivityService(),
    clearSkies: economy.clearSkies,
  );
  unawaited(ads.init());
  unawaited(
    AnalyticsService.init().then((_) {
      AnalyticsService.setAdaptiveDimension(storage.adaptiveStartSpeedEnabled);
      AnalyticsService.setTutorialDimension(storage.tutorialSeen);
    }),
  );
  unawaited(AudioService.warmUp());
  unawaited(MusicService.warmUp());
  runApp(TetrofallApp(storage: storage, ads: ads, economy: economy));
}
