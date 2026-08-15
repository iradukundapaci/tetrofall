import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../game/config/board_config.dart';
import '../../game/engine/events.dart';
import '../../game/render/score_hud.dart';
import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/music_service.dart';
import '../../services/storage_service.dart';
import '../theme/tokens.dart';
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
    // The menu loop keeps playing if there's no gameplay track to swap to.
    MusicService(widget.storage).play(MusicTrack.gameplay);
    if (widget.startTutorial) {
      _tutorial = TutorialController(
        game: _game,
        storage: widget.storage,
        onFinished: _finishTutorial,
      )..addListener(_onTutorialChanged);
    }
    final onGameCreated = widget.onGameCreated;
    if (onGameCreated != null) onGameCreated(_game);
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
      setState(() {
        _gameOverReason = event.reason;
        _confirmingQuit = false;
      });
    }
  }

  void _restart() {
    _game.restart();
    setState(() => _gameOverReason = null);
  }

  /// Freezes the run behind the prompt so the board can't advance (or the
  /// player top out) while they decide.
  void _requestQuit() {
    if (_confirmingQuit) return;
    _wasPausedBeforeConfirm = _game.paused;
    if (!_game.paused) _game.pauseEngine();
    setState(() => _confirmingQuit = true);
  }

  void _cancelQuit() {
    setState(() => _confirmingQuit = false);
    if (!_wasPausedBeforeConfirm) _game.resumeEngine();
  }

  void _confirmQuit() {
    setState(() => _confirmingQuit = false);
    _goHome();
  }

  void _restartAfterGameOver() {
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
    }
    Navigator.of(context).pop();
  }

  Future<void> _continueAfterAd() async {
    final earned = await widget.ads.showRewardedContinue();
    if (!earned) {
      setState(() {});
      return;
    }
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
                    onResume: _game.resumeEngine,
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

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            ScoreHud(game: game, storage: storage),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.spaceMd,
                  Tokens.spaceSm,
                  Tokens.spaceMd,
                  Tokens.spaceMd,
                ),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: BoardConfig.cols / BoardConfig.rows,
                    child: DecoratedBox(
                      key: boardKey,
                      decoration: BoxDecoration(
                        color: const Color(0x47000000),
                        border: Border.all(
                          color: const Color(0x4DF5EAD9),
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(
                          Tokens.radiusSm + 2,
                        ),
                        boxShadow: const [Tokens.shadowSoft],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Tokens.radiusSm),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
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
            BannerAdSlot(ads: ads),
          ],
        ),
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
        imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Opacity(opacity: dimmed ? 0.4 : 1.0, child: content),
      ),
    );
  }
}
