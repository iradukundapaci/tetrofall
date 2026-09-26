import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../game/config/board_config.dart';
import '../../game/config/run_config.dart';
import '../../game/director/director.dart';
import '../../game/director/skill_model.dart';
import '../../game/engine/events.dart';
import '../../game/render/score_hud.dart';
import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/feedback_service.dart';
import '../../services/music_service.dart';
import '../../services/remote_flags.dart';
import '../../services/review_service.dart';
import '../../services/run_summary.dart';
import '../../services/run_tracker.dart';
import '../../services/storage_service.dart';
import '../../services/telemetry.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/banner_ad_slot.dart';
import 'confirm_quit_overlay.dart';
import 'feedback_screen.dart';
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
    this.immersive = false,
  });

  final StorageService storage;
  final AdsService ads;

  /// Runs the coached tutorial before handing off to a scored run; set by the
  /// menu on the very first PLAY.
  final bool startTutorial;

  /// Capture-only: fires once with the live game so `tools/capture/main.dart`
  /// can seed a board. Nothing in `lib/` passes it.
  final void Function(TetrofallGame game)? onGameCreated;

  /// Capture-only: gives the board the whole viewport, with the HUD floated
  /// over it and no banner reservation. Only `tools/` passes true.
  final bool immersive;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> {
  late final TetrofallGame _game =
      TetrofallGame(storage: widget.storage, newRunConfig: _newRunConfig)
        ..showGhost = widget.storage.ghostPieceEnabled;
  GameOverReason? _gameOverReason;
  Duration _runElapsedAtGameOver = Duration.zero;

  /// Set by [_prepareRun] just ahead of the game asking for it.
  RunConfig? _pendingConfig;
  RunConfig _activeConfig = RunConfig.plain;

  /// Zero-based index of the current run.
  int _runIndex = 0;

  /// The best as the run began, before [ScoreHud] overwrites it.
  late int _bestBefore = widget.storage.bestScore;

  /// Whether this run has been recorded; a run bought back with an ad reaches
  /// game over twice but counts once.
  bool _runRecorded = false;

  /// After several quick deaths, game over offers "Too hard? Tell us".
  bool _offerTooHard = false;

  late final ReviewPrompter _reviewPrompter = ReviewPrompter(
    storage: widget.storage,
  );
  int _phaseChanges = 0;
  bool _lastRescueWasComeback = false;

  bool _confirmingQuit = false;

  final RunTracker _tracker = RunTracker();

  /// Non-null only for the duration of the first-run tutorial.
  TutorialController? _tutorial;

  /// Lets [TutorialOverlay] read the board's on-screen rect.
  final GlobalKey _boardKey = GlobalKey();

  /// Whether the run was already paused when the quit prompt opened, so "Keep
  /// Playing" returns to the pause modal.
  bool _wasPausedBeforeConfirm = false;

  @override
  void initState() {
    super.initState();
    _game.engine.addEventListener(_onEngineEvent);
    widget.ads.fullScreenAdShowing.addListener(_onFullScreenAdShowing);
    AnalyticsService.design('screen:gameplay');
    // The menu loop keeps playing if there's no gameplay track.
    MusicService(widget.storage).play(MusicTrack.gameplay);
    if (widget.startTutorial) {
      _tutorial = TutorialController(
        game: _game,
        storage: widget.storage,
        onFinished: _finishTutorial,
      )..addListener(_onTutorialChanged);
    }
    // Coaching is not a run; [_finishTutorial] opens one on hand-off.
    if (!widget.startTutorial) {
      _pendingConfig = _prepareRun();
      _startTrackedRun();
    }
    final onGameCreated = widget.onGameCreated;
    if (onGameCreated != null) onGameCreated(_game);
  }

  /// What the game asks for at each run start: plain during the tutorial (the
  /// Director joins in [_finishTutorial]).
  RunConfig _newRunConfig() {
    if (_tutorial != null) return RunConfig.plain;
    final config = _pendingConfig ?? _prepareRun();
    _pendingConfig = null;
    return config;
  }

  /// Builds the next run's config from the player's skill, run count and flags.
  RunConfig _prepareRun() {
    final storage = widget.storage;
    _runIndex = storage.endlessRunCount;
    _runRecorded = false;
    _offerTooHard = false;
    _phaseChanges = 0;
    _bestBefore = storage.bestScore;

    final config = RunConfig.endless(
      EndlessProfile(
        bestScore: storage.bestScore,
        skill: storage.directorSkill,
        runCount: _runIndex,
        daysSinceInstall: storage.daysSinceInstall(),
        adaptiveStartOptIn: storage.adaptiveStartSpeedEnabled,
        directorEnabled: RemoteFlags.directorEnabled,
        directorV2: RemoteFlags.directorV2,
        gentleFirstRuns: RemoteFlags.gentleFirstRuns,
      ),
    );
    config.director?.onEvent = _onDirectorEvent;
    _activeConfig = config;
    storage.incrementEndlessRunCount();
    return config;
  }

  void _onDirectorEvent(DirectorEvent event) {
    switch (event) {
      case RescueStarted(:final comeback):
        _lastRescueWasComeback = comeback;
      case RescueEnded(:final stress, :final survived):
        Telemetry.directorRescue(
          stress: stress,
          survived: survived,
          comeback: _lastRescueWasComeback,
        );
      case PhaseChanged(:final phase):
        // One report in five is plenty.
        if (_phaseChanges++ % 5 == 0) Telemetry.directorPhase(phase.name);
    }
  }

  /// Opens an analytics run against the head start the game is about to take.
  void _startTrackedRun() {
    _tracker.runStarted(
      initialElapsed: _activeConfig.initialElapsed,
      // Read now: ScoreHud saves a new best as soon as it is passed.
      bestBefore: widget.storage.bestScore,
    );
    Telemetry.endlessStart(
      skillBucket: SkillModel.bucketOf(widget.storage.directorSkill),
      directorOn: _activeConfig.director != null,
      runIndex: _runIndex,
    );
  }

  /// Closes the analytics run; idempotent, so game over and quit can both
  /// call it.
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
    _activeConfig.director?.onEvent = null;
    _game.engine.removeEventListener(_onEngineEvent);
    widget.ads.fullScreenAdShowing.removeListener(_onFullScreenAdShowing);
    _tutorial?.dispose();
    super.dispose();
  }

  void _onFullScreenAdShowing() {
    if (!mounted || !widget.ads.fullScreenAdShowing.value) return;
    if (_gameOverReason != null || _tutorial != null || _game.paused) return;
    _game.pauseEngine();
  }

  void _onTutorialChanged() {
    if (mounted) setState(() {});
  }

  /// Hands off from the tutorial into the real run without touching the board:
  /// the coached session is the run. No [AdsService.notifyRunEnded], since the
  /// tutorial doesn't count toward the interstitial cadence.
  void _finishTutorial() {
    final tutorial = _tutorial;
    if (tutorial == null) return;
    _dropTutorial(tutorial);
    // The coached session is the first run, where the Director matters most.
    _game.engine.adoptConfig(_prepareRun());
    _startTrackedRun();
  }

  /// Detaches the controller and disposes it after the frame that drops it, so
  /// the overlay never listens to a dead notifier.
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
      // A run ending under the tutorial goes straight to game over.
      final tutorial = _tutorial;
      if (tutorial != null) {
        tutorial.abandon();
        _dropTutorial(tutorial);
      }
      _endTrackedRun(event.reason.name, _runElapsedAtGameOver);
      final endedInTutorial = tutorial != null;
      if (!endedInTutorial && !_runRecorded) _recordRun(event.reason);
      // Here rather than in `build`, which reruns on every pause.
      widget.ads.dropExpiredAds();
      if (widget.ads.isRewardedContinueReady &&
          _game.engine.canContinueThisRun) {
        AnalyticsService.design('continue:offered');
      }
      setState(() {
        _gameOverReason = event.reason;
        _confirmingQuit = false;
      });
    }
  }

  /// Folds a finished run into the skill model, recent scores, quick-death
  /// streak, analytics and the rating prompt.
  void _recordRun(GameOverReason reason) {
    _runRecorded = true;
    final storage = widget.storage;
    final engine = _game.engine;
    final scoring = engine.scoring;
    final stats = engine.director.stats;

    final seconds =
        (_runElapsedAtGameOver - _activeConfig.initialElapsed).inMilliseconds /
        1000;

    final outcome = RunOutcome(
      seconds: seconds,
      lines: scoring.totalLines,
      maxChain: scoring.maxChain,
      placementQuality: stats.placementQuality,
    );
    final skillBefore = storage.directorSkill;
    final skillAfter = SkillModel.updated(skillBefore, outcome);
    if (skillAfter != skillBefore) {
      storage.saveDirectorSkill(skillAfter);
      Telemetry.setSkillBucket(SkillModel.bucketOf(skillAfter));
    }

    final summary = EndlessRunSummary(
      score: scoring.score,
      bestBefore: _bestBefore,
      durationSeconds: seconds,
      lines: scoring.totalLines,
      maxChain: scoring.maxChain,
      tetrofalls: scoring.tetrofalls,
      deathReason: switch (reason) {
        GameOverReason.topOut => 'top_out',
        GameOverReason.blockOut => 'block_out',
      },
      runIndex: _runIndex,
      continuesUsed: engine.continuesUsedThisRun,
      directorOn: engine.director.isActive,
      skillBucket: SkillModel.bucketOf(skillBefore),
      rescues: stats.rescues,
      rescuesSurvived: stats.rescuesSurvived,
      comebacks: stats.comebacks,
      giftRows: stats.giftRows,
      bagBiasPicks: stats.bagBiasPicks,
      placementQuality: stats.placementQuality,
    );
    LastRun.summary = summary;
    Telemetry.endlessEnd(summary);

    // Three runs under a minute in a row suggests it's too hard.
    final quick = seconds < 60;
    final streak = quick ? storage.quickDeathStreak + 1 : 0;
    storage.saveQuickDeathStreak(streak);
    _offerTooHard = streak >= 3 && RemoteFlags.feedbackEnabled;

    final recentBefore = storage.recentScores;
    storage.addRecentScore(summary.score);
    _askForReview(summary, recentBefore);
  }

  /// Asks for a rating shortly after game over so the result shows first;
  /// skipped if the player has moved on.
  Future<void> _askForReview(
    EndlessRunSummary summary,
    List<int> recentBefore,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted || _gameOverReason == null) return;
    await _reviewPrompter.maybeAsk(summary, recentScores: recentBefore);
  }

  void _openFeedback({FeedbackCategory? category}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FeedbackScreen(
          initialCategory: category,
          lastRun: LastRun.summary,
        ),
      ),
    );
  }

  void _resumeFromPause() {
    AnalyticsService.design('pause:resume');
    _game.resumeEngine();
  }

  void _restart() {
    // Also reached from the pause menu, where the run is still open; that
    // abandonment gets its own reason.
    if (_tracker.isRunning) {
      _endTrackedRun(
        'restart',
        Duration(
          milliseconds: (_game.engine.riseController.elapsed * 1000).round(),
        ),
      );
    }
    if (_tutorial == null) _pendingConfig = _prepareRun();
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

  bool _restartingAfterGameOver = false;
  Future<void> _restartAfterGameOver() async {
    if (_restartingAfterGameOver) return;
    _restartingAfterGameOver = true;
    AnalyticsService.design('run:again');
    try {
      await widget.ads.notifyRunEnded(_runElapsedAtGameOver);
    } finally {
      _restartingAfterGameOver = false;
    }
    if (!mounted) return;
    _restart();
  }

  void _goHome() {
    // Quitting mid-run counts toward the interstitial cadence (live clock if
    // it never reached game over); quitting the tutorial does not.
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
    if (!mounted) return;
    if (!earned) {
      AnalyticsService.design('continue:declined');
      setState(() {});
      return;
    }
    AnalyticsService.design('continue:earned');
    // GameOverEvent already closed the run, so open a fresh one, reported as
    // `run:resume` and without a second progression Start.
    _tracker.runStarted(resumed: true, bestBefore: widget.storage.bestScore);
    _tracker.continueUsed();
    _game.continueAfterAd();
    setState(() => _gameOverReason = null);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back never leaves directly: it opens or dismisses the quit prompt.
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
                  immersive: widget.immersive,
                  // Lets the coached caption fade while a finger is down.
                  onBoardTouched: tutorial?.setBoardTouched,
                  // Coaching is not a run.
                  recordsBest: tutorial == null,
                  // The tutorial never dims: dimming applies `IgnorePointer`,
                  // which would swallow the gestures being taught.
                  dimmed: showPause || _confirmingQuit,
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
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.ads.rewardedContinueReady,
                    builder: (context, adReady, _) => GameOverOverlay(
                      reason: _gameOverReason!,
                      score: _game.engine.scoring.score,
                      best: _bestBefore,
                      onTooHard: _offerTooHard
                          ? () => _openFeedback(
                              category: FeedbackCategory.tooHard,
                            )
                          : null,
                      onRestart: _restartAfterGameOver,
                      onHome: _goHome,
                      // Gated on consent, not on the ad being loaded: with ads
                      // refused a "Loading" button would never resolve.
                      canContinueWithAd:
                          widget.ads.canRequestAds &&
                          _game.engine.canContinueThisRun,
                      continueAdReady: adReady,
                      onContinueWithAd: _continueAfterAd,
                    ),
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
    required this.immersive,
    this.onBoardTouched,
    this.recordsBest = true,
  });

  final TetrofallGame game;
  final StorageService storage;
  final AdsService ads;
  final bool dimmed;
  final GlobalKey boardKey;

  /// See [GameplayScreen.immersive].
  final bool immersive;

  /// Told when a touch starts or ends on the board; only the tutorial listens.
  final ValueChanged<bool>? onBoardTouched;

  /// False while the tutorial is coaching over the board.
  final bool recordsBest;

  /// 18:32, exactly 9:16: on a 9:16 phone the board is height-bound, so every
  /// point of vertical chrome comes off its width.
  static const _boardAspect = BoardConfig.cols / BoardConfig.rows;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final size = MediaQuery.sizeOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);

    // Every input is known before layout: ScoreHud has a fixed height and the
    // banner slot reserves synchronously.
    final bannerHeight = immersive
        ? 0.0
        : ads.reservedBannerHeight(
            size.width.truncate(),
            screenHeight: size.height,
          );
    final chrome = immersive
        ? 0.0
        : viewPadding.top + ui.hudHeight + bannerHeight + ui.spaceXs * 2;

    // Height the board wants if width-bound; what's left is slack.
    final boardWantsHeight = (size.width - ui.spaceSm * 2) / _boardAspect;
    final slack = size.height - chrome - boardWantsHeight;

    // Spend slack holding the banner clear of the home indicator; with none,
    // the banner runs edge to edge rather than shrinking the board.
    final bannerBottomInset = slack <= 0
        ? 0.0
        : math.min(viewPadding.bottom, slack);

    // Immersive drops the frame: a border would be a visible seam.
    final boardPadding = immersive
        ? EdgeInsets.zero
        : EdgeInsets.symmetric(horizontal: ui.spaceSm, vertical: ui.spaceXs);
    final boardRadius = immersive ? 0.0 : ui.radiusSm;

    final board = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x47000000),
        border: immersive
            ? null
            : Border.all(
                color: const Color(0x4DF5EAD9),
                width: ui.px(Tokens.borderBoard),
              ),
        borderRadius: BorderRadius.circular(
          immersive ? 0 : ui.radiusSm + ui.px(2),
        ),
        boxShadow: immersive ? null : const [Tokens.shadowSoft],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(boardRadius),
        child: Padding(
          padding: EdgeInsets.all(immersive ? 0 : ui.px(Tokens.boardInset)),
          child: Listener(
            onPointerDown: (e) {
              if (game.paused) return;
              onBoardTouched?.call(true);
              game.gestureHandler.onPointerDown(e);
            },
            onPointerMove: (e) {
              if (game.paused) return;
              game.gestureHandler.onPointerMove(e);
            },
            onPointerUp: (e) {
              if (game.paused) return;
              game.gestureHandler.onPointerUp(e);
              onBoardTouched?.call(false);
            },
            onPointerCancel: (e) {
              if (game.paused) return;
              game.gestureHandler.onPointerCancel(e);
              onBoardTouched?.call(false);
            },
            child: GameWidget(game: game),
          ),
        ),
      ),
    );

    final hud = ScoreHud(
      game: game,
      storage: storage,
      recordsBest: recordsBest,
      showNextPiece: recordsBest,
    );

    final content = DecoratedBox(
      decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
      // Immersive floats the HUD over the board; otherwise its fixed height
      // lets the budget above be computed before layout.
      child: immersive
          ? Stack(
              children: [
                Positioned.fill(
                  child: KeyedSubtree(key: boardKey, child: board),
                ),
                Positioned(top: 0, left: 0, right: 0, child: hud),
              ],
            )
          : Column(
              children: [
                hud,
                Expanded(
                  child: Padding(
                    padding: boardPadding,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _boardAspect,
                        child: KeyedSubtree(key: boardKey, child: board),
                      ),
                    ),
                  ),
                ),
                BannerAdSlot(ads: ads, bottomInset: bannerBottomInset),
              ],
            ),
    );

    // Dimming is a parameter, not a wrapper: a different widget shape would
    // reinflate the `GameWidget` and run Flame's `onRemove` on the live game.
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
