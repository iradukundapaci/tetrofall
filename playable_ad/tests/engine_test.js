/* Headless checks for the Google Ads playables. Run: node tests/engine_test.js
 *
 * Covers the ported rules (scoring, ripple chains, rise top-out), the
 * gesture thresholds, every authored rig, and a no-input run of each ad from
 * start to its end card through the real director with rendering stubbed.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const SRC = path.join(__dirname, '..', 'src', 'ads');
globalThis.TF = { ASSETS: {} };
function load(rel) { vm.runInThisContext(fs.readFileSync(path.join(SRC, rel), 'utf8'), { filename: rel }); }
['core/constants.js', 'core/engine.js', 'core/input.js', 'core/director.js'].forEach(load);
TF.audio = { play() {}, unlock() {} };
['deep_well', 'chain_reaction', 'floor_rises', 'where_does_it_go', 'real_game'].forEach((s) => load(`ads/${s}.js`));

let failures = 0, passes = 0;
function check(name, cond, detail) {
  if (cond) { passes++; console.log(`  ok   ${name}`); }
  else { failures++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`); }
}

function placeAndResolve(rows, type, target) {
  const e = new TF.Engine({ seed: 1 });
  e.setRows(rows);
  e.queuePieces([type]);
  e.freezeGravity = true;
  e.freezeRise = true;
  e.start();
  e.lowerTo(2);
  const clears = [];
  let end = null;
  e.on((t, d) => { if (t === 'clear') clears.push(d); if (t === 'resolveEnd') end = d; });
  const bot = new TF.Bot(e);
  for (let i = 0; i < 60 && !end; i++) {
    if (e.phase === 'playing') bot.steer(target);
    for (let k = 0; k < 10; k++) e.tick(1 / 60);
  }
  for (let i = 0; i < 600 && !end; i++) e.tick(1 / 60);
  return { e, clears, end };
}

console.log('scoring');
{
  check('line base table', TF.lineScoreFor(1) === 100 && TF.lineScoreFor(4) === 800 && TF.lineScoreFor(6) === 1400);
  const full = (ex) => Array.from({ length: 18 }, (_, c) => (ex.includes(c) ? '.' : '#')).join('');
  const r = placeAndResolve([full([0, 1, 2, 3])], 'I', { rot: 0, col: 0 });
  check('single row at t=0 scores 100', r.e.score === 100, `score ${r.e.score}`);
  const d = TF.difficultyAt(135);
  check('difficulty interpolates (t=135s)', d.dropMs === 775 && Math.abs(d.riseInterval - 14) < 1e-9, JSON.stringify(d));
}

console.log('rigs');
{
  const dw = TF.ads.deep_well;
  const col14Empty = dw.rig.every((row) => row.charAt(14) === '.');
  check('deep_well well column stays open', col14Empty);
  const e = new TF.Engine({ seed: 1 });
  e.setRows(dw.rig);
  e.queuePieces(['I', 'I']);
  e.freezeGravity = e.freezeRise = true;
  e.start();
  const lines = [];
  e.on((t, d) => { if (t === 'resolveEnd') lines.push(d.lines); });
  const bot = new TF.Bot(e);
  for (let i = 0; i < 400 && lines.length < 2; i++) {
    if (e.phase === 'playing') bot.steer(dw.guide);
    for (let k = 0; k < 10; k++) e.tick(1 / 60);
  }
  check('deep_well: two I pieces clear 4 rows each', lines[0] === 4 && lines[1] === 4, JSON.stringify(lines));

  TF.ads.chain_reaction.rigs.forEach((rig) => {
    const r = placeAndResolve(rig.rows, 'I', rig.guide);
    check(`chain_reaction rig reaches chain x${rig.chains}`, r.end && r.end.chains === rig.chains && r.e.maxChain === rig.chains,
      JSON.stringify(r.end));
  });

  TF.ads.where_does_it_go.rounds.forEach((R, i) => {
    const right = placeAndResolve(R.rows, R.piece, R.right);
    check(`where_does_it_go round ${i + 1}: right slot clears ${R.need}`, right.end && right.end.lines >= R.need, JSON.stringify(right.end));
    const decoy = placeAndResolve(R.rows, R.piece, R.decoy);
    check(`where_does_it_go round ${i + 1}: decoy does not`, decoy.end && decoy.end.lines < R.need, JSON.stringify(decoy.end));
  });
}

console.log('rise');
{
  const e = new TF.Engine({ seed: 2, riseGrace: 0, riseInterval: 0.2 });
  e.setRows(Array(20).fill('#########.########'));
  e.queuePieces(['O']);
  let over = null;
  e.on((t, d) => { if (t === 'gameOver') over = d; });
  e.start();
  for (let i = 0; i < 120 && !over; i++) e.tick(1 / 60);
  check('rise on a full board tops out', over && (over.reason === 'topOut' || over.reason === 'blockOut'), JSON.stringify(over));

  const e2 = new TF.Engine({ seed: 3, fillRatio: 0.75, gapMode: 'adjacent' });
  const row = e2.generateRow();
  const gaps = row.filter((v) => !v).length;
  check('rise row gap count round(18*(1-0.75)) = 5', gaps === 5, `gaps ${gaps}`);
}

console.log('gestures');
{
  const cell = 16;
  function run(points) {
    const out = [];
    const g = new TF.Gestures({ intent: (t) => out.push(t) }, () => cell);
    g.down(1, points[0][0], points[0][1], points[0][2]);
    for (let i = 1; i < points.length - 1; i++) g.move(1, points[i][0], points[i][1], points[i][2]);
    const last = points[points.length - 1];
    g.move(1, last[0], last[1], last[2]);
    g.up(1, last[2] + 0.01);
    return out;
  }
  const line = (x0, y0, x1, y1, seconds, n) =>
    Array.from({ length: n + 1 }, (_, i) => [x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n, seconds * i / n]);

  check('tap rotates', JSON.stringify(run([[100, 100, 0], [102, 101, 0.08]])) === '["rotate"]');
  const flick = run(line(100, 100, 102, 220, 0.12, 8));
  check('fast vertical flick hard drops', flick.includes('hard') && !flick.includes('rotate'), JSON.stringify(flick));
  const slow = run(line(100, 100, 100, 220, 1.5, 40));
  check('slow drag down soft drops, never hard', slow.includes('softStart') && !slow.includes('hard'), JSON.stringify(slow));
  const swipe = run(line(100, 100, 100 + cell * 0.85 * 3 + 2, 102, 0.4, 20));
  check('sideways swipe shifts 3 columns', swipe.filter((t) => t === 'right').length === 3, JSON.stringify(swipe));
}

console.log('ads, no input, start to end card');
{
  const renderer = { reset() {}, onEvent() {}, shake: 0 };
  ['deep_well', 'chain_reaction', 'floor_rises', 'where_does_it_go', 'real_game'].forEach((slug) => {
    const show = new TF.Show(TF.ads[slug], renderer);
    TF.ads[slug].start(show);
    let t = 0;
    while (!show.endState && t < 120) { show.update(1 / 60); t += 1 / 60; }
    check(`${slug} reaches its end card (${t.toFixed(1)}s, "${show.endState && show.endState.title}")`,
      !!show.endState && t < 90, show.endState ? '' : 'never ended');
    show.restart();
    check(`${slug} restarts cleanly`, !show.endState && show.engine && show.engine.phase !== 'gameOver');
  });
}

console.log('floor_rises tuning');
{
  const ad = TF.ads.floor_rises, cfg = ad.config;
  function simulate(withBot) {
    const opts = Object.assign({ seed: cfg.seed }, cfg.engine);
    const e = new TF.Engine(opts);
    e.setRows(ad.startingRows(e));
    e.pendingRow = e.generateRow();
    let over = false;
    e.on((type) => { if (type === 'gameOver') over = true; });
    e.start();
    const bot = new TF.Bot(e);
    let target = null, t = 0, step = 0;
    e.on((type) => { if (type === 'spawn') target = null; });
    while (!over && t < cfg.survive) {
      if (withBot && e.phase === 'playing' && e.piece) {
        step -= 1 / 60;
        if (step <= 0) {
          step = 0.11;
          if (!target) target = bot.choose(e.piece.type);
          bot.steer(target);
        }
      }
      e.tick(1 / 60);
      t += 1 / 60;
    }
    return { over, t };
  }
  const idle = simulate(false);
  const bot = simulate(true);
  console.log(`    idle: ${idle.over ? 'crushed at ' + idle.t.toFixed(1) + 's' : 'survived'} · bot: ${bot.over ? 'crushed at ' + bot.t.toFixed(1) + 's' : 'survived'}`);
  check('idle viewer gets crushed before the clock runs out', idle.over);
  check('a steady player can survive', !bot.over);
}

console.log(`\n${passes} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
