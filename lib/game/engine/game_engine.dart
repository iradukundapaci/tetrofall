import 'dart:math';

import '../config/motion.dart';
import 'booster_engine.dart';
import 'clear_detector.dart';
import 'column_cascade.dart';
import 'combo_tier.dart';
import 'events.dart';
import 'gravity_resolver.dart';
import 'grid.dart';
import 'piece_controller.dart';
import 'rise_controller.dart';
import 'scoring.dart';
import 'special_blocks.dart';
import 'tetromino.dart';

/// See game.md §3.3. PAUSED/BOOSTER_ARMED and the rise-driven transition
/// out of PLAYING join in later phases.
enum GamePhase { ready, spawning, playing, resolving, gameOver }

enum GameIntentType {
  moveLeft,
  moveRight,
  rotateCW,
  rotateCCW,
  softDropStart,
  softDropEnd,
  hardDrop,
}

/// Which sub-step of RESOLVING is waiting on its timer (Phase 5): the
/// shatter sequence plays first (§2.3), then the cascade fall (§2.2), then
/// the chain rescans. Particles themselves are not gated by either stage —
/// they outlive RESOLVING entirely.
enum _ResolveStage { shatter, cascade }

/// Pure-Dart state machine + tick order (§3.4, trimmed to what Phase 1-3
/// need). UI/render reads state and sends intents; the engine emits
/// [GameEvent]s. Zero Flame or Flutter imports.
class GameEngine {
  GameEngine({Random? random, Grid? grid})
    : grid = grid ?? Grid(),
      _random = random ?? Random() {
    pieceController = PieceController(this.grid);
    riseController = RiseController(this.grid, random: _random);
    bag = SevenBag(_random);
  }

  final Grid grid;
  final Random _random;

  late final PieceController pieceController;
  late final RiseController riseController;
  late final SevenBag bag;

  final Scoring scoring = Scoring();
  final BoosterEngine boosterEngine = BoosterEngine();

  GamePhase phase = GamePhase.ready;

  /// Swappable at runtime (e.g. from the debug screen) to play-test
  /// [ColumnCascade] against `StickyGroup` — see §1.6.
  GravityResolver resolver = ColumnCascade();

  /// Cascade chain link count for the resolve currently in progress.
  /// Resets to 0 at the start of each new resolve; each follow-up clear
  /// within the same resolve increments it (§1.6, §1.7).
  int chainIndex = 0;

  /// Time remaining before RESOLVING advances to its next stage — first
  /// the shatter sequence (§2.3), then the cascade fall (§2.2's formula,
  /// computed here in pure Dart) — so gameplay doesn't resume mid-animation
  /// even though the grid data itself is already final (§3.1).
  double _resolveTimer = 0;
  _ResolveStage _resolveStage = _ResolveStage.shatter;

  /// Which banner tiers have already fired within the resolve currently in
  /// progress — each tier fires at most once per resolve, the moment
  /// [Scoring.blocksDestroyedThisResolve] first crosses its threshold.
  final Set<ComboTier> _bannerTiersEmitted = {};

  final _intentQueue = <GameIntentType>[];
  final _eventListeners = <void Function(GameEvent)>[];

  void addEventListener(void Function(GameEvent) listener) =>
      _eventListeners.add(listener);

  void removeEventListener(void Function(GameEvent) listener) =>
      _eventListeners.remove(listener);

  void _emit(GameEvent event) {
    for (final listener in List.of(_eventListeners)) {
      listener(event);
    }
  }

  void enqueueIntent(GameIntentType intent) => _intentQueue.add(intent);

  /// Starts (or restarts) a run: clears the grid and spawns the first
  /// piece.
  void start() {
    grid.clearAll();
    _intentQueue.clear();
    riseController.reset();
    scoring.reset();
    phase = GamePhase.spawning;
    _trySpawn();
  }

  /// One simulation frame. See §3.4 for the full tick order — Phase 1
  /// only needs intents → gravity/lock → transitions.
  void tick(double dt) {
    _drainIntents();

    switch (phase) {
      case GamePhase.ready:
        return;
      case GamePhase.spawning:
        _trySpawn();
      case GamePhase.playing:
        boosterEngine.tickTimedEffects(dt);
        scoring.scoreMultiplierActive = boosterEngine.scoreMultiplierActive;
        // Rise ticks before gravity and is never frozen while a piece is
        // merely falling — the two pressures must overlap (§1.4) — except
        // for the Time Freeze booster, which exists specifically to halt
        // the rise timer for its duration (§1.9).
        if (!boosterEngine.timeFreezeActive && riseController.tick(dt)) {
          _handleRiseCommit();
        }
        if (phase == GamePhase.playing) {
          // §1.10: gravity's own difficulty checkpoint, read from the same
          // clock the rise timeline uses (Phase 6).
          pieceController.dropInterval = riseController.difficultyNow.dropInterval;
          // Arming a booster pauses gravity but not the rise (§1.9) — the
          // two pressures above only ever pause together during RESOLVING.
          if (boosterEngine.armed == null) {
            final result = pieceController.tick(dt);
            if (pieceController.softDropRowsAccrued > 0) {
              scoring.awardDrop(rows: pieceController.softDropRowsAccrued, hard: false);
              pieceController.softDropRowsAccrued = 0;
            }
            if (result == PieceTickResult.locked) {
              _lockAndResolve();
            }
          }
        }
      case GamePhase.resolving:
        // The difficulty clock keeps advancing through long cascades
        // (§6.4) — only the rise progress itself pauses.
        riseController.tickElapsedOnly(dt);
        if (_resolveTimer > 0) {
          _resolveTimer -= dt;
          if (_resolveTimer <= 0) {
            switch (_resolveStage) {
              case _ResolveStage.shatter:
                _runCascade();
              case _ResolveStage.cascade:
                _resolvePass();
            }
          }
        }
      case GamePhase.gameOver:
        return;
    }
  }

  void _drainIntents() {
    if (phase != GamePhase.playing) {
      _intentQueue.clear();
      return;
    }
    for (final intent in _intentQueue) {
      switch (intent) {
        case GameIntentType.moveLeft:
          pieceController.moveLeft();
        case GameIntentType.moveRight:
          pieceController.moveRight();
        case GameIntentType.rotateCW:
          pieceController.rotateCW();
        case GameIntentType.rotateCCW:
          pieceController.rotateCCW();
        case GameIntentType.softDropStart:
          pieceController.softDropActive = true;
        case GameIntentType.softDropEnd:
          pieceController.softDropActive = false;
        case GameIntentType.hardDrop:
          final rows = pieceController.hardDrop();
          scoring.awardDrop(rows: rows, hard: true);
          _lockAndResolve();
      }
    }
    _intentQueue.clear();
  }

  /// A rise commit boundary was crossed this tick (§1.4). Top-out ends the
  /// run instead of committing; otherwise the grid shifts and the active
  /// piece is carried with it — pushed up one more row if the shift now
  /// overlaps it.
  void _handleRiseCommit() {
    if (riseController.wouldTopOut()) {
      phase = GamePhase.gameOver;
      _emit(const GameOverEvent(GameOverReason.topOut));
      return;
    }

    riseController.commitRise();

    final piece = pieceController.piece;
    if (piece != null) {
      final originalRow = piece.anchorRow;
      final shiftedRow = originalRow - 1;
      final pushedRow = shiftedRow - 1;
      if (shiftedRow >= grid.minRow &&
          !pieceController.collidesAt(shiftedRow, piece.anchorCol)) {
        piece.anchorRow = shiftedRow;
      } else if (pushedRow >= grid.minRow &&
          !pieceController.collidesAt(pushedRow, piece.anchorCol)) {
        piece.anchorRow = pushedRow;
      } else if (!pieceController.collidesAt(originalRow, piece.anchorCol)) {
        // Couldn't carry it up any further, but not because anything's
        // actually blocking it — it's simply already at the hidden spawn
        // buffer's ceiling (this fires almost every time a piece spawns
        // right before a rise commit lands). Leaving it at its pre-commit
        // row costs one frame of it lagging a row behind the rest of the
        // scrolling board — harmless, and self-corrects as soon as it next
        // drops. The old behavior force-locked here instead, which is the
        // bug: `RiseController.commitRise` never shifts or clears rows
        // below 0, so a lock at this ceiling silently plants a permanent,
        // invisible block in the hidden buffer — jamming that column's
        // spawn for the rest of the run until a later, seemingly random
        // block-out (reported: "game over before I could reach the top").
        piece.anchorRow = originalRow;
      } else {
        // Its own pre-commit position is now genuinely occupied by a
        // settled block that just rose into it (a real wall, not the
        // ceiling) — there's truly nowhere left for it. That's a top-out.
        phase = GamePhase.gameOver;
        _emit(const GameOverEvent(GameOverReason.topOut));
        return;
      }
    }
    _emit(const RiseCommittedEvent());
  }

  void _trySpawn() {
    final type = bag.next();
    final spawned = pieceController.spawn(type);
    if (!spawned) {
      phase = GamePhase.gameOver;
      _emit(const GameOverEvent(GameOverReason.blockOut));
      return;
    }
    phase = GamePhase.playing;
    _emit(const PieceSpawnedEvent());
  }

  void _lockAndResolve() {
    if (pieceController.piece == null) return;
    pieceController.lockPiece();
    // Soft drop is a per-piece input state; it must never survive a lock —
    // otherwise a hard drop that skips the soft-drop-end intent (or any
    // other missed transition) would leave every following piece falling
    // at the soft-drop rate forever.
    pieceController.softDropActive = false;
    pieceController.softDropRowsAccrued = 0;
    scoring.awardPlacement();
    _emit(const PieceLockedEvent());
    _beginResolve();
    _resolvePass();
  }

  /// Enters RESOLVING fresh: phase, chain counter, and per-resolve scoring
  /// all reset. Shared by both entry points that can start a chain: a
  /// normal lock (which then runs [_resolvePass] to find what cleared),
  /// and a booster destruction (§1.9's "every booster removal triggers a
  /// normal cascade + clear check", which already knows what it destroyed
  /// and skips straight to the shatter).
  void _beginResolve() {
    phase = GamePhase.resolving;
    chainIndex = 0;
    scoring.startResolve();
    _bannerTiersEmitted.clear();
  }

  /// One clear + shatter + cascade pass. Runs immediately after
  /// [_beginResolve], then again each time the chain rescan (end of
  /// [_runCascade]) finds another full row — that's the chain-rescan loop
  /// (§1.6): clear, shatter, drop, rescan, repeat until a pass finds
  /// nothing to clear.
  void _resolvePass() {
    final fullRows = ClearDetector.findFullRows(grid);
    if (fullRows.isEmpty) {
      _resolveTimer = 0;
      phase = GamePhase.spawning;
      return;
    }

    final outcome = SpecialBlocks.resolve(grid, fullRows);
    scoring.addDestroyed(outcome.removedCells.length);
    scoring.awardLineClear(
      lines: fullRows.length,
      chainIndex: chainIndex,
      elapsedSeconds: riseController.elapsed,
    );
    // A small coin drip on every clear (§5) so the wallet isn't
    // permanently 0 for players who never survive to a Diamond/Treasure.
    scoring.addCoins(fullRows.length);
    if (outcome.goldCleared > 0) scoring.awardGold(outcome.goldCleared);
    if (outcome.diamondCleared > 0) scoring.addCoins(outcome.diamondCleared * 5);
    for (var i = 0; i < outcome.treasureCleared; i++) {
      _rollTreasureReward();
    }
    _checkComboBanners();
    _startShatterThenCascade(fullRows, outcome.removedCells);
  }

  void _checkComboBanners() {
    for (final tier in ComboTier.values) {
      if (scoring.blocksDestroyedThisResolve >= tier.threshold &&
          _bannerTiersEmitted.add(tier)) {
        _emit(ComboBannerEvent(tier));
      }
    }
  }

  /// The shatter sequence (§2.3) is a blocking phase for game logic — the
  /// cascade doesn't start until it's done propagating outward from the
  /// row's center — but the shard particles themselves are not: they
  /// outlive RESOLVING entirely (§3.1, game.md Phase 5).
  void _startShatterThenCascade(List<int> rows, List<ClearedCell> removedCells) {
    _emit(RowsClearedEvent(rows, removedCells));
    _resolveStage = _ResolveStage.shatter;
    _resolveTimer = Motion.shatterSequenceSeconds(grid.cols);
  }

  /// Arms [type] if it's a valid HUD booster with a charge available and
  /// the game is actually being played right now. Returns whether arming
  /// succeeded, so the UI can show feedback either way.
  bool armBooster(BoosterType type) {
    if (phase != GamePhase.playing) return false;
    return boosterEngine.arm(type);
  }

  void disarmBooster() => boosterEngine.disarm();

  void useTimeFreeze() {
    if (phase == GamePhase.playing) boosterEngine.useTimeFreeze();
  }

  void useScoreMultiplier() {
    if (phase == GamePhase.playing) boosterEngine.useScoreMultiplier();
  }

  /// The player tapped board cell ([row], [col]) while a booster is armed
  /// (§1.9). Commits it if something was actually destroyed — which,
  /// like a line clear, can start a chain — or just disarms cleanly
  /// without spending a charge if the tap hit nothing.
  void tapBoosterTarget(int row, int col) {
    if (boosterEngine.armed == null || phase != GamePhase.playing) return;
    final removed = boosterEngine.commit(row, col, grid);
    if (removed.isEmpty) return;

    _beginResolve();
    scoring.addDestroyed(removed.length);
    _checkComboBanners();
    _startShatterThenCascade(const [], removed);
  }

  /// Runs the gravity resolver once the shatter sequence has finished
  /// propagating, then waits for the longest resulting fall (§2.2) before
  /// the next chain rescan.
  void _runCascade() {
    final falls = resolver.resolve(grid);
    if (falls.isNotEmpty) {
      _emit(
        BlocksFellEvent([
          for (final f in falls)
            BlockFallEvent(
              fromRow: f.fromRow,
              toRow: f.toRow,
              col: f.col,
              type: f.type,
            ),
        ]),
      );
    }
    _emit(ChainAdvancedEvent(chainIndex));
    chainIndex++;
    _resolveStage = _ResolveStage.cascade;
    _resolveTimer = _settleDuration(falls);
    if (_resolveTimer <= 0) {
      // Nothing fell (e.g. the cleared row(s) had nothing above them) —
      // rescan immediately rather than waiting for an animation that
      // isn't happening.
      _resolvePass();
    }
  }

  static const _treasureBoosterPool = [
    BoosterType.hammer,
    BoosterType.bomb,
    BoosterType.drill,
    BoosterType.lightning,
  ];

  /// Treasure's reward-table roll (§1.8): coins or a booster charge.
  void _rollTreasureReward() {
    if (_random.nextBool()) {
      scoring.addCoins(10 + _random.nextInt(21)); // 10-30
    } else {
      boosterEngine.addCharge(
        _treasureBoosterPool[_random.nextInt(_treasureBoosterPool.length)],
      );
    }
  }

  /// How long the render layer's longest fall + impact squash will take,
  /// computed with the same formula as §2.2 so RESOLVING doesn't let the
  /// player act again before the cascade is visually settled.
  double _settleDuration(List<BlockFall> falls) {
    if (falls.isEmpty) return 0;
    final maxDistance = falls
        .map((f) => (f.toRow - f.fromRow).abs())
        .reduce(max);
    if (maxDistance == 0) return 0;
    final fallSeconds = sqrt(2 * maxDistance / Motion.gravityCellsPerS2);
    return fallSeconds + Motion.impactSquash.inMilliseconds / 1000;
  }
}
