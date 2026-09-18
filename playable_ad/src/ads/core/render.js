/* Canvas renderer. Visual values come from the real game:
 * - blocks: tile_classic_wood.png tinted WoodMid with BlendMode.color (TileCache)
 * - board: bg_wood.png tinted WoodLight, column grooves WoodDark @0.55 (BoardFrame)
 * - ghost: outline only, #F5EAD9 @0.5 (piece_component.dart)
 * - rise danger: #D9432E gradient, alpha 0.12 + 0.22*pulse (board_frame.dart)
 * - logo / wordmark: logo_mark.dart / logo_wordmark.dart gradients
 * - shards: Motion.shard* ranges (motion.dart)
 */
(function () {
  'use strict';

  var C = TF.C, COLOR = C.COLOR, M = C.MOTION;
  var DISPLAY = '"TFDisplay", "Arial Rounded MT Bold", -apple-system, "Segoe UI", Roboto, sans-serif';
  var BODY = '-apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif';

  function display(px) { return '800 ' + px + 'px ' + DISPLAY; }
  function body(px, weight) { return (weight || 600) + ' ' + px + 'px ' + BODY; }
  function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
  function easeOutBack(t) { var c = 1.9; t -= 1; return 1 + (c + 1) * t * t * t + c * t * t; }

  function Renderer(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.blockImg = null;
    this.boardImg = null;
    this.sprite = null;
    this.spriteKey = '';
    this.pattern = null;
    this.reset();

    var self = this;
    loadTinted(TF.ASSETS.blockTile, COLOR.woodMid, function (c) { self.blockImg = c; self.spriteKey = ''; });
    loadTinted(TF.ASSETS.boardTile, COLOR.woodLight, function (c) { self.boardImg = c; self.pattern = null; });
  }

  function loadTinted(src, tint, done) {
    if (!src) return;
    var img = new Image();
    img.onload = function () {
      var off = document.createElement('canvas');
      off.width = img.width;
      off.height = img.height;
      var o = off.getContext('2d');
      o.drawImage(img, 0, 0);
      o.globalCompositeOperation = 'color';
      o.fillStyle = tint;
      o.fillRect(0, 0, off.width, off.height);
      done(off);
    };
    img.src = src;
  }

  var R = Renderer.prototype;

  R.reset = function () {
    this.now = 0;
    this.shards = [];
    this.cracks = [];
    this.falls = {};
    this.trails = [];
    this.flashes = [];
    this.callouts = [];
    this.shake = 0;
    this.riseAnim = 0;
    this.boardFade = 1;
  };

  R.setLayout = function (L, scale, dpr) {
    this.L = L;
    this.scale = scale;
    this.dpr = dpr;
    this.spriteKey = '';
  };

  // ---- engine events ------------------------------------------------------
  R.onEvent = function (type, d, engine) {
    var L = this.L, now = this.now;
    if (type === 'clear') {
      var center = (engine.cols - 1) / 2;
      var ts = d.timeScale || 1;
      for (var i = 0; i < d.cells.length; i++) {
        var cell = d.cells[i];
        this.cracks.push({
          row: cell[0], col: cell[1], t0: now,
          burstAt: now + (M.crackHold + Math.abs(cell[1] - center) * M.shatterStep) * ts,
          lines: d.rows.length
        });
      }
      var avgRow = d.rows.reduce(function (a, b) { return a + b; }, 0) / d.rows.length;
      this.callouts.push({ text: '+' + d.points.toLocaleString(), row: avgRow, t0: now, small: true });
      if (d.chainIndex > 0) {
        this.callouts.push({ text: 'CHAIN x' + (d.chainIndex + 1), row: avgRow - 2.2, t0: now, big: true });
      } else if (d.rows.length >= 4) {
        this.callouts.push({ text: d.rows.length + ' ROWS!', row: avgRow - 2.2, t0: now, big: true });
      }
    } else if (type === 'fall') {
      for (var j = 0; j < d.falls.length; j++) {
        var f = d.falls[j];
        this.falls[f.toRow * 100 + f.col] = { from: f.fromRow, to: f.toRow, t0: now, dur: Math.max(0.05, d.duration) };
      }
    } else if (type === 'hardDrop') {
      var cells = engine.pieceCells();
      var dist = d.to - d.from;
      if (dist > 0) this.trails.push({ cells: cells, dist: dist, t0: now });
      this.shake = Math.max(this.shake, 2.5);
    } else if (type === 'lock') {
      this.flashes.push({ cells: d.cells, t0: now });
    } else if (type === 'rise') {
      this.falls = {};
      this.riseAnim = 1;
    } else if (type === 'board') {
      this.falls = {};
      this.cracks = [];
      this.boardFade = 0;
    }
    if (!L) return;
  };

  R.burst = function (row, col, lines) {
    var L = this.L, cell = L.board.cell;
    var cx = L.board.x + (col + 0.5) * cell, cy = L.board.y + (row + 0.5) * cell;
    var n = 5 + Math.min(4, (lines - 1) * 2);
    if (this.shards.length > 700) n = 2;
    for (var i = 0; i < n; i++) {
      var up = M.shardMinUpSpeedCells + Math.random() * (M.shardMaxUpSpeedCells - M.shardMinUpSpeedCells);
      var life = M.shardMinLifetime + Math.random() * (M.shardMaxLifetime - M.shardMinLifetime);
      var size = M.shardMinSizeCells + Math.random() * (M.shardMaxSizeCells - M.shardMinSizeCells);
      this.shards.push({
        x: cx + (Math.random() - 0.5) * cell, y: cy + (Math.random() - 0.5) * cell,
        vx: (Math.random() - 0.5) * 2 * M.shardMaxOutwardSpeedCells * cell,
        vy: -up * cell * 0.55,
        rot: Math.random() * 6.28, vr: (Math.random() - 0.5) * 12,
        life: life, max: life, s: size * cell,
        color: Math.random() < 0.55 ? COLOR.woodMid : (Math.random() < 0.6 ? COLOR.woodLight : COLOR.woodDark)
      });
    }
    this.shake = Math.max(this.shake, 1.5 + lines);
  };

  R.update = function (dt) {
    this.now += dt;
    var cell = this.L ? this.L.board.cell : 16;
    var g = M.gravityCellsPerS2 * cell * 0.5;
    for (var i = this.cracks.length - 1; i >= 0; i--) {
      var c = this.cracks[i];
      if (this.now >= c.burstAt) {
        this.burst(c.row, c.col, c.lines);
        this.cracks.splice(i, 1);
      }
    }
    for (var j = this.shards.length - 1; j >= 0; j--) {
      var s = this.shards[j];
      s.vy += g * dt;
      s.vx *= Math.max(0, 1 - 1.8 * dt);
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.rot += s.vr * dt;
      s.life -= dt;
      if (s.life <= 0 || s.y > this.L.H + 40) this.shards.splice(j, 1);
    }
    this.shake = Math.max(0, this.shake - dt * 14);
    this.riseAnim = Math.max(0, this.riseAnim - dt / 0.16);
    this.boardFade = Math.min(1, this.boardFade + dt / 0.3);
    var self = this;
    this.trails = this.trails.filter(function (t) { return self.now - t.t0 < 0.22; });
    this.flashes = this.flashes.filter(function (f) { return self.now - f.t0 < 0.25; });
    this.callouts = this.callouts.filter(function (co) { return self.now - co.t0 < (co.big ? 1.3 : 0.9); });
    for (var k in this.falls) if (this.now - this.falls[k].t0 > this.falls[k].dur) delete this.falls[k];
  };

  // ---- primitives ---------------------------------------------------------
  R.roundRect = function (x, y, w, h, r) {
    var ctx = this.ctx;
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  };

  R.ensureSprite = function () {
    var px = Math.max(4, Math.round(this.L.board.cell * this.scale * this.dpr));
    var key = px + ':' + !!this.blockImg;
    if (this.spriteKey === key) return;
    var off = document.createElement('canvas');
    off.width = off.height = px;
    var o = off.getContext('2d');
    var r = Math.max(1, px * 0.06);
    var inset = Math.max(0.5, px * 0.03);
    o.beginPath();
    o.moveTo(inset + r, inset);
    o.arcTo(px - inset, inset, px - inset, px - inset, r);
    o.arcTo(px - inset, px - inset, inset, px - inset, r);
    o.arcTo(inset, px - inset, inset, inset, r);
    o.arcTo(inset, inset, px - inset, inset, r);
    o.closePath();
    o.save();
    o.clip();
    if (this.blockImg) {
      o.drawImage(this.blockImg, 0, 0, px, px);
    } else {
      var grad = o.createLinearGradient(0, 0, 0, px);
      grad.addColorStop(0, '#8A5E38');
      grad.addColorStop(1, COLOR.woodDark);
      o.fillStyle = grad;
      o.fillRect(0, 0, px, px);
    }
    var sheen = o.createLinearGradient(0, 0, 0, px);
    sheen.addColorStop(0, 'rgba(255,255,255,0.16)');
    sheen.addColorStop(0.3, 'rgba(255,255,255,0)');
    sheen.addColorStop(1, 'rgba(0,0,0,0.22)');
    o.fillStyle = sheen;
    o.fillRect(0, 0, px, px);
    o.restore();
    o.strokeStyle = 'rgba(30,18,10,0.55)';
    o.lineWidth = Math.max(1, px * 0.05);
    o.stroke();
    this.sprite = off;
    this.spriteKey = key;
  };

  R.block = function (x, y, alpha) {
    var cell = this.L.board.cell;
    if (alpha != null && alpha < 1) this.ctx.globalAlpha = alpha;
    this.ctx.drawImage(this.sprite, x, y, cell, cell);
    if (alpha != null && alpha < 1) this.ctx.globalAlpha = 1;
  };

  // ---- board --------------------------------------------------------------
  R.drawBoard = function (show) {
    var ctx = this.ctx, L = this.L, b = L.board, e = show.engine, cell = b.cell;
    this.ensureSprite();

    ctx.save();
    ctx.shadowColor = 'rgba(0,0,0,0.45)';
    ctx.shadowBlur = 16;
    ctx.shadowOffsetY = 6;
    ctx.fillStyle = COLOR.woodLight;
    ctx.fillRect(b.x - 3, b.y - 3, b.w + 6, b.h + 6);
    ctx.restore();

    if (this.boardImg && !this.pattern) this.pattern = ctx.createPattern(this.boardImg, 'repeat');
    ctx.fillStyle = this.pattern || COLOR.woodLight;
    ctx.fillRect(b.x, b.y, b.w, b.h);
    ctx.fillStyle = COLOR.woodDark;
    ctx.fillRect(b.x - 3, b.y + b.h, b.w + 6, 5);

    ctx.strokeStyle = 'rgba(74,47,28,0.55)';
    ctx.lineWidth = Math.max(1, cell * 0.06);
    ctx.beginPath();
    for (var gc = 1; gc < C.COLS; gc++) {
      var gx = Math.round(b.x + gc * cell) + 0.5;
      ctx.moveTo(gx, b.y);
      ctx.lineTo(gx, b.y + b.h);
    }
    ctx.stroke();

    // Rise progress: the pending row pushes up under the board frame.
    if (!e.freezeRise && e.phase !== 'gameOver' && e.elapsed - e.riseStartElapsed >= e.riseGrace) {
      ctx.fillStyle = 'rgba(217,67,46,0.9)';
      ctx.fillRect(b.x - 3, b.y + b.h + 1, (b.w + 6) * clamp01(e.riseProgress), 4);
    }

    ctx.save();
    ctx.beginPath();
    ctx.rect(b.x, b.y, b.w, b.h);
    ctx.clip();

    var lift = this.riseAnim * cell;
    var fade = this.boardFade;
    for (var r = 0; r <= e.maxRow; r++) {
      for (var c = 0; c < e.cols; c++) {
        if (!e.at(r, c)) continue;
        var y = b.y + r * cell + lift;
        var anim = this.falls[r * 100 + c];
        if (anim) {
          var p = clamp01((this.now - anim.t0) / anim.dur);
          y = b.y + (anim.from + (anim.to - anim.from) * p * p) * cell;
        }
        this.block(b.x + c * cell, y, fade);
      }
    }

    // Cracking cells: already removed from the grid, drawn until they burst.
    for (var i = 0; i < this.cracks.length; i++) {
      var k = this.cracks[i];
      var kx = b.x + k.col * cell, ky = b.y + k.row * cell;
      this.block(kx, ky);
      var heat = clamp01((this.now - k.t0) / M.crackHold);
      ctx.fillStyle = 'rgba(255,236,190,' + (0.15 + 0.45 * heat) + ')';
      ctx.fillRect(kx, ky, cell, cell);
      ctx.strokeStyle = 'rgba(40,22,10,' + (0.4 + 0.4 * heat) + ')';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(kx + cell * 0.2, ky + cell * 0.1);
      ctx.lineTo(kx + cell * 0.5, ky + cell * 0.55);
      ctx.lineTo(kx + cell * 0.35, ky + cell * 0.9);
      ctx.moveTo(kx + cell * 0.5, ky + cell * 0.55);
      ctx.lineTo(kx + cell * 0.85, ky + cell * 0.7);
      ctx.stroke();
    }

    this.drawGuide(show);
    this.drawPiece(show, lift);

    for (var f = 0; f < this.flashes.length; f++) {
      var fl = this.flashes[f], a = 0.45 * (1 - (this.now - fl.t0) / 0.25);
      ctx.fillStyle = 'rgba(255,240,210,' + a + ')';
      for (var q = 0; q < fl.cells.length; q++) ctx.fillRect(b.x + fl.cells[q][1] * cell, b.y + fl.cells[q][0] * cell, cell, cell);
    }

    // Danger: stack within riseWarnRow of the top.
    if (e.stackTop() <= M.riseWarnRow && e.phase !== 'gameOver') {
      var pulse = 0.5 + 0.5 * Math.sin(this.now * 7);
      var dg = ctx.createLinearGradient(0, b.y, 0, b.y + cell * 6);
      dg.addColorStop(0, 'rgba(217,67,46,' + (0.12 + 0.22 * pulse) + ')');
      dg.addColorStop(1, 'rgba(217,67,46,0)');
      ctx.fillStyle = dg;
      ctx.fillRect(b.x, b.y, b.w, cell * 6);
    }
    ctx.restore();

    this.drawLabels(show);
  };

  R.drawPiece = function (show, lift) {
    var ctx = this.ctx, b = this.L.board, e = show.engine, cell = b.cell;
    if (!e.piece || e.phase !== 'playing') return;
    var cells = e.pieceCells();
    var ghost = e.ghostRow();
    if (ghost != null && ghost !== e.piece.row) {
      ctx.strokeStyle = 'rgba(245,234,217,0.6)';
      ctx.lineWidth = Math.max(1.2, cell * 0.08);
      var dRow = ghost - e.piece.row;
      for (var i = 0; i < cells.length; i++) {
        var gy = b.y + (cells[i][0] + dRow) * cell + lift;
        this.roundRect(b.x + cells[i][1] * cell + 1.5, gy + 1.5, cell - 3, cell - 3, cell * 0.1);
        ctx.stroke();
      }
    }
    for (var t = 0; t < this.trails.length; t++) {
      var tr = this.trails[t], ta = 0.35 * (1 - (this.now - tr.t0) / 0.22);
      ctx.fillStyle = 'rgba(255,236,190,' + ta + ')';
      for (var j = 0; j < tr.cells.length; j++) {
        ctx.fillRect(b.x + tr.cells[j][1] * cell + cell * 0.2, b.y + (tr.cells[j][0] - tr.dist) * cell, cell * 0.6, tr.dist * cell);
      }
    }
    for (var k = 0; k < cells.length; k++) {
      if (cells[k][0] < 0) continue;
      this.block(b.x + cells[k][1] * cell, b.y + cells[k][0] * cell + lift);
    }
  };

  R.drawGuide = function (show) {
    var g = show.guide, e = show.engine;
    if (!g || !e.piece || e.phase !== 'playing' || e.piece.type !== g.type) return;
    var ctx = this.ctx, b = this.L.board, cell = b.cell;
    var row = e.minRow;
    if (e.collides(g.type, g.rot, row, g.col)) return;
    while (!e.collides(g.type, g.rot, row + 1, g.col)) row++;
    var cells = TF.SHAPES[g.type][g.rot];
    var pulse = 0.5 + 0.5 * Math.sin(this.now * 6);
    ctx.save();
    ctx.shadowColor = COLOR.gold;
    ctx.shadowBlur = 8 + 6 * pulse;
    ctx.strokeStyle = 'rgba(242,182,50,' + (0.65 + 0.35 * pulse) + ')';
    ctx.fillStyle = 'rgba(242,182,50,' + (0.12 + 0.12 * pulse) + ')';
    ctx.lineWidth = 2;
    for (var i = 0; i < 4; i++) {
      var x = b.x + (g.col + cells[i][1]) * cell, y = b.y + (row + cells[i][0]) * cell;
      this.roundRect(x + 1.5, y + 1.5, cell - 3, cell - 3, cell * 0.12);
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  };

  R.drawLabels = function (show) {
    if (!show.labels || !show.labels.length) return;
    var ctx = this.ctx, b = this.L.board, cell = b.cell, e = show.engine;
    for (var i = 0; i < show.labels.length; i++) {
      var lb = show.labels[i];
      // Float above the slot's rim (its neighbours), not at the bottom of a well.
      var top = e.maxRow + 1;
      var c0 = Math.floor(lb.col) - 1, c1 = Math.ceil(lb.col) + 1;
      for (var r = 0; r <= e.maxRow && top > e.maxRow; r++) {
        for (var cc = c0; cc <= c1; cc++) if (e.at(r, cc)) { top = r; break; }
      }
      var x = b.x + (lb.col + 0.5) * cell;
      var y = b.y + (top - 1.4) * cell + Math.sin(this.now * 4 + i) * 2;
      var rad = cell * 0.78;
      ctx.fillStyle = lb.state === 'bad' ? COLOR.red : lb.state === 'good' ? COLOR.green : COLOR.gold;
      ctx.beginPath();
      ctx.arc(x, y, rad, 0, Math.PI * 2);
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = COLOR.woodDark;
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(x - 4, y + rad - 1);
      ctx.lineTo(x + 4, y + rad - 1);
      ctx.lineTo(x, y + rad + 6);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = lb.state ? '#fff' : COLOR.woodDark;
      ctx.font = display(Math.round(rad * 1.3));
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(lb.text, x, y + 1);
      ctx.textBaseline = 'alphabetic';
    }
  };

  R.drawShards = function () {
    var ctx = this.ctx;
    for (var i = 0; i < this.shards.length; i++) {
      var s = this.shards[i];
      var p = 1 - s.life / s.max;
      var a = p < M.shardFadeStartFraction ? 1 : 1 - (p - M.shardFadeStartFraction) / (1 - M.shardFadeStartFraction);
      ctx.globalAlpha = clamp01(a);
      ctx.fillStyle = s.color;
      var cos = Math.cos(s.rot), sin = Math.sin(s.rot), h = s.s;
      ctx.beginPath();
      ctx.moveTo(s.x + cos * h, s.y + sin * h);
      ctx.lineTo(s.x - sin * h * 0.7 - cos * h * 0.4, s.y + cos * h * 0.7 - sin * h * 0.4);
      ctx.lineTo(s.x + sin * h * 0.6 - cos * h * 0.5, s.y - cos * h * 0.6 - sin * h * 0.5);
      ctx.closePath();
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  };

  R.drawCallouts = function () {
    var ctx = this.ctx, b = this.L.board, cell = b.cell;
    for (var i = 0; i < this.callouts.length; i++) {
      var co = this.callouts[i], age = this.now - co.t0;
      var dur = co.big ? 1.3 : 0.9;
      var y = b.y + (co.row + 0.5) * cell - age * (co.big ? 10 : 26);
      var alpha = clamp01((dur - age) / 0.3);
      var s = co.big ? easeOutBack(clamp01(age / 0.25)) : 1;
      ctx.save();
      ctx.globalAlpha = alpha;
      ctx.translate(b.x + b.w / 2, y);
      ctx.scale(s, s);
      this.styledText(co.text, 0, 0, co.big ? this.L.callout.size + 6 : this.L.callout.size - 6, co.big ? 'shout' : 'score');
      ctx.restore();
    }
  };

  // ---- text ---------------------------------------------------------------
  R.styledText = function (text, x, y, size, style) {
    var ctx = this.ctx;
    ctx.font = display(size);
    ctx.textAlign = 'center';
    ctx.lineJoin = 'round';
    var fill = '#FFFFFF', stroke = 'rgba(32,18,8,0.95)';
    if (style === 'shout') fill = COLOR.goldLight;
    if (style === 'score') fill = COLOR.gold;
    if (style === 'alarm') { fill = COLOR.red; stroke = '#FFFFFF'; }
    if (style === 'good') fill = '#8EE3A5';
    ctx.lineWidth = Math.max(3, size * 0.2);
    ctx.strokeStyle = stroke;
    ctx.strokeText(text, x, y);
    ctx.fillStyle = fill;
    ctx.fillText(text, x, y);
  };

  R.wrap = function (text, maxW) {
    var words = text.split(' '), lines = [], line = '';
    for (var i = 0; i < words.length; i++) {
      var test = line ? line + ' ' + words[i] : words[i];
      if (this.ctx.measureText(test).width > maxW && line) {
        lines.push(line);
        line = words[i];
      } else {
        line = test;
      }
    }
    if (line) lines.push(line);
    return lines;
  };

  R.drawCaption = function (show) {
    var cap = show.captionState;
    if (!cap) return;
    var age = show.t - cap.t0;
    if (cap.dur != null && age > cap.dur) return;
    var ctx = this.ctx, L = this.L, spec = L.caption;
    var size = cap.size || spec.size;
    ctx.font = display(size);
    // Prefer one slightly smaller line over a wrap that orphans a word and
    // grows the pill down over the falling piece.
    var room = spec.w - (cap.style === 'question' ? 36 : 16);
    while (ctx.measureText(cap.text).width > room && size > spec.size * 0.7) {
      size -= 1;
      ctx.font = display(size);
    }
    var lines = this.wrap(cap.text, room);
    while (lines.length > 3 && size > 14) {
      size -= 2;
      ctx.font = display(size);
      lines = this.wrap(cap.text, spec.w - 16);
    }
    var lh = size * 1.08;
    var s = easeOutBack(clamp01(age / 0.28));
    var alpha = cap.dur != null ? clamp01((cap.dur - age) / 0.25) : 1;
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.translate(spec.cx, spec.y + lh * 0.5);
    ctx.scale(s, s);
    if (cap.style === 'question') {
      var maxW = 0;
      for (var i = 0; i < lines.length; i++) maxW = Math.max(maxW, ctx.measureText(lines[i]).width);
      var pw = Math.min(spec.w, maxW + 28), ph = lines.length * lh + 14;
      ctx.fillStyle = 'rgba(24,14,7,0.88)';
      this.roundRect(-pw / 2, -size * 0.95, pw, ph, 14);
      ctx.fill();
      ctx.strokeStyle = 'rgba(242,182,50,0.8)';
      ctx.lineWidth = 2;
      ctx.stroke();
      ctx.fillStyle = '#fff';
      ctx.textAlign = 'center';
      for (var j = 0; j < lines.length; j++) ctx.fillText(lines[j], 0, j * lh);
    } else {
      for (var k = 0; k < lines.length; k++) this.styledText(lines[k], 0, k * lh, size, cap.style);
    }
    ctx.restore();
  };

  R.drawCountdown = function (show) {
    var cd = show.countdownState;
    if (!cd) return;
    var age = show.t - cd.t0;
    if (age > 0.8) return;
    var b = this.L.board, ctx = this.ctx;
    ctx.save();
    ctx.globalAlpha = clamp01((0.8 - age) / 0.3);
    ctx.translate(b.x + b.w / 2, b.y + b.h * (this.L.name === 'portrait' ? 0.5 : 0.45));
    var s = easeOutBack(clamp01(age / 0.22)) * 1.0;
    ctx.scale(s, s);
    this.styledText(cd.text, 0, 0, cd.text.length > 2 ? 54 : 90, cd.text.length > 2 ? 'shout' : 'hook');
    ctx.restore();
  };

  // ---- hand hint ----------------------------------------------------------
  R.hand = function (x, y, press) {
    var ctx = this.ctx, u = this.L.board.cell * 0.95;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(-0.25);
    ctx.scale(1 - press * 0.12, 1 - press * 0.12);
    ctx.fillStyle = '#FFFFFF';
    ctx.strokeStyle = 'rgba(30,18,10,0.9)';
    ctx.lineWidth = 2;
    ctx.shadowColor = 'rgba(0,0,0,0.4)';
    ctx.shadowBlur = 6;
    ctx.shadowOffsetY = 3;
    ctx.beginPath();
    // index finger (tip at 0,0)
    ctx.moveTo(-0.28 * u, 0.3 * u);
    ctx.arc(0, 0.28 * u, 0.28 * u, Math.PI, 0);
    ctx.lineTo(0.28 * u, 1.3 * u);
    // knuckles
    ctx.arc(0.53 * u, 1.3 * u, 0.25 * u, Math.PI, 0);
    ctx.arc(1.03 * u, 1.45 * u, 0.25 * u, Math.PI, 0);
    ctx.arc(1.48 * u, 1.65 * u, 0.22 * u, Math.PI, 0);
    ctx.lineTo(1.7 * u, 2.5 * u);
    ctx.quadraticCurveTo(1.6 * u, 3.3 * u, 0.8 * u, 3.3 * u);
    ctx.lineTo(0.2 * u, 3.3 * u);
    ctx.quadraticCurveTo(-0.3 * u, 3.2 * u, -0.6 * u, 2.5 * u);
    // thumb
    ctx.lineTo(-0.95 * u, 1.9 * u);
    ctx.quadraticCurveTo(-1.05 * u, 1.55 * u, -0.7 * u, 1.6 * u);
    ctx.lineTo(-0.28 * u, 2.05 * u);
    ctx.closePath();
    ctx.fill();
    ctx.shadowColor = 'transparent';
    ctx.stroke();
    ctx.restore();
  };

  R.ring = function (x, y, p) {
    var ctx = this.ctx, cell = this.L.board.cell;
    ctx.strokeStyle = 'rgba(255,255,255,' + (0.8 * (1 - p)) + ')';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(x, y, cell * (0.4 + 1.2 * p), 0, Math.PI * 2);
    ctx.stroke();
  };

  R.drawHint = function (show) {
    var h = show.hintState, e = show.engine;
    if (!h || !show.hintVisible() || !e.piece || e.phase !== 'playing') return;
    var ctx = this.ctx, b = this.L.board, cell = b.cell;
    var cells = e.pieceCells();
    var minC = 99, maxC = -99, maxR = -99;
    for (var i = 0; i < cells.length; i++) {
      minC = Math.min(minC, cells[i][1]); maxC = Math.max(maxC, cells[i][1]); maxR = Math.max(maxR, cells[i][0]);
    }
    var px = b.x + ((minC + maxC) / 2 + 0.5) * cell;
    var py = b.y + (Math.max(maxR, 0) + 2.2) * cell;
    var t = (show.t - h.t0);
    ctx.save();
    ctx.globalAlpha = clamp01((show.t - show.hintShownAt) / 0.25);
    if (h.kind === 'tap') {
      var p = (t % 1.1) / 1.1;
      var press = p < 0.25 ? p / 0.25 : p < 0.45 ? 1 - (p - 0.25) / 0.2 : 0;
      if (p > 0.2 && p < 0.9) this.ring(px, py, (p - 0.2) / 0.7);
      this.hand(px, py, press);
    } else if (h.kind === 'drag') {
      var tx = b.x + (h.col + 0.5) * cell;
      var q = (t % 1.6) / 1.6;
      var m = q < 0.15 ? 0 : q < 0.7 ? (q - 0.15) / 0.55 : 1;
      m = m * m * (3 - 2 * m);
      var hx = px + (tx - px) * m;
      ctx.strokeStyle = 'rgba(255,255,255,0.55)';
      ctx.lineWidth = 3;
      ctx.setLineDash([6, 6]);
      ctx.beginPath();
      ctx.moveTo(px, py);
      ctx.lineTo(tx, py);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.globalAlpha *= q > 0.85 ? clamp01((1 - q) / 0.15) : 1;
      this.hand(hx, py, q < 0.15 ? q / 0.15 : 1);
    } else if (h.kind === 'flick') {
      var f = (t % 1.2) / 1.2;
      var d = f < 0.2 ? 0 : f < 0.42 ? (f - 0.2) / 0.22 : 1;
      var fy = py + d * d * cell * 5;
      if (f > 0.25 && f < 0.7) {
        ctx.strokeStyle = 'rgba(255,255,255,' + (0.7 * (1 - (f - 0.25) / 0.45)) + ')';
        ctx.lineWidth = 3;
        for (var s = -1; s <= 1; s++) {
          ctx.beginPath();
          ctx.moveTo(px + s * cell * 0.5, fy - cell * 3);
          ctx.lineTo(px + s * cell * 0.5, fy - cell * 0.8);
          ctx.stroke();
        }
      }
      ctx.globalAlpha *= f > 0.8 ? clamp01((1 - f) / 0.2) : 1;
      this.hand(px, fy, f < 0.2 ? f / 0.2 : 1);
    }
    ctx.restore();
  };

  // ---- chrome -------------------------------------------------------------
  R.logoBlock = function (x, y, size) {
    var ctx = this.ctx, radius = size * 0.2;
    ctx.save();
    ctx.shadowColor = 'rgba(0,0,0,0.35)';
    ctx.shadowOffsetY = size * 0.1;
    ctx.shadowBlur = size * 0.3;
    var grad = ctx.createLinearGradient(x + size * 0.2, y, x + size * 0.8, y + size);
    grad.addColorStop(0, COLOR.woodLight);
    grad.addColorStop(0.55, COLOR.woodMid);
    grad.addColorStop(1, COLOR.woodDark);
    ctx.fillStyle = grad;
    this.roundRect(x, y, size, size, radius);
    ctx.fill();
    ctx.restore();
    var bevel = ctx.createLinearGradient(x, y, x, y + size);
    bevel.addColorStop(0, 'rgba(255,255,255,0.28)');
    bevel.addColorStop(0.25, 'rgba(255,255,255,0)');
    bevel.addColorStop(0.7, 'rgba(0,0,0,0)');
    bevel.addColorStop(1, 'rgba(0,0,0,0.3)');
    ctx.fillStyle = bevel;
    this.roundRect(x, y, size, size, radius);
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.35)';
    ctx.lineWidth = 1;
    ctx.stroke();
  };

  R.logoMark = function (x0, y0, cell) {
    var gap = cell * 0.125;
    this.logoBlock(x0 + cell + gap, y0, cell);
    this.logoBlock(x0, y0 + cell + gap, cell);
    this.logoBlock(x0 + cell + gap, y0 + cell + gap, cell);
    this.logoBlock(x0 + (cell + gap) * 2, y0 + cell + gap, cell);
  };

  R.wordmark = function (x, y, size, align) {
    var ctx = this.ctx;
    ctx.save();
    ctx.font = display(size);
    ctx.textAlign = align || 'center';
    ctx.shadowColor = 'rgba(0,0,0,0.45)';
    ctx.shadowOffsetY = 3;
    ctx.shadowBlur = 6;
    var grad = ctx.createLinearGradient(0, y - size * 0.78, 0, y + size * 0.14);
    grad.addColorStop(0, '#FFE9B0');
    grad.addColorStop(0.55, COLOR.gold);
    grad.addColorStop(1, '#C9821A');
    ctx.fillStyle = grad;
    ctx.fillText('TETROFALL', x, y);
    ctx.restore();
  };

  R.button = function (rect, label, size, pulse) {
    var ctx = this.ctx;
    var s = 1 + 0.035 * pulse;
    ctx.save();
    ctx.translate(rect.x + rect.w / 2, rect.y + rect.h / 2);
    ctx.scale(s, s);
    ctx.shadowColor = 'rgba(0,0,0,0.45)';
    ctx.shadowBlur = 12;
    ctx.shadowOffsetY = 4;
    var grad = ctx.createLinearGradient(0, -rect.h / 2, 0, rect.h / 2);
    grad.addColorStop(0, COLOR.goldLight);
    grad.addColorStop(0.45, COLOR.gold);
    grad.addColorStop(1, '#D99A1F');
    ctx.fillStyle = grad;
    this.roundRect(-rect.w / 2, -rect.h / 2, rect.w, rect.h, rect.h / 2);
    ctx.fill();
    ctx.shadowColor = 'transparent';
    ctx.strokeStyle = 'rgba(74,47,28,0.6)';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.fillStyle = COLOR.woodDark;
    ctx.font = display(size);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(label, 0, 2);
    ctx.textBaseline = 'alphabetic';
    ctx.restore();
  };

  R.drawChrome = function (show) {
    var ctx = this.ctx, L = this.L, e = show.engine;
    var br = L.brand;
    if (L.name === 'portrait') {
      this.logoMark(br.x, br.y, br.markCell);
      this.wordmark(br.x + br.markCell * 3.25 + 7, br.y + br.markCell * 2.1, br.wordSize, 'left');
    } else {
      var mw = br.markCell * 3.25;
      this.logoMark(br.cx - mw / 2, br.y, br.markCell);
      this.wordmark(br.cx, br.y + br.markCell * 2.1 + br.wordSize + 6, br.wordSize, 'center');
    }

    ctx.fillStyle = COLOR.text;
    ctx.font = display(L.score.size);
    ctx.textAlign = L.score.align;
    ctx.fillText(e.score.toLocaleString(), L.score.x, L.score.y);
    var stat = show.statText();
    if (stat) {
      ctx.font = display(12);
      ctx.fillStyle = stat.alarm ? COLOR.red : COLOR.gold;
      ctx.textAlign = L.stat.align;
      ctx.fillText(stat.text, L.stat.x, L.stat.y);
    }

    if (show.instructionText) {
      ctx.font = body(L.name === 'portrait' ? 13 : 12, 700);
      ctx.fillStyle = COLOR.textMuted;
      ctx.textAlign = 'center';
      var lines = this.wrap(show.instructionText, L.instruction.w);
      for (var i = 0; i < lines.length; i++) ctx.fillText(lines[i], L.instruction.cx, L.instruction.y - (lines.length - 1 - i) * 15);
    }

    if (!show.endState) this.button(L.cta, L.cta.label, L.name === 'portrait' ? 22 : 19, Math.sin(show.t * 5) > 0.6 ? 1 : 0.3);
  };

  R.drawEnd = function (show) {
    var end = show.endState;
    if (!end) return;
    var ctx = this.ctx, L = this.L, E = L.end;
    var a = clamp01((show.t - end.t0) / 0.4);
    ctx.fillStyle = 'rgba(24,14,7,' + (0.9 * a) + ')';
    ctx.fillRect(0, 0, L.W, L.H);
    if (a <= 0) return;
    ctx.save();
    ctx.globalAlpha = a;
    var cx = L.W / 2;
    var mw = E.markCell * 3.25;
    this.logoMark(cx - mw / 2, E.markY, E.markCell);
    this.wordmark(cx, E.wordY, E.wordSize, 'center');

    var s = easeOutBack(clamp01((show.t - end.t0 - 0.15) / 0.3));
    ctx.save();
    ctx.translate(cx, E.titleY);
    ctx.scale(s, s);
    ctx.font = display(E.titleSize);
    var size = E.titleSize;
    while (ctx.measureText(end.title).width > L.W - 24 && size > 14) { size -= 2; ctx.font = display(size); }
    this.styledText(end.title, 0, 0, size, end.style || 'shout');
    ctx.restore();

    ctx.textAlign = 'center';
    ctx.fillStyle = COLOR.text;
    ctx.font = body(L.name === 'portrait' ? 16 : 14, 700);
    ctx.fillText(end.line, cx, E.lineY);
    if (end.stat) {
      ctx.font = display(L.name === 'portrait' ? 17 : 15);
      ctx.fillStyle = COLOR.gold;
      ctx.fillText(end.stat, cx, E.statY);
    }
    this.button(E.cta, 'INSTALL FREE', L.name === 'portrait' ? 24 : 21, 0.5 + 0.5 * Math.sin(show.t * 5));

    ctx.font = body(14, 700);
    ctx.fillStyle = COLOR.textMuted;
    ctx.fillText('↻  Replay', cx, E.replay.y + E.replay.h / 2 + 5);
    ctx.restore();
  };

  R.draw = function (show) {
    var ctx = this.ctx, L = this.L;
    ctx.setTransform(this.scale * this.dpr, 0, 0, this.scale * this.dpr, 0, 0);
    var bg = ctx.createLinearGradient(0, 0, 0, L.H);
    bg.addColorStop(0, COLOR.woodDark);
    bg.addColorStop(1, COLOR.bg);
    ctx.fillStyle = bg;
    ctx.fillRect(-2, -2, L.W + 4, L.H + 4);

    ctx.save();
    if (this.shake > 0.1) ctx.translate((Math.random() - 0.5) * this.shake, (Math.random() - 0.5) * this.shake);
    this.drawBoard(show);
    this.drawShards();
    this.drawCallouts();
    ctx.restore();

    this.drawChrome(show);
    this.drawCaption(show);
    this.drawCountdown(show);
    this.drawHint(show);
    this.drawEnd(show);
  };

  TF.Renderer = Renderer;
})();
