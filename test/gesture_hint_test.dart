import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/ui/screens/tutorial/gesture_hint.dart';
import 'package:tetrofall/ui/screens/tutorial/tutorial_controller.dart';

/// The hint's [AnimationController] must exist by the time the widget is torn
/// down. A `none` step builds a `SizedBox.shrink()` without ever touching the
/// controller, so a lazily-initialised one would first be constructed inside
/// `dispose()` — where `AnimationController(vsync: this)` asks a defunct
/// element for `TickerMode` and throws.
void main() {
  Future<void> pumpThenUnmount(WidgetTester tester, TutorialHint hint) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: GestureHint(hint: hint)))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  }

  testWidgets('disposes cleanly when it never animated', (tester) async {
    await pumpThenUnmount(tester, TutorialHint.none);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes cleanly after animating', (tester) async {
    await pumpThenUnmount(tester, TutorialHint.tap);
    expect(tester.takeException(), isNull);
  });
}
