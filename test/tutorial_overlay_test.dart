import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/game/tetrofall_game.dart';
import 'package:tetrofall/services/storage_service.dart';
import 'package:tetrofall/ui/screens/tutorial/tutorial_controller.dart';
import 'package:tetrofall/ui/screens/tutorial/tutorial_overlay.dart';

/// Layout and hit-testing for the tutorial's chrome, pumped in a bare `Stack`
/// that mirrors gameplay's without dragging in Flame, audio or ads.
///
/// The first test earns its keep: `Positioned` must be a *direct* child of a
/// `Stack`, and burying one under a `ListenableBuilder` throws
/// `Incorrect use of ParentDataWidget` at layout time — on a device, on the
/// player's first ever PLAY press.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const boardSize = Size(270, 480);

  Future<TutorialController> controller(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.load();
    final game = TetrofallGame(storage: storage, feedbackEnabled: false);
    game.engine.start();
    final c = TutorialController(
      game: game,
      storage: storage,
      onFinished: () {},
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Gameplay's `Stack`: a body with the board in it, then the overlay.
  Future<void> pumpOverlay(
    WidgetTester tester,
    TutorialController c,
    GlobalKey boardKey,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Center(
                child: SizedBox.fromSize(
                  size: boardSize,
                  child: DecoratedBox(
                    key: boardKey,
                    decoration: const BoxDecoration(color: Colors.black12),
                  ),
                ),
              ),
              TutorialOverlay(controller: c, boardKey: boardKey),
            ],
          ),
        ),
      ),
    );
    // Two frames: the first lays the board out, the post-frame measurement
    // lands, and the second builds the coach layer against it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('the overlay lays out legally inside gameplay\'s Stack', (
    tester,
  ) async {
    final c = await controller(tester);
    await pumpOverlay(tester, c, GlobalKey());

    expect(tester.takeException(), isNull);
    expect(find.text('HOW TO PLAY'), findsOneWidget);
  });

  testWidgets('a coach caption stays inside the board', (tester) async {
    // The board rect is the constraint that keeps the caption clear of the
    // banner ad beneath it. Overlaying an AdMob banner is a policy violation,
    // not just untidy.
    final c = await controller(tester);
    final boardKey = GlobalKey();
    await pumpOverlay(tester, c, boardKey);

    c.advance(); // intro -> move, a coach step
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
    expect(find.text('Swipe left or right to move the piece.'), findsOneWidget);

    final board = tester.getRect(find.byKey(boardKey));
    final caption = tester.getRect(
      find.text('Swipe left or right to move the piece.'),
    );
    expect(
      board.contains(caption.topLeft) && board.contains(caption.bottomRight),
      isTrue,
      reason: 'caption $caption escaped the board $board',
    );
  });

  testWidgets('a coach step leaves the board reachable', (tester) async {
    final c = await controller(tester);
    final boardKey = GlobalKey();
    await pumpOverlay(tester, c, boardKey);

    c.advance(); // intro -> move
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // The point of the whole coach mode: a touch on the open board must find
    // the board, not the tutorial. Anything opaque spanning the board here
    // would swallow the gestures the step is teaching.
    final board = tester.getRect(find.byKey(boardKey));
    final hit = tester.hitTestOnBinding(board.topCenter + const Offset(0, 8));
    expect(
      find.byKey(boardKey).evaluate().single.renderObject,
      isIn(hit.path.map((e) => e.target)),
      reason: 'a touch on the open board must reach the board itself',
    );
  });

  testWidgets('Skip is reachable on every coach step', (tester) async {
    final c = await controller(tester);
    await pumpOverlay(tester, c, GlobalKey());

    c.advance();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(c.isFinished, isTrue);
  });
}
