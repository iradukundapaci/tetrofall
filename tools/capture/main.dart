// Screenshot capture harness — android_release_plan.md §4.7.
//
// A SEPARATE ENTRYPOINT, not a flag inside main.dart. §4.7 suggests a
// `--dart-define=CAPTURE=true` branch that you then have to remember to
// assert-gate before release; a second entrypoint is strictly safer, because
// the release build never compiles this file at all. There is nothing to
// remember to remove.
//
//   flutter run -t tools/capture/main.dart --release --dart-define=SCENE=play
//
// Scenes: menu | play | pressure | clear | gameover
//
// Ads: `AdsService.init()` is deliberately never called, so `canRequestAds`
// stays false, `BannerAdSlot` collapses and no ad can appear in any capture.
// §4.7 requires zero ad slots visible in every shot.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tetrofall/game/engine/cell.dart';
import 'package:tetrofall/game/tetrofall_game.dart';
import 'package:tetrofall/services/ads_service.dart';
import 'package:tetrofall/services/storage_service.dart';
import 'package:tetrofall/ui/screens/gameplay_screen.dart';
import 'package:tetrofall/ui/screens/main_menu_screen.dart';
import 'package:tetrofall/ui/theme/tokens.dart';

const _scene = String.fromEnvironment('SCENE', defaultValue: 'play');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final storage = await StorageService.load();
  final ads = AdsService(storage);
  // BEST is read once in the HUD's initState, so it has to be in storage
  // before the first frame rather than seeded alongside the board.
  await storage.saveBestScore(_scores[_scene] ?? 0);

  runApp(
    MaterialApp(
      title: 'Tetrofall (capture)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Tokens.colorBg,
        fontFamily: Tokens.fontBody,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Tokens.colorGold,
          brightness: Brightness.dark,
        ),
      ),
      // Straight to the screen being shot — no splash, no menu walk.
      home: _scene == 'menu'
          ? MainMenuScreen(storage: storage, ads: ads)
          : GameplayScreen(
              storage: storage,
              ads: ads,
              onGameCreated: _seed,
            ),
    ),
  );
}

/// Board layouts, authored bottom row first. `#` is a settled block.
///
/// 18 columns wide, matching `BoardConfig.cols`. Rows are padded/truncated to
/// that width on load, so a layout that drifts fails visibly rather than
/// throwing.
const _layouts = <String, List<String>>{
  // Mid-run: a plausible, worked-in stack with room left to play. Reads as a
  // real game in progress rather than a puzzle diagram.
  'play': [
    '####.#####.#######',
    '###..####..######.',
    '###..####..#####..',
    '##....###...####..',
    '##....###...####..',
    '#......##....###..',
    '#......##....###..',
    '#.......#.....##..',
    '........#.....##..',
    '..............#...',
    '..............#...',
    '..................',
    '..................',
  ],
  // Near the top and running out of room — the rise mechanic biting hard.
  'pressure': [
    '##################',
    '#####.############',
    '####..###########.',
    '###....##########.',
    '###....##########.',
    '###.....#########.',
    '##.......########.',
    '##.......########.',
    '##........#######.',
    '#..........######.',
    '#..........######.',
    '#...........#####.',
    '#............####.',
    '#............####.',
    '..............###.',
    '..............###.',
    '...............##.',
    '................#.',
    '................#.',
    '..................',
  ],
  // One gap left in the bottom row: the frame just before a clear.
  'clear': [
    '#########.########',
    '##################',
    '####.#######.#####',
    '####.#######.#####',
    '###...#####...####',
    '###...#####...####',
    '##.....###.....###',
    '##.....###.....###',
    '#.......#.......##',
    '#.......#.......##',
    '.................#',
    '.................#',
  ],
  // Effectively finished — the board behind the game-over overlay.
  'gameover': [
    '##################',
    '##################',
    '#################.',
    '################..',
    '###############...',
    '##############....',
    '#############.....',
    '############......',
    '###########.......',
    '##########........',
    '#########.........',
    '########..........',
    '#######...........',
    '######............',
    '#####.............',
    '####..............',
    '###...............',
    '##................',
    '#.................',
  ],
};

/// Score shown in the HUD per scene. Plausible and increasing across the shot
/// list, so six screenshots don't read as one board photographed six times
/// (§4.8).
const _scores = <String, int>{
  'play': 8420,
  'pressure': 24680,
  'clear': 15340,
  'gameover': 31905,
};

void _seed(TetrofallGame game) {
  final layout = _layouts[_scene];
  if (layout == null) return;

  // onLoad() is async and starts the engine; seeding has to land after it, or
  // engine.start() wipes the grid straight back out.
  Future<void>.delayed(const Duration(milliseconds: 700), () {
    final grid = game.engine.grid;
    for (var i = 0; i < layout.length; i++) {
      final row = grid.maxRow - i;
      final line = layout[i];
      for (var col = 0; col < grid.cols; col++) {
        final filled = col < line.length && line[col] == '#';
        grid.set(row, col, filled ? Cell(BlockType.wood) : null);
      }
    }
    // `Scoring` notifies through a private `_notify()`, so writing `score`
    // alone never reaches the HUD, which listens rather than polls. Awarding a
    // zero-line clear adds nothing to the score and fires that notification —
    // a public way to get the seeded value on screen without a production
    // change just for the capture harness.
    game.engine.scoring.score = _scores[_scene] ?? 0;
    game.engine.scoring.awardLineClear(
      lines: 0,
      chainIndex: 0,
      elapsedSeconds: 0,
    );
  });
}
