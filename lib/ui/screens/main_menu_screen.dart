import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/ai/demo_bot.dart';
import '../../game/engine/events.dart';
import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/music_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/counter_pill.dart';
import '../widgets/icon_button.dart';
import '../widgets/primary_button.dart';
import 'gameplay_screen.dart';
import 'settings_screen.dart';

/// The main menu, over a live self-playing game. The demo is a decorative
/// throwaway `TetrofallGame` that never touches the saved best score or
/// settings, restarts when it tops out, and hunts line clears so the
/// shatter/cascade shows.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key, required this.storage, required this.ads});

  final StorageService storage;
  final AdsService ads;

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  /// Nullable so the demo can be torn down during a real run: dropping the
  /// reference unmounts the GameWidget and stops it burning CPU behind
  /// gameplay.
  TetrofallGame? _demoGame;
  Timer? _autoplayTimer;
  Timer? _restartTimer;
  DemoBot _bot = DemoBot();

  late final MusicService _music = MusicService(widget.storage);

  @override
  void initState() {
    super.initState();
    AnalyticsService.design('screen:menu');
    _startDemo();
    _music.play(MusicTrack.menu);
  }

  @override
  void dispose() {
    _stopDemo();
    super.dispose();
  }

  void _startDemo() {
    final game = TetrofallGame(storage: widget.storage, feedbackEnabled: false);
    _demoGame = game;
    _bot = DemoBot();
    game.engine.addEventListener(_onDemoEvent);
    _autoplayTimer = Timer.periodic(
      const Duration(milliseconds: 220),
      (_) => _tickAutoplay(),
    );
  }

  void _stopDemo() {
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    _restartTimer?.cancel();
    _restartTimer = null;
    _demoGame?.engine.removeEventListener(_onDemoEvent);
    _demoGame = null;
  }

  Future<void> _openGameplay() async {
    setState(_stopDemo);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameplayScreen(
          storage: widget.storage,
          ads: widget.ads,
          startTutorial: !widget.storage.tutorialSeen,
        ),
      ),
    );
    if (mounted) {
      setState(_startDemo);
      _music.play(MusicTrack.menu);
    }
  }

  void _onDemoEvent(GameEvent event) {
    final game = _demoGame;
    if (game == null) return;
    if (event is PieceSpawnedEvent) {
      final piece = game.engine.pieceController.piece;
      if (piece != null) {
        _bot.onPieceSpawned(game.engine.grid, piece.type);
      }
    } else if (event is GameOverEvent) {
      _restartTimer = Timer(const Duration(seconds: 2), () {
        _demoGame?.restart();
      });
    }
  }

  void _tickAutoplay() {
    final engine = _demoGame?.engine;
    if (engine != null) _bot.tick(engine);
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: _demoGame == null
                  ? const ColoredBox(color: Tokens.colorBg)
                  : ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                      child: GameWidget(game: _demoGame!),
                    ),
            ),
          ),
          const Positioned.fill(child: _MenuScrim()),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                ui.spaceLg,
                ui.spaceLg,
                ui.spaceLg,
                ui.spaceXl,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CounterPill(
                        label: 'BEST',
                        value: _formatScore(widget.storage.bestScore),
                        icon: SvgPicture.asset(
                          AppIcons.trophy,
                          colorFilter: const ColorFilter.mode(
                            Tokens.colorGold,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      CircleIconButton(
                        tooltip: 'Settings',
                        icon: SvgPicture.asset(
                          AppIcons.settings,
                          width: ui.iconMd,
                          height: ui.iconMd,
                          colorFilter: const ColorFilter.mode(
                            Tokens.colorText,
                            BlendMode.srcIn,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SettingsScreen(
                                  storage: widget.storage,
                                  ads: widget.ads,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: ui.px(Tokens.menuPlayWidth),
                            child: PrimaryButton(
                              label: 'PLAY',
                              fontSize: ui.fontMd,
                              onPressed: _openGameplay,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Darkens the demo so the controls stay readable, lighter in the middle.
class _MenuScrim extends StatelessWidget {
  const _MenuScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.black.withValues(alpha: 0.32),
            Colors.black.withValues(alpha: 0.65),
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }
}

String _formatScore(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
