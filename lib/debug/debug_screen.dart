import 'dart:math';

import 'package:flutter/material.dart';

import '../game/engine/cell.dart';
import '../game/engine/column_cascade.dart';
import '../game/engine/events.dart';
import '../game/engine/game_engine.dart';
import '../game/engine/sticky_group.dart';
import '../ui/theme/tokens.dart';
import 'debug_fixtures.dart';

/// Reachable by a long-press on the board (see `app.dart`). Prints the grid
/// as ASCII text and drives the engine one step at a time — this is what
/// makes Phase 1-8's manual verification fast instead of tedious (§5).
/// Kept until Phase 12, extended each phase along the way.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  late GameEngine _engine;
  late int _seed;
  final List<String> _eventLog = [];
  final _seedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    _seedController.text = '$_seed';
    _newGame();
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  void _newGame() {
    _engine = GameEngine(random: Random(_seed));
    _engine.addEventListener(_onEvent);
    _eventLog.clear();
    _engine.start();
  }

  void _onEvent(GameEvent event) {
    _eventLog.insert(0, event.runtimeType.toString());
    if (_eventLog.length > 6) _eventLog.removeLast();
  }

  /// Advances the simulation by [frames] frames at a fixed 60fps step —
  /// matches the cadence Flame will drive in Phase 2+, so lock-delay and
  /// gravity behave the same here as in real play.
  void _step({int frames = 1}) {
    setState(() {
      for (var i = 0; i < frames; i++) {
        _engine.tick(1 / 60);
      }
    });
  }

  /// Applies a discrete intent (move/rotate/drop) with no time passing, so
  /// pressing a button doesn't also sneak in a gravity/lock-delay tick.
  void _intent(GameIntentType type) {
    setState(() {
      _engine.enqueueIntent(type);
      _engine.tick(0);
    });
  }

  /// Phase 3: stamps a preset board (tall stack with holes and one
  /// nearly-complete middle row) and spawns a fresh piece so a cascade can
  /// be triggered on demand instead of playing toward one.
  void _loadFixture() {
    setState(() {
      DebugFixtures.loadCascadeTest(_engine.grid);
      final spawned = _engine.pieceController.spawn(_engine.bag.next());
      _engine.phase = spawned ? GamePhase.playing : GamePhase.gameOver;
      _eventLog
        ..clear()
        ..insert(0, 'FixtureLoaded');
    });
  }

  void _toggleResolver() {
    setState(() {
      _engine.resolver = _engine.resolver is ColumnCascade
          ? StickyGroup()
          : ColumnCascade();
    });
  }

  static String _cellGlyph(BlockType type) => switch (type) {
    BlockType.wood => 'X',
    BlockType.stone => '#',
    BlockType.ice => 'i',
    BlockType.iceCracked => 'c',
    BlockType.bomb => 'B',
    BlockType.gold => 'G',
    BlockType.diamond => 'D',
    BlockType.treasure => 'T',
    BlockType.locked => 'L',
    BlockType.rainbow => 'R',
    BlockType.key => 'K',
  };

  String _renderGrid() {
    final grid = _engine.grid;
    final piece = _engine.pieceController.piece;
    final pieceCells = piece?.absoluteCells() ?? const [];
    final buf = StringBuffer();
    for (var r = grid.minRow; r <= grid.maxRow; r++) {
      buf.write(r < 0 ? '~' : ' ');
      for (var c = 0; c < grid.cols; c++) {
        final onPiece = pieceCells.any((o) => o.row == r && o.col == c);
        if (onPiece) {
          buf.write(piece!.type.name[0]);
        } else {
          final cell = grid.at(r, c);
          buf.write(cell == null ? '.' : _cellGlyph(cell.type));
        }
        buf.write(' ');
      }
      if (r == -1) buf.write(' <- row 0 below');
      buf.write('\n');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final piece = engine.pieceController.piece;
    final bagPreview = engine.bag
        .peekAll()
        .map((t) => t.name)
        .join(', ');

    return Scaffold(
      backgroundColor: Tokens.colorBg,
      appBar: AppBar(
        backgroundColor: Tokens.colorWoodDark,
        title: const Text('Tetrofall Debug'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'phase: ${engine.phase.name}   chain: ${engine.chainIndex}   '
                'resolver: ${engine.resolver.runtimeType}\n'
                'piece: ${piece == null ? '-' : '${piece.type.name} '
                    '${piece.rotation.name} '
                    '(${piece.anchorRow},${piece.anchorCol})'}\n'
                'elapsed: ${engine.riseController.elapsed.toStringAsFixed(1)}s   '
                'drop: ${engine.pieceController.dropInterval.inMilliseconds}ms   '
                'rise: ${engine.riseController.riseInterval.toStringAsFixed(1)}s   '
                'fill: ${(engine.riseController.fillRatio * 100).toStringAsFixed(0)}%\n'
                'score: ${engine.scoring.score}   coins: ${engine.scoring.coins}   '
                'destroyed(resolve): ${engine.scoring.blocksDestroyedThisResolve}',
                style: const TextStyle(color: Tokens.colorText),
              ),
              const SizedBox(height: Tokens.spaceXs),
              Text(
                'bag: $bagPreview',
                style: const TextStyle(color: Tokens.colorTextMuted),
              ),
              const SizedBox(height: Tokens.spaceXs),
              Text(
                'events: ${_eventLog.join(' | ')}',
                style: const TextStyle(color: Tokens.colorTextMuted),
              ),
              const SizedBox(height: Tokens.spaceMd),
              Container(
                padding: const EdgeInsets.all(Tokens.spaceSm),
                color: Colors.black,
                child: Text(
                  _renderGrid(),
                  style: const TextStyle(
                    color: Tokens.colorText,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: Tokens.spaceMd),
              Wrap(
                spacing: Tokens.spaceSm,
                runSpacing: Tokens.spaceSm,
                children: [
                  ElevatedButton(
                    onPressed: () => _step(),
                    child: const Text('Step 1 Tick'),
                  ),
                  ElevatedButton(
                    onPressed: () => _step(frames: 10),
                    child: const Text('Step 10 Ticks'),
                  ),
                  ElevatedButton(
                    onPressed: () => _step(frames: 60),
                    child: const Text('Step 60 Ticks'),
                  ),
                  ElevatedButton(
                    onPressed: () => _intent(GameIntentType.moveLeft),
                    child: const Text('Move L'),
                  ),
                  ElevatedButton(
                    onPressed: () => _intent(GameIntentType.moveRight),
                    child: const Text('Move R'),
                  ),
                  ElevatedButton(
                    onPressed: () => _intent(GameIntentType.rotateCW),
                    child: const Text('Rotate CW'),
                  ),
                  ElevatedButton(
                    onPressed: () => _intent(GameIntentType.rotateCCW),
                    child: const Text('Rotate CCW'),
                  ),
                  ElevatedButton(
                    onPressed: () => _intent(GameIntentType.hardDrop),
                    child: const Text('Hard Drop'),
                  ),
                  ElevatedButton(
                    onPressed: _loadFixture,
                    child: const Text('Load Fixture (cascade)'),
                  ),
                  ElevatedButton(
                    onPressed: _toggleResolver,
                    child: Text('Resolver: ${_engine.resolver.runtimeType}'),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.spaceMd),
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _seedController,
                      style: const TextStyle(color: Tokens.colorText),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'seed',
                        labelStyle: TextStyle(color: Tokens.colorTextMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: Tokens.spaceSm),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _seed =
                            int.tryParse(_seedController.text) ?? _seed;
                        _newGame();
                      });
                    },
                    child: const Text('New Game (seed)'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
