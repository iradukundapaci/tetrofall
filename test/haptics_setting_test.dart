import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/game/engine/game_engine.dart';
import 'package:tetrofall/game/input/gesture_handler.dart';
import 'package:tetrofall/services/haptics_service.dart';
import 'package:tetrofall/services/storage_service.dart';

/// The Settings "Vibration" switch was persisted and then never read: every
/// `HapticFeedback` call fired unconditionally, so turning it off changed
/// nothing. These pin it to the channel the buzz actually goes out on —
/// whatever the intensity, it arrives as `HapticFeedback.vibrate`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<String> recordHaptics() {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add(call.arguments as String? ?? 'default');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return calls;
  }

  Future<StorageService> storageWithVibrate({required bool enabled}) async {
    SharedPreferences.setMockInitialValues({'vibrate_enabled': enabled});
    return StorageService.load();
  }

  /// A sideways swipe past the 0.85-cell column threshold — one of the
  /// moments the game ticks the player's hand.
  Future<void> swipeSideways(GestureHandler handler) async {
    const pointer = 1;
    var pos = const Offset(200, 100);
    handler.onPointerDown(PointerDownEvent(pointer: pointer, position: pos));
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      pos = pos + const Offset(10, 0);
      handler.onPointerMove(PointerMoveEvent(pointer: pointer, position: pos));
    }
  }

  test('a column shift buzzes when vibration is on', () async {
    final calls = recordHaptics();
    final storage = await storageWithVibrate(enabled: true);
    final engine = GameEngine(random: Random(1));
    engine.start();
    final startCol = engine.pieceController.piece!.anchorCol;

    await swipeSideways(
      GestureHandler(engine, () => 30.0, haptics: HapticsService(storage)),
    );

    engine.tick(1 / 60);
    expect(
      engine.pieceController.piece!.anchorCol,
      startCol + 1,
      reason: 'the swipe has to actually move the piece for this to mean much',
    );
    expect(calls, isNotEmpty);
  });

  test('the same shift stays silent when vibration is off', () async {
    final calls = recordHaptics();
    final storage = await storageWithVibrate(enabled: false);
    final engine = GameEngine(random: Random(1));
    engine.start();
    final startCol = engine.pieceController.piece!.anchorCol;

    await swipeSideways(
      GestureHandler(engine, () => 30.0, haptics: HapticsService(storage)),
    );

    engine.tick(1 / 60);
    expect(
      engine.pieceController.piece!.anchorCol,
      startCol + 1,
      reason: 'the piece still moves — only the buzz is suppressed',
    );
    expect(calls, isEmpty);
  });

  test('the switch is read per call, not captured at construction', () async {
    final calls = recordHaptics();
    SharedPreferences.setMockInitialValues({'vibrate_enabled': false});
    final prefs = await SharedPreferences.getInstance();
    final haptics = HapticsService(StorageService(prefs));

    haptics.light();
    expect(calls, isEmpty);

    // Flipping it from the pause menu has to land on the next lock.
    await prefs.setBool('vibrate_enabled', true);
    haptics.light();
    expect(calls, hasLength(1));
  });
}
