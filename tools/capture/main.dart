// Screenshot and video capture harness — android_release_plan.md §4.7.
//
// A SEPARATE ENTRYPOINT, not a flag inside main.dart. §4.7 suggests a
// `--dart-define=CAPTURE=true` branch that you then have to remember to
// assert-gate before release; a second entrypoint is strictly safer, because
// the release build never compiles this file at all. There is nothing to
// remember to remove.
//
//   # one still
//   flutter run -t tools/capture/main.dart --release --dart-define=SCENE=shatter
//
//   # one video reel, then `adb shell screenrecord` against it
//   flutter run -t tools/capture/main.dart --release --dart-define=REEL=blunder_well
//
// Scenes and reels are listed in `scenes.dart` and `reels.dart`.
//
// Ads: `AdsService.init()` is deliberately never called, so `canRequestAds`
// stays false and no ad can appear in any capture. On top of that every
// screen here is mounted `immersive: true`, which removes the banner's
// *reservation* as well — §4.7 requires zero ad slots visible, and an empty
// reserved slot is still a visible dead band.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tetrofall/game/ai/demo_bot.dart';
import 'package:tetrofall/game/engine/cell.dart';
import 'package:tetrofall/game/engine/events.dart';
import 'package:tetrofall/game/engine/game_engine.dart';
import 'package:tetrofall/game/tetrofall_game.dart';
import 'package:tetrofall/services/ads_service.dart';
import 'package:tetrofall/services/audio_service.dart';
import 'package:tetrofall/services/storage_service.dart';
import 'package:tetrofall/ui/screens/gameplay_screen.dart';
import 'package:tetrofall/ui/screens/main_menu_screen.dart';
import 'package:tetrofall/ui/theme/tokens.dart';

import 'reels.dart';
import 'scenes.dart';

const _sceneName = String.fromEnvironment('SCENE');
const _reelName = String.fromEnvironment('REEL');

/// Overrides for iterating on a shot without editing `scenes.dart` and
/// waiting on another release build.
const _freezeOverride = int.fromEnvironment('FREEZE_MS', defaultValue: -1);
const _settleOverride = int.fromEnvironment('SETTLE_MS', defaultValue: -1);

/// Seeded so a reel replays identically — the blunder has to land on the same
/// frame every take, or re-recording it means re-authoring it.
const _seed = int.fromEnvironment('SEED', defaultValue: 20260905);

/// Printed once the board is seeded and the first frame is up. `capture.sh`
/// blocks on this in logcat, which is the only reliable way to know the app
/// is actually on screen — cold-start time varies by seconds under load.
const _readyMarker = 'TETROFALL_CAPTURE_READY';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // The status and nav bars are the last chrome standing between the board
  // and the full 1080x1920 frame. `immersiveSticky` keeps them gone even if
  // something swipes at the edge mid-recording.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final storage = await StorageService.load();
  final ads = AdsService(storage);

  // `AudioService.play` is a no-op until `warmUp` has built the voice rings,
  // and only `lib/main.dart` calls it — so every reel shot from this
  // entrypoint was silent no matter what the SFX slider said. Reels are
  // mirrored with scrcpy, which does carry audio, so warm the rings here too.
  // Unawaited for the same reason `lib/main.dart` does it: loading nine
  // players must not hold up the first frame, and the ready marker below is
  // what `capture.sh` gates the recording on.
  unawaited(AudioService.warmUp());

  if (_reelName.isNotEmpty) {
    runApp(_CaptureApp(child: await _mountReel(reelNamed(_reelName), storage, ads)));
    return;
  }

  final scene = sceneNamed(_sceneName.isEmpty ? 'shatter' : _sceneName);
  // BEST is read once in the HUD's initState, so it has to be in storage
  // before the first frame rather than seeded alongside the board.
  await storage.saveBestScore(scene.best0);
  runApp(_CaptureApp(child: _mountScene(scene, storage, ads)));
}

class _CaptureApp extends StatelessWidget {
  const _CaptureApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
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
    home: child,
  );
}

// ─── stills ──────────────────────────────────────────────────────────────

Widget _mountScene(Scene scene, StorageService storage, AdsService ads) {
  if (scene.screen == SceneScreen.menu) {
    return MainMenuScreen(storage: storage, ads: ads);
  }
  return GameplayScreen(
    storage: storage,
    ads: ads,
    immersive: true,
    startTutorial: scene.screen == SceneScreen.tutorial,
    onGameCreated: (game) => _StillDirector(scene, game).run(),
  );
}

/// Drives one scene from "the game just mounted" to "the frame is frozen and
/// ready to photograph".
class _StillDirector {
  _StillDirector(this.scene, this.game);

  final Scene scene;
  final TetrofallGame game;

  int get _settle =>
      _settleOverride >= 0 ? _settleOverride : scene.settleMs;
  int get _freeze => _freezeOverride >= 0 ? _freezeOverride : scene.freezeMs;

  void run() {
    if (scene.screen == SceneScreen.tutorial) {
      // The tutorial rigs its own board and scripts its own pieces; seeding
      // over the top of it would fight the coach. Just let it get to a step
      // worth photographing.
      Timer(Duration(milliseconds: _settle), _freezeNow);
      return;
    }

    // `onLoad()` is async and starts the engine; seeding has to land after
    // it, or `engine.start()` wipes the grid straight back out.
    Timer(const Duration(milliseconds: 700), () {
      _seedBoard();
      switch (scene.action) {
        case SceneAction.still:
          Timer(Duration(milliseconds: _settle), _freezeNow);
        case SceneAction.dropInFlight:
          _dropInFlight();
        case SceneAction.clearAndFreeze:
          _clearAndFreeze();
      }
      if (scene.screen == SceneScreen.gameOver) _forceGameOver();
    });
  }

  void _seedBoard() {
    final engine = game.engine;
    final grid = engine.grid;
    for (var i = 0; i < scene.layout.length; i++) {
      final row = grid.maxRow - i;
      final line = scene.layout[i];
      for (var col = 0; col < grid.cols; col++) {
        final filled = col < line.length && line[col] == '#';
        grid.set(row, col, filled ? Cell(BlockType.wood) : null);
      }
    }

    // Seed the difficulty clock too, so a "late game" board is actually
    // running at late-game speed rather than only claiming to on the HUD.
    engine.riseController.elapsed = scene.elapsedSeconds.toDouble();

    // Then stop the rise. A still is shot up to fifteen seconds after
    // seeding, and a live rise commits several rows in that time — the
    // authored layout walks up and off the top of the frame and the shot
    // becomes whatever the board drifted into. `riseProgress` is set by hand
    // at freeze time instead, which is also the only way to catch the pending
    // row mid-push rather than settled.
    engine.freezeRise = true;

    // A still also freezes gravity. Without it the piece spawns and creeps
    // down through the two hidden rows, so the shot catches it half-clipped
    // by the top edge — and, over a long settle, lands and changes the board
    // that was authored. Frozen, it stays in the spawn buffer and out of
    // frame, leaving the stack as the whole subject.
    if (scene.action == SceneAction.still) engine.freezeGravity = true;

    // `Scoring` notifies through a private `_notify()`, so writing `score`
    // alone never reaches the HUD, which listens rather than polls. Awarding
    // a zero-line clear adds nothing to the score and fires that
    // notification — a public way to get the seeded value on screen without a
    // production change made only for the capture harness.
    engine.scoring.score = scene.score;
    engine.scoring.awardLineClear(lines: 0, chainIndex: 0, elapsedSeconds: 0);
  }

  /// Hands the bot the scene's piece and lets it find the clear itself. The
  /// boards are authored one move from a multi-row clear, so the skilled
  /// search lands on that move without a scripted placement to maintain.
  void _clearAndFreeze() {
    final engine = game.engine;
    var armed = false;
    engine.addEventListener((event) {
      if (event is RowsClearedEvent && !armed) {
        armed = true;
        Timer(Duration(milliseconds: _freeze), _freezeNow);
      }
    });
    final bot = DemoBot(random: math.Random(_seed));
    engine.addEventListener((event) {
      if (event is! PieceSpawnedEvent) return;
      final piece = engine.pieceController.piece;
      if (piece != null) bot.onPieceSpawned(engine.grid, piece.type);
    });
    _handPiece();
    Timer.periodic(const Duration(milliseconds: 45), (t) {
      if (game.paused || armed) {
        t.cancel();
        return;
      }
      bot.tick(engine);
    });

    // If the clear never fires — an edited layout that is no longer one move
    // from completing a row — freeze anyway. A wrong frame is a fixable
    // result; a bot playing on forever until the screencap lands is a
    // different board every run and diagnoses nothing.
    Timer(const Duration(seconds: 8), () {
      if (!armed) _freezeNow();
    });
  }

  /// Leaves the piece hanging in mid-air with its ghost on the landing row.
  /// Soft drop rather than gravity: at the opening `dropInterval` of 1000ms a
  /// piece takes six seconds to clear the two hidden spawn rows, and freezing
  /// before then photographs an empty sky.
  void _dropInFlight() {
    final engine = game.engine;
    // Arm on the spawn, not on the call. `respawnPiece()` only moves the
    // engine into `spawning`; the piece itself arrives on a later tick, and
    // an intent enqueued in between is drained against no piece and lost —
    // which left the piece sitting in the spawn rows, clipped by the top of
    // the frame, with its ghost a dozen rows below it.
    var armed = false;
    engine.addEventListener((event) {
      if (event is! PieceSpawnedEvent || armed) return;
      armed = true;
      engine.enqueueIntent(GameIntentType.softDropStart);
      Timer(Duration(milliseconds: _settle), () {
        engine.enqueueIntent(GameIntentType.softDropEnd);
        _freezeNow();
      });
    });
    _handPiece();
  }

  void _handPiece() {
    final piece = scene.piece;
    if (piece == null) return;
    game.engine
      ..queuePieces([piece])
      ..respawnPiece();
  }

  /// Blocks the spawn rows so the next spawn collides.
  ///
  /// `GameplayScreen` raises its overlay off `GameOverEvent`, not off
  /// `engine.phase` — writing the phase directly stranded the screen with a
  /// finished board and no overlay on it. `_trySpawn` failing is the engine's
  /// own block-out path, so this reaches the overlay the way a real loss does.
  void _forceGameOver() {
    Timer(Duration(milliseconds: _settle ~/ 2), () {
      final grid = game.engine.grid;
      for (var row = grid.minRow; row < 0; row++) {
        for (var col = 0; col < grid.cols; col++) {
          grid.set(row, col, Cell(BlockType.wood));
        }
      }
      game.engine.respawnPiece();
    });
  }

  /// Sets the sub-cell rise offset, gives the board one frame to render it,
  /// then stops the clock.
  ///
  /// The order matters: `BoardComponent.update` is what turns `riseProgress`
  /// into the content layer's offset, and a frozen clock never runs `update`.
  /// Setting it after the freeze would leave the pending row sitting flush
  /// under the floor — the settled state, which is exactly the state the
  /// rise-pressure shot exists to avoid showing.
  void _freezeNow() {
    if (scene.riseProgress > 0) {
      game.engine.riseController.riseProgress = scene.riseProgress;
    }
    Timer(const Duration(milliseconds: 50), game.freezeForCapture);
  }
}

// ─── reels ───────────────────────────────────────────────────────────────

Future<Widget> _mountReel(
  Reel reel,
  StorageService storage,
  AdsService ads,
) async {
  await storage.saveBestScore(reel.best);
  return GameplayScreen(
    storage: storage,
    ads: ads,
    immersive: true,
    onGameCreated: (game) => _ReelDirector(reel, game).run(),
  );
}

/// Plays a reel: a scripted opening if it has one, then a bot playing under
/// the reel's policy for as long as the recording lasts.
class _ReelDirector {
  _ReelDirector(this.reel, this.game);

  final Reel reel;
  final TetrofallGame game;

  late final DemoBot _bot = DemoBot(
    policy: reel.policy,
    random: math.Random(_seed),
    script: reel.script,
    blunderRate: reel.blunderRate,
  );

  void run() {
    Timer(const Duration(milliseconds: 700), () {
      final engine = game.engine;
      if (reel.layout.isNotEmpty) _seedBoard(engine);
      if (reel.pieces.isNotEmpty) engine.queuePieces(reel.pieces);
      engine.riseController
        ..elapsed = reel.elapsedSeconds.toDouble()
        ..debugSpeedMultiplier = reel.riseSpeed;
      engine.scoring.score = reel.startScore;
      engine.scoring.awardLineClear(lines: 0, chainIndex: 0, elapsedSeconds: 0);

      engine.addEventListener((event) {
        if (event is! PieceSpawnedEvent) return;
        final piece = engine.pieceController.piece;
        if (piece != null) _bot.onPieceSpawned(engine.grid, piece.type);
      });
      if (engine.pieceController.piece case final p?) {
        _bot.onPieceSpawned(engine.grid, p.type);
      }

      // Slower than a bot could go: the reels are meant to be watched, and a
      // piece that teleports into place reads as a simulation rather than as
      // someone playing.
      void startBot() {
        Timer.periodic(Duration(milliseconds: reel.tickMs), (_) {
          _bot.tick(engine);
        });
      }

      // Both of the next two things have to wait for the seeded board to be
      // *drawn*, not merely written to the grid.
      //
      // `freezeForCapture` stops Flame's clock, so calling it in the same
      // tick as `_seedBoard` freezes the board as it looked before the seed:
      // an empty board sitting under a seeded score, because the HUD is
      // Flutter widgets and repaints regardless. And `capture.sh` starts
      // `screenrecord` the moment it sees the ready marker, so printing that
      // early opens the take on the same stale frame.
      //
      // A couple of frames of grace fixes both. `openingHoldMs` then buys a
      // beat on the built board before the first piece moves — the hold is
      // Flame's clock stopped, without raising the player-facing pause
      // overlay; Dart timers are not driven by that clock, so these still
      // fire.
      Timer(const Duration(milliseconds: 150), () {
        if (reel.openingHoldMs > 0) {
          game.freezeForCapture();
          Timer(Duration(milliseconds: reel.openingHoldMs), () {
            game.resumeEngine();
            startBot();
          });
        } else {
          startBot();
        }

        // Only now is the board on screen, so only now is this true.
        debugPrint(_readyMarker);
      });
    });
  }

  void _seedBoard(GameEngine engine) {
    final grid = engine.grid;
    for (var i = 0; i < reel.layout.length; i++) {
      final row = grid.maxRow - i;
      final line = reel.layout[i];
      for (var col = 0; col < grid.cols; col++) {
        final filled = col < line.length && line[col] == '#';
        grid.set(row, col, filled ? Cell(BlockType.wood) : null);
      }
    }
  }
}
