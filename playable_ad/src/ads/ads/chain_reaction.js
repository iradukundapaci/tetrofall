/* Ad 2 — "CLEAR ONE ROW… AND THE STACK COMES DOWN"
 * Ripple gravity is the hook: one I clears the bottom row, the stack above
 * drops into the caves beneath it and completes row after row. First a x3,
 * then a x4 on a second board, then 20 seconds of real play.
 */
(function () {
  'use strict';

  function full(except) {
    var s = '';
    for (var c = 0; c < TF.C.COLS; c++) s += except.indexOf(c) >= 0 ? '.' : '#';
    return s;
  }

  // Well at col 13; each row's hole is covered by the row above, so every
  // ripple step lands one block into the row beneath and completes it.
  var RIG_X3 = [full([13, 6]), full([13, 15]), full([13, 3]), full([13])];
  var GUIDE_X3 = { type: 'I', rot: 1, col: 11 };
  // Same construction, one row taller, well at col 4.
  var RIG_X4 = [full([4, 8, 9]), full([4, 16]), full([4, 1]), full([4, 12]), full([4])];
  var GUIDE_X4 = { type: 'I', rot: 1, col: 2 };

  TF.ads.chain_reaction = {
    title: 'Tetrofall - Chain reaction',
    rigs: [{ rows: RIG_X3, guide: GUIDE_X3, chains: 3 }, { rows: RIG_X4, guide: GUIDE_X4, chains: 4 }],

    start: function (show) {
      var e = show.newEngine({ seed: 21, dropMs: 650, riseGrace: 5, riseInterval: 8, fillRatio: 0.7, gapMode: 'adjacent' });
      e.setRows(RIG_X3);
      e.queuePieces(['I']);
      e.freezeGravity = true;
      e.freezeRise = true;
      show.on('spawn', function () { if (e.freezeGravity) e.lowerTo(4); });
      e.start();

      var ended = false;
      function finish(crushed) {
        if (ended) return;
        ended = true;
        show.after(crushed ? 1.1 : 0.2, function () {
          show.end({
            title: crushed ? 'CRUSHED.' : 'SATISFYING?',
            style: crushed ? 'alarm' : 'shout',
            line: crushed ? "Think you'd do better? Prove it." : "It's the whole game.",
            stat: 'BEST CHAIN x' + e.maxChain + '  ·  SCORE ' + e.score.toLocaleString()
          });
        });
      }

      show.caption('CLEAR ONE ROW…', 'hook');
      show.guided(GUIDE_X3);
      show.once('clear', function () { show.caption('…AND THE STACK COMES DOWN', 'shout'); });

      show.once('resolveEnd', function (d) {
        e.holdSpawn = true;
        show.caption('CHAIN x' + d.chains + '!', 'shout');

        show.after(1.6, function () {
          show.caption('NOW GO BIGGER', 'hook');
          e.setRows(RIG_X4);
          e.queuePieces(['I']);
          e.holdSpawn = false;
          show.guided({ type: GUIDE_X4.type, rot: GUIDE_X4.rot, col: GUIDE_X4.col, idle: 6 });

          show.once('resolveEnd', function (d2) {
            show.caption('CHAIN x' + d2.chains + '!!', 'shout', 1.8);
            show.after(1.4, function () {
              show.caption('YOUR TURN!', 'shout', 1.6);
              show.instruction('Clear rows before the floor rises');
              e.freezeGravity = false;
              e.freezeRise = false;
              e.riseStartElapsed = e.elapsed;
              show.autopilot({ idle: 5, target: 'bot' });
              show.timer(20, 'TIME', function () { finish(false); });
              show.on('gameOver', function () {
                show.caption('CRUSHED.', 'alarm');
                finish(true);
              });
            });
          });
        });
      });
    }
  };
})();
