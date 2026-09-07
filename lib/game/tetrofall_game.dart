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
import 'engine/events.dart';
import 'engine/game_engine.dart';
import 'input/gesture_handler.dart';
import 'render/board_component.dart';

class TetrofallGame extends FlameGame {
  TetrofallGame({
    this.theme = ThemeDefinition.classicWood,
    required this.storage,
    this.feedbackEnabled = true,
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

  /// Whether this game may reach the player's senses at all.
  ///
  /// The menu's attract-mode demo runs a full engine behind the buttons and
  /// is decoration rather than play: it stays silent so the main menu isn't
  /// a drum solo, and — the reason this covers haptics too — it must not
  /// sit there buzzing a phone nobody is touching.
  final bool feedbackEnabled;

  late final AudioService _audio = AudioService(storage);
  late final HapticsService _haptics = HapticsService(storage);

  final GameEngine engine;
  late final GestureHandler gestureHandler;

  BoardComponent? _board;

  BoardComponent get board => _board!;

  /// The board if Flame has loaded one yet. Callers that can run before
  /// [onLoad] — the tutorial rigs a board from the widget's `initState` — use
  /// this rather than asserting one into existence.
  BoardComponent? get boardOrNull => _board;

  bool showGhost = true;

  final ValueNotifier<bool> pausedNotifier = ValueNotifier(false);

  @override
  void pauseEngine() {
    gestureHandler.reset();
    super.pauseEngine();
    pausedNotifier.value = true;
  }

  /// Stops Flame's clock **without** flipping [pausedNotifier], so no pause
  /// overlay appears over the frozen frame.
  ///
  /// Capture-only (`tools/capture/main.dart`): the shatter and the ripple
  /// cascade are the best-looking moments in the game and are three frames
  /// long, so the store harness runs them and then freezes mid-flight to
  /// photograph one. [pauseEngine] can't do this — it is the player-facing
  /// pause, and raising the overlay is the whole point of it.
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
    // `resetForRestart` wipes the shards mid-flight, so a crush still waiting
    // on its crack delay would land over an empty board.
    _cancelPendingSfx();
    if (paused) resumeEngine();
    engine.start(initialElapsed: _adaptiveStartElapsed);
  }

  /// Watch-Ad-To-Continue from the game-over overlay (game.md §1.9).
  void continueAfterAd() {
    board.resetForRestart();
    gestureHandler.reset();
    _cancelPendingSfx();
    if (paused) resumeEngine();
    engine.continueAfterAd();
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
      // The row cracks for `crackHold` before it actually bursts apart, so
      // the crush lands with the shards rather than with the cracks.
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

  /// Note what is deliberately *not* here: the feedback listener registered in
  /// the constructor.
  ///
  /// Flame runs this whenever a `GameWidget` holding this game is torn down,
  /// which is not the same thing as the game being finished — the widget can
  /// be reinflated over a game that is still mid-run, and Flame does not
  /// re-run `onLoad` (or anything else that could re-register) when it comes
  /// back. Unhooking here left the run playing on in silence until the player
  /// started a new one. The listener instead lives as long as the game, which
  /// leaks nothing: [engine] is built by this game's own constructor and held
  /// by nothing else, so the pair is collected together.
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
