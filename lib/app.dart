import 'package:flutter/material.dart';

import 'services/ads_service.dart';
import 'services/storage_service.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/theme/tokens.dart';
import 'ui/theme/ui_scale.dart';

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
      // Wraps the Navigator, so one install covers splash, menu, gameplay,
      // settings and every overlay. The text scaler is clamped *before*
      // [UiScale] reads the metrics, so the two can never disagree about how
      // large text is — 1.15 is the ceiling a fixed-height game HUD and a
      // board with a locked aspect ratio can stay honest at.
      builder: (context, child) {
        final data = MediaQuery.of(context);
        final clamped = data.copyWith(
          textScaler: data.textScaler.clamp(maxScaleFactor: 1.15),
        );
        return MediaQuery(
          data: clamped,
          child: UiScaleScope(
            scale: UiScale.fromParts(clamped.size, clamped.viewPadding),
            child: child!,
          ),
        );
      },
      home: SplashScreen(storage: storage, ads: ads),
    );
  }
}
