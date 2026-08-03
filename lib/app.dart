import 'package:flutter/material.dart';

import 'services/ads_service.dart';
import 'services/storage_service.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/theme/tokens.dart';

class TetrofallApp extends StatelessWidget {
  const TetrofallApp({super.key, required this.storage, required this.ads});

  final StorageService storage;
  final AdsService ads;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tetrofall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Tokens.colorBg,
        fontFamily: Tokens.fontBody,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Tokens.colorGold,
          brightness: Brightness.dark,
        ),
      ),
      home: SplashScreen(storage: storage, ads: ads),
    );
  }
}
