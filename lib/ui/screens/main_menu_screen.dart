import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/engine/events.dart';
import '../../game/engine/game_engine.dart';
import '../../game/engine/grid.dart';
import '../../game/engine/tetromino.dart';
import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/music_service.dart';
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
/// settings, autoplaying itself and restarting whenever it tops out —
/// tuned to actively hunt for line clears so the shatter/cascade "juice"
/// (the whole point of the game) actually shows up on the menu instead
/// of just watching pieces stack.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key, required this.storage, required this.ads});

  final StorageService storage;
  final AdsService ads;

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  /// Nullable (rather than the live-forever `late final` this started as)
  /// so the demo can be fully torn down while a real run is in progress:
  /// dropping the reference lets the GameWidget unmount, which makes Flame
  /// release the demo's component tree and stop ticking it in the
  /// background instead of burning memory/CPU behind the gameplay screen.
  TetrofallGame? _demoGame;
  Timer? _autoplayTimer;
  Timer? _restartTimer;
  RotationState _targetRotation = RotationState.spawn;
  int _targetCol = 0;

  late final MusicService _music = MusicService(widget.storage);

  @override
  void initState() {
    super.initState();
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
        builder: (_) =>
            GameplayScreen(storage: widget.storage, ads: widget.ads),
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
        final placement = _bestPlacement(game.engine.grid, piece.type);
        _targetRotation = placement.$1;
        _targetCol = placement.$2;
      }
    } else if (event is GameOverEvent) {
      _restartTimer = Timer(const Duration(seconds: 2), () {
        _demoGame?.restart();
      });
    }
  }

  /// Steer to the pre-computed rotation and column, then hard-drop —
  /// the placement itself is what does the work of hunting for clears,
  /// this just drives the piece there.
  void _tickAutoplay() {
    final engine = _demoGame?.engine;
    if (engine == null || engine.phase != GamePhase.playing) return;
    final piece = engine.pieceController.piece;
    if (piece == null) return;
    if (piece.rotation != _targetRotation) {
      engine.enqueueIntent(GameIntentType.rotateCW);
    } else if (piece.anchorCol < _targetCol) {
      engine.enqueueIntent(GameIntentType.moveRight);
    } else if (piece.anchorCol > _targetCol) {
      engine.enqueueIntent(GameIntentType.moveLeft);
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
              child: _demoGame == null
                  ? const ColoredBox(color: Tokens.colorBg)
                  : ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                      child: GameWidget(game: _demoGame!),
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

final _demoRandom = math.Random();

/// Brute-force search over every (rotation, column) placement for the
/// given piece — no multi-piece lookahead, just whatever gets the
/// current one down best. Scored by rows cleared first (so the demo
/// actively hunts for the shatter/cascade effect instead of merely
/// stacking), then by holes created and resulting height as tie-breakers
/// so it doesn't bury gaps chasing a clear two pieces away.
(RotationState, int) _bestPlacement(Grid grid, TetrominoType type) {
  RotationState? bestRotation;
  int? bestCol;
  var bestScore = double.negativeInfinity;
  var ties = 0;

  for (final rotation in RotationState.values) {
    final cells = Tetromino.cellsFor(type, rotation);
    final cellCols = cells.map((c) => c.col);
    final minCol = cellCols.reduce(math.min);
    final maxCol = cellCols.reduce(math.max);

    for (var col = -minCol; col <= grid.cols - 1 - maxCol; col++) {
      final landingRow = _demoLandingRow(grid, cells, col);
      if (landingRow == null) continue;
      final score = _demoScorePlacement(grid, cells, landingRow, col);
      if (score > bestScore) {
        bestScore = score;
        bestRotation = rotation;
        bestCol = col;
        ties = 1;
      } else if (score == bestScore) {
        // Reservoir sampling: ties are common (every rotation of an O
        // piece scores identically), so without this the demo would
        // always resolve them to the same rotation/column and look
        // robotic.
        ties++;
        if (_demoRandom.nextInt(ties) == 0) {
          bestRotation = rotation;
          bestCol = col;
        }
      }
    }
  }

  return (
    bestRotation ?? RotationState.spawn,
    bestCol ?? Tetromino.spawnColumn[type]!,
  );
}

bool _demoCollidesAt(
  Grid grid,
  List<GridOffset> cells,
  int anchorRow,
  int anchorCol,
) {
  for (final c in cells) {
    final row = anchorRow + c.row;
    final col = anchorCol + c.col;
    if (!grid.inBounds(row, col)) return true;
    if (grid.isOccupied(row, col)) return true;
  }
  return false;
}

int? _demoLandingRow(Grid grid, List<GridOffset> cells, int anchorCol) {
  var row = grid.minRow;
  if (_demoCollidesAt(grid, cells, row, anchorCol)) return null;
  while (!_demoCollidesAt(grid, cells, row + 1, anchorCol)) {
    row++;
  }
  return row;
}

double _demoScorePlacement(
  Grid grid,
  List<GridOffset> cells,
  int landingRow,
  int anchorCol,
) {
  final rows = grid.maxRow + 1;
  final occ = List.generate(
    rows,
    (r) => List.generate(grid.cols, (c) => grid.isOccupied(r, c)),
  );
  for (final cell in cells) {
    final r = landingRow + cell.row;
    final c = anchorCol + cell.col;
    if (r >= 0 && r < rows) occ[r][c] = true;
  }

  var cleared = 0;
  for (final row in occ) {
    if (row.every((occupied) => occupied)) cleared++;
  }

  var holes = 0;
  var maxHeight = 0;
  for (var c = 0; c < grid.cols; c++) {
    var seenBlock = false;
    for (var r = 0; r < rows; r++) {
      if (occ[r][c]) {
        if (!seenBlock) maxHeight = math.max(maxHeight, rows - r);
        seenBlock = true;
      } else if (seenBlock) {
        holes++;
      }
    }
  }

  return cleared * 1000.0 - holes * 40.0 - maxHeight * 2.0;
}
