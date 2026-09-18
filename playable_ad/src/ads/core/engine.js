/* Headless game model — a port of lib/game/engine/{game_engine,piece_controller,
 * rise_controller,ripple_cascade,tetromino,scoring}.dart. No DOM: it also runs
 * under node for tests/engine_test.js.
 *
 * Rows are indexed downward like grid.dart: spawn rows are negative
 * (minRow = -SPAWN_ROWS), the bottom row is ROWS - 1.
 */
(function () {
  'use strict';

  var C = TF.C, M = C.MOTION;

  // lib/game/engine/tetromino.dart — [row, col] per rotation (spawn, right, flip, left)
  var SHAPES = {
    I: [[[1, 0], [1, 1], [1, 2], [1, 3]], [[0, 2], [1, 2], [2, 2], [3, 2]], [[2, 0], [2, 1], [2, 2], [2, 3]], [[0, 1], [1, 1], [2, 1], [3, 1]]],
    O: [[[0, 0], [0, 1], [1, 0], [1, 1]], [[0, 0], [0, 1], [1, 0], [1, 1]], [[0, 0], [0, 1], [1, 0], [1, 1]], [[0, 0], [0, 1], [1, 0], [1, 1]]],
    T: [[[0, 1], [1, 0], [1, 1], [1, 2]], [[0, 1], [1, 1], [1, 2], [2, 1]], [[1, 0], [1, 1], [1, 2], [2, 1]], [[0, 1], [1, 0], [1, 1], [2, 1]]],
    S: [[[0, 1], [0, 2], [1, 0], [1, 1]], [[0, 1], [1, 1], [1, 2], [2, 2]], [[1, 1], [1, 2], [2, 0], [2, 1]], [[0, 0], [1, 0], [1, 1], [2, 1]]],
    Z: [[[0, 0], [0, 1], [1, 1], [1, 2]], [[0, 2], [1, 1], [1, 2], [2, 1]], [[1, 0], [1, 1], [2, 1], [2, 2]], [[0, 1], [1, 0], [1, 1], [2, 0]]],
    J: [[[0, 0], [1, 0], [1, 1], [1, 2]], [[0, 1], [0, 2], [1, 1], [2, 1]], [[1, 0], [1, 1], [1, 2], [2, 2]], [[0, 1], [1, 1], [2, 0], [2, 1]]],
    L: [[[0, 2], [1, 0], [1, 1], [1, 2]], [[0, 1], [1, 1], [2, 1], [2, 2]], [[1, 0], [1, 1], [1, 2], [2, 0]], [[0, 0], [0, 1], [1, 1], [2, 1]]]
  };
  var TYPES = ['I', 'O', 'T', 'S', 'Z', 'J', 'L'];

  // Wall kicks, listed (dCol, dRow) exactly as tetromino.dart's _k tables.
  var JLSTZ_KICKS = {
    '0>1': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    '1>0': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
    '1>2': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
    '2>1': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    '2>3': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    '3>2': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    '3>0': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    '0>3': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]]
  };
  var I_KICKS = {
    '0>1': [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
    '1>0': [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
    '1>2': [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]],
    '2>1': [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -1]],
    '2>3': [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
    '3>2': [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
    '3>0': [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -1]],
    '0>3': [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]]
  };

  function kicksFor(type, from, to) {
    if (type === 'O') return [[0, 0]];
    var table = type === 'I' ? I_KICKS : JLSTZ_KICKS;
    return table[from + '>' + to] || [[0, 0]];
  }

  function spawnColumn(type, cols) {
    if (type === 'I') return (cols - 4) >> 1;
    if (type === 'O') return (cols - 2) >> 1;
    return (cols - 3) >> 1;
  }

  function mulberry32(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function lineScoreFor(lines) {
    if (lines <= 0) return 0;
    var tabled = C.LINE_BASE_SCORE[lines];
    if (tabled != null) return tabled;
    return C.LINE_BASE_SCORE[4] + (lines - 4) * 300;
  }

  // lib/game/config/difficulty.dart Difficulty.at
  function difficultyAt(seconds) {
    var cps = C.CHECKPOINTS;
    if (seconds <= cps[0][0]) return { dropMs: cps[0][1], riseInterval: cps[0][2], fillRatio: cps[0][3] };
    var last = cps[cps.length - 1];
    if (seconds >= last[0]) return { dropMs: last[1], riseInterval: last[2], fillRatio: last[3] };
    for (var i = 0; i < cps.length - 1; i++) {
      var a = cps[i], b = cps[i + 1];
      if (seconds >= a[0] && seconds <= b[0]) {
        var t = (seconds - a[0]) / (b[0] - a[0]);
        return {
          dropMs: Math.round(a[1] + (b[1] - a[1]) * t),
          riseInterval: a[2] + (b[2] - a[2]) * t,
          fillRatio: a[3] + (b[3] - a[3]) * t
        };
      }
    }
    return { dropMs: last[1], riseInterval: last[2], fillRatio: last[3] };
  }

  /* opts: rows, cols, seed, dropMs, riseGrace, riseInterval, fillRatio,
   * gapMode ('auto' | 'adjacent' | 'scattered'), startElapsed, resolveScale */
  function Engine(opts) {
    opts = opts || {};
    this.cols = opts.cols || C.COLS;
    this.rows = opts.rows || C.ROWS;
    this.spawnRows = C.SPAWN_ROWS;
    this.minRow = -this.spawnRows;
    this.maxRow = this.rows - 1;
    this.random = mulberry32(opts.seed != null ? opts.seed : 1);
    this.opts = opts;

    // Per-ad overrides; null falls back to the difficulty curve.
    this.dropMs = opts.dropMs != null ? opts.dropMs : null;
    this.riseGrace = opts.riseGrace != null ? opts.riseGrace : C.RISE_GRACE;
    this.riseIntervalOverride = opts.riseInterval != null ? opts.riseInterval : null;
    this.fillRatioOverride = opts.fillRatio != null ? opts.fillRatio : null;
    this.gapMode = opts.gapMode || 'auto';
    this.resolveScale = opts.resolveScale != null ? opts.resolveScale : 1;

    this.freezeGravity = false;
    this.freezeRise = false;
    this.holdSpawn = false;
    this.canHardDrop = null; // optional function(piece) -> bool

    this.listeners = [];
    this.cells = [];
    for (var r = 0; r < this.rows + this.spawnRows; r++) this.cells.push(new Array(this.cols).fill(0));
    this.reset();
  }

  var P = Engine.prototype;

  P.reset = function () {
    for (var r = 0; r < this.cells.length; r++) this.cells[r].fill(0);
    this.phase = 'ready';
    this.piece = null;
    this.intents = [];
    this.scripted = [];
    this.bag = [];
    this.score = 0;
    this.maxChain = 0;
    this.totalLines = 0;
    this.chainIndex = 0;
    this.resolveLines = 0;
    this.elapsed = this.opts.startElapsed || 0;
    this.riseStartElapsed = this.elapsed;
    this.riseProgress = 0;
    this.previousGapCols = [];
    this.softDropActive = false;
    this.pendingRow = this.generateRow();
    this.resetPieceTimers();
  };

  P.on = function (fn) { this.listeners.push(fn); };
  P.emit = function (type, data) {
    var ls = this.listeners.slice();
    for (var i = 0; i < ls.length; i++) ls[i](type, data || {});
  };

  // ---- grid ---------------------------------------------------------------
  P.inBounds = function (r, c) { return c >= 0 && c < this.cols && r >= this.minRow && r <= this.maxRow; };
  P.at = function (r, c) { return this.inBounds(r, c) ? this.cells[r + this.spawnRows][c] : 0; };
  P.set = function (r, c, v) { this.cells[r + this.spawnRows][c] = v ? 1 : 0; };
  P.rowFull = function (r) {
    for (var c = 0; c < this.cols; c++) if (!this.at(r, c)) return false;
    return true;
  };
  P.rowAny = function (r) {
    for (var c = 0; c < this.cols; c++) if (this.at(r, c)) return true;
    return false;
  };
  P.fullRows = function () {
    var out = [];
    for (var r = this.minRow; r <= this.maxRow; r++) if (this.rowFull(r)) out.push(r);
    return out;
  };

  /* Rig helper: strings top→bottom, aligned to the board's bottom row.
   * '#' is a block, anything else is empty. */
  P.setRows = function (rows) {
    for (var r = 0; r < this.cells.length; r++) this.cells[r].fill(0);
    var top = this.maxRow - rows.length + 1;
    for (var i = 0; i < rows.length; i++) {
      for (var c = 0; c < this.cols; c++) this.set(top + i, c, rows[i].charAt(c) === '#');
    }
    this.emit('board', {});
  };

  P.rowString = function (r) {
    var s = '';
    for (var c = 0; c < this.cols; c++) s += this.at(r, c) ? '#' : '.';
    return s;
  };

  P.stackTop = function () {
    for (var r = this.minRow; r <= this.maxRow; r++) if (this.rowAny(r)) return r;
    return this.maxRow + 1;
  };

  // ---- difficulty ---------------------------------------------------------
  P.difficulty = function () {
    var d = difficultyAt(this.elapsed);
    if (this.dropMs != null) d.dropMs = this.dropMs;
    if (this.riseIntervalOverride != null) d.riseInterval = this.riseIntervalOverride;
    if (this.fillRatioOverride != null) d.fillRatio = this.fillRatioOverride;
    return d;
  };

  // ---- pieces -------------------------------------------------------------
  P.cellsOf = function (type, rot) { return SHAPES[type][rot]; };

  P.collides = function (type, rot, row, col) {
    var cells = SHAPES[type][rot];
    for (var i = 0; i < 4; i++) {
      var r = row + cells[i][0], c = col + cells[i][1];
      if (!this.inBounds(r, c) || this.at(r, c)) return true;
    }
    return false;
  };

  P.pieceCells = function (piece) {
    piece = piece || this.piece;
    if (!piece) return [];
    return SHAPES[piece.type][piece.rot].map(function (o) {
      return [piece.row + o[0], piece.col + o[1]];
    });
  };

  P.queuePieces = function (types) {
    for (var i = 0; i < types.length; i++) this.scripted.push(types[i]);
  };

  P.nextType = function () {
    if (this.scripted.length) return this.scripted.shift();
    if (!this.bag.length) {
      var bag = TYPES.slice();
      for (var i = bag.length - 1; i > 0; i--) {
        var j = Math.floor(this.random() * (i + 1));
        var t = bag[i]; bag[i] = bag[j]; bag[j] = t;
      }
      this.bag = bag;
    }
    return this.bag.shift();
  };

  P.resetPieceTimers = function () {
    this.grounded = false;
    this.gravityTimer = 0;
    this.lockTimer = 0;
    this.resetCount = 0;
  };

  P.updateGrounded = function () {
    var p = this.piece;
    if (!p) return;
    var below = this.collides(p.type, p.rot, p.row + 1, p.col);
    if (below && !this.grounded && this.resetCount < M.lockResetLimit) this.lockTimer = 0;
    this.grounded = below;
  };

  P.onSuccessfulAction = function () {
    if (!this.grounded) return;
    if (this.resetCount < M.lockResetLimit) {
      this.lockTimer = 0;
      this.resetCount++;
    }
  };

  P.shift = function (dRow, dCol) {
    var p = this.piece;
    if (!p || this.collides(p.type, p.rot, p.row + dRow, p.col + dCol)) return false;
    p.row += dRow;
    p.col += dCol;
    this.updateGrounded();
    return true;
  };

  P.rotate = function (dir) {
    var p = this.piece;
    if (!p) return false;
    var target = (p.rot + (dir > 0 ? 1 : 3)) % 4;
    var kicks = kicksFor(p.type, p.rot, target);
    for (var i = 0; i < kicks.length; i++) {
      var row = p.row + kicks[i][1], col = p.col + kicks[i][0];
      if (!this.collides(p.type, target, row, col)) {
        p.rot = target;
        p.row = row;
        p.col = col;
        this.updateGrounded();
        this.onSuccessfulAction();
        return true;
      }
    }
    return false;
  };

  P.ghostRow = function () {
    var p = this.piece;
    if (!p) return null;
    var row = p.row;
    while (!this.collides(p.type, p.rot, row + 1, p.col)) row++;
    return row;
  };

  /* piece_controller.dart lowerTo: slides the fresh piece into view while
   * gravity is frozen, so a coached step never steers an invisible piece. */
  P.lowerTo = function (targetRow) {
    var p = this.piece;
    if (!p) return;
    while (p.row < targetRow && !this.collides(p.type, p.rot, p.row + 1, p.col)) p.row++;
    this.updateGrounded();
  };

  P.trySpawn = function () {
    var type = this.nextType();
    var col = spawnColumn(type, this.cols);
    this.piece = { type: type, rot: 0, row: this.minRow, col: col };
    this.resetPieceTimers();
    if (this.collides(type, 0, this.minRow, col)) {
      this.phase = 'gameOver';
      this.emit('gameOver', { reason: 'blockOut' });
      return;
    }
    this.updateGrounded();
    this.phase = 'playing';
    this.emit('spawn', { type: type });
  };

  P.start = function () {
    this.phase = 'spawning';
    if (!this.holdSpawn) this.trySpawn();
  };

  // ---- intents ------------------------------------------------------------
  P.intent = function (type) { this.intents.push({ type: type, age: 0 }); };

  P.drainIntents = function (dt) {
    var i;
    if (this.phase !== 'playing') {
      for (i = this.intents.length - 1; i >= 0; i--) {
        var b = this.intents[i];
        b.age += dt;
        var bufferable = b.type === 'left' || b.type === 'right' || b.type === 'rotate';
        if (b.age > C.INPUT_BUFFER_WINDOW || !bufferable) this.intents.splice(i, 1);
      }
      return;
    }
    var queue = this.intents;
    this.intents = [];
    for (i = 0; i < queue.length; i++) {
      if (this.phase !== 'playing') break;
      var t = queue[i].type;
      if (t === 'left' || t === 'right') {
        if (this.shift(0, t === 'left' ? -1 : 1)) {
          this.onSuccessfulAction();
          this.emit('move', { dir: t === 'left' ? -1 : 1 });
        }
      } else if (t === 'rotate') {
        var turned = this.rotate(1);
        this.emit('rotate', { turned: turned });
      } else if (t === 'softStart') {
        this.softDropActive = true;
        this.emit('softDrop', {});
      } else if (t === 'softEnd') {
        this.softDropActive = false;
      } else if (t === 'hard') {
        if (this.canHardDrop && !this.canHardDrop(this.piece)) {
          this.emit('dropBlocked', {});
          continue;
        }
        var from = this.piece.row;
        while (this.shift(1, 0)) { /* slide */ }
        this.emit('hardDrop', { from: from, to: this.piece.row });
        this.lockAndResolve();
      }
    }
  };

  // ---- main tick ----------------------------------------------------------
  P.tick = function (dt) {
    this.drainIntents(dt);
    switch (this.phase) {
      case 'spawning':
        if (!this.holdSpawn) this.trySpawn();
        break;
      case 'playing':
        if (!this.freezeRise && this.riseTick(dt)) this.handleRiseCommit();
        if (this.phase === 'playing' && !this.freezeGravity && this.pieceTick(dt)) this.lockAndResolve();
        break;
      case 'resolving':
        this.elapsed += dt;
        this.resolveElapsed += dt;
        this.flightRemaining = Math.max(0, this.flightRemaining - dt);
        if (!this.flushed && this.resolveElapsed > this.hardCapSeconds()) {
          this.flushResolve();
        } else if (this.resolveTimer > 0) {
          this.resolveTimer -= dt;
          if (this.resolveTimer <= 0) {
            if (this.resolveStage === 'shatter') this.beginRipple();
            else if (this.resolveStage === 'ripple') this.rippleStep();
            else this.resolvePass();
          }
        }
        break;
    }
  };

  P.pieceTick = function (dt) {
    var p = this.piece;
    if (!p) return false;
    var intervalS = this.difficulty().dropMs / 1000;
    if (this.softDropActive) intervalS /= M.softDropDivisor;
    this.gravityTimer += dt;
    if (this.gravityTimer >= intervalS) {
      this.gravityTimer -= intervalS;
      this.shift(1, 0);
    }
    this.updateGrounded();
    if (this.grounded) {
      this.lockTimer += dt;
      if (this.lockTimer >= M.lockDelay) return true;
    }
    return false;
  };

  // ---- rise (rise_controller.dart) ----------------------------------------
  P.riseInterval = function () { return this.difficulty().riseInterval; };

  P.riseTick = function (dt) {
    this.elapsed += dt;
    if (this.elapsed - this.riseStartElapsed < this.riseGrace) return false;
    this.riseProgress += dt / this.riseInterval();
    if (this.riseProgress >= 1) {
      this.riseProgress -= 1;
      return true;
    }
    return false;
  };

  P.generateRow = function (fillRatio, mode) {
    var cols = this.cols;
    var fill = fillRatio != null ? fillRatio : this.difficulty().fillRatio;
    var maxGaps = Math.min(Math.max(Math.round(cols * 0.4), 1), cols - 1);
    var gapCount = Math.min(Math.max(Math.round(cols * (1 - fill)), 1), maxGaps);
    mode = mode || this.gapMode;
    var adjacent = mode === 'adjacent' || (mode === 'auto' && this.elapsed < 60);
    var gaps = adjacent ? this.adjacentGaps(gapCount) : this.scatteredGaps(gapCount);
    this.previousGapCols = gaps;
    var row = [];
    for (var c = 0; c < cols; c++) row.push(gaps.indexOf(c) >= 0 ? 0 : 1);
    return row;
  };

  P.adjacentGaps = function (count) {
    var start = Math.floor(this.random() * (this.cols - count + 1));
    var out = [];
    for (var i = 0; i < count; i++) out.push(start + i);
    return out;
  };

  P.scatteredGaps = function (count) {
    var self = this;
    function pick() {
      var set = [];
      while (set.length < count) {
        var c = Math.floor(self.random() * self.cols);
        if (set.indexOf(c) < 0) set.push(c);
      }
      return set;
    }
    for (var attempt = 0; attempt < 8; attempt++) {
      var cols = pick();
      var overlaps = cols.some(function (c) { return self.previousGapCols.indexOf(c) >= 0; });
      if (!overlaps) return cols;
    }
    return pick();
  };

  P.wouldTopOut = function () { return this.rowAny(0); };

  P.commitRise = function () {
    for (var r = 1; r <= this.maxRow; r++) {
      for (var c = 0; c < this.cols; c++) this.set(r - 1, c, this.at(r, c));
    }
    for (var c2 = 0; c2 < this.cols; c2++) this.set(this.maxRow, c2, this.pendingRow[c2]);
    this.pendingRow = this.generateRow();
  };

  P.handleRiseCommit = function () {
    if (this.wouldTopOut()) {
      this.phase = 'gameOver';
      this.emit('gameOver', { reason: 'topOut' });
      return;
    }
    this.commitRise();
    var p = this.piece;
    if (p) {
      var original = p.row, shifted = original - 1, pushed = shifted - 1;
      if (shifted >= this.minRow && !this.collides(p.type, p.rot, shifted, p.col)) p.row = shifted;
      else if (pushed >= this.minRow && !this.collides(p.type, p.rot, pushed, p.col)) p.row = pushed;
      else if (this.collides(p.type, p.rot, original, p.col)) {
        this.phase = 'gameOver';
        this.emit('gameOver', { reason: 'topOut' });
        return;
      }
    }
    this.emit('rise', {});
  };

  // ---- lock + resolve (game_engine.dart) ----------------------------------
  P.lockAndResolve = function () {
    var p = this.piece;
    if (!p) return;
    var cells = this.pieceCells(p);
    for (var i = 0; i < cells.length; i++) this.set(cells[i][0], cells[i][1], 1);
    this.piece = null;
    this.softDropActive = false;
    this.emit('lock', { cells: cells, type: p.type });
    this.phase = 'resolving';
    this.chainIndex = 0;
    this.resolveLines = 0;
    this.resolveElapsed = 0;
    this.flightRemaining = 0;
    this.flushed = false;
    this.gravityFloor = null;
    this.resolvePass();
  };

  P.finishResolve = function () {
    this.resolveTimer = 0;
    this.phase = 'spawning';
    this.emit('resolveEnd', { chains: this.chainIndex, lines: this.resolveLines });
  };

  P.schedule = function (stage, seconds) {
    this.resolveStage = stage;
    this.resolveTimer = Math.max(seconds, 1e-6);
  };

  P.resolveTimeScale = function () {
    var base = C.CHECKPOINTS[0][1];
    var scale = Math.min(1, Math.max(M.resolveMinTimeScale, this.difficulty().dropMs / base));
    return scale * this.resolveScale;
  };

  P.chainTimeScale = function () {
    return this.resolveTimeScale() * Math.max(M.chainShatterFloor, 1 - M.chainShatterFalloff * this.chainIndex);
  };

  P.hardCapSeconds = function () { return M.resolveHardCap * this.resolveTimeScale(); };

  P.stripRows = function (rows) {
    var removed = [];
    for (var i = 0; i < rows.length; i++) {
      for (var c = 0; c < this.cols; c++) {
        if (this.at(rows[i], c)) {
          removed.push([rows[i], c]);
          this.set(rows[i], c, 0);
        }
      }
    }
    return removed;
  };

  P.lowerGravityFloor = function (rows) {
    var lowest = Math.max.apply(null, rows);
    if (this.gravityFloor == null || lowest > this.gravityFloor) this.gravityFloor = lowest;
  };

  P.awardClear = function (rows, removed, scale) {
    var capped = Math.min(this.chainIndex, C.MAX_CHAIN_STEPS);
    var points = Math.round(lineScoreFor(rows.length) * (1 + 0.5 * capped) * (1 + (this.elapsed / 60) * 0.1));
    this.score += points;
    this.totalLines += rows.length;
    this.resolveLines += rows.length;
    if (this.chainIndex + 1 > this.maxChain) this.maxChain = this.chainIndex + 1;
    this.emit('clear', { rows: rows, cells: removed, chainIndex: this.chainIndex, points: points, timeScale: scale });
    this.chainIndex++;
  };

  P.resolvePass = function () {
    var full = this.fullRows();
    if (!full.length) {
      if (this.chainIndex === 0) { this.finishResolve(); return; }
      this.beginRipple();
      return;
    }
    var removed = this.stripRows(full);
    this.lowerGravityFloor(full);
    var scale = this.chainTimeScale();
    this.awardClear(full, removed, scale);
    this.schedule('shatter', C.shatterSequenceSeconds(this.cols) * scale);
  };

  // ripple_cascade.dart nextFloatingRow
  P.nextFloatingRow = function (fromRow) {
    // Spawn rows (negative indices) are left alone, as in the Dart original.
    var r = fromRow < this.maxRow ? fromRow : this.maxRow - 1;
    for (; r >= 0; r--) {
      for (var c = 0; c < this.cols; c++) {
        if (this.at(r, c) && !this.at(r + 1, c)) return r;
      }
    }
    return null;
  };

  // ripple_cascade.dart settleRow
  P.settleRow = function (row) {
    var falls = [];
    if (row < 0 || row >= this.maxRow) return falls;
    for (var c = 0; c < this.cols; c++) {
      if (!this.at(row, c)) continue;
      var rest = row;
      while (rest < this.maxRow && !this.at(rest + 1, c)) rest++;
      if (rest === row) continue;
      this.set(row, c, 0);
      this.set(rest, c, 1);
      falls.push({ col: c, fromRow: row, toRow: rest });
    }
    return falls;
  };

  P.rowsRemaining = function (fromRow) {
    var n = 0;
    for (var r = Math.min(fromRow, this.maxRow); r >= 0; r--) if (this.rowAny(r)) n++;
    return n;
  };

  P.beginRipple = function () {
    var row = this.gravityFloor == null ? null : this.nextFloatingRow(this.gravityFloor - 1);
    if (row == null) { this.finishResolve(); return; }
    this.rippleRow = row;
    this.rippleRowsRemaining = this.rowsRemaining(row);
    this.schedule('ripple', 0);
  };

  P.emitFalls = function (falls) {
    if (!falls.length) return;
    var maxDist = 0;
    for (var i = 0; i < falls.length; i++) maxDist = Math.max(maxDist, falls[i].toRow - falls[i].fromRow);
    var seconds = Math.sqrt(2 * maxDist / M.gravityCellsPerS2) * this.chainTimeScale();
    this.emit('fall', { falls: falls, duration: seconds });
    this.flightRemaining = Math.max(this.flightRemaining, seconds + M.impactSquash);
  };

  P.rippleStep = function () {
    this.emitFalls(this.settleRow(this.rippleRow));
    if (this.rippleRowsRemaining > 0) this.rippleRowsRemaining--;
    if (this.fullRows().length) { this.schedule('settle', this.flightRemaining); return; }
    var next = this.nextFloatingRow(this.rippleRow - 1);
    if (next == null) { this.schedule('settle', this.flightRemaining); return; }
    this.rippleRow = next;
    this.schedule('ripple', this.stepInterval());
  };

  P.stepInterval = function () {
    var scale = this.chainTimeScale();
    var paced = M.rippleBudget * scale / Math.max(1, this.rippleRowsRemaining);
    return Math.max(M.rippleStepMin, Math.min(M.rippleStepBase * scale, paced));
  };

  P.settleAboveFloor = function () {
    var falls = [];
    if (this.gravityFloor == null) return falls;
    for (var r = this.gravityFloor - 1; r >= 0; r--) falls = falls.concat(this.settleRow(r));
    return falls;
  };

  P.flushResolve = function () {
    this.flushed = true;
    var falls = this.settleAboveFloor();
    for (var guard = 0; guard <= this.rows; guard++) {
      var full = this.fullRows();
      if (!full.length) break;
      var removed = this.stripRows(full);
      this.lowerGravityFloor(full);
      this.awardClear(full, removed, this.chainTimeScale());
      falls = this.settleAboveFloor();
    }
    this.flightRemaining = 0;
    this.emitFalls(falls);
    this.schedule('settle', Math.max(this.flightRemaining, C.shatterSequenceSeconds(this.cols) * this.chainTimeScale()));
  };

  // ---- bot (lib/game/ai/demo_bot.dart, skilled policy) --------------------
  function Bot(engine) { this.engine = engine; this.target = null; this.stepTimer = 0; }

  Bot.prototype.choose = function (type) {
    var e = this.engine;
    var best = null, bestScore = -Infinity, ties = 0;
    for (var rot = 0; rot < 4; rot++) {
      var cells = SHAPES[type][rot];
      var minC = 9, maxC = -9;
      for (var i = 0; i < 4; i++) { minC = Math.min(minC, cells[i][1]); maxC = Math.max(maxC, cells[i][1]); }
      for (var col = -minC; col <= e.cols - 1 - maxC; col++) {
        if (e.collides(type, rot, e.minRow, col)) continue;
        var row = e.minRow;
        while (!e.collides(type, rot, row + 1, col)) row++;
        var s = scorePlacement(e, cells, row, col);
        if (s > bestScore) { bestScore = s; best = { rot: rot, col: col }; ties = 1; }
        else if (s === bestScore) {
          ties++;
          if (Math.floor(e.random() * ties) === 0) best = { rot: rot, col: col };
        }
      }
    }
    return best || { rot: 0, col: spawnColumn(type, e.cols) };
  };

  function scorePlacement(e, cells, landingRow, col) {
    var occ = [];
    for (var r = 0; r <= e.maxRow; r++) {
      var row = [];
      for (var c = 0; c < e.cols; c++) row.push(!!e.at(r, c));
      occ.push(row);
    }
    for (var i = 0; i < 4; i++) {
      var rr = landingRow + cells[i][0];
      if (rr >= 0 && rr <= e.maxRow) occ[rr][col + cells[i][1]] = true;
    }
    var cleared = 0, holes = 0, maxHeight = 0;
    for (var r2 = 0; r2 < occ.length; r2++) if (occ[r2].every(Boolean)) cleared++;
    for (var c2 = 0; c2 < e.cols; c2++) {
      var seen = false;
      for (var r3 = 0; r3 < occ.length; r3++) {
        if (occ[r3][c2]) {
          if (!seen) maxHeight = Math.max(maxHeight, occ.length - r3);
          seen = true;
        } else if (seen) holes++;
      }
    }
    return cleared * 1000 - holes * 40 - maxHeight * 2;
  }

  /* Pushes one intent toward target {rot, col}; returns true once it drops. */
  Bot.prototype.steer = function (target) {
    var e = this.engine, p = e.piece;
    if (e.phase !== 'playing' || !p || !target) return false;
    if (p.rot !== target.rot) e.intent('rotate');
    else if (p.col < target.col) e.intent('right');
    else if (p.col > target.col) e.intent('left');
    else { e.intent('hard'); return true; }
    return false;
  };

  TF.Engine = Engine;
  TF.Bot = Bot;
  TF.SHAPES = SHAPES;
  TF.lineScoreFor = lineScoreFor;
  TF.difficultyAt = difficultyAt;
})();
