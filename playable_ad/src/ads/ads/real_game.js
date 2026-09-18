/* Ad 5 — "NO FAKE ADS. This is the real game."
 * No rig, no script: the real engine at its 3-minute difficulty checkpoint
 * with a random seed. The first piece waits while the hand teaches tap,
 * drag and flick once each; after that it is 45 seconds of the game.
 */
(function () {
  'use strict';

  var CFG = { startRows: 4, startFill: 0.8, seconds: 45, engine: { startElapsed: 180, riseGrace: 8, gapMode: 'adjacent' } };

  TF.ads.real_game = {
    title: 'Tetrofall - No fake ads',
    config: CFG,

    start: function (show) {
      var opts = { seed: (Math.random() * 1e9) >>> 0 };
      for (var k in CFG.engine) opts[k] = CFG.engine[k];
      var e = show.newEngine(opts);

      var rows = [];
      for (var i = 0; i < CFG.startRows; i++) {
        rows.push(e.generateRow(CFG.startFill, 'adjacent').map(function (v) { return v ? '#' : '.'; }).join(''));
      }
      e.setRows(rows);
      var topGap = rows[0].indexOf('.');

      e.freezeGravity = true;
      e.freezeRise = true;
      show.on('spawn', function () { if (e.freezeGravity) e.lowerTo(4); });
      e.start();

      show.caption('NO FAKE ADS.', 'hook', 2.2);
      show.after(2.2, function () { show.caption('THIS IS THE REAL GAME.', 'shout', 2.6); });

      var stage = 'tap';
      show.hint('tap');
      show.instruction('TAP anywhere to rotate');
      show.once('rotate', function () {
        if (stage !== 'tap') return;
        stage = 'drag';
        show.hint('drag', { col: topGap + 1.5 });
        show.instruction('DRAG left or right to move');
      });
      show.once('move', function () {
        if (stage === 'play') return;
        stage = 'flick';
        show.hint('flick');
        show.instruction('FLICK down to drop');
      });

      var ended = false;
      function finish(crushed) {
        if (ended) return;
        ended = true;
        show.after(crushed ? 1.1 : 0.2, function () {
          show.end({
            title: crushed ? 'CRUSHED.' : 'NOT BAD!',
            style: crushed ? 'alarm' : 'shout',
            line: crushed ? "Think you'd do better? Prove it." : 'Keep your streak going in the app.',
            stat: 'SCORE ' + e.score.toLocaleString() + (e.maxChain > 1 ? '  ·  BEST CHAIN x' + e.maxChain : '')
          });
        });
      }

      function play() {
        if (stage === 'play') return;
        stage = 'play';
        show.hint(null);
        show.instruction('Clear rows before the floor rises');
        e.freezeGravity = false;
        e.freezeRise = false;
        e.riseStartElapsed = e.elapsed;
        show.autopilot({ idle: 6, target: 'bot' });
        show.timer(CFG.seconds, 'TIME', function () { finish(false); });
      }

      show.once('lock', play);
      show.after(9, play);
      show.on('gameOver', function () {
        show.caption('CRUSHED.', 'alarm');
        finish(true);
      });
    }
  };
})();
