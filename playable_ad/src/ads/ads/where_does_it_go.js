/* Ad 4 — "WHERE DOES THE I GO? 3-2-1"
 * Three quick placement puzzles. Each shows two lettered slots, counts down,
 * then lets gravity run while the viewer steers. The right slot shatters;
 * the wrong one leaves its hole, exactly as the real game would. An idle
 * viewer's piece is steered into the decoy — the blunder is the bait.
 */
(function () {
  'use strict';

  var ROUNDS = [
    {
      piece: 'I', question: 'WHERE DOES THE I GO?', need: 4,
      rows: ['###...#####..#####', '####.#############', '####.#############', '####.#############', '####.#############'],
      right: { rot: 1, col: 2 }, decoy: { rot: 1, col: 9 },
      labels: [{ col: 4, text: 'A', right: true }, { col: 11.5, text: 'B' }]
    },
    {
      piece: 'T', question: 'WHERE DOES THE T GO?', need: 2,
      rows: ['####..........####', '########...#######', '#########.########'],
      right: { rot: 2, col: 8 }, decoy: { rot: 0, col: 4 },
      labels: [{ col: 5, text: 'A' }, { col: 9, text: 'B', right: true }]
    },
    {
      piece: 'S', question: 'AND THE S?', need: 2,
      rows: ['#####.....##..####', '#######..#########', '########.#########'],
      right: { rot: 1, col: 6 }, decoy: { rot: 0, col: 11 },
      labels: [{ col: 12.5, text: 'A' }, { col: 7.5, text: 'B', right: true }]
    }
  ];

  TF.ads.where_does_it_go = {
    title: 'Tetrofall - Where does it go?',
    rounds: ROUNDS,

    start: function (show) {
      var e = show.newEngine({ seed: 3, dropMs: 230, resolveScale: 0.85 });
      e.freezeRise = true;
      show.on('spawn', function () { if (e.freezeGravity) e.lowerTo(4); });
      var correct = 0;

      function round(i) {
        var R = ROUNDS[i];
        e.setRows(R.rows);
        e.queuePieces([R.piece]);
        e.freezeGravity = true;
        e.holdSpawn = false;
        if (e.phase === 'ready') e.start();

        show.setLabels(R.labels.map(function (l) { return { col: l.col, text: l.text }; }));
        show.caption(R.question, 'question');
        show.instruction(i === 0 ? 'TAP rotate · DRAG move · FLICK drop' : '');
        show.stat('ROUND ' + (i + 1) + '/' + ROUNDS.length);
        show.autopilot({ idle: 5.2, target: R.decoy });
        show.after(0.5, function () {
          show.countdown(3, function () { e.freezeGravity = false; });
        });

        show.once('resolveEnd', function (d) {
          e.holdSpawn = true;
          show.autopilot(null);
          var ok = d.lines >= R.need;
          var rightLabel = R.labels.filter(function (l) { return l.right; })[0];
          show.setLabels(R.labels.map(function (l) {
            return { col: l.col, text: l.text, state: l.right ? 'good' : (ok ? null : 'bad') };
          }));
          if (ok) {
            correct++;
            show.caption('PERFECT!', 'shout');
            show.sfx('win');
          } else {
            show.caption(d.lines > 0 ? 'SO CLOSE…' : 'NOPE.', 'alarm');
            show.after(0.8, function () { show.caption('IT WAS ' + rightLabel.text + '!', 'hook'); });
          }
          show.after(ok ? 1.6 : 2.2, function () {
            if (i + 1 < ROUNDS.length) {
              round(i + 1);
            } else {
              show.end({
                title: correct + '/' + ROUNDS.length + (correct === ROUNDS.length ? ' PERFECT!' : ''),
                style: correct >= 2 ? 'shout' : 'alarm',
                line: 'Rate yourself. Then prove it.',
                stat: 'SCORE ' + e.score.toLocaleString()
              });
            }
          });
        });
      }

      round(0);
    }
  };
})();
