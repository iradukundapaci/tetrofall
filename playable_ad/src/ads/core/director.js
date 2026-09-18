/* Director — owns the canvas, the loop and the "show" API each ad script
 * drives: captions, hints, guides, autopilot, timers, the end card and the
 * store exit.
 *
 * Google App campaign rules this file enforces:
 * - the store is only ever opened by ExitApi.exit() from a user tap, never on
 *   a timer;
 * - audio is unlocked only inside pointer handlers;
 * - no storage APIs, no network.
 */
(function () {
  'use strict';

  TF.exit = function () {
    if (typeof ExitApi !== 'undefined' && ExitApi && typeof ExitApi.exit === 'function') {
      ExitApi.exit();
    } else {
      console.log('[TF] ExitApi.exit() unavailable (local preview) — would open the store.');
    }
  };

  TF.ads = TF.ads || {};

  var IDLE_HINT_AFTER = 2.5;
  var STEP = 1 / 120;

  function normShape(type, rot) {
    var cells = TF.SHAPES[type][rot];
    var mr = 9, mc = 9;
    cells.forEach(function (c) { mr = Math.min(mr, c[0]); mc = Math.min(mc, c[1]); });
    return cells.map(function (c) { return (c[0] - mr) + ':' + (c[1] - mc); }).sort().join('|');
  }

  function landingCells(e, type, rot, col) {
    var row = e.minRow;
    if (e.collides(type, rot, row, col)) return null;
    while (!e.collides(type, rot, row + 1, col)) row++;
    return TF.SHAPES[type][rot].map(function (o) { return (row + o[0]) * 100 + (col + o[1]); }).sort().join(',');
  }

  function Show(def, renderer) {
    this.def = def;
    this.renderer = renderer;
    this.reset();
  }

  var S = Show.prototype;

  S.reset = function () {
    this.t = 0;
    this.engine = null;
    this.bot = null;
    this.timers = [];
    this.frameFns = [];
    this.handlers = [];
    this.captionState = null;
    this.instructionText = '';
    this.hintState = null;
    this.hintShownAt = 0;
    this.hintWasVisible = false;
    this.lastInput = -99;
    this.spawnAt = 0;
    this.guide = null;
    this.labels = [];
    this.autopilotSpec = null;
    this.botTarget = null;
    this.stepTimer = 0;
    this.timerState = null;
    this.countdownState = null;
    this.endState = null;
    this.statOverride = null;
    this.generation = (this.generation || 0) + 1;
    this.renderer.reset();
  };

  // ---- engine + events ----------------------------------------------------
  S.newEngine = function (opts) {
    var self = this, e = new TF.Engine(opts);
    this.engine = e;
    this.bot = new TF.Bot(e);
    e.on(function (type, d) { self.dispatch(type, d); });
    return e;
  };

  S.dispatch = function (type, d) {
    var e = this.engine;
    this.renderer.onEvent(type, d, e);
    switch (type) {
      case 'lock': TF.audio.play('lock'); break;
      case 'clear':
        TF.audio.play('clear', { rate: 1 + 0.07 * Math.min(d.chainIndex, 6) });
        if (d.chainIndex > 0) TF.audio.play('chime', { step: d.chainIndex - 1 });
        break;
      case 'hardDrop': TF.audio.play('whoosh'); break;
      case 'move': case 'rotate': TF.audio.play('tick'); break;
      case 'rise': TF.audio.play('rise'); break;
      case 'gameOver': TF.audio.play('buzzer'); break;
      case 'spawn':
        this.spawnAt = this.t;
        this.botTarget = null;
        break;
      case 'dropBlocked':
        TF.audio.play('buzzer');
        this.renderer.shake = 4;
        this.flashCaption('NOT THERE!', 'alarm', 0.9);
        break;
    }
    var hs = this.handlers.slice();
    for (var i = 0; i < hs.length; i++) {
      if (hs[i].type === type && !hs[i].dead) {
        if (hs[i].once) hs[i].dead = true;
        hs[i].fn(d);
      }
    }
    this.handlers = this.handlers.filter(function (h) { return !h.dead; });
  };

  S.on = function (type, fn) { this.handlers.push({ type: type, fn: fn }); };
  S.once = function (type, fn) { this.handlers.push({ type: type, fn: fn, once: true }); };

  S.after = function (sec, fn) { this.timers.push({ at: this.t + sec, fn: fn }); };
  S.onFrame = function (fn) { this.frameFns.push(fn); };

  // ---- presentation -------------------------------------------------------
  S.caption = function (text, style, dur) {
    this.captionState = text ? { text: text, style: style || 'hook', t0: this.t, dur: dur == null ? null : dur } : null;
  };

  S.flashCaption = function (text, style, dur) {
    var prev = this.captionState, self = this;
    this.caption(text, style, dur);
    this.after(dur, function () {
      if (self.captionState && self.captionState.text === text && prev && prev.dur == null) {
        self.captionState = { text: prev.text, style: prev.style, t0: self.t - 1, dur: null };
      }
    });
  };

  S.instruction = function (text) { this.instructionText = text || ''; };

  S.hint = function (kind, opts) {
    if (!kind) { this.hintState = null; return; }
    if (this.hintState && this.hintState.kind === kind && (!opts || opts.col === this.hintState.col)) return;
    this.hintState = { kind: kind, col: opts && opts.col, t0: this.t };
    this.hintShownAt = this.t;
  };

  S.hintVisible = function () {
    if (!this.hintState || this.endState) return false;
    return this.lastInput < this.hintState.t0 || this.t - this.lastInput > IDLE_HINT_AFTER;
  };

  S.setLabels = function (labels) { this.labels = labels || []; };

  S.stat = function (text) { this.statOverride = text; };

  S.statText = function () {
    var ts = this.timerState;
    if (ts) {
      var left = Math.max(0, ts.left);
      return { text: ts.label + ' ' + left.toFixed(left < 10 ? 1 : 0) + 's', alarm: left < 5 };
    }
    if (this.statOverride) return { text: this.statOverride };
    if (this.engine && this.engine.maxChain > 1) return { text: 'BEST CHAIN x' + this.engine.maxChain };
    return null;
  };

  S.sfx = function (name, opts) { TF.audio.play(name, opts); };

  // ---- guidance -----------------------------------------------------------
  S.setGuide = function (g) { this.guide = g; };

  S.guideMatches = function () {
    var e = this.engine, p = e.piece, g = this.guide;
    if (!p || !g || p.type !== g.type) return false;
    return landingCells(e, p.type, p.rot, p.col) === landingCells(e, g.type, g.rot, g.col);
  };

  S.strict = function (on) {
    var self = this;
    this.engine.canHardDrop = on ? function () { return !self.guide || self.guideMatches(); } : null;
  };

  /* spec: { idle: seconds, target: 'bot' | 'guide' | {rot, col} } or null */
  S.autopilot = function (spec) { this.autopilotSpec = spec; };

  /* Coached placement: gold outline where the piece belongs, the hand hint
   * for whichever gesture is still missing (tap → drag → flick), hard drops
   * blocked anywhere else, and autopilot if the viewer never touches it. */
  S.guided = function (g) {
    var self = this, gen = this.generation;
    this.setGuide(g);
    this.strict(true);
    this.autopilot({ idle: g.idle || 7, target: 'guide' });
    var shape = normShape(g.type, g.rot);
    var guideCol = TF.SHAPES[g.type][g.rot].reduce(function (a, c) { return a + c[1]; }, 0) / 4 + g.col - 0.5;
    this.onFrame(function () {
      if (self.generation !== gen || self.guide !== g) return true;
      var e = self.engine, p = e.piece;
      if (!p || e.phase !== 'playing' || p.type !== g.type) return false;
      if (normShape(p.type, p.rot) !== shape) {
        self.hint('tap');
        if (g.teach !== false) self.instruction('TAP anywhere to rotate');
      } else if (!self.guideMatches()) {
        self.hint('drag', { col: guideCol });
        if (g.teach !== false) self.instruction('DRAG left or right to move');
      } else {
        self.hint('flick');
        if (g.teach !== false) self.instruction('FLICK down to drop');
      }
      return false;
    });
    this.once('lock', function () {
      if (self.generation !== gen) return;
      self.setGuide(null);
      self.strict(false);
      self.hint(null);
      self.autopilot(null);
      if (g.teach !== false) self.instruction('');
      if (g.onLocked) g.onLocked();
    });
  };

  S.timer = function (seconds, label, onDone) {
    this.timerState = { left: seconds, label: label || 'TIME', onDone: onDone };
  };

  S.countdown = function (n, onDone) {
    var self = this, gen = this.generation;
    for (var i = 0; i <= n; i++) {
      (function (k) {
        self.after(k * 0.75, function () {
          if (self.generation !== gen) return;
          var text = k < n ? String(n - k) : 'GO!';
          self.countdownState = { text: text, t0: self.t };
          TF.audio.play(k < n ? 'beep' : 'go');
          if (k === n && onDone) onDone();
        });
      })(i);
    }
  };

  S.end = function (opts) {
    if (this.endState) return;
    this.endState = {
      title: opts.title, style: opts.style || 'shout', line: opts.line || '',
      stat: opts.stat || '', t0: this.t
    };
    this.hint(null);
    this.caption(null);
    this.setGuide(null);
    this.setLabels(null);
    this.timerState = null;
    this.instruction('');
    TF.audio.play(opts.style === 'alarm' ? 'buzzer' : 'win');
  };

  S.restart = function () {
    this.reset();
    this.def.start(this);
  };

  // ---- per-frame ----------------------------------------------------------
  S.update = function (dt) {
    this.t += dt;
    var e = this.engine;

    var due = [], keep = [];
    for (var i = 0; i < this.timers.length; i++) (this.timers[i].at <= this.t ? due : keep).push(this.timers[i]);
    this.timers = keep;
    var gen = this.generation;
    for (var j = 0; j < due.length && this.generation === gen; j++) due[j].fn();
    if (this.generation !== gen) return;

    this.frameFns = this.frameFns.filter(function (fn) { return !fn(); });

    if (!this.endState && e) {
      this.runAutopilot(dt);
      var steps = Math.min(8, Math.ceil(dt / STEP));
      for (var k = 0; k < steps; k++) e.tick(dt / steps);
      if (this.timerState && e.phase !== 'gameOver') {
        this.timerState.left -= dt;
        if (this.timerState.left <= 0) {
          var done = this.timerState.onDone;
          this.timerState = null;
          if (done) done();
        }
      }
    }

    var vis = this.hintVisible();
    if (vis && !this.hintWasVisible) this.hintShownAt = this.t;
    this.hintWasVisible = vis;
  };

  S.runAutopilot = function (dt) {
    var spec = this.autopilotSpec, e = this.engine;
    if (!spec || e.phase !== 'playing' || !e.piece) return;
    var idleFor = this.t - Math.max(this.lastInput, this.spawnAt);
    if (idleFor < spec.idle) return;
    this.stepTimer -= dt;
    if (this.stepTimer > 0) return;
    this.stepTimer = 0.11;
    var target = spec.target;
    if (target === 'guide') target = this.guide;
    else if (target === 'bot') {
      if (!this.botTarget) this.botTarget = this.bot.choose(e.piece.type);
      target = this.botTarget;
    }
    if (target) this.bot.steer(target);
  };

  // ---- boot ---------------------------------------------------------------
  TF.boot = function (slug) {
    var def = TF.ads[slug];
    var canvas = document.getElementById('tf-canvas');
    var renderer = new TF.Renderer(canvas);
    var show = new Show(def, renderer);
    TF.show = show;
    var L = null, scale = 1;

    function fit() {
      var iw = window.innerWidth || document.documentElement.clientWidth || 320;
      var ih = window.innerHeight || document.documentElement.clientHeight || 480;
      L = TF.Layout.pick(iw, ih);
      scale = Math.min(iw / L.W, ih / L.H);
      var dpr = Math.min(3, window.devicePixelRatio || 1);
      canvas.style.width = Math.round(L.W * scale) + 'px';
      canvas.style.height = Math.round(L.H * scale) + 'px';
      canvas.width = Math.round(L.W * scale * dpr);
      canvas.height = Math.round(L.H * scale * dpr);
      renderer.setLayout(L, scale, dpr);
    }
    fit();
    window.addEventListener('resize', fit);
    window.addEventListener('orientationchange', function () { setTimeout(fit, 120); });

    var gestures = new TF.Gestures({
      intent: function (type) {
        show.lastInput = show.t;
        if (show.engine && !show.endState) show.engine.intent(type);
      }
    }, function () { return L.board.cell * scale; });

    function logical(ev) {
      var rect = canvas.getBoundingClientRect();
      return { x: (ev.clientX - rect.left) / scale, y: (ev.clientY - rect.top) / scale };
    }
    function inRect(p, r) { return p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h; }

    var press = null;
    canvas.addEventListener('pointerdown', function (ev) {
      ev.preventDefault();
      TF.audio.unlock();
      try { canvas.setPointerCapture(ev.pointerId); } catch (err) { /* ignore */ }
      var p = logical(ev);
      show.lastInput = show.t;
      if (show.endState) {
        if (show.t - show.endState.t0 < 0.6) return;
        var target = inRect(p, L.end.replay) ? 'replay' : 'exit';
        press = { id: ev.pointerId, x: ev.clientX, y: ev.clientY, target: target };
        return;
      }
      if (inRect(p, L.cta)) {
        press = { id: ev.pointerId, x: ev.clientX, y: ev.clientY, target: 'exit' };
        return;
      }
      gestures.down(ev.pointerId, ev.clientX, ev.clientY, ev.timeStamp / 1000);
    }, { passive: false });

    canvas.addEventListener('pointermove', function (ev) {
      ev.preventDefault();
      gestures.move(ev.pointerId, ev.clientX, ev.clientY, ev.timeStamp / 1000);
    }, { passive: false });

    function release(ev, cancelled) {
      TF.audio.unlock();
      if (press && press.id === ev.pointerId) {
        var moved = Math.abs(ev.clientX - press.x) + Math.abs(ev.clientY - press.y);
        var target = press.target;
        press = null;
        if (cancelled || moved > 24) return;
        if (target === 'replay') show.restart();
        else TF.exit();
        return;
      }
      if (cancelled) gestures.cancel(ev.pointerId);
      else gestures.up(ev.pointerId, ev.timeStamp / 1000);
    }
    canvas.addEventListener('pointerup', function (ev) { release(ev, false); });
    canvas.addEventListener('pointercancel', function (ev) { release(ev, true); });
    document.addEventListener('touchmove', function (ev) { ev.preventDefault(); }, { passive: false });

    def.start(show);

    var last = null;
    function frame(ts) {
      var dt = last == null ? 0 : Math.min(0.05, (ts - last) / 1000);
      last = ts;
      show.update(dt);
      renderer.update(dt);
      renderer.draw(show);
      requestAnimationFrame(frame);
    }
    renderer.draw(show);
    requestAnimationFrame(frame);
  };

  TF.Show = Show;
})();
