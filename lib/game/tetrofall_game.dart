import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/theme_definition.dart';
import 'engine/events.dart';
import 'engine/game_engine.dart';
import 'input/gesture_handler.dart';
import 'render/board_component.dart';

/// FlameGame root. Owns the pure-Dart [GameEngine] and ticks it every
/// frame; the render tree only reads engine state (§3.1).
class TetrofallGame extends FlameGame {
  TetrofallGame({this.theme = ThemeDefinition.classicWood, int initialCoins = 0})
    : engine = GameEngine() {
    gestureHandler = GestureHandler(engine, () => _board?.cellSize ?? 0);
    // Coins are a persistent wallet, not a per-run stat (§8) — seeded here
    // rather than in `GameEngine` itself, which stays pure Dart with no
    // knowledge of `StorageService`.
    engine.scoring.coins = initialCoins;
    engine.addEventListener(_onHapticEvent);
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

  /// Mirrors [paused] so Flutter widgets outside the Flame tree (the pause
  /// scrim, §6.1) can react to pause state without polling — Flame's own
  /// `paused` field is a plain getter/setter, not observable on its own.
  final ValueNotifier<bool> pausedNotifier = ValueNotifier(false);

  @override
  void pauseEngine() {
    // A swipe that's mid-flight when pause is hit would otherwise leave
    // `GestureHandler` in a stale state — the Flutter `Listener` in
    // app.dart keeps forwarding pointer events while paused, but is told
    // to ignore them, so without this reset the in-progress gesture would
    // just silently hang rather than resuming cleanly (§6.1).
    gestureHandler.reset();
    super.pauseEngine();
    pausedNotifier.value = true;
  }

  @override
  void resumeEngine() {
    super.resumeEngine();
    pausedNotifier.value = false;
  }

  /// Starts a fresh run after game-over or a mid-run restart (§4, §6.1):
  /// clears lingering render-only animation state (shatter shards, an
  /// in-flight cascade, the combo banner) that would otherwise carry over
  /// from the run that just ended, resets any in-progress gesture, resumes
  /// if paused, then hands off to [GameEngine.start].
  void restart() {
    board.resetForRestart();
    gestureHandler.reset();
    if (paused) resumeEngine();
    engine.start();
  }

  /// Tactile confirmation for the two silent, non-gesture-driven moments
  /// (§6.6) — a piece locking (gravity can trigger this with no touch at
  /// all) and a clear resolving.
  void _onHapticEvent(GameEvent event) {
    if (event is PieceLockedEvent) {
      HapticFeedback.lightImpact();
    } else if (event is RowsClearedEvent) {
      HapticFeedback.mediumImpact();
    }
  }

  // Transparent so the Flutter-side bg_wood backdrop (app.dart) shows
  // through any sub-pixel slack around the board inside its frame.
  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    final board = BoardComponent(engine: engine, theme: theme);
    _board = board;
    await add(board);

    engine.start();
  }

  @override
  void update(double dt) {
    super.update(dt);
    engine.tick(dt);
  }
}
