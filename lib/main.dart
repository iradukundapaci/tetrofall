import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/ads_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final storage = await StorageService.load();
  final ads = AdsService(storage);
  unawaited(ads.init());
  runApp(TetrofallApp(storage: storage, ads: ads));
}
