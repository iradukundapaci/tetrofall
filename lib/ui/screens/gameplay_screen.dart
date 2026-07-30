import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../game/config/board_config.dart';
import '../../game/engine/events.dart';
import '../../game/render/score_hud.dart';
import '../../game/tetrofall_game.dart';
import '../../services/storage_service.dart';
import '../theme/tokens.dart';
import 'game_over_overlay.dart';
import 'pause_overlay.dart';

/// 1:1 port of gameplay.html — hosts the Flame `GameWidget` plus the HUD
/// overlays (score/pause topbar, ad banner slot, pause + game-over
/// modals). No settings or ghost-piece controls live here: gameplay.html
/// has only score and pause, everything else is reached through Settings.
class GameplayScreen extends StatefulWidget {
  const GameplayScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> {
  late final TetrofallGame _game = TetrofallGame(storage: widget.storage)
    ..showGhost = widget.storage.ghostPieceEnabled;
  GameOverReason? _gameOverReason;

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
      setState(() => _gameOverReason = event.reason);
    }
  }

  void _restart() {
    _game.restart();
    setState(() => _gameOverReason = null);
  }

  void _continueAfterAd() {
    _game.continueAfterAd();
    setState(() => _gameOverReason = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: ValueListenableBuilder<bool>(
        valueListenable: _game.pausedNotifier,
        builder: (context, paused, _) {
          // pause.html mocks the paused state as a frozen snapshot of the
          // *entire* gameplay screen (topbar, board, ad banner all dimmed
          // and blurred), with the modal covering the whole frame — not
          // just the board area. Game-over gets the same full-frame
          // treatment, edge to edge.
          final showPause = paused && _gameOverReason == null;
          return Stack(
            children: [
              _GameplayBody(
                game: _game,
                storage: widget.storage,
                dimmed: showPause,
              ),
              if (showPause)
                PauseOverlay(
                  storage: widget.storage,
                  liveGame: _game,
                  onResume: _game.resumeEngine,
                  onRestart: _restart,
                ),
              if (_gameOverReason != null)
                GameOverOverlay(
                  reason: _gameOverReason!,
                  score: _game.engine.scoring.score,
                  best: widget.storage.bestScore,
                  onRestart: _restart,
                  onContinueWithAd: _continueAfterAd,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GameplayBody extends StatelessWidget {
  const _GameplayBody({
    required this.game,
    required this.storage,
    required this.dimmed,
  });

  final TetrofallGame game;
  final StorageService storage;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
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
                      borderRadius: BorderRadius.circular(Tokens.radiusSm + 2),
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
          const _AdSlot(),
        ],
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

class _AdSlot extends StatelessWidget {
  const _AdSlot();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 50,
        margin: const EdgeInsets.fromLTRB(
          Tokens.spaceMd,
          0,
          Tokens.spaceMd,
          Tokens.spaceSm,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: const Text(
          'AD BANNER — 320×50',
          style: TextStyle(
            fontFamily: Tokens.fontBody,
            fontSize: Tokens.fontSizeXs,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
            color: Tokens.colorTextMuted,
          ),
        ),
      ),
    );
  }
}
