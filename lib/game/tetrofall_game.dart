import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../models/theme_definition.dart';
import 'engine/booster_engine.dart';
import 'engine/game_engine.dart';
import 'input/gesture_handler.dart';
import 'render/board_component.dart';
import 'render/wood_background.dart';

/// FlameGame root. Owns the pure-Dart [GameEngine] and ticks it every
/// frame; the render tree only reads engine state (§3.1).
class TetrofallGame extends FlameGame {
  TetrofallGame({this.theme = ThemeDefinition.classicWood})
    : engine = GameEngine() {
    gestureHandler = GestureHandler(engine, () => _board?.cellSize ?? 0);
  }

  final ThemeDefinition theme;

  // Created in the constructor, not onLoad: app.dart wires the Flutter
  // `Listener` to `gestureHandler` synchronously at build time, before
  // onLoad's async `add()` calls would otherwise have run.
  final GameEngine engine;
  late final GestureHandler gestureHandler;

  BoardComponent? _board;

  /// Set once [onLoad] finishes. Nullable until then so
  /// [gestureHandler]'s cell-relative thresholds (I2) have something safe
  /// to fall back on in the brief window before the board's first layout.
  BoardComponent get board => _board!;

  /// Temporary in-memory toggle — the real Settings row lands in Phase 10.
  /// Enabled by default per §1.2.
  bool showGhost = true;

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
    final board = BoardComponent(engine: engine, theme: theme);
    _board = board;
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
