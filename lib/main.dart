import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/ads_service.dart';
import 'services/audio_service.dart';
import 'services/music_service.dart';
import 'services/storage_service.dart';

/// Nunito and Baloo 2 ship under the SIL Open Font License, which requires the
/// licence to travel with the fonts. Flutter's built-in licence page (reachable
/// from Settings -> Open source licences) collects entries from this registry,
/// so registering them here is what turns a bundled OFL.txt into actual
/// attribution. Lazy: the callback runs only if someone opens that page.
///
/// Public so `test/font_licenses_test.dart` can assert it actually yields both
/// licences — this is a legal obligation that fails silently if an asset path
/// drifts, since nothing in the app reads it until a user opens the page.
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
