/* Ad 3 — "THE FLOOR IS RISING"
 * A survival challenge on the real engine: a half-full board, the floor
 * pushing a new row up every few seconds, 25 seconds on the clock. Nothing is
 * scripted — a viewer who never touches it gets crushed.
 */
(function () {
  'use strict';

  var CFG = {
    seed: 5,
    startRows: 10,
    survive: 25,
    engine: { dropMs: 520, riseGrace: 2.5, riseInterval: 3.4, fillRatio: 0.75, gapMode: 'adjacent' }
  };

  function startingRows(e) {
    var rows = [];
    for (var i = 0; i < CFG.startRows; i++) {
      var row = e.generateRow(CFG.engine.fillRatio, 'adjacent');
      rows.push(row.map(function (v) { return v ? '#' : '.'; }).join(''));
    }
    return rows;
  }

  TF.ads.floor_rises = {
    title: 'Tetrofall - The floor is rising',
    config: CFG,
    startingRows: startingRows,

    start: function (show) {
      var opts = { seed: CFG.seed };
      for (var k in CFG.engine) opts[k] = CFG.engine[k];
      var e = show.newEngine(opts);
      e.setRows(startingRows(e));
      e.pendingRow = e.generateRow();
      e.start();

      var ended = false;
      function finish(crushed, survived) {
        if (ended) return;
        ended = true;
        show.after(crushed ? 1.2 : 0.4, function () {
          show.end(crushed
            ? { title: 'CRUSHED.', style: 'alarm', line: "Think you'd do better? Prove it.", stat: 'SURVIVED ' + survived.toFixed(1) + 's' }
            : { title: 'YOU SURVIVED!', style: 'shout', line: 'The real floor never stops.', stat: 'SCORE ' + e.score.toLocaleString() });
        });
      }

      show.caption('THE FLOOR IS RISING', 'alarm', 2.2);
      show.after(2.2, function () { show.caption('SURVIVE ' + CFG.survive + ' SECONDS', 'shout', 2.2); });
      show.instruction('DRAG to move · TAP to rotate · FLICK to drop');
      show.hint('drag', { col: 3 });
      show.once('move', function () { show.hint('flick'); });
      show.once('hardDrop', function () { show.hint(null); });

      show.timer(CFG.survive, 'SURVIVE', function () {
        e.freezeRise = true;
        e.freezeGravity = true;
        finish(false);
      });
      show.on('gameOver', function () {
        var left = show.timerState ? show.timerState.left : 0;
        show.timerState = null;
        show.caption('CRUSHED.', 'alarm');
        finish(true, CFG.survive - left);
      });
    }
  };
})();
