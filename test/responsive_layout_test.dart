import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/engine/events.dart';
import 'package:tetrofall/ui/screens/confirm_quit_overlay.dart';
import 'package:tetrofall/ui/screens/game_over_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/game/config/board_config.dart';
import 'package:tetrofall/services/ads_service.dart';
import 'package:tetrofall/services/storage_service.dart';
import 'package:tetrofall/services/economy.dart';
import 'package:tetrofall/ui/screens/gameplay_screen.dart';
import 'package:tetrofall/ui/theme/ui_scale.dart';

/// The chrome is sized from one scalar, so the regression net only has to
/// cover two things: that the scalar lands where it is meant to across the
/// device range, and that nothing overflows once it does.
///
/// Overflow surfaces as an exception in tests rather than as stripes, which
/// is what makes the second half cheap — every overlay used to be a bare
/// `Center` with no scroll fallback.
void main() {
  /// Phone through tablet, plus the reference frame every screen was drawn
  /// against. Expected factors are `min(w / 375, h / 812)` clamped to
  /// 0.80–1.25.
  const cases = <(Size, double)>[
    (Size(320, 568), 0.80), // iPhone SE — the floor
    (Size(360, 640), 0.80), // the Android phone from the bug report
    (Size(375, 812), 1.00), // the reference
    (Size(393, 852), 1.048), // iPhone 15 Pro
    (Size(430, 932), 1.147), // iPhone Pro Max
    (Size(768, 1024), 1.25), // iPad portrait — the ceiling
  ];

  group('UiScale', () {
    for (final (size, expected) in cases) {
      test('$size scales geometry by $expected', () {
        final ui = UiScale.fromParts(size, EdgeInsets.zero);
        expect(ui.s, closeTo(expected, 0.005));
      });
    }

    test('type is damped toward 1.0, so captions stay legible', () {
      final small = UiScale.fromParts(const Size(360, 640), EdgeInsets.zero);
      // Geometry takes the full 20% cut; type takes 60% of it.
      expect(small.s, closeTo(0.80, 0.005));
      expect(small.t, closeTo(0.88, 0.005));
      expect(small.fontXs, greaterThan(10.0));
    });

    test('a touch target never scales below 44', () {
      final tiny = UiScale.fromParts(const Size(240, 320), EdgeInsets.zero);
      expect(tiny.tap, 44.0);
    });

    test('a modal never outgrows the viewport it sits in', () {
      final narrow = UiScale.fromParts(const Size(320, 568), EdgeInsets.zero);
      expect(narrow.panelWidth, lessThanOrEqualTo(320 - narrow.spaceLg * 2));
    });
  });

  group('overlays lay out without overflowing', () {
    Future<void> pumpOverlay(
      WidgetTester tester,
      Size size,
      double textScale,
      Widget overlay,
    ) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Stack(children: [overlay]))),
      );
      await tester.pump();
    }

    // The tallest state either overlay can reach: a new best (which adds the
    // pill), plus the continue button, plus a six-digit score. The balance is
    // deliberately zero, because the can't-afford label is the longer one.
    Widget gameOver() => GameOverOverlay(
      reason: GameOverReason.topOut,
      score: 999999,
      best: 1,
      onRestart: () {},
      onHome: () {},
      canContinue: true,
      continuePrice: 120,
      coinBalance: 0,
      onContinue: () {},
    );

    Widget confirmQuit() => ConfirmQuitOverlay(
      score: 123456,
      onContinue: () {},
      onQuit: () {},
    );

    for (final (size, _) in cases) {
      // 1.3 is deliberately above the 1.15 the app clamps to: the clamp lives
      // in TetrofallApp, so pumping an overlay bare proves the scroll
      // fallback holds on its own if that clamp is ever loosened.
      for (final textScale in [1.0, 1.3]) {
        testWidgets('game over at $size @${textScale}x', (tester) async {
          await pumpOverlay(tester, size, textScale, gameOver());
          expect(tester.takeException(), isNull);
        });

        testWidgets('confirm quit at $size @${textScale}x', (tester) async {
          await pumpOverlay(tester, size, textScale, confirmQuit());
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  /// `GameplayScreen.immersive` exists only for the store-capture harness in
  /// `tools/capture/`: it floats the HUD over the board and drops the frame,
  /// the booster bar and the safe-area padding, which is honest for a store
  /// shot and wrong for play. Constructing the widget is enough to catch a
  /// flipped default; mounting it would boot Flame for no extra signal.
  group('immersive capture flag', () {
    test('defaults to off, so the shipped layout keeps its chrome', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService(await SharedPreferences.getInstance());
      final shipped = GameplayScreen(
        storage: storage,
        ads: AdsService(storage),
        economy: Economy(storage),
      );
      expect(shipped.immersive, isFalse);
    });

    test('the board is exactly 9:16, which is why chrome costs width', () {
      // The reason immersive reclaims so much: with the board height-bound at
      // 9:16 on a 9:16 screen, every point of HUD or booster bar above and
      // below it comes back out of the board's *width* at 0.5625pt a time.
      expect(BoardConfig.cols / BoardConfig.rows, closeTo(9 / 16, 1e-9));
    });
  });
}
