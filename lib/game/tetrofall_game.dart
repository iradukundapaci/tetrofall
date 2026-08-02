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

  @override
  void update(double dt) {
    super.update(dt);
    engine.tick(dt);
  }
}
