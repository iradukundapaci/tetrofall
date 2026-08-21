import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../game/config/board_config.dart';
import '../../game/config/difficulty.dart';
import '../../game/engine/events.dart';
import '../../game/render/score_hud.dart';
import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/music_service.dart';
import '../../services/run_tracker.dart';
import '../../services/storage_service.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/banner_ad_slot.dart';
import 'confirm_quit_overlay.dart';
import 'game_over_overlay.dart';
import 'pause_overlay.dart';
import 'tutorial/tutorial_controller.dart';
import 'tutorial/tutorial_overlay.dart';

class GameplayScreen extends StatefulWidget {
  const GameplayScreen({
    super.key,
    required this.storage,
    required this.ads,
    this.startTutorial = false,
    this.onGameCreated,
  });

  final StorageService storage;
  final AdsService ads;

  /// Runs the first-run coached tutorial over this screen before handing off
  /// to a normal scored run. Set by the main menu on the very first PLAY.
  final bool startTutorial;

  /// Capture-only seam (android_release_plan.md §4.7). Fires once with the
  /// live game so `tools/capture/main.dart` can seed a hand-authored board —
  /// the money-shot states are three frames long and cannot be reached by
  /// playing. Always null in the shipped app: nothing in `lib/` passes it, and
  /// the capture harness is a separate entrypoint that the release build never
  /// compiles.
  final void Function(TetrofallGame game)? onGameCreated;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> {
  late final TetrofallGame _game = TetrofallGame(storage: widget.storage)
    ..showGhost = widget.storage.ghostPieceEnabled;
  GameOverReason? _gameOverReason;
  Duration _runElapsedAtGameOver = Duration.zero;

  bool _confirmingQuit = false;

  final RunTracker _tracker = RunTracker();

  /// Non-null only for the duration of the first-run tutorial.
  TutorialController? _tutorial;

  /// Lets [TutorialOverlay] read the board's real on-screen rect so its
  /// caption stays inside the board — clear of the HUD above and, more to the
  /// point, clear of the banner ad below.
  final GlobalKey _boardKey = GlobalKey();

  /// Whether the run was already paused when the quit prompt opened, so
  /// "Keep Playing" returns to the pause modal instead of resuming a game
  /// the player deliberately paused.
  bool _wasPausedBeforeConfirm = false;

  @override
  void initState() {
    super.initState();
    _game.engine.addEventListener(_onEngineEvent);
    AnalyticsService.design('screen:gameplay');
    // The menu loop keeps playing if there's no gameplay track to swap to.
    MusicService(widget.storage).play(MusicTrack.gameplay);
    if (widget.startTutorial) {
      _tutorial = TutorialController(
        game: _game,
        storage: widget.storage,
        onFinished: _finishTutorial,
      )..addListener(_onTutorialChanged);
    }
    // Coaching is not a run. The tutorial opens its own run when it hands off
    // in [_finishTutorial], which is the same boundary [AdsService] already
    // draws with `notifyRunEnded`.
    if (!widget.startTutorial) _startTrackedRun();
    final onGameCreated = widget.onGameCreated;
    if (onGameCreated != null) onGameCreated(_game);
  }

  /// Opens an analytics run against the head start the game is about to take.
  /// Mirrors [TetrofallGame]'s own `_adaptiveStartElapsed` — the value is only
  /// reported, never used to drive anything.
  void _startTrackedRun() {
    _tracker.runStarted(
      initialElapsed: widget.storage.adaptiveStartSpeedEnabled
          ? Difficulty.adaptiveStartElapsed(widget.storage.bestScore)
          : Duration.zero,
      // Read now, before the run overwrites it — ScoreHud saves a new best the
      // moment it is passed, so by game over `storage.bestScore` is this run.
      bestBefore: widget.storage.bestScore,
    );
  }

  /// Closes the analytics run out. Idempotent inside [RunTracker], so the
  /// game-over path and the quit path can both reach it.
  void _endTrackedRun(String reason, Duration elapsed) {
    final scoring = _game.engine.scoring;
    _tracker.runEnded(
      reason: reason,
      elapsed: elapsed,
      score: scoring.score,
      maxChain: scoring.maxChain,
      blocksDestroyed: scoring.totalBlocksDestroyed,
    );
  }

  @override
  void dispose() {
    _game.engine.removeEventListener(_onEngineEvent);
    _tutorial?.dispose();
    super.dispose();
  }

  /// Hands off from the tutorial into the real run. The board is restarted so
  /// neither the rigged row nor the practice drops can leak into a scored
  /// game — and pointedly *without* [AdsService.notifyRunEnded], because the
  /// tutorial is not a run the interstitial cadence should count.
  /// The whole screen rebuilds on a step change, not just the overlay: the
  /// `dimmed` flag below is derived from the step, and a stale one would leave
  /// the board blurred and `IgnorePointer`-ed under a card asking for a swipe.
  void _onTutorialChanged() {
    if (mounted) setState(() {});
  }

  void _finishTutorial() {
    final tutorial = _tutorial;
    if (tutorial == null) return;
    _dropTutorial(tutorial);
    _game.restart();
    _startTrackedRun();
  }

  /// Detaches the controller and schedules its disposal for after the frame
  /// that drops it from the tree, so the overlay is never left listening to a
  /// dead notifier mid-build.
  void _dropTutorial(TutorialController tutorial) {
    tutorial.removeListener(_onTutorialChanged);
    if (mounted) {
      setState(() => _tutorial = null);
    } else {
      _tutorial = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => tutorial.dispose());
  }

  void _onEngineEvent(GameEvent event) {
    _tracker.onEvent(event);
    if (event is GameOverEvent) {
      _runElapsedAtGameOver = Duration(
        milliseconds: (_game.engine.riseController.elapsed * 1000).round(),
      );
      // A run that ends under the tutorial hands the screen straight to the
      // game-over overlay; the controller releases the engine on its way out
      // rather than asking for the usual hand-off restart.
      final tutorial = _tutorial;
      if (tutorial != null) {
        tutorial.abandon();
        _dropTutorial(tutorial);
      }
      _endTrackedRun(event.reason.name, _runElapsedAtGameOver);
      // Reported here rather than from `build`, which reruns on every pause
      // and every rebuild behind the overlay.
      if (widget.ads.isRewardedContinueReady &&
          !_game.engine.hasUsedContinueThisRun) {
        AnalyticsService.design('continue:offered');
      }
      setState(() {
        _gameOverReason = event.reason;
        _confirmingQuit = false;
      });
    }
  }

  void _resumeFromPause() {
    AnalyticsService.design('pause:resume');
    _game.resumeEngine();
  }

  void _restart() {
    // Reached from the pause menu as well as from game over, and only the
    // latter has already closed the run out. A pause-menu restart abandons a
    // live run, which is worth its own reason: it is the one run ending that
    // says the player chose to walk away from a board rather than lost it.
    if (_tracker.isRunning) {
      _endTrackedRun(
        'restart',
        Duration(
          milliseconds: (_game.engine.riseController.elapsed * 1000).round(),
        ),
      );
    }
    _game.restart();
    _startTrackedRun();
    setState(() => _gameOverReason = null);
  }

  /// Freezes the run behind the prompt so the board can't advance (or the
  /// player top out) while they decide.
  void _requestQuit() {
    if (_confirmingQuit) return;
    AnalyticsService.design('quit:prompt');
    _wasPausedBeforeConfirm = _game.paused;
    if (!_game.paused) _game.pauseEngine();
    setState(() => _confirmingQuit = true);
  }

  void _cancelQuit() {
    AnalyticsService.design('quit:cancel');
    setState(() => _confirmingQuit = false);
    if (!_wasPausedBeforeConfirm) _game.resumeEngine();
  }

  void _confirmQuit() {
    AnalyticsService.design('quit:confirm');
    setState(() => _confirmingQuit = false);
    _goHome();
  }

  void _restartAfterGameOver() {
    AnalyticsService.design('run:again');
    widget.ads.notifyRunEnded(_runElapsedAtGameOver);
    _restart();
  }

  void _goHome() {
    // Quitting mid-run still counts toward the interstitial cadence, so use
    // the live clock when the run never reached game over. Quitting mid-
    // *tutorial* does not: coaching is not a run, and burning a slot in the
    // frequency cap on it would bring an interstitial forward for free.
    if (_tutorial == null) {
      final elapsed = _gameOverReason != null
          ? _runElapsedAtGameOver
          : Duration(
              milliseconds: (_game.engine.riseController.elapsed * 1000)
                  .round(),
            );
      widget.ads.notifyRunEnded(elapsed);
      _endTrackedRun('quit', elapsed);
    }
    Navigator.of(context).pop();
  }

  Future<void> _continueAfterAd() async {
    AnalyticsService.design('continue:accepted');
    final earned = await widget.ads.showRewardedContinue();
    if (!earned) {
      AnalyticsService.design('continue:declined');
      setState(() {});
      return;
    }
    AnalyticsService.design('continue:earned');
    // The run the player is buying back into was already closed out by the
    // GameOverEvent, so this opens a fresh one rather than resuming the old
    // counters — reported as `run:resume` so continues are separable from
    // clean starts, and without a second progression Start, which would
    // otherwise show up as two attempts for one life.
    _tracker.runStarted(resumed: true, bestBefore: widget.storage.bestScore);
    _tracker.continueUsed();
    _game.continueAfterAd();
    setState(() => _gameOverReason = null);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // A back gesture mid-run never leaves directly — it opens the quit
      // prompt (or dismisses it, if it is already up).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_gameOverReason != null) {
          _goHome();
        } else if (_confirmingQuit) {
          _cancelQuit();
        } else {
          _requestQuit();
        }
      },
      child: Scaffold(
        backgroundColor: Tokens.colorBg,
        body: ValueListenableBuilder<bool>(
          valueListenable: _game.pausedNotifier,
          builder: (context, paused, _) {
            final tutorial = _tutorial;
            final showPause =
                paused && _gameOverReason == null && !_confirmingQuit;
            return Stack(
              children: [
                _GameplayBody(
                  game: _game,
                  storage: widget.storage,
                  ads: widget.ads,
                  boardKey: _boardKey,
                  // A coach step must never dim: the dim treatment applies
                  // `IgnorePointer`, which would swallow the very gestures the
                  // step is teaching.
                  dimmed:
                      showPause ||
                      _confirmingQuit ||
                      (tutorial?.dimsBoard ?? false),
                ),
                if (tutorial != null &&
                    !showPause &&
                    !_confirmingQuit &&
                    _gameOverReason == null)
                  TutorialOverlay(controller: tutorial, boardKey: _boardKey),
                if (showPause)
                  PauseOverlay(
                    storage: widget.storage,
                    ads: widget.ads,
                    liveGame: _game,
                    onResume: _resumeFromPause,
                    onRestart: _restart,
                    onQuit: _requestQuit,
                  ),
                if (_confirmingQuit && _gameOverReason == null)
                  ConfirmQuitOverlay(
                    score: _game.engine.scoring.score,
                    onContinue: _cancelQuit,
                    onQuit: _confirmQuit,
                  ),
                if (_gameOverReason != null)
                  GameOverOverlay(
                    reason: _gameOverReason!,
                    score: _game.engine.scoring.score,
                    best: widget.storage.bestScore,
                    onRestart: _restartAfterGameOver,
                    onHome: _goHome,
                    canContinueWithAd:
                        widget.ads.isRewardedContinueReady &&
                        !_game.engine.hasUsedContinueThisRun,
                    onContinueWithAd: _continueAfterAd,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GameplayBody extends StatelessWidget {
  const _GameplayBody({
    required this.game,
    required this.storage,
    required this.ads,
    required this.dimmed,
    required this.boardKey,
  });

  final TetrofallGame game;
  final StorageService storage;
  final AdsService ads;
  final bool dimmed;
  final GlobalKey boardKey;

  /// Aspect ratio of the visible grid — 18:32, which is exactly 9:16. That
  /// equality is why the layout below is so miserly with vertical space: on a
  /// 9:16 phone the board is height-bound, so every point of chrome above or
  /// below it comes back out of the board's *width* at 0.5625 points a time.
  static const _boardAspect = BoardConfig.cols / BoardConfig.rows;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final size = MediaQuery.sizeOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);

    // Every input here is known before layout — which is the whole reason
    // ScoreHud has a fixed height and the banner slot reserves synchronously.
    final bannerHeight = ads.reservedBannerHeight(
      size.width.truncate(),
      screenHeight: size.height,
    );
    final chrome =
        viewPadding.top + ui.hudHeight + bannerHeight + ui.spaceXs * 2;

    // What the board would want if it were width-bound: filling the screen
    // edge to edge. Anything left over after that is genuine slack.
    final boardWantsHeight = (size.width - ui.spaceSm * 2) / _boardAspect;
    final slack = size.height - chrome - boardWantsHeight;

    // Spend whatever slack exists on holding the banner clear of the home
    // indicator. When there is none, the banner runs edge to edge rather than
    // taking the inset out of the board.
    final bannerBottomInset = slack <= 0
        ? 0.0
        : math.min(viewPadding.bottom, slack);

    final content = DecoratedBox(
      decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
      child: Column(
        children: [
          ScoreHud(game: game, storage: storage),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ui.spaceSm,
                vertical: ui.spaceXs,
              ),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _boardAspect,
                  child: DecoratedBox(
                    key: boardKey,
                    decoration: BoxDecoration(
                      color: const Color(0x47000000),
                      border: Border.all(
                        color: const Color(0x4DF5EAD9),
                        width: ui.px(Tokens.borderBoard),
                      ),
                      borderRadius: BorderRadius.circular(
                        ui.radiusSm + ui.px(2),
                      ),
                      boxShadow: const [Tokens.shadowSoft],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(ui.radiusSm),
                      child: Padding(
                        padding: EdgeInsets.all(ui.px(Tokens.boardInset)),
                        child: Listener(
                          onPointerDown: (e) {
                            if (game.paused) return;
                            game.gestureHandler.onPointerDown(e);
                          },
                          onPointerMove: (e) {
                            if (game.paused) return;
                            game.gestureHandler.onPointerMove(e);
                          },
                          onPointerUp: (e) {
                            if (game.paused) return;
                            game.gestureHandler.onPointerUp(e);
                          },
                          onPointerCancel: (e) {
                            if (game.paused) return;
                            game.gestureHandler.onPointerCancel(e);
                          },
                          child: GameWidget(game: game),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          BannerAdSlot(ads: ads, bottomInset: bannerBottomInset),
        ],
      ),
    );

    // The dim treatment is switched by parameter rather than by wrapping, and
    // that is load-bearing rather than tidy: returning a different widget
    // *shape* for the paused frame changes the type of this element's child,
    // which reinflates everything below it — including the `GameWidget`. That
    // teardown runs Flame's `onRemove` on the still-live game, which is how
    // opening the pause menu used to unhook the run from its own sound
    // effects and haptics for good.
    return IgnorePointer(
      ignoring: dimmed,
      child: ImageFiltered(
        enabled: dimmed,
        imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Opacity(opacity: dimmed ? 0.4 : 1.0, child: content),
      ),
    );
  }
}
