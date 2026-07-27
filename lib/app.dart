import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'debug/debug_screen.dart';
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
            onPointerDown: _game.gestureHandler.onPointerDown,
            onPointerMove: _game.gestureHandler.onPointerMove,
            onPointerUp: _game.gestureHandler.onPointerUp,
            onPointerCancel: _game.gestureHandler.onPointerCancel,
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
        ],
      ),
    );
  }
}
