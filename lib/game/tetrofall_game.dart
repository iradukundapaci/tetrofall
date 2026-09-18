import 'dart:async';
import 'dart:math' show Random;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../models/theme_definition.dart';
import '../services/audio_service.dart';
import '../services/clear_skies_service.dart';
import '../services/haptics_service.dart';
import '../services/storage_service.dart';
import 'boosters/booster_run_state.dart';
import 'config/difficulty.dart';
import 'config/motion.dart';
import 'engine/events.dart';
import 'engine/game_engine.dart';
import 'input/booster_aim_handler.dart';
import 'input/gesture_handler.dart';
import 'render/board_component.dart';

class TetrofallGame extends FlameGame {
  TetrofallGame({
    this.theme = ThemeDefinition.classicWood,
    required this.storage,
    this.clearSkies,
    this.feedbackEnabled = true,
    this.autoStart = true,
    Random? random,
  }) : engine = GameEngine(random: random) {
    gestureHandler = GestureHandler(
      engine,
      () => _board?.cellSize ?? 0,
      haptics: feedbackEnabled ? _haptics : null,
    );
    boosterAimHandler = BoosterAimHandler(
      state: boosters,
      boardProvider: () => _board,
    );
    engine.addEventListener(_onFeedbackEvent);
  }

  final ThemeDefinition theme;

  final StorageService storage;

  /// The player's ad-free balance, drained by [update] while a run is in play.
  ///
  /// Null for games that are not the player's run — the menu's attract-mode
  /// demo and the tutorial — so nothing can spend the balance on a board
  /// nobody is playing. That is not a nicety: the menu builds a full engine
  /// behind its buttons, and Flame ticks it the whole time the menu is open.
  final ClearSkiesService? clearSkies;

  /// Whether this game may reach the player's senses at all.
  ///
  /// The menu's attract-mode demo runs a full engine behind the buttons and
  /// is decoration rather than play: it stays silent so the main menu isn't
  /// a drum solo, and — the reason this covers haptics too — it must not
  /// sit there buzzing a phone nobody is touching.
  final bool feedbackEnabled;

  /// Whether the run begins the moment the board loads.
  ///
  /// False when a loadout roll is going to open over the board: the engine
  /// sits in [GamePhase.ready] with the arena already laid out behind the
  /// overlay, and [startRun] is called when it closes (`boosters.md` §3.1).
  final bool autoStart;

  late final AudioService _audio = AudioService(storage);
  late final HapticsService _haptics = HapticsService(storage);

  final GameEngine engine;

  /// The run's four boosters, their charges and whatever is currently armed
  /// (`boosters.md` §4). Always present, never populated until a loadout is
  /// handed to it — the tutorial run and the menu's demo simply never call
  /// `beginRun`, which is what "no bar in the tutorial" comes down to (§4.1).
  late final BoosterRunState boosters = BoosterRunState(engine: engine);

  late final GestureHandler gestureHandler;
  late final BoosterAimHandler boosterAimHandler;

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
    // Pause cancels aiming and keeps the charge (§4.7).
    boosterAimHandler.reset();
    boosters.cancelAim(BoosterCancelReason.pause);
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

  void restart() => startRun();

  /// Opens a run. Safe to call before the board has loaded, which is what the
  /// roll overlay needs: it can close on the very first frame.
  void startRun() {
    _board?.resetForRestart();
    gestureHandler.reset();
    boosterAimHandler.reset();
    boosters.endRun();
    // `resetForRestart` wipes the shards mid-flight, so a crush still waiting
    // on its crack delay would land over an empty board.
    _cancelPendingSfx();
    if (paused) resumeEngine();
    engine.start(initialElapsed: _adaptiveStartElapsed);
  }

  /// Stops the clock **without** raising the pause overlay.
  ///
  /// Two overlays need this. A rewarded ad sheet freezes the run the way a
  /// pause does, because the app is about to lose focus to a video
  /// (`boosters.md` §4.9 rule 2); and the loadout roll opens over the board a
  /// finished run is still standing on. Neither is a pause the player asked
  /// for, so neither may raise the pause menu.
  void holdForOverlay() {
    gestureHandler.reset();
    boosterAimHandler.reset();
    if (!paused) super.pauseEngine();
  }

  void releaseOverlayHold() {
    if (paused && !pausedNotifier.value) super.resumeEngine();
  }

  /// Watch-Ad-To-Continue from the game-over overlay (game.md §1.9).
  void continueAfterAd() {
    board.resetForRestart();
    gestureHandler.reset();
    boosterAimHandler.reset();
    // A rewarded continue keeps the loadout and any unused charges, and
    // pointedly does not refill the spent ones — a booster comes back only
    // through its own offer (`boosters.md` §4.7).
    boosters.cancelAim(BoosterCancelReason.pause);
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
    } else if (event is BoosterFiredEvent) {
      if (feedbackEnabled) _haptics.medium();
      _playSfx(Sfx.woodCrush);
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
    final board = BoardComponent(
      engine: engine,
      boosters: boosters,
      theme: theme,
    );
    _board = board;
    await add(board);

    if (autoStart) engine.start(initialElapsed: _adaptiveStartElapsed);
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
    boosters.tick(dt);
    _tickClearSkies(dt);
    final armed = boosters.takePendingArmed();
    if (armed != null) {
      if (armed.type != null) _playSfx(Sfx.blockSpawn);
      if (feedbackEnabled && armed.type != null) _haptics.selection();
    }
    super.update(dt);
  }

  /// Burns ad-free balance, but only for time the player actually spent
  /// playing.
  ///
  /// Flame stops calling [update] whenever the clock is stopped, which covers
  /// the pause overlay, [holdForOverlay] (ad sheets and the loadout roll) and
  /// [freezeForCapture] for free. What it does not cover is the two states
  /// where the engine is idle but the clock is still running: [GamePhase.ready]
  /// before the first piece, and [GamePhase.gameOver] for as long as the
  /// overlay sits there. Hence the phase test rather than a bare `update`.
  void _tickClearSkies(double dt) {
    final balance = clearSkies;
    if (balance == null) return;
    if (engine.phase != GamePhase.playing &&
        engine.phase != GamePhase.resolving) {
      return;
    }
    balance.tick(dt);
  }

  /// Board pointers go to the aim handler while a booster is armed, and to
  /// the normal gesture handler otherwise. Swipes and taps must not move or
  /// rotate the piece while aiming (`boosters.md` §4.4).
  void onBoardPointerDown(PointerDownEvent event) {
    if (boosterAimHandler.isAiming) {
      boosterAimHandler.onPointerDown(event);
    } else {
      gestureHandler.onPointerDown(event);
    }
  }

  void onBoardPointerMove(PointerMoveEvent event) {
    if (boosterAimHandler.isAiming) {
      boosterAimHandler.onPointerMove(event);
    } else {
      gestureHandler.onPointerMove(event);
    }
  }

  void onBoardPointerUp(PointerEvent event) {
    if (boosterAimHandler.isAiming) {
      boosterAimHandler.onPointerUp(event);
    } else {
      gestureHandler.onPointerUp(event);
    }
  }

  void onBoardPointerCancel(PointerEvent event) {
    boosterAimHandler.onPointerCancel(event);
    gestureHandler.onPointerCancel(event);
  }
}
