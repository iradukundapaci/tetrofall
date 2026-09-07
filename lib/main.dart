import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/ads_service.dart';
import 'services/analytics_service.dart';
import 'services/audio_service.dart';
import 'services/connectivity_service.dart';
import 'services/music_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final storage = await StorageService.load();
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
