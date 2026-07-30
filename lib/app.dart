import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'game/config/board_config.dart';
import 'game/engine/events.dart';
import 'game/render/score_hud.dart';
import 'game/tetrofall_game.dart';
import 'services/storage_service.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/theme/app_icons.dart';
import 'ui/theme/tokens.dart';

class TetrofallApp extends StatelessWidget {
  const TetrofallApp({super.key, required this.storage});

  final StorageService storage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tetrofall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Tokens.colorBg,
        fontFamily: Tokens.fontBody,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Tokens.colorGold,
          brightness: Brightness.dark,
        ),
      ),
      home: _GameHome(storage: storage),
    );
  }
}

class _GameHome extends StatefulWidget {
  const _GameHome({required this.storage});

  final StorageService storage;

  @override
  State<_GameHome> createState() => _GameHomeState();
}

class _GameHomeState extends State<_GameHome> {
  late final TetrofallGame _game = TetrofallGame(storage: widget.storage);
  bool _showGhost = true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/textures/bg_wood.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Color(0x59000000), BlendMode.darken),
          ),
        ),
        child: Column(
          children: [
            ScoreHud(game: _game, storage: widget.storage),
            Expanded(
              child: Stack(
                children: [
                  Padding(
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
                            border: Border.all(
                              color: Tokens.colorWoodDark,
                              width: 4,
                            ),
                            borderRadius: BorderRadius.circular(
                              Tokens.radiusMd,
                            ),
                            boxShadow: const [Tokens.shadowSoft],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              Tokens.radiusMd - 4,
                            ),
                            child: Listener(
                              onPointerDown: (e) {
                                if (_game.paused) return;
                                _game.gestureHandler.onPointerDown(e);
                              },
                              onPointerMove: (e) {
                                if (_game.paused) return;
                                _game.gestureHandler.onPointerMove(e);
                              },
                              onPointerUp: (e) {
                                if (_game.paused) return;
                                _game.gestureHandler.onPointerUp(e);
                              },
                              onPointerCancel: (e) {
                                if (_game.paused) return;
                                _game.gestureHandler.onPointerCancel(e);
                              },
                              child: GameWidget(game: _game),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: Tokens.spaceSm,
                    right: Tokens.spaceSm,
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Toggle ghost piece',
                            icon: Icon(
                              _showGhost
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Tokens.colorText,
                            ),
                            onPressed: () {
                              setState(() {
                                _showGhost = !_showGhost;
                                _game.showGhost = _showGhost;
                              });
                            },
                          ),
                          IconButton(
                            tooltip: 'Settings',
                            icon: SvgPicture.asset(
                              AppIcons.settings,
                              width: 22,
                              height: 22,
                              colorFilter: const ColorFilter.mode(
                                Tokens.colorText,
                                BlendMode.srcIn,
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SettingsScreen(storage: widget.storage),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_gameOverReason == null)
                    ValueListenableBuilder<bool>(
                      valueListenable: _game.pausedNotifier,
                      builder: (context, paused, _) {
                        if (!paused) return const SizedBox.shrink();
                        return _PauseOverlay(
                          onResume: _game.resumeEngine,
                          onRestart: _restart,
                        );
                      },
                    ),
                  if (_gameOverReason != null)
                    _GameOverOverlay(
                      reason: _gameOverReason!,
                      score: _game.engine.scoring.score,
                      best: widget.storage.bestScore,
                      onRestart: _restart,
                    ),
                ],
              ),
            ),
            const _AdSlot(),
          ],
        ),
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
        height: 64,
        margin: const EdgeInsets.fromLTRB(
          Tokens.spaceMd,
          0,
          Tokens.spaceMd,
          Tokens.spaceSm,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          border: Border.all(color: Tokens.colorPanelBorder),
        ),
        child: const Text(
          'AD',
          style: TextStyle(
            fontFamily: Tokens.fontDisplay,
            fontSize: Tokens.fontSizeSm,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
            color: Tokens.colorTextMuted,
          ),
        ),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume, required this.onRestart});

  final VoidCallback onResume;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: _OverlayPanel(
            title: 'PAUSED',
            children: [
              _OverlayButton(
                label: 'Resume',
                filled: true,
                onPressed: onResume,
              ),
              const SizedBox(height: Tokens.spaceSm),
              _OverlayButton(label: 'Restart', onPressed: onRestart),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({
    required this.reason,
    required this.score,
    required this.best,
    required this.onRestart,
  });

  final GameOverReason reason;
  final int score;
  final int best;
  final VoidCallback onRestart;

  String get _reasonLabel => switch (reason) {
    GameOverReason.topOut => 'The rising floor reached the top.',
    GameOverReason.blockOut => 'No room left to spawn the next piece.',
  };

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: _OverlayPanel(
            title: 'GAME OVER',
            subtitle: _reasonLabel,
            children: [
              Text(
                '$score',
                style: const TextStyle(
                  fontFamily: Tokens.fontDisplay,
                  fontSize: Tokens.fontSizeXxl,
                  fontWeight: FontWeight.w800,
                  color: Tokens.colorText,
                  height: 1.1,
                ),
              ),
              Text(
                'BEST $best',
                style: const TextStyle(
                  fontSize: Tokens.fontSizeSm,
                  fontWeight: FontWeight.bold,
                  color: Tokens.colorTextMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: Tokens.spaceLg),
              _OverlayButton(
                label: 'Play Again',
                filled: true,
                onPressed: onRestart,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayPanel extends StatelessWidget {
  const _OverlayPanel({
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.spaceLg,
        vertical: Tokens.spaceXl,
      ),
      decoration: BoxDecoration(
        color: Tokens.colorBg,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: Tokens.colorPanelBorder),
        boxShadow: const [Tokens.shadowLift],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: Tokens.fontSizeLg,
              fontWeight: FontWeight.w800,
              color: Tokens.colorGold,
              letterSpacing: 1.0,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: Tokens.spaceSm),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: Tokens.fontSizeSm,
                color: Tokens.colorTextMuted,
              ),
            ),
          ],
          const SizedBox(height: Tokens.spaceLg),
          ...children,
        ],
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: filled ? Tokens.colorGold : Tokens.colorPanel,
          foregroundColor: filled ? Tokens.colorWoodDark : Tokens.colorText,
          side: filled
              ? null
              : const BorderSide(color: Tokens.colorPanelBorder),
          padding: const EdgeInsets.symmetric(vertical: Tokens.spaceMd),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: Tokens.fontDisplay,
            fontSize: Tokens.fontSizeMd,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
