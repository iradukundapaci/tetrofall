// The store shot list, as data — android_release_plan.md §4.8.
//
// Every scene is one Play Store screenshot. Boards are authored bottom row
// first, `#` for a settled block, `.` for empty, 18 columns wide to match
// `BoardConfig.cols`; short rows are padded and long ones truncated, so a
// layout that drifts fails visibly rather than throwing.
//
// Scores are hand-picked distinct and increasing across the list. Twelve
// screenshots of the same board with the same number on it reads as one
// screenshot uploaded twelve times, which §4.8 calls out by name.
library;

import 'package:tetrofall/game/engine/tetromino.dart';

/// What the harness does after seeding, and when it photographs the result.
enum SceneAction {
  /// Seed, let the board settle, shoot. Everything static.
  still,

  /// Seed, hand the bot a piece that completes rows, let it drop — then
  /// freeze [Scene.freezeMs] after the clear fires. The shatter and the
  /// ripple cascade are the best-looking moments in the game and are three
  /// frames long; this is the only way to photograph one.
  clearAndFreeze,

  /// Seed, spawn a piece, freeze it in mid-air with its ghost showing.
  dropInFlight,
}

/// Which screen to mount. Most scenes are gameplay.
enum SceneScreen { gameplay, menu, tutorial, gameOver }

class Scene {
  const Scene({
    required this.name,
    required this.caption,
    this.layout = const [],
    this.score = 0,
    this.best,
    this.action = SceneAction.still,
    this.screen = SceneScreen.gameplay,
    this.freezeMs = 0,
    this.settleMs = 900,
    this.piece,
    this.riseProgress = 0.0,
    this.elapsedSeconds = 0,
  });

  final String name;

  /// The §4.9 caption. Max five words — it has to be legible at the 120px
  /// thumbnail Play renders in search results.
  final String caption;

  final List<String> layout;
  final int score;

  /// BEST, when it should differ from [score]. `ScoreHud` reads it once in
  /// initState, so the harness writes it to storage before the first frame.
  final int? best;

  final SceneAction action;
  final SceneScreen screen;

  /// Milliseconds after the clear fires to hold before freezing the clock.
  final int freezeMs;

  /// Milliseconds to wait after seeding before acting or shooting.
  final int settleMs;

  /// The piece to hand the bot. An I into a one-wide well is what produces a
  /// four-row clear on cue.
  final TetrominoType? piece;

  /// Sub-cell rise offset, 0..1. Non-zero leaves the pending row visibly
  /// half-emerged below the floor — the rise mechanic caught mid-push, which
  /// a settled board never shows.
  final double riseProgress;

  /// Seeds the difficulty clock, so a late-game board actually runs at
  /// late-game speed and the HUD isn't the only thing claiming it is.
  final int elapsedSeconds;

  int get best0 => best ?? score;
}

/// The twelve phone scenes, in upload order. Shots 1–4 are gameplay by
/// design: menu and game-over convert badly and belong at the end (§4.8).
const shotList = <Scene>[
  // ── 1 ────────────────────────────────────────────────────────────────
  // The hero. Four rows bursting centre-out with the shards at full spread.
  // Freeze lands well after `Motion.crackHold` (380ms) so the cracks have
  // already given way to particles.
  Scene(
    name: 'shatter',
    caption: 'Clear rows. Watch them shatter.',
    score: 18450,
    best: 24680,
    action: SceneAction.clearAndFreeze,
    piece: TetrominoType.I,
    freezeMs: 620,
    layout: [
      '###.##############',
      '###.##############',
      '###.##############',
      '###.##############',
      '###.##############',
      '###.##############',
      '###.##############',
      '###.##############',
      '###.##############',
      '#################.',
      '#################.',
      '#################.',
      '#################.',
      '##.##############.',
      '#################.',
      '#################.',
      '#.###############.',
      '#################.',
      '#################.',
      '#################.',
      '.#########.#.####.',
      '.#####.##########.',
      '#####.#.#######.#.',
      '###############.#.',
      '###########.##....',
      '######.####.......',
      '.####..###........',
    ],
  ),

  // ── 2 ────────────────────────────────────────────────────────────────
  // Ripple gravity: the row that cleared was a *middle* row, so the stack
  // above it is in free fall at different heights while everything below is
  // untouched. This is the mechanic that separates the game from Tetris.
  Scene(
    name: 'cascade',
    caption: 'Blocks fall on their own.',
    score: 21300,
    best: 24680,
    action: SceneAction.clearAndFreeze,
    piece: TetrominoType.I,
    freezeMs: 1250,
    layout: [
      '#####.############',
      '#####.############',
      '#####.############',
      '#####.############',
      '#####.############',
      '#####.############',
      '#####.############',
      '#####.############',
      '###########.######',
      '#######.###..#####',
      '###..######.#####.',
      '#########.#.######',
      '###########.#####.',
      '###.#######.######',
      '###########.######',
      '#########.#..##...',
      '###.#..#.##...#...',
      '###.#..#.#........',
      '#.................',
      '.#................',
      '..................',
      '..................',
      '..................',
      '..................',
      '..................',
      '..................',
    ],
  ),

  // ── 3 ────────────────────────────────────────────────────────────────
  // The rise biting. Stack into the warning band (rows 0–3 light the frame
  // red), and the pending row caught 60% of the way up rather than settled.
  Scene(
    name: 'rise_pressure',
    caption: 'The floor rises. Every second counts.',
    score: 24680,
    best: 31905,
    riseProgress: 0.62,
    elapsedSeconds: 240,
    layout: [
      '########.#########',
      '#######.##########',
      '#####.############',
      '#########.########',
      '##########.#######',
      '################.#',
      '#.####.######.####',
      '##############.###',
      '#######.##########',
      '.#################',
      '.#################',
      '###.##############',
      '#######.##########',
      '##############.###',
      '........##########',
      '.........#########',
      '.........#########',
      '..........########',
      '...........#######',
      '............######',
      '............####.#',
      '.............#####',
      '...............##.',
      '................#.',
    ],
  ),

  // ── 4 ────────────────────────────────────────────────────────────────
  // Controls. A piece mid-flight with its ghost outline on the landing row,
  // over a board open enough that the drop line reads at thumbnail size.
  Scene(
    name: 'ghost_drop',
    caption: 'One thumb. Swipe, tap, drop.',
    score: 8420,
    best: 24680,
    action: SceneAction.dropInFlight,
    piece: TetrominoType.T,
    settleMs: 1400,
    layout: [
      '####.#####.#######',
      '###..####..######.',
      '###..####..#####..',
      '##....###...####..',
      '##....###...####..',
      '#......##....###..',
      '#......##....###..',
      '#.......#.....##..',
      '........#.....##..',
      '#.......##....##..',
      '##.....###...###..',
      '##.....###...###..',
      '###...####..####..',
      '###...####..####..',
      '####.#####.#####..',
      '####.#####.#####..',
      '#####.###.######..',
      '######.#.#######..',
      '#######.########..',
    ],
  ),

  // ── 5 ────────────────────────────────────────────────────────────────
  // The setup shot: a four-deep well with the I on its way. Reads as a plan
  // in progress, which is the feeling the listing is selling.
  Scene(
    name: 'deep_well',
    caption: 'Set up the big one.',
    score: 11960,
    best: 24680,
    action: SceneAction.dropInFlight,
    piece: TetrominoType.I,
    settleMs: 1400,
    layout: [
      '#################.',
      '#################.',
      '#################.',
      '#################.',
      '#################.',
      '#################.',
      '#################.',
      '#################.',
      '########.########.',
      '#######...#######.',
      '######.....######.',
      '#####.......#####.',
      '####.........####.',
      '####.........####.',
      '###...........###.',
      '###...........###.',
      '##.............##.',
      '##.............##.',
      '#...............#.',
      '#...............#.',
    ],
  ),

  // ── 6 ────────────────────────────────────────────────────────────────
  // The same four-row clear as shot 1, caught 250ms earlier — every cell
  // cracked, nothing burst yet. Different frame, different board, so the two
  // don't read as duplicates.
  Scene(
    name: 'tetrofall_clear',
    caption: 'Four rows. One piece.',
    score: 26800,
    best: 31905,
    action: SceneAction.clearAndFreeze,
    piece: TetrominoType.I,
    freezeMs: 300,
    layout: [
      '##############.###',
      '##############.###',
      '##############.###',
      '##############.###',
      '##############.###',
      '##############.###',
      '##############.###',
      '##############.###',
      '##############.###',
      '.#################',
      '.#################',
      '.#################',
      '.#################',
      '.#################',
      '.##.##############',
      '.##########.######',
      '..################',
      '.#################',
      '.############.####',
      '.##############.##',
      '.#################',
      '.#################',
      '...###########.###',
      '.#.##########..#..',
      '.....#.###..#...#.',
      '......###.........',
    ],
  ),

  // ── 7 ────────────────────────────────────────────────────────────────
  // Deep into a chain: the first clear released the stack, the falling rows
  // completed more, and the multiplier is climbing. Frozen late enough that
  // a second link is already resolving.
  Scene(
    name: 'chain_x3',
    caption: 'Chains build themselves.',
    score: 29740,
    best: 31905,
    action: SceneAction.clearAndFreeze,
    piece: TetrominoType.I,
    freezeMs: 1900,
    elapsedSeconds: 180,
    layout: [
      '##.###############',
      '##.###############',
      '##.###############',
      '##.###############',
      '##.###############',
      '##.###############',
      '##.###############',
      '##.###############',
      '##.###############',
      '################.#',
      '################.#',
      '################.#',
      '################.#',
      '################..',
      '##.#############.#',
      '################.#',
      '#######.##.##.##.#',
      '################.#',
      '######.#####.###.#',
      '.#####.#########.#',
      '################.#',
      '################.#',
      '#.#....##......#.#',
      '.......#.......#.#',
      '.................#',
      '.................#',
      '.................#',
    ],
  ),

  // ── 8 ────────────────────────────────────────────────────────────────
  // Late game: dense, fast, high score. The difficulty clock is seeded to
  // eight minutes so the piece really is falling at the endurance rate.
  Scene(
    name: 'late_game',
    caption: 'It never stops speeding up.',
    score: 31905,
    best: 31905,
    elapsedSeconds: 480,
    action: SceneAction.dropInFlight,
    piece: TetrominoType.S,
    settleMs: 1200,
    layout: [
      '#############.####',
      '.#################',
      '######.######.####',
      '##############.###',
      '######.###########',
      '###.##############',
      '#########.########',
      '##########.#.#####',
      '###########.######',
      '.#################',
      '###########.######',
      '#################.',
      '########.#########',
      '############.#####',
      '##.##########.####',
      '######.###########',
      '###########.######',
      '.#################',
      '########.#########',
      '#####.############',
      '###.##############',
      '##########.#######',
      '#################.',
      '############.###..',
      '####.#########....',
      '.###.#.#..#..#....',
    ],
  ),

  // ── 9 ────────────────────────────────────────────────────────────────
  // The rule nothing else in the genre has: gravity runs only *above* the
  // cleared line, so the overhangs below it survive. Shown as a board full
  // of caves that plainly did not collapse.
  Scene(
    name: 'overhang',
    caption: 'Your overhangs stay put.',
    score: 14220,
    best: 24680,
    action: SceneAction.dropInFlight,
    piece: TetrominoType.T,
    settleMs: 1100,
    layout: [
      '###...####...#####',
      '###...####...#####',
      '##.....##.....####',
      '#.###############.',
      '#.###############.',
      '#####.......######',
      '####.........#####',
      '###...........####',
      '#######...########',
      '######.....#######',
      '#####.......######',
      '#.###############.',
      '#.###############.',
      '####...#####...###',
      '####...#####...###',
      '###.....###.....##',
      '##.......#.......#',
      '#####.......######',
      '######.....#######',
      '#######...########',
    ],
  ),

  // ── 10 ───────────────────────────────────────────────────────────────
  Scene(
    name: 'tutorial',
    caption: 'Learn it in 60 seconds.',
    screen: SceneScreen.tutorial,
    // Long, because `capture.sh` taps "Let's Go" and then a coached step
    // forward before this fires: the intro modal dims and blurs the board
    // behind it, and a blurred board is the one thing this shot must not
    // show. The freeze has to land after the taps, not before them.
    settleMs: 11000,
    score: 0,
    best: 0,
  ),

  // ── 11 ───────────────────────────────────────────────────────────────
  // The menu autoplays a real engine behind the buttons, so this shot needs
  // no seeding — only long enough for the attract run to build a board worth
  // photographing.
  Scene(
    name: 'main_menu',
    caption: 'Easy to learn. Hard to master.',
    screen: SceneScreen.menu,
    best: 31905,
    settleMs: 14000,
  ),

  // ── 12 ───────────────────────────────────────────────────────────────
  Scene(
    name: 'game_over',
    caption: 'One more run.',
    screen: SceneScreen.gameOver,
    score: 27310,
    best: 31905,
    settleMs: 1600,
    layout: [
      '.#################',
      '.#################',
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
      '#.................',
      '##................',
      '###...............',
      '####..............',
      '#####.............',
      '######............',
      '#######...........',
    ],
  ),
];

/// Scenes 1–8: the gameplay half, reused for both tablet slots. Play allows
/// eight per slot, and menu/tutorial/game-over are the ones to drop first.
List<Scene> get tabletShotList => shotList.take(8).toList();

Scene sceneNamed(String name) => shotList.firstWhere(
  (s) => s.name == name,
  orElse: () => throw ArgumentError(
    'unknown scene "$name"; have ${shotList.map((s) => s.name).join(', ')}',
  ),
);
