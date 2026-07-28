import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'debug/debug_overlay.dart';
import 'debug/debug_screen.dart';
import 'game/render/booster_hud.dart';
import 'game/tetrofall_game.dart';
import 'ui/theme/tokens.dart';

class TetrofallApp extends StatelessWidget {
  const TetrofallApp({super.key});

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
      home: const _GameHome(),
    );
  }
}

/// Hosts the Flame board. Forwards raw pointer events to the game's
/// [GestureHandler] (§1.12). Long-press anywhere to reach the debug screen
/// (§5) — kept until Phase 12. The ghost-piece toggle here is temporary;
/// the real Settings row lands in Phase 10.
class _GameHome extends StatefulWidget {
  const _GameHome();

  @override
  State<_GameHome> createState() => _GameHomeState();
}

class _GameHomeState extends State<_GameHome> {
  late final TetrofallGame _game = TetrofallGame();
  bool _showGhost = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: Stack(
        children: [
          Listener(
            // Three input modes share this Listener, in priority order:
            // an armed booster (§1.9's arm -> drag-preview -> release-to-
            // commit) beats the Phase 7 block-type stamper, which in turn
            // hijacks taps so a stamp never also rotates the live piece
            // underneath it. Plain gameplay gestures get whatever's left.
            onPointerDown: (e) {
              if (_game.engine.boosterEngine.armed != null) {
                _game.previewBoosterAt(e.localPosition);
              } else if (_game.debugStampType != null) {
                _game.debugStampAt(e.localPosition);
              } else {
                _game.gestureHandler.onPointerDown(e);
              }
            },
            onPointerMove: (e) {
              if (_game.engine.boosterEngine.armed != null) {
                _game.previewBoosterAt(e.localPosition);
              } else if (_game.debugStampType == null) {
                _game.gestureHandler.onPointerMove(e);
              }
            },
            onPointerUp: (e) {
              if (_game.engine.boosterEngine.armed != null) {
                _game.commitBoosterAt(e.localPosition);
              } else if (_game.debugStampType == null) {
                _game.gestureHandler.onPointerUp(e);
              }
            },
            onPointerCancel: (e) {
              if (_game.engine.boosterEngine.armed != null) {
                _game.engine.disarmBooster();
              } else if (_game.debugStampType == null) {
                _game.gestureHandler.onPointerCancel(e);
              }
            },
            child: GestureDetector(
              onLongPress: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const DebugScreen()));
              },
              child: GameWidget(game: _game),
            ),
          ),
          Positioned(
            top: 40,
            right: 12,
            child: SafeArea(
              child: IconButton(
                tooltip: 'Toggle ghost piece',
                icon: Icon(
                  _showGhost ? Icons.visibility : Icons.visibility_off,
                  color: Tokens.colorText,
                ),
                onPressed: () {
                  setState(() {
                    _showGhost = !_showGhost;
                    _game.showGhost = _showGhost;
                  });
                },
              ),
            ),
          ),
          BoosterHud(game: _game),
          DebugOverlay(game: _game),
        ],
      ),
    );
  }
}
