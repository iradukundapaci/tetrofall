import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/ads_service.dart';
import 'services/audio_service.dart';
import 'services/music_service.dart';
import 'services/storage_service.dart';

void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/Nunito/OFL.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Baloo 2',
    ], await rootBundle.loadString('assets/fonts/Baloo_2/OFL.txt'));
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final storage = await StorageService.load();
  final ads = AdsService(storage);
  unawaited(ads.init());
  unawaited(AudioService.warmUp());
  unawaited(MusicService.warmUp());
  runApp(TetrofallApp(storage: storage, ads: ads));
}
