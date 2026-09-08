/* Tetrofall playable ad — shared core.
 * See playable_ad_plan.md at the repo root for the full production plan this
 * implements. This file is concatenated into a single inline <script> by
 * build.py; it must never fetch anything or reference external files.
 *
 * Values marked "ported from lib/..." are copied from the real Dart source
 * so this demo's numbers stay honest. If those files change, re-check here.
 */
(function () {
  'use strict';

  // ---------------------------------------------------------------------
  // TF namespace — build.py appends a shim script *after* this file that
  // overrides TF.exitToStore for the target network. Without a shim (local
  // dev build), it just logs, so the whole demo runs standalone in a plain
  // browser tab.
  // ---------------------------------------------------------------------
  window.TF = window.TF || {};
  TF.exitToStore = TF.exitToStore || function () {
    console.log('[TF] exitToStore() — no network shim loaded (local build).');
  };
  TF.ASSETS = TF.ASSETS || {};

  // ---------------------------------------------------------------------
  // Audio — the real game's own lock/clear sounds (assets/audio/sfx/
  // block_settle.wav, wood_crush.wav), re-encoded small by
  // tools/prepare_assets.py and base64-inlined by build.py as
  // TF.ASSETS.sfxLock / .sfxClear. The AudioContext is created suspended
  // and only resumed on the player's first tap (see unsuspendIfNeeded
  // below) — Google rejects creatives that make sound without a user
  // gesture, and this also means Beat A's cold open stays silent by
  // construction with no special-casing: it plays out before any tap.
  // ---------------------------------------------------------------------
  (function setupAudio() {
    var AudioCtx = window.AudioContext || window.webkitAudioContext;
    var actx = AudioCtx ? new AudioCtx() : null;
    var buffers = { lock: null, clear: null };

    function decode(name, dataUri) {
      if (!actx || !dataUri) return;
      var b64 = dataUri.split(',')[1];
      var raw = atob(b64);
      var bytes = new Uint8Array(raw.length);
      for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
      actx.decodeAudioData(bytes.buffer, function (buf) {
        buffers[name] = buf;
      }, function () { /* decode failed — play() below just no-ops */ });
    }
    decode('lock', TF.ASSETS.sfxLock);
    decode('clear', TF.ASSETS.sfxClear);

    TF.audio = {
      unlock: function () {
        if (actx && actx.state === 'suspended') actx.resume();
      },
      play: function (name) {
        if (!actx || actx.state !== 'running' || !buffers[name]) return;
        var src = actx.createBufferSource();
        src.buffer = buffers[name];
        src.connect(actx.destination);
        src.start(0);
      }
    };
  })();

  // ---------------------------------------------------------------------
  // Palette — ported from lib/ui/theme/tokens.dart (Tokens class)
  // ---------------------------------------------------------------------
  var COLOR = {
    woodDark: '#4A2F1C',
    woodMid: '#7A5230',
    woodLight: '#C89B6A',
    bg: '#2B1C12',
    gold: '#F2B632',
    red: '#D9432E',
    blue: '#3AA0D9',
    purple: '#9B5CD6',
    green: '#4CAF6B',
    text: '#F5EAD9',
    textMuted: '#B9A889'
  };

  // ---------------------------------------------------------------------
  // Scoring — ported from lib/game/engine/scoring.dart
  // ---------------------------------------------------------------------
  var LINE_BASE_SCORE = { 1: 100, 2: 300, 3: 500, 4: 800 };
  var MAX_CHAIN_STEPS = 8; // chain multiplier caps at 1 + 0.5*8 = 5.0x

  function lineScoreFor(lines) {
    if (lines <= 0) return 0;
    var tabled = LINE_BASE_SCORE[lines];
    if (tabled != null) return tabled;
    return LINE_BASE_SCORE[4] + (lines - 4) * 300;
  }

  // ---------------------------------------------------------------------
  // Board — ported dimensions from lib/game/config/board_config.dart
  // ---------------------------------------------------------------------
  var COLS = 18;
  var ROWS_TOTAL = 34; // 32 visible + 2 hidden spawn rows in the real game

  // The real phone screen never shows all 34 rows at once either — only a
  // window around the action. VIEW_ROWS mirrors that: we render/interact
  // with the bottom slice of the grid, not the whole tall board.
  var VIEW_ROWS = 15;
  var VIEW_ROW_START = ROWS_TOTAL - VIEW_ROWS; // = 19

  // ---------------------------------------------------------------------
  // Canvas / layout
  // ---------------------------------------------------------------------
  var BASE_W = 360, BASE_H = 640; // 9:16, matches an 18:32 board ratio exactly
  var CELL = 18;
  var BOARD_X = Math.round((BASE_W - COLS * CELL) / 2); // 18
  var BOARD_Y = 130;
  var BOARD_BOTTOM = BOARD_Y + VIEW_ROWS * CELL; // 400

  // Meta safe zone (playable_ad_plan.md Section 1 / "Canvas safe zone"):
  // Instagram Stories/Reels and Facebook Feed overlay native chrome over the
  // top ~14% and bottom ~20-35% of a 9:16 placement. Every interactive
  // element and the persistent score readout stay inside this band. This is
  // applied in the shared core (not just the Meta build) so both network
  // variants share one layout and can't drift apart.
  var SAFE_TOP = Math.round(BASE_H * 0.15);   // 96
  var SAFE_BOTTOM = Math.round(BASE_H * 0.75); // 480

  var HUD_Y0 = SAFE_TOP, HUD_Y1 = BOARD_Y; // 96-130
  var BTN_Y0 = BOARD_BOTTOM, BTN_Y1 = SAFE_BOTTOM; // 400-480
  var BTN_ROTATE = { x: 110, y: (BTN_Y0 + BTN_Y1) / 2, r: 32 };
  var BTN_DROP = { x: 250, y: (BTN_Y0 + BTN_Y1) / 2, r: 32 };

  var canvas = document.getElementById('tf-canvas');
  var ctx = canvas.getContext('2d');
  var dpr = window.devicePixelRatio || 1;
  canvas.width = BASE_W * dpr;
  canvas.height = BASE_H * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  function fitCanvas() {
    var scale = Math.min(window.innerWidth / BASE_W, window.innerHeight / BASE_H);
    canvas.style.width = Math.floor(BASE_W * scale) + 'px';
    canvas.style.height = Math.floor(BASE_H * scale) + 'px';
  }
  window.addEventListener('resize', fitCanvas);
  fitCanvas();

  function toLogicalXY(clientX, clientY) {
    var rect = canvas.getBoundingClientRect();
    return {
      x: (clientX - rect.left) * (BASE_W / rect.width),
      y: (clientY - rect.top) * (BASE_H / rect.height)
    };
  }

  // ---------------------------------------------------------------------
  // Tetromino shapes — standard 7, classic bounding boxes. Rotation is a
  // generic 90°-CW matrix transform with no wall-kick table (the plan
  // explicitly says not to port SRS kicks — nothing in this scripted demo
  // needs them).
  // ---------------------------------------------------------------------
  var SHAPES = {
    I: [[0, 0, 0, 0], [1, 1, 1, 1], [0, 0, 0, 0], [0, 0, 0, 0]],
    O: [[1, 1], [1, 1]],
    T: [[0, 1, 0], [1, 1, 1], [0, 0, 0]],
    S: [[0, 1, 1], [1, 1, 0], [0, 0, 0]],
    Z: [[1, 1, 0], [0, 1, 1], [0, 0, 0]],
    J: [[1, 0, 0], [1, 1, 1], [0, 0, 0]],
    L: [[0, 0, 1], [1, 1, 1], [0, 0, 0]]
  };
  // No per-type color table: the real game draws the falling piece with the
  // exact same cached wood tile as settled blocks (block_component.dart
  // draws the same TileCache image used for the board), not a classic-
  // Tetris color-per-shape scheme. drawBlock below does the same — see
  // drawActivePiece for how the falling piece is told apart from locked
  // blocks (a light outline, our own addition since the real game relies
  // on it already being the only thing moving).

  function rotateMatrix(m) {
    var n = m.length, res = [];
    for (var r = 0; r < n; r++) res.push(new Array(n).fill(0));
    for (var r2 = 0; r2 < n; r2++) {
      for (var c = 0; c < n; c++) res[c][n - 1 - r2] = m[r2][c];
    }
    return res;
  }

  function verticalI() { return rotateMatrix(SHAPES.I); }

  function leftmostFilledCol(matrix) {
    for (var c = 0; c < matrix[0].length; c++) {
      for (var r = 0; r < matrix.length; r++) if (matrix[r][c]) return c;
    }
    return 0;
  }

  // ---------------------------------------------------------------------
  // Grid helpers
  // ---------------------------------------------------------------------
  function emptyRow() { return new Array(COLS).fill(null); }
  function emptyGrid() {
    var g = [];
    for (var r = 0; r < ROWS_TOTAL; r++) g.push(emptyRow());
    return g;
  }

  // fromBottom=0 is the bottommost row. gaps is an array of column indices
  // left empty; every other column becomes a wood block.
  function rigRowFromBottom(grid, fromBottom, gaps) {
    var row = ROWS_TOTAL - 1 - fromBottom;
    var gapSet = {};
    (gaps || []).forEach(function (c) { gapSet[c] = true; });
    for (var c = 0; c < COLS; c++) {
      grid[row][c] = gapSet[c] ? null : { wood: true };
    }
  }

  function fitsAt(grid, matrix, row, col) {
    for (var r = 0; r < matrix.length; r++) {
      for (var c = 0; c < matrix[r].length; c++) {
        if (!matrix[r][c]) continue;
        var gr = row + r, gc = col + c;
        if (gc < 0 || gc >= COLS || gr < 0 || gr >= ROWS_TOTAL) return false;
        if (grid[gr][gc]) return false;
      }
    }
    return true;
  }

  function computeDropRow(grid, matrix, row, col) {
    var r = row;
    while (fitsAt(grid, matrix, r + 1, col)) r++;
    return r;
  }

  function lockPiece(grid, matrix, row, col) {
    for (var r = 0; r < matrix.length; r++) {
      for (var c = 0; c < matrix[r].length; c++) {
        if (!matrix[r][c]) continue;
        var gr = row + r, gc = col + c;
        if (gr >= 0 && gr < ROWS_TOTAL) grid[gr][gc] = { wood: false };
      }
    }
  }

  function findBottommostFullRow(grid) {
    for (var r = ROWS_TOTAL - 1; r >= 0; r--) {
      var full = true;
      for (var c = 0; c < COLS; c++) if (!grid[r][c]) { full = false; break; }
      if (full) return r;
    }
    return -1;
  }

  function removeRowWithGravity(grid, row) {
    grid.splice(row, 1);
    grid.unshift(emptyRow());
  }

  // ---------------------------------------------------------------------
  // Juice: particles + screen shake
  // ---------------------------------------------------------------------
  var particles = [];
  var shakeMag = 0;

  function spawnShatter(row, intensity) {
    var y = BOARD_Y + (row - VIEW_ROW_START) * CELL + CELL / 2;
    if (row < VIEW_ROW_START) return; // above the viewport, nothing to draw
    for (var c = 0; c < COLS; c++) {
      var x = BOARD_X + c * CELL + CELL / 2;
      var n = 2 + intensity;
      for (var i = 0; i < n; i++) {
        // Small rotated rects rather than axis-aligned squares — a cheap
        // approximation of the real ShatterLayer's tinted polygon shards
        // (procedural facets, not a sprite — see the SHAPES comment above
        // for why nothing here needs an asset).
        particles.push({
          x: x, y: y,
          vx: (Math.random() - 0.5) * 220,
          vy: -80 - Math.random() * 160,
          rot: Math.random() * Math.PI * 2,
          vrot: (Math.random() - 0.5) * 10,
          life: 0.45 + Math.random() * 0.25,
          maxLife: 0.7,
          color: Math.random() < 0.5 ? COLOR.gold : COLOR.woodLight,
          w: 3 + Math.random() * 4,
          h: 2 + Math.random() * 3
        });
      }
    }
    shakeMag = Math.max(shakeMag, 3 + intensity * 2.5);
  }

  function updateParticles(dt) {
    for (var i = particles.length - 1; i >= 0; i--) {
      var p = particles[i];
      p.vy += 420 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vrot * dt;
      p.life -= dt;
      if (p.life <= 0) particles.splice(i, 1);
    }
    shakeMag = Math.max(0, shakeMag - dt * 18);
  }

  function drawParticles() {
    particles.forEach(function (p) {
      ctx.save();
      ctx.globalAlpha = Math.max(0, p.life / p.maxLife);
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rot);
      ctx.fillStyle = p.color;
      ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
      ctx.restore();
    });
    ctx.globalAlpha = 1;
  }

  // ---------------------------------------------------------------------
  // Captions (the tutorial's "instruction -> effect" rhythm, compressed)
  // ---------------------------------------------------------------------
  var caption = { text: '', until: 0, big: false };
  function showCaption(text, ms, big) {
    caption.text = text;
    caption.until = performance.now() + (ms || 1100);
    caption.big = !!big;
  }

  // ---------------------------------------------------------------------
  // Show state machine
  // ---------------------------------------------------------------------
  var BEAT = {
    A_COLD_OPEN: 'A', B_TITLE: 'B', C_GUIDED1: 'C', D_GUIDED2: 'D',
    E_FREEPLAY: 'E', F_PAYOFF: 'F', G_ENDCARD: 'G'
  };

  var show = {
    beat: null,
    beatEnteredAt: 0,
    grid: emptyGrid(),
    score: 0,
    maxChain: 0,
    resolving: false,
    resolveToken: 0, // bumped on every enterBeat() to invalidate in-flight chains (see resolveClears)
    startedAt: performance.now(),
    piece: null,       // {matrix, row, col, color}
    hintCol: null,
    allowDrop: false,
    allowMove: false,
    freeplayStep: 0,   // 0 or 1, which of the two free-play pieces is live
    idleTimer: null,
    autoTimer: null
  };

  function clearTimers() {
    if (show.idleTimer) { clearTimeout(show.idleTimer); show.idleTimer = null; }
    if (show.autoTimer) { clearTimeout(show.autoTimer); show.autoTimer = null; }
  }

  function elapsedSeconds() { return (performance.now() - show.startedAt) / 1000; }

  function awardClear(chainIndex) {
    var base = lineScoreFor(1);
    var capped = Math.min(chainIndex, MAX_CHAIN_STEPS);
    var chainMult = 1 + 0.5 * capped;
    var levelMult = 1 + (elapsedSeconds() / 60) * 0.1; // ported, cosmetic at this timescale
    show.score += Math.round(base * chainMult * levelMult);
    var chainLength = chainIndex + 1;
    if (chainLength > show.maxChain) show.maxChain = chainLength;
    showCaption(chainLength > 1 ? 'Chain x' + chainLength + '!' : 'Row cleared!', 900, chainLength > 2);
  }

  // `token` guards against a beat change happening mid-chain (e.g. the
  // player tapping to skip Beat A while its cold-open chain is still
  // playing out): enterBeat() bumps show.resolveToken, so any callback
  // from a now-stale chain sees a mismatched token and bails instead of
  // mutating the *new* beat's freshly-rigged grid.
  function resolveClears(cb, token, chainIndex) {
    if (token !== show.resolveToken) return;
    var row = findBottommostFullRow(show.grid);
    if (row === -1) { show.resolving = false; cb && cb(); return; }
    show.resolving = true;
    spawnShatter(row, chainIndex);
    TF.audio.play('clear'); // real game's wood_crush.wav, same event (RowsClearedEvent)
    setTimeout(function () {
      if (token !== show.resolveToken) return;
      removeRowWithGravity(show.grid, row);
      awardClear(chainIndex);
      resolveClears(cb, token, chainIndex + 1);
    }, 260);
  }
  function startResolve(cb) {
    resolveClears(cb, show.resolveToken, 0);
  }

  // ---------------------------------------------------------------------
  // Beat setup
  // ---------------------------------------------------------------------
  function enterBeat(beat) {
    clearTimers();
    show.resolveToken++; // invalidate any in-flight resolveClears chain from the previous beat
    show.resolving = false;
    show.beat = beat;
    show.beatEnteredAt = performance.now();
    show.piece = null;
    show.hintCol = null;
    show.allowDrop = false;
    show.allowMove = false;

    if (beat === BEAT.A_COLD_OPEN) setupColdOpen();
    else if (beat === BEAT.B_TITLE) setupTitle();
    else if (beat === BEAT.C_GUIDED1) setupGuided(1);
    else if (beat === BEAT.D_GUIDED2) setupGuided(2);
    else if (beat === BEAT.E_FREEPLAY) setupFreeplay();
    else if (beat === BEAT.F_PAYOFF) setupPayoff();
    else if (beat === BEAT.G_ENDCARD) setupEndcard();
  }

  function setupColdOpen() {
    show.grid = emptyGrid();
    rigRowFromBottom(show.grid, 0, []);
    rigRowFromBottom(show.grid, 1, []);
    rigRowFromBottom(show.grid, 2, []);
    rigRowFromBottom(show.grid, 3, []);
    setTimeout(function () { startResolve(function () {}); }, 250);
    show.autoTimer = setTimeout(function () { enterBeat(BEAT.B_TITLE); }, 3000);
  }

  function setupTitle() {
    show.autoTimer = setTimeout(function () { enterBeat(BEAT.C_GUIDED1); }, 2000);
  }

  // guidedNum: 1 -> beat C (single gap, drop only), 2 -> beat D (one move + drop)
  function setupGuided(guidedNum) {
    show.grid = emptyGrid();
    var targetCol, spawnCol;
    if (guidedNum === 1) {
      targetCol = 9;
      rigRowFromBottom(show.grid, 0, [targetCol]);
      spawnCol = 9;
      showCaption('Tap DROP to clear the row', 1400);
    } else {
      targetCol = 12;
      rigRowFromBottom(show.grid, 0, [targetCol]);
      rigRowFromBottom(show.grid, 1, [targetCol]);
      rigRowFromBottom(show.grid, 2, [targetCol]);
      spawnCol = 11; // one tap right reaches the gap
      showCaption('Move, then DROP', 1400);
    }
    var matrix = verticalI();
    var localCol = leftmostFilledCol(matrix);
    show.piece = { matrix: matrix, row: 6, col: spawnCol - localCol };
    show.hintCol = targetCol;
    show.allowDrop = true;
    show.allowMove = true;
    show.pendingTargetCol = targetCol;

    show.autoTimer = setTimeout(function () {
      performScriptedDrop(guidedNum === 1 ? BEAT.D_GUIDED2 : BEAT.E_FREEPLAY);
    }, 4200);
  }

  function setupFreeplay() {
    show.grid = emptyGrid();
    rigRowFromBottom(show.grid, 0, [7, 8, 9, 10]);
    show.freeplayStep = 0;
    showCaption('Your turn — clear the row!', 1400);
    spawnFreeplayPiece();
  }

  function spawnFreeplayPiece() {
    var defaultCol = show.freeplayStep === 0 ? 7 : 9;
    show.piece = { matrix: SHAPES.O.map(function (r) { return r.slice(); }), row: 6, col: defaultCol };
    show.allowDrop = true;
    show.allowMove = true;
    show.hintCol = null;
    show.autoTimer = setTimeout(function () { performFreeplayDrop(); }, 2600);
  }

  function setupPayoff() {
    show.grid = emptyGrid();
    var targetCol = 6;
    rigRowFromBottom(show.grid, 0, [targetCol]);
    rigRowFromBottom(show.grid, 1, [targetCol]);
    rigRowFromBottom(show.grid, 2, [targetCol]);
    rigRowFromBottom(show.grid, 3, [targetCol]);
    var matrix = verticalI();
    var localCol = leftmostFilledCol(matrix);
    show.piece = { matrix: matrix, row: 6, col: 5 - localCol };
    show.hintCol = targetCol;
    show.allowDrop = true;
    show.allowMove = true;
    show.pendingTargetCol = targetCol;
    showCaption('One more...', 1000);

    show.autoTimer = setTimeout(function () { performScriptedDrop(BEAT.G_ENDCARD); }, 3400);
  }

  function setupEndcard() {
    show.grid = emptyGrid();
    show.piece = null;
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------
  function moveActive(dir) {
    if (!show.piece || !show.allowMove || show.resolving) return;
    var p = show.piece;
    var newCol = p.col + dir;
    if (fitsAt(show.grid, p.matrix, p.row, newCol)) p.col = newCol;
  }

  function rotateActive() {
    if (!show.piece || !show.allowMove || show.resolving) return;
    var p = show.piece;
    var rotated = rotateMatrix(p.matrix);
    if (fitsAt(show.grid, rotated, p.row, p.col)) p.matrix = rotated;
  }

  // Guided/payoff beats: whatever the player did with move/rotate, the DROP
  // action snaps back to the authored rig (matrix + column) before landing
  // is computed. This is the "misplay safeguard" from the plan — move/
  // rotate taps still animate for feel, but a scripted beat can never fail
  // to land its chain because of a stray tap. Free-play (beat E) does NOT
  // snap; that beat's rig is just forgiving by design (a 4-wide gap).
  function performScriptedDrop(nextBeat) {
    if (!show.piece || show.resolving) return;
    clearTimers();
    var p = show.piece;
    // Unconditionally reset to the canonical vertical-I shape, undoing any
    // rotation the player applied — rotate/move stay purely cosmetic during
    // guided/payoff beats so a stray tap can never miss the rigged well.
    p.matrix = verticalI();
    var localCol = leftmostFilledCol(p.matrix);
    p.col = show.pendingTargetCol - localCol;
    p.row = computeDropRow(show.grid, p.matrix, p.row, p.col);
    lockPiece(show.grid, p.matrix, p.row, p.col);
    TF.audio.play('lock'); // real game's block_settle.wav, same event (PieceLockedEvent)
    show.piece = null;
    show.allowDrop = false;
    show.allowMove = false;
    startResolve(function () {
      show.autoTimer = setTimeout(function () { enterBeat(nextBeat); }, 500);
    });
  }

  function performFreeplayDrop() {
    if (!show.piece || show.resolving) return;
    clearTimers();
    var p = show.piece;
    p.row = computeDropRow(show.grid, p.matrix, p.row, p.col);
    lockPiece(show.grid, p.matrix, p.row, p.col);
    TF.audio.play('lock');
    show.piece = null;
    show.allowDrop = false;
    show.allowMove = false;
    startResolve(function () {
      show.freeplayStep++;
      if (show.freeplayStep < 2) {
        show.autoTimer = setTimeout(spawnFreeplayPiece, 350);
      } else {
        show.autoTimer = setTimeout(function () { enterBeat(BEAT.F_PAYOFF); }, 500);
      }
    });
  }

  function handleDropTap() {
    if (!show.allowDrop) return;
    if (show.beat === BEAT.C_GUIDED1) performScriptedDrop(BEAT.D_GUIDED2);
    else if (show.beat === BEAT.D_GUIDED2) performScriptedDrop(BEAT.E_FREEPLAY);
    else if (show.beat === BEAT.F_PAYOFF) performScriptedDrop(BEAT.G_ENDCARD);
    else if (show.beat === BEAT.E_FREEPLAY) performFreeplayDrop();
  }

  function replay() {
    show.score = 0;
    show.maxChain = 0;
    show.startedAt = performance.now();
    particles.length = 0;
    shakeMag = 0;
    enterBeat(BEAT.A_COLD_OPEN);
  }

  // ---------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------
  var unsuspended = false;
  function unsuspendIfNeeded() {
    if (unsuspended) return;
    unsuspended = true;
    TF.audio.unlock();
  }

  function inRect(x, y, rx, ry, rw, rh) { return x >= rx && x <= rx + rw && y >= ry && y <= ry + rh; }
  function inCircle(x, y, cx, cy, r) { var dx = x - cx, dy = y - cy; return dx * dx + dy * dy <= r * r; }

  function onPointerDown(clientX, clientY) {
    unsuspendIfNeeded();
    var pt = toLogicalXY(clientX, clientY);
    var x = pt.x, y = pt.y;

    if (show.beat === BEAT.A_COLD_OPEN || show.beat === BEAT.B_TITLE) {
      enterBeat(BEAT.C_GUIDED1);
      return;
    }
    if (show.beat === BEAT.G_ENDCARD) {
      if (inRect(x, y, 120, 500, 120, 40)) { replay(); return; }
      TF.exitToStore();
      return;
    }

    // Everything below is confined to the safe zone (plan Section 1): a tap
    // outside [SAFE_TOP, SAFE_BOTTOM] is ignored rather than hit-tested.
    if (y < SAFE_TOP || y > SAFE_BOTTOM) return;

    if (inCircle(x, y, BTN_ROTATE.x, BTN_ROTATE.y, BTN_ROTATE.r)) { rotateActive(); return; }
    if (inCircle(x, y, BTN_DROP.x, BTN_DROP.y, BTN_DROP.r)) { handleDropTap(); return; }

    if (y >= BOARD_Y && y <= BOARD_BOTTOM) {
      var third = BASE_W / 3;
      if (x < third) moveActive(-1);
      else if (x > 2 * third) moveActive(1);
    }
  }

  canvas.addEventListener('pointerdown', function (e) {
    e.preventDefault();
    onPointerDown(e.clientX, e.clientY);
  }, { passive: false });

  // ---------------------------------------------------------------------
  // Real-game textures — assets/images/blocks/tile_classic_wood.png and
  // assets/images/textures/bg_wood.png, cropped/downscaled by
  // tools/prepare_assets.py into a couple-KB JPEG each and base64-inlined
  // as TF.ASSETS.blockTile / .boardTile. Both are pre-tinted once here into
  // an offscreen canvas (mirrors the real game's TileCache/BoardFrame,
  // which each bake their tinted texture once rather than per draw call).
  // Both fall back to a flat gradient / solid fill if the image fails to
  // load, so a broken asset never blanks the board.
  //
  // Tint uses the 'color' composite operation specifically because it's
  // what the real game's ColorFilter.mode(tint, BlendMode.color) actually
  // does: keep the photo's luminance, replace its hue/saturation with the
  // tint's. 'multiply' looks like the obvious substitute but is NOT
  // equivalent — multiplying two already-medium-dark colors (a brown photo
  // times a brown tint) crushes toward black, which is visibly wrong here.
  // 'color' has broad support in evergreen mobile browsers/webviews.
  // ---------------------------------------------------------------------
  var blockTileTinted = null;
  var boardTileTinted = null;
  var boardPattern = null;

  function loadImage(src, onReady) {
    if (!src) return;
    var img = new Image();
    img.onload = function () { onReady(img); };
    img.src = src;
  }

  function tintedTile(img, tintColor) {
    var off = document.createElement('canvas');
    off.width = img.width;
    off.height = img.height;
    var octx = off.getContext('2d');
    octx.drawImage(img, 0, 0);
    octx.globalCompositeOperation = 'color';
    octx.fillStyle = tintColor;
    octx.fillRect(0, 0, off.width, off.height);
    octx.globalCompositeOperation = 'source-over';
    return off;
  }

  loadImage(TF.ASSETS.blockTile, function (img) {
    blockTileTinted = tintedTile(img, COLOR.woodMid);
  });

  loadImage(TF.ASSETS.boardTile, function (img) {
    boardTileTinted = tintedTile(img, COLOR.woodLight);
    boardPattern = ctx.createPattern(boardTileTinted, 'repeat');
  });

  // ---------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------
  function cellRect(rowAbs, col) {
    return {
      x: BOARD_X + col * CELL,
      y: BOARD_Y + (rowAbs - VIEW_ROW_START) * CELL
    };
  }

  function roundRectPath(x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  // isActive: the falling piece the player controls gets a light outline
  // so it reads as distinct from locked blocks (see the SHAPES comment
  // above for why there's no per-type color to rely on instead).
  function drawBlock(x, y, isActive) {
    var inset = 1, r = CELL * 0.18;
    roundRectPath(x + inset, y + inset, CELL - inset * 2, CELL - inset * 2, r);
    ctx.save();
    ctx.clip();
    if (blockTileTinted) {
      ctx.drawImage(blockTileTinted, x, y, CELL, CELL);
    } else {
      var grad = ctx.createLinearGradient(x, y, x, y + CELL);
      grad.addColorStop(0, COLOR.woodLight);
      grad.addColorStop(1, COLOR.woodDark);
      ctx.fillStyle = grad;
      ctx.fillRect(x, y, CELL, CELL);
    }
    ctx.fillStyle = 'rgba(255,255,255,0.18)';
    ctx.fillRect(x + inset, y + inset, CELL - inset * 2, 3);
    ctx.restore();
    if (isActive) {
      ctx.strokeStyle = 'rgba(242,182,50,0.85)';
      ctx.lineWidth = 1.5;
      roundRectPath(x + inset, y + inset, CELL - inset * 2, CELL - inset * 2, r);
      ctx.stroke();
    }
  }

  function drawBoard() {
    if (boardPattern) {
      ctx.fillStyle = boardPattern;
      ctx.fillRect(BOARD_X - 4, BOARD_Y - 4, COLS * CELL + 8, VIEW_ROWS * CELL + 8);
    } else {
      ctx.fillStyle = 'rgba(0,0,0,0.25)';
      ctx.fillRect(BOARD_X - 4, BOARD_Y - 4, COLS * CELL + 8, VIEW_ROWS * CELL + 8);
    }
    // Thin dark column grooves, matching board_frame.dart's separators
    // (frameDark @ ~55% alpha, ~3.5% of a cell's width) — approximated with
    // woodDark since the exact per-theme frameDark hex wasn't in scope.
    ctx.strokeStyle = 'rgba(74,47,28,0.55)';
    ctx.lineWidth = Math.max(1, CELL * 0.035);
    for (var gc = 1; gc < COLS; gc++) {
      var gx = BOARD_X + gc * CELL;
      ctx.beginPath();
      ctx.moveTo(gx, BOARD_Y);
      ctx.lineTo(gx, BOARD_BOTTOM);
      ctx.stroke();
    }
    for (var r = VIEW_ROW_START; r < ROWS_TOTAL; r++) {
      for (var c = 0; c < COLS; c++) {
        var cell = show.grid[r][c];
        var pos = cellRect(r, c);
        if (cell) drawBlock(pos.x, pos.y, false);
      }
    }
  }

  function drawActivePiece() {
    if (!show.piece) return;
    var p = show.piece;
    for (var r = 0; r < p.matrix.length; r++) {
      for (var c = 0; c < p.matrix[r].length; c++) {
        if (!p.matrix[r][c]) continue;
        var rowAbs = p.row + r, colAbs = p.col + c;
        if (rowAbs < VIEW_ROW_START) continue;
        var pos = cellRect(rowAbs, colAbs);
        drawBlock(pos.x, pos.y, true);
      }
    }
  }

  function drawHint() {
    if (show.hintCol == null || show.resolving) return;
    var bob = Math.sin(performance.now() / 180) * 4;
    var x = BOARD_X + show.hintCol * CELL + CELL / 2;
    var y = HUD_Y1 - 6 + bob;
    ctx.fillStyle = COLOR.gold;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x - 7, y - 10);
    ctx.lineTo(x + 7, y - 10);
    ctx.closePath();
    ctx.fill();
  }

  // ---------------------------------------------------------------------
  // Logo — reproduces lib/ui/widgets/logo_mark.dart / logo_wordmark.dart
  // exactly (colors, gradient stops, layout fractions). The real game has
  // no logo raster asset at all — this *is* the asset, just ported from
  // Dart drawing code to Canvas, which is why it costs ~0 extra bytes.
  // ---------------------------------------------------------------------
  function drawLogoBlock(x, y, size) {
    var radius = size * 0.2;
    ctx.save();
    ctx.shadowColor = 'rgba(0,0,0,0.35)';
    ctx.shadowOffsetY = 4;
    ctx.shadowBlur = 12;
    var grad = ctx.createLinearGradient(x + size * 0.2, y, x + size * 0.8, y + size);
    grad.addColorStop(0, COLOR.woodLight);
    grad.addColorStop(0.55, COLOR.woodMid);
    grad.addColorStop(1, COLOR.woodDark);
    ctx.fillStyle = grad;
    roundRectPath(x, y, size, size, radius);
    ctx.fill();
    ctx.restore();

    ctx.strokeStyle = 'rgba(0,0,0,0.35)';
    ctx.lineWidth = 1;
    roundRectPath(x + 0.5, y + 0.5, size - 1, size - 1, radius);
    ctx.stroke();

    // Inset bevel: white highlight fading to a black shade at the bottom —
    // Canvas has no inset-shadow primitive, so an overlay gradient fakes it
    // exactly like the Dart widget's own comment says it does with CSS.
    var bevel = ctx.createLinearGradient(x, y, x, y + size);
    bevel.addColorStop(0, 'rgba(255,255,255,0.28)');
    bevel.addColorStop(0.25, 'rgba(255,255,255,0)');
    bevel.addColorStop(0.7, 'rgba(0,0,0,0)');
    bevel.addColorStop(1, 'rgba(0,0,0,0.3)');
    ctx.fillStyle = bevel;
    roundRectPath(x, y, size, size, radius);
    ctx.fill();
  }

  // x0,y0 is the top-left of the mark's bounding box (cellSize*3+gap*2 wide,
  // cellSize*2+gap tall) — matches LogoMark's Positioned offsets.
  function drawLogoMark(x0, y0, cellSize) {
    var gap = cellSize * 0.125;
    drawLogoBlock(x0 + cellSize + gap, y0, cellSize);
    drawLogoBlock(x0, y0 + cellSize + gap, cellSize);
    drawLogoBlock(x0 + cellSize + gap, y0 + cellSize + gap, cellSize);
    drawLogoBlock(x0 + (cellSize + gap) * 2, y0 + cellSize + gap, cellSize);
  }

  // cx,y is the horizontal center / text baseline, matching how the rest of
  // this file already centers text. fontSize maps to logo_wordmark.dart's
  // TextStyle(fontSize:), letter-spacing is dropped for canvas/webview
  // compatibility (no reliable ctx.letterSpacing support yet).
  function drawWordmark(text, cx, y, fontSize) {
    ctx.save();
    ctx.textAlign = 'center';
    ctx.font = '800 ' + fontSize + 'px "TFBaloo", -apple-system, "Segoe UI", Roboto, sans-serif';
    ctx.shadowColor = 'rgba(0,0,0,0.45)';
    ctx.shadowOffsetY = 4;
    ctx.shadowBlur = 8;
    var grad = ctx.createLinearGradient(cx, y - fontSize * 0.78, cx, y + fontSize * 0.14);
    grad.addColorStop(0, '#FFE9B0');
    grad.addColorStop(0.55, COLOR.gold);
    grad.addColorStop(1, '#C9821A');
    ctx.fillStyle = grad;
    ctx.fillText(text, cx, y);
    ctx.restore();
  }

  // Plain (non-gradient) Baloo 2 numerals for the score/chain readout — the
  // real game's HUD score uses this display font solid-filled, not the
  // wordmark's gold gradient treatment (that's reserved for the logo).
  function displayFont(px) {
    return '800 ' + px + 'px "TFBaloo", -apple-system, "Segoe UI", Roboto, sans-serif';
  }

  function drawHud() {
    ctx.fillStyle = COLOR.text;
    ctx.font = displayFont(19);
    ctx.textAlign = 'left';
    ctx.fillText(show.score.toLocaleString(), 16, HUD_Y0 + 22);
    if (show.maxChain > 1) {
      ctx.fillStyle = COLOR.gold;
      ctx.textAlign = 'right';
      ctx.fillText('x' + show.maxChain, BASE_W - 16, HUD_Y0 + 22);
    }
    if (caption.text && performance.now() < caption.until) {
      ctx.textAlign = 'center';
      ctx.fillStyle = COLOR.gold;
      ctx.font = (caption.big ? '700 22px' : '600 15px') + ' -apple-system, "Segoe UI", Roboto, sans-serif';
      ctx.fillText(caption.text, BASE_W / 2, HUD_Y1 - 20);
    }
  }

  function drawButtons() {
    if (show.beat === BEAT.A_COLD_OPEN || show.beat === BEAT.B_TITLE || show.beat === BEAT.G_ENDCARD) return;
    [[BTN_ROTATE, '⟳', show.allowMove], [BTN_DROP, '▼', show.allowDrop]].forEach(function (b) {
      var btn = b[0], label = b[1], active = b[2];
      ctx.beginPath();
      ctx.arc(btn.x, btn.y, btn.r, 0, Math.PI * 2);
      ctx.fillStyle = active ? 'rgba(242,182,50,0.9)' : 'rgba(255,255,255,0.12)';
      ctx.fill();
      ctx.fillStyle = active ? COLOR.woodDark : COLOR.textMuted;
      ctx.font = '700 22px -apple-system, "Segoe UI", Roboto, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(label, btn.x, btn.y + 1);
    });
    ctx.textBaseline = 'alphabetic';
  }

  function drawTitleCard() {
    drawBoard();
    ctx.fillStyle = 'rgba(43,28,18,0.82)';
    ctx.fillRect(0, 0, BASE_W, BASE_H);

    var markCell = 34, markGap = markCell * 0.125;
    var markW = markCell * 3 + markGap * 2;
    drawLogoMark(BASE_W / 2 - markW / 2, 190, markCell);

    drawWordmark('TETROFALL', BASE_W / 2, 300, 34);

    ctx.textAlign = 'center';
    ctx.fillStyle = COLOR.text;
    ctx.font = '500 17px -apple-system, "Segoe UI", Roboto, sans-serif';
    ctx.fillText('Clear rows before the floor', BASE_W / 2, 336);
    ctx.fillText('swallows you.', BASE_W / 2, 360);
  }

  function drawEndcard() {
    var grad = ctx.createLinearGradient(0, 0, 0, BASE_H);
    grad.addColorStop(0, COLOR.woodDark);
    grad.addColorStop(1, COLOR.bg);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, BASE_W, BASE_H);

    var markCell = 30, markGap = markCell * 0.125;
    var markW = markCell * 3 + markGap * 2;
    drawLogoMark(BASE_W / 2 - markW / 2, 140, markCell);

    drawWordmark('TETROFALL', BASE_W / 2, 280, 28);

    ctx.textAlign = 'center';
    ctx.font = '500 15px -apple-system, "Segoe UI", Roboto, sans-serif';
    ctx.fillStyle = COLOR.textMuted;
    ctx.fillText('Endless block puzzle. Clear rows.', BASE_W / 2, 306);
    ctx.fillText('Survive the rise.', BASE_W / 2, 326);

    ctx.fillStyle = COLOR.text;
    ctx.font = displayFont(16);
    ctx.fillText('Score ' + show.score.toLocaleString() + '  ·  Chain x' + show.maxChain, BASE_W / 2, 362);

    // CTA button — kept inside the safe zone (SAFE_TOP..SAFE_BOTTOM) even
    // though the end-card art itself is full-bleed, per the plan.
    ctx.fillStyle = COLOR.gold;
    roundRectPath(BASE_W / 2 - 100, 400, 200, 52, 26);
    ctx.fill();
    ctx.fillStyle = COLOR.woodDark;
    ctx.font = '700 18px -apple-system, "Segoe UI", Roboto, sans-serif';
    ctx.fillText('Install Now', BASE_W / 2, 434);

    ctx.fillStyle = COLOR.textMuted;
    ctx.font = '600 14px -apple-system, "Segoe UI", Roboto, sans-serif';
    ctx.fillText('Replay', BASE_W / 2, 520);
  }

  function drawFrame() {
    ctx.save();
    if (shakeMag > 0.1) {
      ctx.translate((Math.random() - 0.5) * shakeMag, (Math.random() - 0.5) * shakeMag);
    }
    ctx.fillStyle = COLOR.bg;
    ctx.fillRect(-20, -20, BASE_W + 40, BASE_H + 40);

    if (show.beat === BEAT.B_TITLE) {
      drawTitleCard();
    } else if (show.beat === BEAT.G_ENDCARD) {
      drawEndcard();
    } else {
      drawBoard();
      drawActivePiece();
      drawHint();
      drawParticles();
      drawHud();
      drawButtons();
    }
    ctx.restore();
  }

  // ---------------------------------------------------------------------
  // Main loop
  // ---------------------------------------------------------------------
  var lastTs = performance.now();
  function loop(ts) {
    var dt = Math.min(0.05, (ts - lastTs) / 1000);
    lastTs = ts;
    updateParticles(dt);
    drawFrame();
    requestAnimationFrame(loop);
  }

  // Draw one frame synchronously before the rAF loop starts — some
  // ad-network webviews suspend rAF until the first user gesture, and we
  // never want the very first paint to be blank (plan Section 2's
  // "Beat A autoplay-suspend edge case").
  enterBeat(BEAT.A_COLD_OPEN);
  drawFrame();
  requestAnimationFrame(loop);
})();
