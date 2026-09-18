// Video reels for the store listing and paid social.
//
// Four of the five are deliberate-blunder cuts. That is a UA creative
// convention, not a bug: a clip where the player misses something the viewer
// can plainly see converts far better than a clip of competent play, because
// the viewer wants to correct it. The fifth reel is honest gameplay, for the
// listing's promo-video slot where a misleading clip would be a policy
// problem rather than a hook.
//
// Every reel is seeded (`SEED`) and the bot is deterministic, so a take can be
// re-recorded frame-for-frame instead of re-authored.
library;

import 'package:tetrofall/game/ai/demo_bot.dart';
import 'package:tetrofall/game/engine/tetromino.dart';

class Reel {
  const Reel({
    required this.name,
    required this.blurb,
    required this.seconds,
    this.policy = BotPolicy.skilled,
    this.blunderRate = 1.0,
    this.script = const [],
    this.pieces = const [],
    this.layout = const [],
    this.startScore = 0,
    this.best = 31905,
    this.riseSpeed = 1.0,
    this.elapsedSeconds = 0,
    this.tickMs = 150,
    this.openingHoldMs = 0,
    this.dealFirst = false,
    this.feintPiece = -1,
    this.feintRotations = 0,
    this.feintColumns = const [],
    this.feintDwellMs = const [],
  });

  final String name;

  /// What the cut is for, in one line — this ends up in `gameplay/README.md`.
  final String blurb;

  /// How long to run `adb shell screenrecord`.
  final int seconds;

  final BotPolicy policy;
  final double blunderRate;

  /// Placements the bot must make, in order, before its policy takes over.
  /// Paired with [pieces] so the piece and the placement stay in lockstep.
  final List<BotPlacement> script;
  final List<TetrominoType> pieces;

  final List<String> layout;
  final int startScore;
  final int best;

  /// Multiplier on the rise timer. Above 1.0 the floor comes up faster than
  /// the difficulty curve would have it — how the "ignored the rise" cut gets
  /// to its ending inside 25 seconds.
  final double riseSpeed;
  final int elapsedSeconds;

  /// Milliseconds between bot intents. Deliberately unhurried: a bot playing
  /// at machine speed reads as a simulation, not as a person.
  final int tickMs;

  /// How long to hold the seeded board, motionless, before the bot starts
  /// playing — a beat for the viewer to read the board before it moves.
  ///
  /// This matters more than it sounds: the first take of `01_skilled_run`
  /// seeded its board, cleared four rows and two more besides, and only then
  /// started recording, so the take opened on the aftermath — an empty board
  /// and a score that had already jumped.
  final int openingHoldMs;

  /// Throw away the piece the engine dealt from the bag at start, so the
  /// first piece on screen is `pieces[0]`. Without it the bag piece comes
  /// first and every `script` entry lands on the piece before the one it was
  /// written for.
  final bool dealFirst;

  /// Index (counting spawns from the seed) of the piece that hovers: rotated
  /// [feintRotations] times, steered over each of [feintColumns] in turn with
  /// a pause of [feintDwellMs] over each, then handed back to the bot. The
  /// "don't do it… don't do it…" beat of the frustration cuts. -1 is off.
  final int feintPiece;
  final int feintRotations;
  final List<int> feintColumns;
  final List<int> feintDwellMs;
}

// Every layout is BOTTOM-FIRST: `layout[0]` is seeded into the floor row and
// each later string sits one row higher. Every row must keep at least one gap
// — the clear check scans the whole board on each lock, so a seeded full row
// would vanish the first time any piece landed.

/// Three rows of old garbage, then a one-wide well nine rows deep on the
/// right — the shape every player recognises as "the I-piece goes there" —
/// under a ragged left surface that leaves the mouth of the well wide open.
///
/// This replaces an earlier `_wellBoard` that was written top-first. Seeded
/// bottom-first it put the "well" under a pyramid, sealed, so the blunder the
/// reel was built around could not happen.
const _deepWellBoard = <String>[
  '######..##########',
  '#####.######..####',
  '###############..#',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#####..###........',
  '###...............',
];

/// A four-deep, one-wide slot at column 9: a vertical I there clears four.
const _slotBoard = <String>[
  '#############.##.#',
  '###.####.###.#####',
  '######.########.##',
  '##########.#.#####',
  '#####.##########..',
  '#########.########',
  '#########.########',
  '#########.########',
  '#########.########',
  '######.......#####',
  '#####.........####',
];

/// Stacked to row 3 of 32, with the top four rows one I from clearing — the
/// only move on the board that survives the next few rises.
const _lastChanceBoard = <String>[
  '#####.##########.#',
  '.###########.#.###',
  '##.########.######',
  '####.####.########',
  '##.#####.##.######',
  '###.##.###########',
  '#############..###',
  '.###.#############',
  '############.###.#',
  '###.###.##.#######',
  '.###.####.########',
  '######.#########.#',
  '.##.##############',
  '############.#.###',
  '#.##.#############',
  '.#######..########',
  '###.#######.#.####',
  '####.#.###########',
  '#####.#######..###',
  '##########..######',
  '.#.#.#############',
  '###########.#.####',
  '####.##########..#',
  '#########.#.######',
  '#######.######.###',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
];

/// A low ragged base, column 8 solid on top, for the tower to stand on.
const _towerBoard = <String>[
  '#####.###.##.#####',
  '#######.###.###.##',
  '####.#####.#######',
  '#########.#####.##',
  '####..##########.#',
  '##############..##',
  '#####..##########.',
  '#######.###.######',
];

/// Two slots. Column 4 runs eight deep and its lower four rows are complete
/// but for it, so an I there clears four. Column 13 is a decoy: the four rows
/// around it are also missing column 4, so filling it clears nothing.
const _twoSlotsBoard = <String>[
  '#########.##.#.###',
  '######.###.#######',
  '##.############.##',
  '#.###############.',
  '######.#######.###',
  '############.###.#',
  '####.#############',
  '####.#############',
  '####.#############',
  '####.#############',
  '####.########.####',
  '####.########.####',
  '####.########.####',
  '####.########.####',
];

/// A three-wide trough one row deep that an L fills exactly lying flat.
const _troughBoard = <String>[
  '##..###.##########',
  '###########.#####.',
  '##############...#',
  '#.#####.#########.',
  '############.##.##',
  '.###.########.####',
  '###########.##.###',
  '########...#######',
  '#####.......######',
];

/// A sixteen-deep well on the right, for a reel that never deals an I.
const _longWellBoard = <String>[
  '#.###.############',
  '#######.###.######',
  '#########..#######',
  '#.#############..#',
  '####.#..##########',
  '.##.#.############',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
];

/// The never-an-I reel's pieces, and where each goes: all flat, all left of
/// the well, so the well stays open the whole way up. Twenty-eight, so the
/// floor wins before the queue runs out and the bag can deal the I.
const _waitingPieces = <TetrominoType>[
  TetrominoType.O, TetrominoType.L, TetrominoType.J, TetrominoType.T,
  TetrominoType.O, TetrominoType.S, TetrominoType.Z, TetrominoType.O,
  TetrominoType.L, TetrominoType.T, TetrominoType.J, TetrominoType.O,
  TetrominoType.S, TetrominoType.Z, TetrominoType.T, TetrominoType.L,
  TetrominoType.O, TetrominoType.J, TetrominoType.O, TetrominoType.T,
  TetrominoType.Z, TetrominoType.L, TetrominoType.O, TetrominoType.S,
  TetrominoType.J, TetrominoType.T, TetrominoType.O, TetrominoType.Z,
];

const _waitingScript = <BotPlacement>[
  (RotationState.spawn, 0), (RotationState.spawn, 2),
  (RotationState.spawn, 5), (RotationState.spawn, 8),
  (RotationState.spawn, 11), (RotationState.spawn, 13),
  (RotationState.spawn, 0), (RotationState.spawn, 15),
  (RotationState.spawn, 3), (RotationState.spawn, 6),
  (RotationState.spawn, 10), (RotationState.spawn, 13),
  (RotationState.spawn, 0), (RotationState.spawn, 4),
  (RotationState.spawn, 8), (RotationState.spawn, 12),
  (RotationState.spawn, 15), (RotationState.spawn, 1),
  (RotationState.spawn, 6), (RotationState.spawn, 10),
  (RotationState.spawn, 13), (RotationState.spawn, 0),
  (RotationState.spawn, 4), (RotationState.spawn, 7),
  (RotationState.spawn, 10), (RotationState.spawn, 13),
  (RotationState.spawn, 15), (RotationState.spawn, 2),
];

/// The opening board for the honest reel: a built stack that already reads as
/// a game in progress, with a four-deep well waiting on the right.
///
/// The top four rows are complete but for that well, so a queued I clears
/// four rows on cue. Every row below carries a gap at least five columns
/// wide, and no tetromino spans more than four — so no single placement and
/// no cascade can complete one in one step. The bot can still fill a wide gap
/// over several pieces, and does, so this slows the board's erosion rather
/// than preventing it; measured over a 40s take it holds density where the
/// earlier boards did not.
///
/// Two earlier versions are worth not repeating. Scattering single-cell gaps
/// across different columns let the opening clear chain down through all of
/// them, and the reel spent its remaining thirty seconds on a near-empty
/// board. Staggering the wide gaps across columns looks better in a single
/// frame — caves instead of one straight channel — but gives the bot a
/// reachable gap on every row, and the take drifted sparse by t=30. Keeping
/// them in one column is the version that measures best.
///
/// Do not tune this by eye on one frame. Net stack height is the rise rate
/// minus the bot's clear rate, a small difference of two large numbers, so
/// two takes of the same reel can look quite different; sample a frame a
/// second and read mean luma across the whole take instead. `gameplay/
/// README.md` has the one-liner.
const _skilledBoard = <String>[
  '#######.....######',
  '#######.....##.###',
  '##.####.....######',
  '#######.....####.#',
  '####.##.....######',
  '#######.....###.##',
  '#.#####.....######',
  '#######.....#.####',
  '#####.#.....######',
  '#######......#####',
  '###.###.....######',
  '######......######',
  '#################.',
  '#################.',
  '#################.',
  '#################.',
];

/// A cascade-prone base for the chain reel: every row full but for one cell,
/// and those cells in different columns row to row. One clear drops the stack
/// above it onto material that completes more rows, which completes more
/// again — the ripple gravity the game is built on, running at length.
///
/// This is the same shape that wrecked an early take of `01_skilled_run`,
/// where a single opening clear chained through the whole board and left
/// thirty seconds of empty wood. Paired with a rise fast enough to keep
/// refeeding it, the same fault becomes the subject.
const _cascadeBoard = <String>[
  '###.##############',
  '###########.######',
  '#######.##########',
  '###############.##',
  '#.################',
  '#########.########',
  '#############.####',
  '#####.############',
  '################.#',
  '##.###############',
  '########.#########',
  '############.#####',
  '######.###########',
  '##############.###',
  '####.#############',
  '##########.#######',
  '.#################',
  '#################.',
  '#######.##########',
  '###########.######',
];

const reels = <Reel>[
  // ── 1 ── the honest one ──────────────────────────────────────────────
  Reel(
    name: '01_skilled_run',
    blurb:
        'Straight gameplay: a four-row clear off the opening well, then clean '
        'stacking with the score climbing. The cut for the listing slot.',
    seconds: 40,
    startScore: 6200,
    tickMs: 115,
    // Without the floor pushing, this reel dies after its opening clear: the
    // bot wipes the seeded stack in the first few seconds and then plays on
    // a near-empty 18-wide board, where a single row costs ~4.5 pieces, for
    // the remaining thirty. The rise is what keeps the board populated — and
    // it is the mechanic the listing is selling, so a promo cut that doesn't
    // show it is the wrong cut regardless.
    riseSpeed: 1.6,
    elapsedSeconds: 150,
    layout: _skilledBoard,
    // A beat on the built board before the first piece moves. Short, because
    // `capture.sh` now gates the recording on the readiness marker rather
    // than sleeping, so this no longer has to cover cold start.
    openingHoldMs: 1500,
    // The I first, so the opening well pays off inside the first few
    // seconds rather than whenever the randomiser gets around to it. After
    // this list the engine's own bag takes over, so the rest of the run is
    // ordinary play — seeding the order is not the same as faking it.
    pieces: [
      TetrominoType.I,
      TetrominoType.T,
      TetrominoType.L,
      TetrominoType.O,
      TetrominoType.J,
      TetrominoType.S,
      TetrominoType.I,
      TetrominoType.Z,
    ],
  ),

  // ── 2 ── the archetype ───────────────────────────────────────────────
  // A nine-deep well, the I-piece arrives, and it goes down FLAT across the
  // top — sealing six rows the viewer has been staring at for ten seconds.
  // The whole reel exists for that one placement.
  Reel(
    name: '02_blunder_i_well',
    blurb:
        'The well is nine deep, the I-piece arrives, and it gets laid flat '
        'across the top. The comment-bait cut.',
    seconds: 20,
    layout: _deepWellBoard,
    startScore: 9840,
    elapsedSeconds: 20,
    openingHoldMs: 2500,
    dealFirst: true,
    // Two O pieces of ordinary play first, so the viewer settles in and reads
    // the board, and then the I. Handing it over on frame one gives them
    // nothing to anticipate.
    pieces: [
      TetrominoType.O,
      TetrominoType.O,
      TetrominoType.I,
      TetrominoType.T,
      TetrominoType.S,
      TetrominoType.L,
      TetrominoType.Z,
      TetrominoType.J,
    ],
    policy: BotPolicy.scripted,
    // The Os fill the notches in the left surface. Rotation `spawn` is the I
    // lying flat; column 14 spans 14–17, across the mouth of the well.
    script: [
      (RotationState.spawn, 5),
      (RotationState.spawn, 3),
      (RotationState.spawn, 14),
    ],
    tickMs: 170,
  ),

  // ── 3 ── death by inattention ────────────────────────────────────────
  Reel(
    name: '03_blunder_ignore_rise',
    blurb:
        'Walks up to every clear on the board and refuses it while the floor '
        'climbs, until it tops out.',
    seconds: 30,
    policy: BotPolicy.blunder,
    blunderRate: 1.0,
    // From an empty board at 2.6 this ran five rises in 25 seconds and never
    // came near the top, so it starts on a built stack, with an open slot the
    // blunder policy will conspicuously never fill, and a faster floor.
    layout: _slotBoard,
    riseSpeed: 5.0,
    elapsedSeconds: 150,
    openingHoldMs: 2000,
    startScore: 4180,
    tickMs: 140,
  ),

  // ── 4 ── the near miss ───────────────────────────────────────────────
  // Plays well enough to build a real chain setup, then throws roughly one
  // placement in three. The board stays legible, so the mistake is always
  // the thing the viewer notices.
  Reel(
    name: '04_near_miss',
    blurb:
        'One placement from a five-chain, and it buries the whole thing '
        'instead. Plays well between the mistakes.',
    seconds: 25,
    layout: _deepWellBoard,
    openingHoldMs: 2000,
    policy: BotPolicy.blunder,
    blunderRate: 0.34,
    startScore: 15600,
    elapsedSeconds: 90,
    tickMs: 145,
  ),

  // ── 5 ── the long one ────────────────────────────────────────────────
  Reel(
    name: '05_long_form',
    blurb:
        'A minute of mixed play for a YouTube promo URL — competent opening, '
        'a bad stretch, then a recovery.',
    seconds: 60,
    policy: BotPolicy.blunder,
    blunderRate: 0.18,
    startScore: 2400,
    riseSpeed: 1.3,
    tickMs: 135,
  ),

  // ── 6 ── the long grind ──────────────────────────────────────────────
  // Two minutes of dense, deteriorating survival. Same unclearable-ish base
  // as the listing cut, but the difficulty clock starts early and runs the
  // full two minutes, so the fall speed and the rise both climb inside the
  // take rather than sitting at one rate.
  Reel(
    name: '06_endurance_2min',
    blurb:
        'Two minutes of dense survival: the board stays full and the pace '
        'climbs on the difficulty curve. The grinding cut.',
    seconds: 120,
    startScore: 4800,
    tickMs: 120,
    // Bracketed by two bad takes. At 1.4 the bot had eroded the seeded base
    // by t=30 and the remaining ninety seconds ran near-empty (mean luma 198,
    // 37 of 60 samples sparse). At 2.8 it went the other way and topped out
    // at t=96, so the reel ended on twenty-four seconds of GAME OVER screen —
    // which is the one thing a promo cut must not do. Reel 7 survives 120s at
    // 2.4, but its bot ticks at 105ms against this one's 120ms and therefore
    // clears more, so the safe value here sits below it. 2.0 held a dense
    // board the whole way (mean luma 171, nothing sparse) but still topped
    // out at t=114 — density and survival pull against each other over two
    // minutes. There is no stable middle: 1.4 and 1.8 both let the bot
    // out-clear the floor and the board sat near-empty for ninety seconds
    // (mean luma 198/199), while 2.0 and above let the floor win and the run
    // died before the end. So this takes the dense side deliberately and
    // `trim_reel.py` cuts the take before the top-out — a board nearly
    // buried is a better close for an endurance cut than an empty one.
    riseSpeed: 2.0,
    elapsedSeconds: 60,
    layout: _skilledBoard,
    openingHoldMs: 1200,
    pieces: [
      TetrominoType.I,
      TetrominoType.T,
      TetrominoType.L,
      TetrominoType.O,
      TetrominoType.J,
      TetrominoType.S,
      TetrominoType.Z,
    ],
  ),

  // ── 7 ── the long chain ──────────────────────────────────────────────
  // The other two minutes, deliberately unlike reel 6: where that one is a
  // board that stays full and grinds, this one repeatedly collapses. The
  // cascade base chains on almost every clear, and a fast rise refills it,
  // so the take is a sequence of big shatter events rather than a slow
  // build. Same honest skilled policy — the drama is the board, not a bot
  // throwing the game.
  Reel(
    name: '07_cascade_2min',
    blurb:
        'Two minutes of ripple gravity: clears chain down the stack, a fast '
        'floor refills it, repeat. The showy cut.',
    seconds: 120,
    startScore: 9100,
    tickMs: 105,
    riseSpeed: 2.4,
    elapsedSeconds: 180,
    layout: _cascadeBoard,
    openingHoldMs: 1200,
  ),

  // ── 8–14 ── the paid frustration cuts ────────────────────────────────
  // Built for the Google Ads video set (`tools/store/ad_videos.json`). Each
  // one is a single legible mistake on a board authored so the right move is
  // obvious. All of them are the shipped game played badly on purpose —
  // nothing is drawn on, and the bot is steering the real piece.

  // The hover. The I goes vertical, hangs over the well, drifts off it and
  // back twice — and then lies down flat across the top of it.
  Reel(
    name: '08_edge_hover',
    blurb:
        'The I hovers over the nine-deep well, wobbles off it and back, and '
        'then goes down flat across the top.',
    seconds: 25,
    layout: _deepWellBoard,
    startScore: 11260,
    elapsedSeconds: 20,
    openingHoldMs: 2500,
    dealFirst: true,
    pieces: [
      TetrominoType.O,
      TetrominoType.I,
      TetrominoType.T,
      TetrominoType.S,
      TetrominoType.L,
      TetrominoType.Z,
      TetrominoType.J,
      TetrominoType.O,
    ],
    policy: BotPolicy.scripted,
    script: [(RotationState.spawn, 5), (RotationState.spawn, 14)],
    // `right` puts the I's cells in anchor column + 2, so 15 is over the well.
    feintPiece: 1,
    feintRotations: 1,
    feintColumns: [15, 13, 15, 14, 15],
    feintDwellMs: [1400, 500, 1100, 350, 900],
    tickMs: 170,
  ),

  Reel(
    name: '09_one_off',
    blurb:
        'A four-deep slot, a vertical I, and it lands one column to the right '
        'of it.',
    seconds: 15,
    layout: _slotBoard,
    startScore: 7420,
    elapsedSeconds: 20,
    openingHoldMs: 2000,
    dealFirst: true,
    pieces: [
      TetrominoType.O,
      TetrominoType.I,
      TetrominoType.T,
      TetrominoType.L,
      TetrominoType.J,
      TetrominoType.S,
      TetrominoType.Z,
    ],
    policy: BotPolicy.scripted,
    script: [(RotationState.spawn, 11), (RotationState.right, 8)],
    tickMs: 170,
  ),

  Reel(
    name: '10_last_chance_topout',
    blurb:
        'Stacked to the ceiling with a four-row clear waiting in the well. The '
        'I goes flat in the middle and the floor finishes it.',
    seconds: 22,
    layout: _lastChanceBoard,
    startScore: 18950,
    elapsedSeconds: 150,
    riseSpeed: 4.0,
    openingHoldMs: 3000,
    dealFirst: true,
    pieces: [
      TetrominoType.I,
      TetrominoType.O,
      TetrominoType.O,
      TetrominoType.T,
      TetrominoType.O,
    ],
    policy: BotPolicy.scripted,
    script: [(RotationState.spawn, 7)],
    tickMs: 180,
  ),

  Reel(
    name: '11_tower_middle',
    blurb:
        'Six I-pieces stood on end in the same column while the floor rises '
        'underneath the tower.',
    seconds: 25,
    layout: _towerBoard,
    startScore: 5310,
    elapsedSeconds: 30,
    riseSpeed: 3.0,
    openingHoldMs: 2000,
    dealFirst: true,
    pieces: [
      TetrominoType.I,
      TetrominoType.I,
      TetrominoType.I,
      TetrominoType.I,
      TetrominoType.I,
      TetrominoType.I,
      TetrominoType.O,
      TetrominoType.T,
      TetrominoType.O,
      TetrominoType.L,
    ],
    policy: BotPolicy.scripted,
    script: [
      (RotationState.right, 6),
      (RotationState.right, 6),
      (RotationState.right, 6),
      (RotationState.right, 6),
      (RotationState.right, 6),
      (RotationState.right, 6),
    ],
    tickMs: 190,
  ),

  // The same hover, the other way round: it hangs over the slot that clears
  // four, then drives across the board into the decoy that clears nothing.
  Reel(
    name: '12_wrong_slot',
    blurb:
        'Two slots. The I hovers over the one that clears four rows, then '
        'goes into the one that clears none.',
    seconds: 20,
    layout: _twoSlotsBoard,
    startScore: 8830,
    elapsedSeconds: 20,
    openingHoldMs: 2000,
    dealFirst: true,
    pieces: [
      TetrominoType.I,
      TetrominoType.O,
      TetrominoType.T,
      TetrominoType.S,
      TetrominoType.Z,
      TetrominoType.L,
      TetrominoType.J,
    ],
    policy: BotPolicy.scripted,
    script: [(RotationState.right, 11)],
    feintPiece: 0,
    feintRotations: 1,
    feintColumns: [2, 3, 2, 6],
    feintDwellMs: [1300, 400, 900, 300],
    tickMs: 170,
  ),

  Reel(
    name: '13_wrong_rotation',
    blurb:
        'An L that fills the trough lying flat gets turned upside down and '
        'leaves two holes under it.',
    seconds: 15,
    layout: _troughBoard,
    startScore: 6140,
    elapsedSeconds: 20,
    openingHoldMs: 2000,
    dealFirst: true,
    pieces: [
      TetrominoType.L,
      TetrominoType.O,
      TetrominoType.T,
      TetrominoType.S,
      TetrominoType.Z,
      TetrominoType.J,
      TetrominoType.I,
    ],
    policy: BotPolicy.scripted,
    // `flip` hangs the L's foot down on the left; flat (`spawn`) was the fit.
    script: [(RotationState.flip, 8)],
    tickMs: 200,
  ),

  Reel(
    name: '14_waiting_for_i',
    blurb:
        'A sixteen-deep well, kept open for an I that never comes, while the '
        'floor pushes the whole stack into the ceiling.',
    seconds: 30,
    layout: _longWellBoard,
    startScore: 14720,
    elapsedSeconds: 150,
    riseSpeed: 3.0,
    openingHoldMs: 2000,
    dealFirst: true,
    pieces: _waitingPieces,
    policy: BotPolicy.scripted,
    script: _waitingScript,
    tickMs: 140,
  ),
];

Reel reelNamed(String name) => reels.firstWhere(
  (r) => r.name == name,
  orElse: () => throw ArgumentError(
    'unknown reel "$name"; have ${reels.map((r) => r.name).join(', ')}',
  ),
);
