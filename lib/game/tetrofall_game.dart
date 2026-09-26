import 'dart:async';
import 'dart:math' show Random;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../models/theme_definition.dart';
import '../services/audio_service.dart';
import '../services/haptics_service.dart';
import '../services/storage_service.dart';
import 'config/difficulty.dart';
import 'config/motion.dart';
import 'config/run_config.dart';
import 'engine/events.dart';
import 'engine/game_engine.dart';
import 'input/gesture_handler.dart';
import 'render/board_component.dart';

class TetrofallGame extends FlameGame {
  TetrofallGame({
    this.theme = ThemeDefinition.classicWood,
    required this.storage,
    this.feedbackEnabled = true,
    this.newRunConfig,
    Random? random,
  }) : engine = GameEngine(random: random) {
    gestureHandler = GestureHandler(
      engine,
      () => _board?.cellSize ?? 0,
      haptics: feedbackEnabled ? _haptics : null,
    );
    engine.addEventListener(_onFeedbackEvent);
  }

  final ThemeDefinition theme;

  final StorageService storage;

  /// False for the menu demo, which must stay silent and not buzz the phone.
  final bool feedbackEnabled;

  /// Builds the [RunConfig] as each run starts, so player state is read fresh.
  /// Null for the menu demo, which runs the plain game.
  final RunConfig Function()? newRunConfig;

  late final AudioService _audio = AudioService(storage);
  late final HapticsService _haptics = HapticsService(storage);

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

  /// Stops Flame's clock without flipping [pausedNotifier], so no pause
  /// overlay covers the frame. Capture-only (`tools/capture/main.dart`).
  void freezeForCapture() {
    super.pauseEngine();
  }

  @override
  void resumeEngine() {
    super.resumeEngine();
    pausedNotifier.value = false;
  }

  void restart() {
    board.resetForRestart();
    gestureHandler.reset();
    // Shards are wiped mid-flight, so a crush still waiting on its crack delay
    // would land over an empty board.
    _cancelPendingSfx();
    if (paused) resumeEngine();
    _startRun();
  }

  void continueAfterAd() {
    board.resetForRestart();
    gestureHandler.reset();
    _cancelPendingSfx();
    if (paused) resumeEngine();
    engine.continueAfterAd();
  }

  void _startRun() {
    final builder = newRunConfig;
    if (builder == null) {
      engine.start(initialElapsed: _adaptiveStartElapsed);
    } else {
      engine.start(config: builder());
    }
  }

  Duration get _adaptiveStartElapsed => storage.adaptiveStartSpeedEnabled
      ? Difficulty.adaptiveStartElapsed(storage.bestScore)
      : Duration.zero;

  final Set<Timer> _pendingSfx = {};

  void _onFeedbackEvent(GameEvent event) {
    if (event is PieceSpawnedEvent) {
      _playSfx(Sfx.blockSpawn);
    } else if (event is PieceLockedEvent) {
      if (feedbackEnabled) _haptics.light();
      _playSfx(Sfx.blockSettle);
    } else if (event is RowsClearedEvent) {
      if (feedbackEnabled) _haptics.medium();
      // The crush lands with the shards, after the crack hold.
      _playSfx(Sfx.woodCrush, after: Motion.crackHold);
    }
  }

  void _playSfx(Sfx sfx, {Duration? after}) {
    if (!feedbackEnabled) return;
    if (after == null) {
      _audio.play(sfx);
      return;
    }
    late final Timer timer;
    timer = Timer(after, () {
      _pendingSfx.remove(timer);
      _audio.play(sfx);
    });
    _pendingSfx.add(timer);
  }

  void _cancelPendingSfx() {
    for (final timer in _pendingSfx) {
      timer.cancel();
    }
    _pendingSfx.clear();
  }

  /// Deliberately does not unhook the feedback listener from the constructor:
  /// Flame calls this when a `GameWidget` is torn down, but the widget can be
  /// reinflated over a live run without re-running `onLoad`, which would leave
  /// it silent.
  @override
  void onRemove() {
    _cancelPendingSfx();
    super.onRemove();
  }

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    final board = BoardComponent(engine: engine, theme: theme);
    _board = board;
    await add(board);

    _startRun();
  }

  /// The engine must tick before the component tree. `BoardComponent` reads
  /// `riseProgress` in `update` but `BoardBlocksComponent` reads the grid at
  /// render time; ticking the engine last made them disagree on the frame a
  /// rise commits, so the stack jumped up a cell once per rise.
  @override
  void update(double dt) {
    engine.tick(dt);
    super.update(dt);
  }
}
