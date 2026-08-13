import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/ui/theme/tokens.dart';
import 'package:tetrofall/ui/widgets/logo_mark.dart';
import 'package:tetrofall/ui/widgets/logo_wordmark.dart';

import 'icon_art.dart';

/// Writes the branding masters listed in android_release_plan.md §1.1.
///
/// It lives in `tools/` and not `test/` on purpose: it is a generator, not a
/// test, and `flutter test` only scans `test/` so it never runs in CI.
///
/// ```bash
/// flutter test tools/branding/forge_test.dart
/// ```
///
/// Rendering through `flutter_test` rather than a throwaway app is what keeps
/// this runnable with no device attached, and it draws with the same engine
/// the app draws with, so the splash mark is the mark the app hands off to.
void main() {
  const out = 'branding';

  // The mark as the adaptive layers carry it. 0.608 of 1024 is a 623px mark,
  // which looks oversized against the 683px (66%) safe circle until you
  // account for flutter_launcher_icons wrapping both the foreground and the
  // monochrome layer in `<inset android:inset="16%">`: what actually ships is
  // 623 × 0.68 = 424px, a comfortable 62% of the visible viewport, and its
  // half-diagonal (253px) clears the 341px safe radius with room to spare.
  // Sizing the source to the safe zone *and* taking the inset would leave the
  // mark shrunken twice over.
  const adaptiveMark = MarkArt(style: MarkStyle.gold, markWidthFraction: 0.608);

  // The legacy/listing icon has no mask to survive, so the mark runs larger.
  const fullBleedMark = MarkArt(
    style: MarkStyle.gold,
    markWidthFraction: 0.645,
  );

  testWidgets('forge branding masters', (tester) async {
    final texture = await _loadTexture(tester);

    // 1024×1024 full-bleed. No transparency and no rounded corners: every
    // Android launcher masks the legacy icon itself.
    await _capture(
      tester,
      size: const Size.square(1024),
      path: '$out/icon_master.png',
      child: _plated(texture, fullBleedMark),
    );

    // The Play listing icon is the same art at listing size.
    await _capture(
      tester,
      size: const Size.square(512),
      path: '$out/play_icon_512.png',
      child: _plated(texture, fullBleedMark),
    );

    await _capture(
      tester,
      size: const Size.square(1024),
      path: '$out/icon_foreground.png',
      child: adaptiveMark,
    );

    // Adaptive background: the plate on its own, no mark.
    await _capture(
      tester,
      size: const Size.square(1024),
      path: '$out/icon_background.png',
      child: WoodPlate(texture: texture),
    );

    // Android 13+ themed icon: flat silhouette at the same fraction as the
    // foreground — and it takes the same 16% inset — so the mark doesn't move
    // when a launcher swaps between the two.
    await _capture(
      tester,
      size: const Size.square(1024),
      path: '$out/icon_monochrome.png',
      child: const MarkArt(
        style: MarkStyle.monochrome,
        markWidthFraction: 0.608,
      ),
    );

    // The native splash mark is the *app's* LogoMark, wood tones and all, so
    // the Android splash hands off to SplashScreen's drop animation without
    // the mark changing colour mid-boot.
    //
    // Two sizes, because the two Android splash mechanisms scale a source
    // image differently and the goal is for the mark to be the same size on
    // screen either way — SplashScreen draws it at 130dp:
    //
    //  * Android 12+ maps the whole 1152px canvas onto a 240dp icon slot, so
    //    620px lands at 129dp and also stays inside the 768px (160dp) keyline
    //    the platform clips a splash icon to.
    //  * Pre-12, flutter_native_splash treats the source as xxxhdpi and
    //    divides it down per density, so the source is in physical pixels at
    //    4x: 520px is 130dp on every device.
    await _capture(
      tester,
      size: const Size.square(1152),
      path: '$out/splash_logo.png',
      child: const Center(child: LogoMark(cellSize: 620 / 3.25)),
    );
    await _capture(
      tester,
      size: const Size.square(1152),
      path: '$out/splash_logo_legacy.png',
      child: const Center(child: LogoMark(cellSize: 520 / 3.25)),
    );
  });

  // §4.10. Required by Play, and it appears in promo surfaces where it plays
  // *alone with no screenshots* — so it has to carry the whole pitch by itself.
  testWidgets('forge feature graphic', (tester) async {
    final texture = await _loadTexture(tester);
    await _loadLabelFont();

    await _capture(
      tester,
      // 1024x500 exactly. Play rejects any other ratio for this slot — it is
      // NOT square, which is the usual mistake.
      size: const Size(1024, 500),
      path: '$out/store/feature_graphic.png',
      child: _FeatureGraphic(texture: texture),
    );
  });

  // §1.1 asks for two eyeball checks that a 1024px master can't answer: does
  // it read at 48px, and does it hold up on both a white and a black
  // wallpaper. This renders exactly that, masked the way Android masks it.
  testWidgets('forge contact sheet', (tester) async {
    final texture = await _loadTexture(tester);
    await _loadLabelFont();

    await _capture(
      tester,
      size: const Size(1600, 560),
      path: '$out/contact_sheet.png',
      child: _ContactSheet(texture: texture),
    );
  });
}

/// Composites [mark] over the wood plate.
Widget _plated(ui.Image? texture, Widget mark) => Stack(
  fit: StackFit.expand,
  children: [
    WoodPlate(texture: texture),
    mark,
  ],
);

/// Decodes the shipped board texture so the icon grain is the game's grain.
Future<ui.Image?> _loadTexture(WidgetTester tester) async {
  ui.Image? image;
  await tester.runAsync(() async {
    try {
      final data = await rootBundle.load('assets/images/textures/bg_wood.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 1024,
        targetHeight: 1024,
      );
      image = (await codec.getNextFrame()).image;
    } catch (error) {
      // A flat plate is an acceptable fallback (§1.1 allows a flat colour),
      // but it is a visible downgrade, so say so rather than swallowing it.
      // ignore: avoid_print
      print('WARNING: wood texture unavailable, using a flat plate: $error');
    }
  });
  return image;
}

/// flutter_test draws every glyph as a filled box unless a real font is
/// registered, which would make the sheet's labels unreadable.
Future<void> _loadLabelFont() async {
  final body = FontLoader(Tokens.fontBody)
    ..addFont(rootBundle.load('assets/fonts/Nunito/static/Nunito-Bold.ttf'));
  final display = FontLoader(Tokens.fontDisplay)
    ..addFont(
      rootBundle.load('assets/fonts/Baloo_2/static/Baloo2-ExtraBold.ttf'),
    );
  await Future.wait([body.load(), display.load()]);
}

/// Renders [child] at [size] logical pixels with a 1.0 device pixel ratio —
/// so one logical pixel is one output pixel — and writes the PNG.
Future<void> _capture(
  WidgetTester tester, {
  required Size size,
  required String path,
  required Widget child,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: boundaryKey,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    ),
  );
  await tester.pump();

  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late final Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
    image.dispose();
  });

  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png);
  // ignore: avoid_print
  print(
    'wrote $path (${size.width.toInt()}×${size.height.toInt()}, '
    '${png.length} bytes)',
  );
}

/// A proof sheet of every masked form of the icon, at the sizes a launcher
/// actually draws, over a light and a dark wallpaper.
class _ContactSheet extends StatelessWidget {
  const _ContactSheet({required this.texture});

  final ui.Image? texture;

  /// Android crops the 108dp adaptive layers down to a 72dp viewport, so a
  /// preview has to blow the layer up by the same 1.5× to be honest.
  static const _adaptiveZoom = 1.5;

  /// ...and flutter_launcher_icons wraps the foreground and monochrome layers
  /// in `<inset android:inset="16%">`, which scales them to 68%. Modelling
  /// both is what makes this sheet show the shipped icon rather than the
  /// source art.
  static const _foregroundInset = 0.68;

  static const _sizes = [192.0, 96.0, 48.0];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF6B6B6B),
      child: Column(
        children: [
          _wallpaper(const Color(0xFFFFFFFF), const Color(0xFF1A1A1A)),
          _wallpaper(const Color(0xFF000000), const Color(0xFFEDEDED)),
        ],
      ),
    );
  }

  /// One wallpaper band: every variant at every size, plus labels in [ink].
  Widget _wallpaper(Color background, Color ink) {
    return Expanded(
      child: ColoredBox(
        color: background,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _variant('Legacy', ink, (size) => _legacy(size)),
              _variant('Adaptive', ink, (size) => _adaptive(size)),
              _variant('Themed', ink, (size) => _themed(size, background, ink)),
              _variant('Splash', ink, (size) => _splash(size)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _variant(String label, Color ink, Widget Function(double) build) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: Tokens.fontBody,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: ink,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final size in _sizes) ...[
              build(size),
              const SizedBox(width: 14),
            ],
          ],
        ),
      ],
    );
  }

  /// The squircle most launchers apply to a legacy `ic_launcher.png`.
  Widget _legacy(double size) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: SizedBox(
      width: size,
      height: size,
      child: _plated(
        texture,
        const MarkArt(style: MarkStyle.gold, markWidthFraction: 0.645),
      ),
    ),
  );

  /// Background + inset foreground under a circular mask — the harshest
  /// common mask, composed exactly as `mipmap-anydpi-v26/ic_launcher.xml`
  /// composes it.
  Widget _adaptive(double size) => ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: Transform.scale(
        scale: _adaptiveZoom,
        child: Stack(
          fit: StackFit.expand,
          children: [
            WoodPlate(texture: texture),
            Transform.scale(
              scale: _foregroundInset,
              child: const MarkArt(
                style: MarkStyle.gold,
                markWidthFraction: 0.608,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Android 13+ themed icons: the monochrome layer tinted by the system on a
  /// flat system background. Approximated here by inverting the wallpaper.
  Widget _themed(double size, Color background, Color ink) => ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: ColoredBox(
        color: ink,
        child: Transform.scale(
          scale: _adaptiveZoom * _foregroundInset,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(background, BlendMode.srcIn),
            child: const MarkArt(
              style: MarkStyle.monochrome,
              markWidthFraction: 0.608,
            ),
          ),
        ),
      ),
    ),
  );

  /// The splash mark on the colour the native splash actually paints.
  Widget _splash(double size) => SizedBox(
    width: size,
    height: size,
    child: ColoredBox(
      color: Tokens.colorBg,
      // 240dp circle, 160dp of art — the Android 12 splash proportion.
      child: Center(child: LogoMark(cellSize: size * 0.54 / 3.25)),
    ),
  );
}


/// The 1024x500 Play feature graphic (§4.10).
///
/// Composition per the spec: wood plate, the T-mark left of centre, the
/// wordmark in Baloo 2 ExtraBold, and a few falling blocks over one rising row
/// as visual shorthand for the mechanic. No screenshots, no device frames, no
/// call to action and no store badges — all four are policy violations here.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.texture});

  final ui.Image? texture;

  /// Play crops the outer margins in some placements, so the mark and every
  /// glyph stay inside the centre 80%. The decorative blocks may bleed past it;
  /// nothing that carries meaning does.
  static const _safeInsetX = 1024 * 0.1;
  static const _safeInsetY = 500 * 0.1;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WoodPlate(texture: texture),

        // The mechanic, stated in one picture: blocks coming down, a row
        // coming up. Deliberately low-contrast so it reads as texture at
        // 250px wide rather than competing with the wordmark.
        const Positioned(
          left: 726,
          top: 34,
          child: _WoodBlock(size: 46, tilt: -0.18, opacity: 0.85),
        ),
        const Positioned(
          left: 848,
          top: 96,
          child: _WoodBlock(size: 62, tilt: 0.12, opacity: 0.7),
        ),
        const Positioned(
          left: 782,
          top: 186,
          child: _WoodBlock(size: 38, tilt: 0.3, opacity: 0.5),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: -26,
          child: _RisingRow(),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _safeInsetX,
            vertical: _safeInsetY,
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 190,
                height: 190,
                child: MarkArt(style: MarkStyle.gold, markWidthFraction: 1.0),
              ),
              const SizedBox(width: 34),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LogoWordmark(fontSize: 86),
                  const SizedBox(height: 10),
                  Text(
                    'The floor rises. Clear rows or get crushed.',
                    style: TextStyle(
                      fontFamily: Tokens.fontBody,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: Tokens.colorText.withValues(alpha: 0.92),
                      shadows: const [
                        Shadow(color: Color(0x99000000), offset: Offset(0, 2), blurRadius: 5),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A single wood cell, matching `LogoMark`'s block treatment.
class _WoodBlock extends StatelessWidget {
  const _WoodBlock({required this.size, this.tilt = 0, this.opacity = 1});

  final double size;
  final double tilt;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: tilt,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.2),
            border: Border.all(color: const Color(0x59000000)),
            gradient: const LinearGradient(
              begin: Alignment(-0.6, -1),
              end: Alignment(0.6, 1),
              colors: [
                Tokens.colorWoodLight,
                Tokens.colorWoodMid,
                Tokens.colorWoodDark,
              ],
              stops: [0, 0.55, 1],
            ),
            boxShadow: const [Tokens.shadowSoft],
          ),
        ),
      ),
    );
  }
}

/// The row pushing up from the bottom — the thing that makes this game
/// different, drawn as a partial row cut off by the canvas edge.
class _RisingRow extends StatelessWidget {
  const _RisingRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 14; i++) ...[
          _WoodBlock(size: 64, opacity: i.isEven ? 0.55 : 0.4),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}
