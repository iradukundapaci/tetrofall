/* Two logical canvases, picked by the host frame's aspect: 320x480 portrait
 * and 480x320 landscape (Google App campaign HTML5 sizes). Each is scaled to
 * fit the frame with a devicePixelRatio backing store; the letterbox is the
 * page background. The engine board is the same 18x20 in both, so turning
 * the device mid-run only moves pixels, never game state.
 */
(function () {
  'use strict';

  var C = TF.C;

  function portrait() {
    var cell = 16;
    var board = { x: 16, y: 54, cell: cell, w: C.COLS * cell, h: C.ROWS * cell };
    return {
      name: 'portrait', W: 320, H: 480, board: board,
      brand: { x: 16, y: 13, markCell: 8, wordSize: 17 },
      score: { x: 304, y: 34, align: 'right', size: 20 },
      stat: { x: 304, y: 48, align: 'right' },
      caption: { cx: 160, y: board.y + 26, w: 288, size: 28 },
      callout: { size: 22 },
      instruction: { cx: 160, y: 398, w: 300 },
      cta: { x: 50, y: 414, w: 220, h: 50, label: 'PLAY FREE' },
      end: {
        markCell: 26, markY: 78, wordY: 170, wordSize: 34,
        titleY: 224, titleSize: 30, lineY: 256, statY: 288,
        cta: { x: 50, y: 320, w: 220, h: 58 },
        replay: { x: 110, y: 400, w: 100, h: 36 }
      }
    };
  }

  function landscape() {
    var cell = 14;
    var board = { x: 16, y: 20, cell: cell, w: C.COLS * cell, h: C.ROWS * cell };
    var cx = 374;
    return {
      name: 'landscape', W: 480, H: 320, board: board,
      brand: { cx: cx, y: 16, markCell: 10, wordSize: 22 },
      score: { x: cx, y: 100, align: 'center', size: 22 },
      stat: { x: cx, y: 118, align: 'center' },
      caption: { cx: cx, y: 150, w: 188, size: 22 },
      callout: { size: 18 },
      instruction: { cx: cx, y: 238, w: 190 },
      cta: { x: cx - 88, y: 254, w: 176, h: 46, label: 'PLAY FREE' },
      end: {
        side: true,
        markCell: 18, markY: 34, wordY: 104, wordSize: 30,
        titleY: 146, titleSize: 24, lineY: 172, statY: 196,
        cta: { x: 150, y: 216, w: 180, h: 50 },
        replay: { x: 190, y: 274, w: 100, h: 32 }
      }
    };
  }

  TF.Layout = {
    pick: function (w, h) { return w > h * 1.05 ? landscape() : portrait(); }
  };
})();
