import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/theme_definition.dart';
import '../services/storage_service.dart';
import 'config/difficulty.dart';
import 'engine/events.dart';
import 'engine/game_engine.dart';
import 'input/gesture_handler.dart';
import 'render/board_component.dart';

class TetrofallGame extends FlameGame {
  TetrofallGame({
    this.theme = ThemeDefinition.classicWood,
    required this.storage,
  }) : engine = GameEngine() {
    gestureHandler = GestureHandler(engine, () => _board?.cellSize ?? 0);
    engine.addEventListener(_onHapticEvent);
  }

  final ThemeDefinition theme;

  final StorageService storage;

  final GameEngine engine;
  late final GestureHandler gestureHandler;

  BoardComponent? _board;

  BoardComponent get board => _board!;

  bool showGhost = true;

  final ValueNotifier<bool> pausedNotifier = ValueNotifier(false);

  @override
  void pauseEngine() {
    gestureHandler.reset();
    super.pauseEngine();
    pausedNotifier.value = true;
  }

  @override
  void resumeEngine() {
    super.resumeEngine();
    pausedNotifier.value = false;
  }

  void restart() {
    board.resetForRestart();
    gestureHandler.reset();
    if (paused) resumeEngine();
    engine.start(initialElapsed: _adaptiveStartElapsed);
  }

  /// Watch-Ad-To-Continue from the game-over overlay (game.md §1.9).
  void continueAfterAd() {
    board.resetForRestart();
    gestureHandler.reset();
    if (paused) resumeEngine();
    engine.continueAfterAd();
  }

  Duration get _adaptiveStartElapsed => storage.adaptiveStartSpeedEnabled
      ? Difficulty.adaptiveStartElapsed(storage.bestScore)
      : Duration.zero;

  void _onHapticEvent(GameEvent event) {
    if (event is PieceLockedEvent) {
      HapticFeedback.lightImpact();
    } else if (event is RowsClearedEvent) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    final board = BoardComponent(engine: engine, theme: theme);
    _board = board;
    await add(board);

    engine.start(initialElapsed: _adaptiveStartElapsed);
  }

  /// The engine must advance *before* the component tree, and the order is
  /// load-bearing rather than arbitrary.
  ///
  /// Flame runs `update` for every component and only then `render`, so a
  /// component that reads engine state inside `render` sees the state as of
  /// the end of this method, while one that reads it inside `update` sees
  /// whatever it was when the component's turn came. With the engine ticking
  /// last those two disagreed: `BoardComponent` positioned the scrolling
  /// content layer from the pre-tick `riseProgress`, but
  /// `BoardBlocksComponent` reads the grid straight out of the engine at
  /// render time. On an ordinary frame they differ by one frame of rise —
  /// invisible. On the frame a rise commits, `riseProgress` has just wrapped
  /// from ~1 back to ~0 *and* every settled block has moved up a row, so the
  /// board drew a full cell too high for exactly that frame and dropped back
  /// on the next one: the whole stack visibly jumping up and falling back,
  /// once per rise interval.
  @override
  void update(double dt) {
    engine.tick(dt);
    super.update(dt);
  }
}
