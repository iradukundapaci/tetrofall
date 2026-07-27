import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../models/theme_definition.dart';
import 'engine/game_engine.dart';
import 'input/gesture_handler.dart';
import 'render/board_component.dart';
import 'render/wood_background.dart';

/// FlameGame root. Owns the pure-Dart [GameEngine] and ticks it every
/// frame; the render tree only reads engine state (§3.1).
class TetrofallGame extends FlameGame {
  TetrofallGame({this.theme = ThemeDefinition.classicWood})
    : engine = GameEngine() {
    gestureHandler = GestureHandler(engine);
  }

  final ThemeDefinition theme;

  // Created in the constructor, not onLoad: app.dart wires the Flutter
  // `Listener` to `gestureHandler` synchronously at build time, before
  // onLoad's async `add()` calls would otherwise have run.
  final GameEngine engine;
  late final GestureHandler gestureHandler;

  late final BoardComponent board;

  /// Temporary in-memory toggle — the real Settings row lands in Phase 10.
  /// Enabled by default per §1.2.
  bool showGhost = true;

  @override
  Color backgroundColor() => theme.background;

  @override
  Future<void> onLoad() async {
    await add(WoodBackground());
    board = BoardComponent(engine: engine, theme: theme);
    await add(board);

    engine.start();
  }

  @override
  void update(double dt) {
    super.update(dt);
    gestureHandler.update(dt);
    engine.tick(dt);
  }
}
