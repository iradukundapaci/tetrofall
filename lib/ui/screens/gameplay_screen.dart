import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../game/config/board_config.dart';
import '../../game/engine/events.dart';
import '../../game/render/score_hud.dart';
import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/storage_service.dart';
import '../theme/tokens.dart';
import '../widgets/banner_ad_slot.dart';
import 'confirm_quit_overlay.dart';
import 'game_over_overlay.dart';
import 'pause_overlay.dart';

class GameplayScreen extends StatefulWidget {
  const GameplayScreen({super.key, required this.storage, required this.ads});

  final StorageService storage;
  final AdsService ads;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> {
  late final TetrofallGame _game = TetrofallGame(storage: widget.storage)
    ..showGhost = widget.storage.ghostPieceEnabled;
  GameOverReason? _gameOverReason;
  Duration _runElapsedAtGameOver = Duration.zero;
  bool _confirmingQuit = false;

  /// Whether the run was already paused when the quit prompt opened, so
  /// "Keep Playing" returns to the pause modal instead of resuming a game
  /// the player deliberately paused.
  bool _wasPausedBeforeConfirm = false;

  @override
  void initState() {
    super.initState();
    _game.engine.addEventListener(_onEngineEvent);
  }

  @override
  void dispose() {
    _game.engine.removeEventListener(_onEngineEvent);
    super.dispose();
  }

  void _onEngineEvent(GameEvent event) {
    if (event is GameOverEvent) {
      _runElapsedAtGameOver = Duration(
        milliseconds: (_game.engine.riseController.elapsed * 1000).round(),
      );
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
    // the live clock when the run never reached game over.
    final elapsed = _gameOverReason != null
        ? _runElapsedAtGameOver
        : Duration(
            milliseconds: (_game.engine.riseController.elapsed * 1000).round(),
          );
    widget.ads.notifyRunEnded(elapsed);
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
            final showPause =
                paused && _gameOverReason == null && !_confirmingQuit;
            return Stack(
              children: [
                _GameplayBody(
                  game: _game,
                  storage: widget.storage,
                  ads: widget.ads,
                  dimmed: showPause || _confirmingQuit,
                ),
                if (showPause)
                  PauseOverlay(
                    storage: widget.storage,
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
  });

  final TetrofallGame game;
  final StorageService storage;
  final AdsService ads;
  final bool dimmed;

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

    if (!dimmed) return content;

    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Opacity(opacity: 0.4, child: content),
      ),
    );
  }
}
