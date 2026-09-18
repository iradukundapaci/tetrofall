import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../game/boosters/booster_type.dart';
import '../../game/boosters/loadout.dart';
import '../../game/config/board_config.dart';
import '../../game/config/booster_tuning.dart';
import '../../game/config/difficulty.dart';
import '../../game/config/economy_tuning.dart';
import '../../game/engine/events.dart';
import '../../game/render/score_hud.dart';
import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/economy.dart';
import '../../services/music_service.dart';
import '../../services/run_tracker.dart';
import '../../services/storage_service.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/booster_bar.dart';
import '../widgets/booster_coin_sheet.dart';
import '../widgets/purchase_prompt.dart';
import 'confirm_quit_overlay.dart';
import 'game_over_overlay.dart';
import 'loadout_overlay.dart';
import 'pause_overlay.dart';
import 'tutorial/tutorial_controller.dart';
import 'tutorial/tutorial_overlay.dart';

class GameplayScreen extends StatefulWidget {
  const GameplayScreen({
    super.key,
    required this.storage,
    required this.ads,
    required this.economy,
    this.startTutorial = false,
    this.onGameCreated,
    this.immersive = false,
  });

  final StorageService storage;
  final AdsService ads;
  final Economy economy;

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

  /// Capture-only (android_release_plan.md §4.7). Gives the board the whole
  /// viewport: no banner reservation, no padding, and the HUD floated over
  /// the board instead of stacked above it.
  ///
  /// The board is `AspectRatio(18/32)` — exactly 9:16 — so on a 9:16 screen
  /// every point of chrome the layout spends vertically comes straight back
  /// out of the board's *width* at 0.5625pt a time. In the shipped layout the
  /// HUD, the status bar and a ~90pt banner reservation between them cost the
  /// board roughly two thirds of its area, which is what makes an honest
  /// screenshot look like a small board on a large empty background.
  ///
  /// Defaults to false and nothing in `lib/` passes true: the shipped app
  /// keeps its banner, and its revenue. Only the separate capture entrypoint
  /// under `tools/` turns this on.
  final bool immersive;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> {
  late final TetrofallGame _game = TetrofallGame(
    storage: widget.storage,
    theme: widget.economy.wallet.equippedTheme,
    clearSkies: widget.economy.clearSkies,
    // The tutorial coaches over a board with no boosters and no roll, so it
    // opens its run immediately. Everything else waits for the roll to close
    // (`boosters.md` §3.1).
    autoStart: widget.startTutorial,
  )..showGhost = widget.storage.ghostPieceEnabled;
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

  /// The loadout roll is open over the board (`boosters.md` §3.1). True from
  /// the moment the screen opens until START is pressed, and again between
  /// runs — the engine sits in `ready` behind it.
  bool _showRoll = false;

  /// Whether this roll is a replay, which opens with the previous loadout
  /// already in the reels and offers "Same boosters" (§3.7).
  bool _rollIsReplay = false;

  /// The slot whose refill purchase sheet is open, if any (§4.9).
  int? _refillSlot;

  @override
  void initState() {
    super.initState();
    _game.engine.addEventListener(_onEngineEvent);
    _lifecycle = AppLifecycleListener(onStateChange: _onAppLifecycleChange);
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
    // Coaching is not a run, and it has no boosters and no roll (§3.1). Every
    // other entry into this screen opens on the roll, and the run — and the
    // tracker with it — starts when that closes.
    _showRoll = !widget.startTutorial;
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
    _lifecycle.dispose();
    // Anything the ticker had not yet written out belongs to the player.
    widget.economy.clearSkies.flush();
    super.dispose();
  }

  /// Pauses the run when the app goes to the background.
  ///
  /// Nothing else in the app did this, which was already a bug — a run left
  /// mid-piece kept its rise timer going in the player's pocket. Ad-free time
  /// is metered off the same clock, so leaving it unfixed would also have
  /// billed them for a game they were not playing.
  ///
  /// Created in [initState], not lazily: nothing reads it until [dispose], so a
  /// lazy field would only ever be built on the way out and never listen.
  late final AppLifecycleListener _lifecycle;

  void _onAppLifecycleChange(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    widget.economy.clearSkies.flush();
    if (!_game.paused) _game.pauseEngine();
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
    // The first runs after the tutorial are the starter kit, so the hand-off
    // goes through the roll like any other run start (§3.6).
    _game.holdForOverlay();
    setState(() {
      _showRoll = true;
      _rollIsReplay = false;
    });
  }

  /// Closes the roll and opens the run it picked.
  void _beginRunWith(Loadout loadout) {
    widget.storage.setBoosterLastLoadout(loadout.encode());
    _game.releaseOverlayHold();
    _game.startRun();
    _game.boosters.beginRun(loadout);
    // A refill is bought with Coins, not with an ad, so its availability no
    // longer depends on ad inventory — and an empty wallet is not a reason to
    // hide the badge, because the sheet routes to the earn screen rather than
    // dead-ending (§4.9 rule 4 is satisfied by the purchase always being
    // completable, one way or another).
    _game.boosters.refillAvailable = BoosterTuning.adRefillEnabled;
    _startTrackedRun();
    setState(() {
      _showRoll = false;
      _gameOverReason = null;
      _refillSlot = null;
    });
  }

  /// Puts the roll back up over a board that is still standing, freezing the
  /// run behind it.
  void _openRoll({required bool replay}) {
    // A pause-menu restart arrives with the pause overlay up. Drop it first,
    // then take the quieter hold: two overlays must never stack.
    if (_game.pausedNotifier.value) _game.resumeEngine();
    _game.holdForOverlay();
    setState(() {
      _showRoll = true;
      _rollIsReplay = replay;
      _gameOverReason = null;
      _confirmingQuit = false;
    });
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
    // The tutorial's rigged board is not something the player achieved.
    if (_tutorial == null) widget.economy.daily.onEvent(event);
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
      // Drives the starter kit: the first runs after the tutorial are fixed,
      // and rolls start from run 4 (§3.6).
      widget.storage.setBoosterRunsCompleted(
        widget.storage.boosterRunsCompleted + 1,
      );
      // Reported here rather than from `build`, which reruns on every pause
      // and every rebuild behind the overlay.
      if (!_game.engine.hasUsedContinueThisRun) {
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
    // A restart discards the loadout's charges and the refill counter; the
    // loadout itself is remembered, so the roll offers it back (§4.7).
    _openRoll(replay: true);
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
    _openRoll(replay: true);
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

  Widget _refillSheet(int index) {
    final boosters = _game.boosters;
    final type = boosters.loadout![index];
    final left = BoosterTuning.adRefillsPerRun - boosters.refillsThisRun;
    return BoosterCoinSheet(
      title: 'Recharge ${type.displayName}?',
      // The sheet names the booster and then says what it gets back, in that
      // order (§4.9 Copy).
      message:
          'This booster comes back for the rest of the run. '
          '$left left this run.',
      // Priced by slot, which is the game's own power ladder: a Board booster
      // costs nearly three times a Small one because it does nearly three
      // times as much.
      price: EconomyTuning.chargePrice(type.slot),
      balance: widget.economy.wallet.coins,
      onSpend: () => _buyRefill(index),
      onEarn: _openCoinVault,
      onDecline: _closeRefillSheet,
    );
  }

  /// Opens the earn screen from a purchase the player cannot afford.
  ///
  /// The run stays held for the whole trip, so going to fetch Coins never
  /// costs the player the board they were looking at.
  Future<void> _openCoinVault() async {
    await openCoinVault(
      context,
      ads: widget.ads,
      wallet: widget.economy.wallet,
    );
    if (mounted) setState(() {});
  }

  /// A tap on a slot in the bar. Arming, firing and the refill offer are all
  /// decided here, because only the screen can open a sheet (§4.3, §4.9).
  void _onSlotTapped(int index) {
    final boosters = _game.boosters;
    if (boosters.offersRefill(index)) {
      // A charge the player already owns (bought in the shop, or from a
      // daily reward or chest) is spent without a sheet: they paid for it
      // once already, and asking again would be a second checkout for one
      // purchase. The per-run refill cap still applies — offersRefill checks
      // it — because the cap is what keeps the run a game.
      final type = boosters.loadout![index];
      if (widget.economy.wallet.chargesOf(type) > 0) {
        _useHeldCharge(index, type);
        return;
      }
      // The run freezes the way a pause does: the rise, the piece and the
      // difficulty clock all stop while the sheet is open (§4.9 rule 2).
      _game.holdForOverlay();
      setState(() => _refillSlot = index);
      return;
    }
    boosters.tapSlot(index);
  }

  Future<void> _useHeldCharge(int index, BoosterType type) async {
    if (!await widget.economy.wallet.consumeCharge(type)) return;
    if (!mounted) return;
    _game.boosters.grantRefill(index);
  }

  Future<void> _buyRefill(int index) async {
    final type = _game.boosters.loadout![index];
    if (!await widget.economy.wallet.trySpend(
      EconomyTuning.chargePrice(type.slot),
    )) {
      return;
    }
    if (!mounted) return;
    _game.boosters.grantRefill(index);
    _closeRefillSheet();
  }

  void _closeRefillSheet() {
    _game.releaseOverlayHold();
    setState(() => _refillSlot = null);
  }

  /// Buys the run back for Coins.
  ///
  /// Game over is the most urgent moment in the game, which is exactly why
  /// there is an earn route inline here: sending a broke player away to watch
  /// an ad would cost them the run they were trying to save, and that is the
  /// one thing this economy must never do.
  Future<void> _continueWithCoins() async {
    AnalyticsService.design('continue:accepted');
    if (!widget.economy.wallet.canAfford(EconomyTuning.continuePrice)) {
      await _openCoinVault();
      if (!mounted) return;
      if (!widget.economy.wallet.canAfford(EconomyTuning.continuePrice)) {
        AnalyticsService.design('continue:declined');
        setState(() {});
        return;
      }
    }
    if (!await widget.economy.wallet.trySpend(EconomyTuning.continuePrice)) {
      AnalyticsService.design('continue:declined');
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
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
        backgroundColor: _game.theme.background,
        body: ValueListenableBuilder<bool>(
          valueListenable: _game.pausedNotifier,
          builder: (context, paused, _) {
            final tutorial = _tutorial;
            final showPause =
                paused &&
                _gameOverReason == null &&
                !_confirmingQuit &&
                !_showRoll &&
                _refillSlot == null;
            return Stack(
              children: [
                _GameplayBody(
                  game: _game,
                  storage: widget.storage,
                  boardKey: _boardKey,
                  immersive: widget.immersive,
                  // Lets the coached caption duck out of the way while a
                  // finger is on the glass. Null outside the tutorial, which
                  // is every frame of a real run.
                  onBoardTouched: tutorial?.setBoardTouched,
                  // Coaching is not a run — the same line drawn for
                  // RunTracker above and for the interstitial cadence.
                  recordsBest: tutorial == null,
                  // No bar in the tutorial run (§4.1). Everywhere else it is
                  // the bottom row of the screen, and the banner is gone.
                  showBoosterBar: tutorial == null,
                  onSlotTapped: _onSlotTapped,
                  // A coach step must never dim: the dim treatment applies
                  // `IgnorePointer`, which would swallow the very gestures the
                  // step is teaching.
                  dimmed:
                      showPause ||
                      _confirmingQuit ||
                      _showRoll ||
                      _refillSlot != null ||
                      (tutorial?.dimsBoard ?? false),
                ),
                if (_showRoll)
                  LoadoutOverlay(
                    theme: _game.theme,
                    previousLoadout: _rollIsReplay
                        ? Loadout.decode(widget.storage.boosterLastLoadout)
                        : null,
                    useStarterKit:
                        widget.storage.boosterRunsCompleted <
                        BoosterTuning.starterKitRuns,
                    wallet: widget.economy.wallet,
                    onEarnCoins: _openCoinVault,
                    onStart: _beginRunWith,
                  ),
                if (_refillSlot != null) _refillSheet(_refillSlot!),
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
                    canContinue: !_game.engine.hasUsedContinueThisRun,
                    continuePrice: EconomyTuning.continuePrice,
                    coinBalance: widget.economy.wallet.coins,
                    onContinue: _continueWithCoins,
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
    required this.dimmed,
    required this.boardKey,
    required this.immersive,
    required this.showBoosterBar,
    required this.onSlotTapped,
    this.onBoardTouched,
    this.recordsBest = true,
  });

  final TetrofallGame game;
  final StorageService storage;
  final bool dimmed;
  final GlobalKey boardKey;

  /// See [GameplayScreen.immersive]. Capture-only; false in the shipped app.
  final bool immersive;

  /// Told whenever a touch starts or ends on the board. Only the tutorial
  /// listens; it fades its chrome down for the duration of the gesture.
  final ValueChanged<bool>? onBoardTouched;

  /// Whether this board's score may become the player's best. False while the
  /// tutorial is coaching over it.
  final bool recordsBest;

  /// False in the tutorial run, which has no boosters — and so gives the
  /// board the strip the bar would have taken (`boosters.md` §4.1).
  final bool showBoosterBar;

  final ValueChanged<int> onSlotTapped;

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
    // ScoreHud has a fixed height and why the booster bar has one too. The
    // banner slot that used to sit here is gone: it cost 50pt of play area on
    // every run for the lowest-value unit in the build, and the boosters buy
    // that income back through rewarded video the player opts into (§4.1).
    final barHeight = immersive || !showBoosterBar
        ? 0.0
        : ui.px(Tokens.boosterBarHeight);
    final chrome = immersive
        ? 0.0
        : viewPadding.top + ui.hudHeight + barHeight + ui.spaceXs * 2;

    // What the board would want if it were width-bound: filling the screen
    // edge to edge. Anything left over after that is genuine slack.
    final boardWantsHeight = (size.width - ui.spaceSm * 2) / _boardAspect;
    final slack = size.height - chrome - boardWantsHeight;

    // Spend whatever slack exists on holding the bar clear of the home
    // indicator. When there is none, the bar sits at the very bottom rather
    // than taking the inset out of the board.
    final barBottomInset = slack <= 0
        ? 0.0
        : math.min(viewPadding.bottom, slack);

    final boosterBar = BoosterBar(
      state: game.boosters,
      theme: game.theme,
      onSlotTapped: onSlotTapped,
    );

    // Immersive drops the frame entirely rather than merely thinning it: a
    // rounded gold border is a nicety when the board floats on a background,
    // and a visible seam once the board *is* the screen.
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
              game.onBoardPointerDown(e);
            },
            onPointerMove: (e) {
              if (game.paused) return;
              game.onBoardPointerMove(e);
            },
            onPointerUp: (e) {
              if (game.paused) return;
              game.onBoardPointerUp(e);
              onBoardTouched?.call(false);
            },
            onPointerCancel: (e) {
              if (game.paused) return;
              game.onBoardPointerCancel(e);
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
    );

    final content = DecoratedBox(
      decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
      // Immersive floats the HUD *over* the board so it costs no height;
      // the shipped layout stacks it above, where its fixed `ui.hudHeight`
      // is what lets the budget above be computed before layout runs.
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
                  child: Stack(
                    children: [
                      Padding(
                        padding: boardPadding,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _boardAspect,
                            child: KeyedSubtree(key: boardKey, child: board),
                          ),
                        ),
                      ),
                      // The first-use tip and the aim hint float over the
                      // bottom of the board, so a line of coaching can never
                      // push the board around mid-run (§4.8).
                      if (showBoosterBar)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: ui.spaceXs,
                          child: BoosterTipLine(
                            state: game.boosters,
                            theme: game.theme,
                          ),
                        ),
                    ],
                  ),
                ),
                if (showBoosterBar)
                  Padding(
                    padding: EdgeInsets.only(bottom: barBottomInset),
                    child: boosterBar,
                  ),
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
