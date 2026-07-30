import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/engine/events.dart';
import '../../game/engine/game_engine.dart';
import '../../game/tetrofall_game.dart';
import '../../services/storage_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../widgets/counter_pill.dart';
import '../widgets/icon_button.dart';
import '../widgets/primary_button.dart';
import 'gameplay_screen.dart';
import 'settings_screen.dart';

/// 1:1 port of main-menu.html — plus a live, self-playing game running
/// full-bleed behind the menu in place of main-menu.html's empty
/// `.menu-video-slot` (there's no gameplay clip to drop in, so the real
/// engine stands in for one). It's purely decorative: a separate
/// throwaway `TetrofallGame` that never touches saved best score or
/// settings, autoplaying itself and restarting whenever it tops out.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  // Mock purchase state only — IAP itself is Phase 11. Tapping just
  // flips the button, exactly like main-menu.html's script does; nothing
  // is persisted and nothing is actually hidden yet, since there is no ad
  // to remove.
  bool _adsRemoved = false;

  late final TetrofallGame _demoGame = TetrofallGame(storage: widget.storage);
  final _random = math.Random();
  Timer? _autoplayTimer;
  Timer? _restartTimer;
  int _targetCol = 0;

  @override
  void initState() {
    super.initState();
    _demoGame.engine.addEventListener(_onDemoEvent);
    _autoplayTimer = Timer.periodic(
      const Duration(milliseconds: 220),
      (_) => _tickAutoplay(),
    );
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _restartTimer?.cancel();
    _demoGame.engine.removeEventListener(_onDemoEvent);
    super.dispose();
  }

  void _onDemoEvent(GameEvent event) {
    if (event is PieceSpawnedEvent) {
      _targetCol = _pickTargetColumn();
    } else if (event is GameOverEvent) {
      _restartTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _demoGame.restart();
      });
    }
  }

  /// No line-clearing lookahead — just aims each piece at whichever
  /// column is currently shortest. That alone keeps the stack roughly
  /// level instead of the jagged, fast-topping-out mess a fully random
  /// column choice produces, and it's enough to clear rows now and then.
  int _pickTargetColumn() {
    final grid = _demoGame.engine.grid;
    final heights = List<int>.generate(grid.cols, (col) {
      for (var row = 0; row <= grid.maxRow; row++) {
        if (grid.at(row, col) != null) return grid.maxRow - row + 1;
      }
      return 0;
    });
    final minHeight = heights.reduce(math.min);
    final shortest = [
      for (var c = 0; c < heights.length; c++)
        if (heights[c] == minHeight) c,
    ];
    return shortest[_random.nextInt(shortest.length)];
  }

  /// Simple decorative autoplay: steer toward the target column, then
  /// hard-drop — no rotation-aware placement, just enough motion to read
  /// as "a game is being played" behind the menu.
  void _tickAutoplay() {
    final engine = _demoGame.engine;
    if (engine.phase != GamePhase.playing) return;
    final piece = engine.pieceController.piece;
    if (piece == null) return;
    if (piece.anchorCol < _targetCol) {
      engine.enqueueIntent(GameIntentType.moveRight);
    } else if (piece.anchorCol > _targetCol) {
      engine.enqueueIntent(GameIntentType.moveLeft);
    } else if (_random.nextDouble() < 0.15) {
      engine.enqueueIntent(GameIntentType.rotateCW);
    } else {
      engine.enqueueIntent(GameIntentType.hardDrop);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: GameWidget(game: _demoGame),
              ),
            ),
          ),
          const Positioned.fill(child: _MenuScrim()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.spaceLg,
                Tokens.spaceLg,
                Tokens.spaceLg,
                Tokens.spaceXl,
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
                          width: 20,
                          height: 20,
                          colorFilter: const ColorFilter.mode(
                            Tokens.colorText,
                            BlendMode.srcIn,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SettingsScreen(storage: widget.storage),
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
                            width: 160,
                            child: PrimaryButton(
                              label: 'PLAY',
                              fontSize: Tokens.fontSizeMd,
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      GameplayScreen(storage: widget.storage),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: Tokens.spaceMd),
                          SizedBox(
                            width: 200,
                            child: SecondaryButton(
                              label: _adsRemoved
                                  ? 'Ads Removed'
                                  : 'No Ads — \$2.99',
                              highlighted: _adsRemoved,
                              icon: SvgPicture.asset(
                                _adsRemoved
                                    ? AppIcons.checkCircle
                                    : AppIcons.soundOff,
                                width: 18,
                                height: 18,
                                colorFilter: ColorFilter.mode(
                                  _adsRemoved
                                      ? Tokens.colorGold
                                      : Tokens.colorText,
                                  BlendMode.srcIn,
                                ),
                              ),
                              onPressed: _adsRemoved
                                  ? () {}
                                  : () => setState(() => _adsRemoved = true),
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

/// Darkens the live demo board so the topbar and buttons on top of it
/// stay readable, lighter in the middle so the board is still visible.
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
