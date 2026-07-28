import 'package:flame/components.dart' show HasTimeScale;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../models/theme_definition.dart';
import 'engine/booster_engine.dart';
import 'engine/cell.dart';
import 'engine/game_engine.dart';
import 'input/gesture_handler.dart';
import 'render/board_component.dart';
import 'render/wood_background.dart';

/// FlameGame root. Owns the pure-Dart [GameEngine] and ticks it every
/// frame; the render tree only reads engine state (§3.1).
///
/// Mixes in [HasTimeScale] for Phase 5's global time-scale debug slider
/// (0.1x-1x) — inspecting the shatter sequence frame by frame. Shipping
/// gameplay never touches [timeScale]; it stays 1.0 outside the debug tools.
class TetrofallGame extends FlameGame with HasTimeScale {
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

  /// Phase 7's block-type stamper (debug only): when set, taps on the
  /// board place this type directly instead of reaching the gameplay
  /// gesture handler — see `DebugOverlay` and `app.dart`.
  BlockType? debugStampType;

  /// Converts a screen-space tap to a grid cell and stamps [debugStampType]
  /// there — see `BoardComponent.cellFromScreen`.
  void debugStampAt(Offset screenPos) {
    final type = debugStampType;
    if (type == null) return;
    final cell = board.cellFromScreen(Vector2(screenPos.dx, screenPos.dy));
    if (cell == null) return;
    engine.grid.set(cell.$1, cell.$2, Cell(type));
  }

  /// Phase 8: updates the pre-commit highlight for the armed booster as
  /// the player's finger moves, without destroying anything yet (§1.9).
  void previewBoosterAt(Offset screenPos) {
    final type = engine.boosterEngine.armed;
    if (type == null) return;
    final cell = board.cellFromScreen(Vector2(screenPos.dx, screenPos.dy));
    if (cell == null) {
      board.boosterTargetOverlay.hide();
      return;
    }
    board.boosterTargetOverlay.show(
      BoosterEngine.targetCells(type, cell.$1, cell.$2, engine.grid),
    );
  }

  /// Phase 8: commits the armed booster at the released position, or
  /// disarms cleanly (no charge spent) if the release misses the board.
  void commitBoosterAt(Offset screenPos) {
    board.boosterTargetOverlay.hide();
    final cell = board.cellFromScreen(Vector2(screenPos.dx, screenPos.dy));
    if (cell == null) {
      engine.disarmBooster();
      return;
    }
    engine.tapBoosterTarget(cell.$1, cell.$2);
  }

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
    super.update(dt); // scales the whole child tree by [timeScale] (HasTimeScale)
    final scaledDt = dt * timeScale;
    gestureHandler.update(scaledDt);
    engine.tick(scaledDt);
  }
}
