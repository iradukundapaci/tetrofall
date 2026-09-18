/* Audio — the real game's lock/clear sounds (assets/audio/sfx/block_settle.wav,
 * wood_crush.wav, re-encoded by tools/prepare_assets.py and base64-inlined),
 * plus a few stingers synthesised in WebAudio after tools/store/ad_sfx.py.
 * Google only accepts CSS/GIF/HTML/JPEG/JS/PNG/SVG inside the zip, so nothing
 * here is a separate audio file.
 *
 * The AudioContext starts suspended and is resumed only from a pointer
 * gesture: Google rejects creatives that make sound before interaction.
 */
(function () {
  'use strict';

  var AudioCtx = window.AudioContext || window.webkitAudioContext;
  var actx = null, master = null, noise = null;
  var buffers = {};

  function ensure() {
    if (actx || !AudioCtx) return actx;
    try {
      actx = new AudioCtx();
    } catch (err) {
      return null;
    }
    master = actx.createGain();
    master.gain.value = 0.7;
    master.connect(actx.destination);
    decode('lock', TF.ASSETS.sfxLock);
    decode('clear', TF.ASSETS.sfxClear);
    var len = Math.floor(actx.sampleRate * 0.5);
    noise = actx.createBuffer(1, len, actx.sampleRate);
    var ch = noise.getChannelData(0);
    for (var i = 0; i < len; i++) ch[i] = Math.random() * 2 - 1;
    return actx;
  }

  function decode(name, dataUri) {
    if (!dataUri) return;
    var raw = atob(dataUri.split(',')[1]);
    var bytes = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    try {
      actx.decodeAudioData(bytes.buffer, function (buf) { buffers[name] = buf; }, function () {});
    } catch (err) { /* old webviews: no sample, synth stingers still work */ }
  }

  function ready() { return actx && actx.state === 'running'; }

  function tone(freq, start, dur, type, gain, endFreq) {
    var o = actx.createOscillator(), g = actx.createGain();
    o.type = type || 'sine';
    o.frequency.setValueAtTime(freq, start);
    if (endFreq) o.frequency.exponentialRampToValueAtTime(endFreq, start + dur);
    g.gain.setValueAtTime(0.0001, start);
    g.gain.exponentialRampToValueAtTime(gain || 0.3, start + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, start + dur);
    o.connect(g);
    g.connect(master);
    o.start(start);
    o.stop(start + dur + 0.02);
  }

  function noiseBurst(start, dur, fromHz, toHz, gain) {
    var src = actx.createBufferSource(), f = actx.createBiquadFilter(), g = actx.createGain();
    src.buffer = noise;
    f.type = 'bandpass';
    f.Q.value = 1.2;
    f.frequency.setValueAtTime(fromHz, start);
    f.frequency.exponentialRampToValueAtTime(toHz, start + dur);
    g.gain.setValueAtTime(0.0001, start);
    g.gain.exponentialRampToValueAtTime(gain, start + dur * 0.3);
    g.gain.exponentialRampToValueAtTime(0.0001, start + dur);
    src.connect(f);
    f.connect(g);
    g.connect(master);
    src.start(start);
    src.stop(start + dur + 0.02);
  }

  var CHIME = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568];

  TF.audio = {
    unlock: function () {
      if (!ensure()) return;
      if (actx.state === 'suspended') actx.resume();
    },
    play: function (name, opts) {
      if (!ready()) return;
      opts = opts || {};
      var now = actx.currentTime;
      if (buffers[name]) {
        var src = actx.createBufferSource(), g = actx.createGain();
        src.buffer = buffers[name];
        src.playbackRate.value = opts.rate || 1;
        g.gain.value = opts.gain || 1;
        src.connect(g);
        g.connect(master);
        src.start(0);
        return;
      }
      switch (name) {
        case 'whoosh': noiseBurst(now, 0.18, 2400, 500, 0.35); break;
        case 'tick': tone(1400, now, 0.03, 'square', 0.05); break;
        case 'beep': tone(880, now, 0.12, 'sine', 0.3); break;
        case 'go': tone(1320, now, 0.25, 'sine', 0.35); break;
        case 'chime': {
          var n = Math.min(opts.step || 0, CHIME.length - 1);
          tone(CHIME[n], now, 0.35, 'triangle', 0.25);
          tone(CHIME[n] * 2, now + 0.04, 0.3, 'sine', 0.08);
          break;
        }
        case 'win':
          for (var i = 0; i < 4; i++) tone(CHIME[i], now + i * 0.09, 0.4, 'triangle', 0.22);
          break;
        case 'buzzer':
          tone(150, now, 0.4, 'sawtooth', 0.12, 110);
          tone(155, now, 0.4, 'square', 0.05, 112);
          break;
        case 'rise': tone(90, now, 0.22, 'sine', 0.35, 55); break;
      }
    }
  };
})();
