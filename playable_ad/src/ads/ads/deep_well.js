/* Ad 1 — "SEE THAT GAP?"
 * An eight-deep one-column well. The viewer rotates, steers and flicks an I
 * into it for a 4-row shatter, does it again as the stack ripples down, then
 * gets 20 seconds of real play under the rising floor.
 */
(function () {
  'use strict';

  var WELL = '##############.###';
  var RIG = ['###.....##.....#..', '#####..####..#..##'].concat([WELL, WELL, WELL, WELL, WELL, WELL, WELL, WELL]);
  var GUIDE = { type: 'I', rot: 1, col: 12 };

  TF.ads.deep_well = {
    title: 'Tetrofall - See that gap?',
    rig: RIG,
    guide: GUIDE,

    start: function (show) {
      var e = show.newEngine({ seed: 7, dropMs: 650, riseGrace: 5, riseInterval: 8, fillRatio: 0.7, gapMode: 'adjacent' });
      e.setRows(RIG);
      e.queuePieces(['I', 'I']);
      e.freezeGravity = true;
      e.freezeRise = true;
      show.on('spawn', function () { if (e.freezeGravity) e.lowerTo(4); });
      e.start();

      var ended = false;
      function finish(crushed) {
        if (ended) return;
        ended = true;
        show.after(crushed ? 1.1 : 0.2, function () {
          show.end(crushed
            ? { title: 'CRUSHED.', style: 'alarm', line: "Think you'd do better? Prove it.", stat: 'SCORE ' + e.score.toLocaleString() }
            : { title: 'COULD YOU DO BETTER?', style: 'shout', line: 'Prove it.', stat: 'SCORE ' + e.score.toLocaleString() });
        });
      }

      show.caption('SEE THAT GAP?', 'question');
      show.guided({ type: GUIDE.type, rot: GUIDE.rot, col: GUIDE.col });

      show.once('resolveEnd', function () {
        show.caption('WAIT FOR IT… 4 MORE!', 'shout');
        show.guided({ type: GUIDE.type, rot: GUIDE.rot, col: GUIDE.col, idle: 5 });

        show.once('resolveEnd', function () {
          show.caption('YOUR TURN!', 'shout', 1.8);
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
    }
  };
})();
