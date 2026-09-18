/* Gesture recogniser — a port of lib/game/input/gesture_handler.dart with the
 * thresholds from input_tuning.dart, scaled by the on-screen cell size:
 * drag sideways shifts a column per 0.85 cell, a quick tap rotates, a slow
 * drag down soft drops, and a fast vertical flick hard drops.
 *
 * Positions are CSS px (like the game's logical px); time is seconds.
 * sink.intent(type) receives 'left' | 'right' | 'rotate' | 'softStart' |
 * 'softEnd' | 'hard'.
 */
(function () {
  'use strict';

  var T = TF.C.INPUT;

  function Gestures(sink, cellSizeCss) {
    this.sink = sink;
    this.cellSize = cellSizeCss;
    this.pointer = null;
  }

  var G = Gestures.prototype;

  G.down = function (id, x, y, t) {
    if (this.pointer != null) return;
    this.pointer = id;
    this.downX = x; this.downY = y;
    this.lastX = x; this.lastY = y;
    this.downT = t; this.lastT = t;
    this.movedBeyondSlop = false;
    this.softDropEngaged = false;
    this.consumed = false;
    this.hardDropArmed = false;
    this.anyMove = false;
    this.accumDx = 0;
    this.smoothDx = 0;
    this.smoothDy = 0;
    this.smoothSpeedY = 0;
    this.hasSpeedSample = false;
    this.sidewaysActive = false;
  };

  G.move = function (id, x, y, t) {
    if (id !== this.pointer || this.consumed) return;
    var cell = this.cellSize();
    var dx = x - this.lastX, dy = y - this.lastY;
    var elapsed = t - this.lastT;
    this.lastX = x; this.lastY = y; this.lastT = t;

    var tdx = x - this.downX, tdy = y - this.downY;
    if (Math.sqrt(tdx * tdx + tdy * tdy) > T.tapSlop) this.movedBeyondSlop = true;

    var swipeColumn = cell * T.swipeColumnFraction;
    var softDropDistance = cell * T.softDropFraction;
    var hardDropDistance = cell * T.hardDropFraction;
    var flickSpeed = cell * T.flickCellsPerSecond;

    if (elapsed > 0) {
      var speedY = dy / elapsed;
      this.smoothSpeedY = this.hasSpeedSample
        ? this.smoothSpeedY * T.velocitySmoothing + speedY * (1 - T.velocitySmoothing)
        : speedY;
      this.hasSpeedSample = true;
    }

    this.smoothDx = this.smoothDx * T.axisSmoothing + dx * (1 - T.axisSmoothing);
    this.smoothDy = this.smoothDy * T.axisSmoothing + dy * (1 - T.axisSmoothing);
    var axisRatio = Math.abs(this.smoothDy) < 1e-6 ? Infinity : Math.abs(this.smoothDx) / Math.abs(this.smoothDy);
    if (this.sidewaysActive) {
      if (axisRatio < T.horizontalExitRatio) this.sidewaysActive = false;
    } else if (axisRatio > T.horizontalEnterRatio) {
      this.sidewaysActive = true;
    }

    var isVertical = tdy > T.hardDropVerticalityRatio * Math.abs(tdx);

    if (!this.softDropEngaged && tdy >= softDropDistance && tdy > Math.abs(tdx)) {
      this.softDropEngaged = true;
      this.hardDropArmed = isVertical && this.smoothSpeedY >= flickSpeed;
      this.sink.intent('softStart');
    } else if (this.hardDropArmed && this.smoothSpeedY < flickSpeed) {
      this.hardDropArmed = false;
    }

    var holdSideways = this.hardDropArmed || this.smoothSpeedY >= flickSpeed * T.flickSuppressionFraction;

    if (this.sidewaysActive) {
      if (this.accumDx !== 0 && dx !== 0 && (this.accumDx > 0) !== (dx > 0)) this.accumDx = dx;
      else this.accumDx += dx;
      while (!holdSideways && Math.abs(this.accumDx) >= swipeColumn) {
        var dir = this.accumDx > 0 ? 1 : -1;
        this.anyMove = true;
        this.sink.intent(dir > 0 ? 'right' : 'left');
        this.accumDx -= dir * swipeColumn;
      }
    }

    if (this.hardDropArmed && tdy >= hardDropDistance && isVertical) {
      this.consumed = true;
      if (this.softDropEngaged) this.sink.intent('softEnd');
      this.sink.intent('hard');
    }
  };

  G.up = function (id, t) {
    if (id !== this.pointer) return;
    if (!this.consumed) {
      if (this.softDropEngaged) {
        this.sink.intent('softEnd');
      } else if (!this.anyMove && !this.movedBeyondSlop && t - this.downT <= T.tapMaxDuration) {
        this.sink.intent('rotate');
      }
    }
    this.pointer = null;
  };

  G.cancel = function (id) {
    if (id !== this.pointer) return;
    if (this.softDropEngaged && !this.consumed) this.sink.intent('softEnd');
    this.pointer = null;
  };

  TF.Gestures = Gestures;
})();
