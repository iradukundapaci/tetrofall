import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/render/booster_hud.dart';
import 'game/render/score_hud.dart';
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
/// [GestureHandler] (§1.12). The ghost-piece toggle here is temporary;
/// the real Settings row lands in Phase 10.
///
/// Layout budget (R4): a single `Column` — top HUD, then the board's
/// `Expanded` share of whatever's left, then the booster panel — so each
/// section is sized by real Flutter layout (via `MediaQuery`/intrinsic
/// widget size), never a fixed offset or a guessed fraction of the screen.
/// `BoardComponent` derives `cellSize` from exactly the box the `Expanded`
/// hands it, so nothing here needs to know the board's internal geometry
/// (combo banner strip, pending-row reveal margin) — that budget lives in
/// `BoardComponent._layout`.
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
      body: Column(
        children: [
          ScoreHud(game: _game),
          Expanded(
            child: Stack(
              children: [
                Listener(
                  // Two input modes share this Listener: an armed booster
                  // (§1.9's arm -> drag-preview -> release-to-commit)
                  // beats plain gameplay gestures, which get whatever's
                  // left.
                  onPointerDown: (e) {
                    if (_game.engine.boosterEngine.armed != null) {
                      _game.previewBoosterAt(e.localPosition);
                    } else {
                      _game.gestureHandler.onPointerDown(e);
                    }
                  },
                  onPointerMove: (e) {
                    if (_game.engine.boosterEngine.armed != null) {
                      _game.previewBoosterAt(e.localPosition);
                    } else {
                      _game.gestureHandler.onPointerMove(e);
                    }
                  },
                  onPointerUp: (e) {
                    if (_game.engine.boosterEngine.armed != null) {
                      _game.commitBoosterAt(e.localPosition);
                    } else {
                      _game.gestureHandler.onPointerUp(e);
                    }
                  },
                  onPointerCancel: (e) {
                    if (_game.engine.boosterEngine.armed != null) {
                      _game.engine.disarmBooster();
                    } else {
                      _game.gestureHandler.onPointerCancel(e);
                    }
                  },
                  child: GameWidget(game: _game),
                ),
                Positioned(
                  top: Tokens.spaceSm,
                  right: Tokens.spaceSm,
                  child: SafeArea(
                    top: false,
                    bottom: false,
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
          ),
          BoosterHud(game: _game),
        ],
      ),
    );
  }
}
