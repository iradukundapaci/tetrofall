import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// The gameplay sound effects shipped in `assets/audio/sfx/`.
///
/// [voices] is how many copies of the clip may overlap, and — since the voices
/// are allocated up front and reused forever — also the hard ceiling on the
/// players this effect will ever own. Spawns are one at a time, settles can
/// double up when a cascade lands, and a multi-row clear fires several crushes
/// within a few frames.
enum Sfx {
  blockSpawn('sfx/block_spawn.wav', voices: 2),
  blockSettle('sfx/block_settle.wav', voices: 3),
  woodCrush('sfx/wood_crush.wav', voices: 4);

  const Sfx(this.asset, {required this.voices});

  final String asset;
  final int voices;
}

/// Maps the 0–1 Settings slider onto a playback amplitude.
///
/// `audioplayers` takes a linear amplitude multiplier, but loudness is roughly
/// logarithmic in it: halving the amplitude is only −6 dB, so a linear slider
/// spends most of its travel sounding the same and reads as broken. Squaring
/// spreads the audible change across the whole track.
double volumeToAmplitude(double slider) => slider * slider;

/// Audio must never take gameplay down, so every call into the player is
/// wrapped — but it must not vanish either. A dead SFX layer went unnoticed
/// precisely because the failures were swallowed by bare `catch (_)` blocks,
/// so every swallow leaves a trace in debug builds.
void logAudioFailure(String what, Object error) {
  if (kDebugMode) {
    debugPrint('[audio] $what failed: $error');
  }
}

/// One playback voice: something that can be retriggered at a given amplitude.
///
/// Exists so tests can watch what the [AudioService] ring does without a
/// platform behind it.
@visibleForTesting
abstract class SfxVoice {
  Future<void> trigger(double amplitude);
}

/// Plays one-shot sound effects at the volume the player set in Settings.
///
/// Every effect owns a fixed ring of pre-loaded players, allocated once at
/// startup by [warmUp] and reused for the life of the process. The ring is the
/// point: the previous implementation used `AudioPool`, whose `maxPlayers` caps
/// how many players are *kept* rather than how many are *created* — a burst
/// mints extra native players and drops them without disposing. Working the
/// Settings slider is such a burst (a preview per drag release, each holding a
/// player for the clip's full second), and once Android's process-wide
/// `MediaPlayer` ceiling was reached every effect went silent for good. Here
/// nothing is allocated at play time, so there is nothing to leak.
///
/// The players are static and shared: they are per-asset, and the app can have
/// more than one game alive at once.
class AudioService {
  AudioService(this._storage);

  final StorageService _storage;

  static final Map<Sfx, _VoiceRing> _rings = {};
  static Future<void>? _warmUpFuture;

  /// Matches `FlameAudio`'s own default, so these players share the one
  /// SoundPool that `FlameAudio.bgm` set up rather than standing up a second.
  static final AudioContext _context = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  /// Loads every effect. Safe to call more than once — the work runs once.
  static Future<void> warmUp() => _warmUpFuture ??= _createVoices();

  static Future<void> _createVoices() async {
    for (final sfx in Sfx.values) {
      final voices = <SfxVoice>[];
      for (var i = 0; i < sfx.voices; i++) {
        try {
          voices.add(_PlayerVoice(await _createPlayer(sfx)));
        } catch (error) {
          // A device that refuses to open an audio player, or a missing asset,
          // must not take gameplay down with it — that effect just stays
          // silent. One failure means the rest will fail the same way.
          logAudioFailure('loading ${sfx.asset}', error);
          break;
        }
      }
      if (voices.isNotEmpty) {
        _rings[sfx] = _VoiceRing(voices);
      }
    }
  }

  static Future<AudioPlayer> _createPlayer(Sfx sfx) async {
    final player = AudioPlayer()..audioCache = FlameAudio.audioCache;
    // Low latency is `SoundPool` on Android: the sample is decoded once and
    // shared by every player pointing at the same asset, and triggering one
    // costs a stream rather than a `MediaPlayer`. That is what a 1-second
    // one-shot wants, and it is why the ring can stay resident.
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setAudioContext(_context);
    await player.setSource(AssetSource(sfx.asset));
    await player.setReleaseMode(ReleaseMode.stop);
    return player;
  }

  /// Fires [sfx] if it is loaded and the SFX slider is above zero. Never
  /// throws and never blocks the frame.
  ///
  /// [volumeOverride] is for the Settings screen previewing the level the
  /// player just dragged to. Everything else reads the slider here, per call,
  /// so a change from the pause menu lands on the very next lock.
  void play(Sfx sfx, {double? volumeOverride}) {
    final volume = volumeOverride ?? _storage.sfxVolume;
    if (volume <= 0) return;
    _rings[sfx]?.trigger(volumeToAmplitude(volume));
  }

  /// Swaps the warmed-up players for fakes, so a test can assert what reaches
  /// them. Passing `{}` leaves every effect silent.
  @visibleForTesting
  static void installVoicesForTest(Map<Sfx, List<SfxVoice>> voices) {
    _warmUpFuture = Future.value();
    _rings
      ..clear()
      ..addAll({
        for (final entry in voices.entries) entry.key: _VoiceRing(entry.value),
      });
  }
}

/// The fixed set of voices for one effect, handed out round-robin.
class _VoiceRing {
  _VoiceRing(this._voices);

  final List<SfxVoice> _voices;
  int _next = 0;

  void trigger(double amplitude) {
    if (_voices.isEmpty) return;
    final voice = _voices[_next];
    _next = (_next + 1) % _voices.length;
    unawaited(voice.trigger(amplitude));
  }
}

class _PlayerVoice implements SfxVoice {
  _PlayerVoice(this._player);

  final AudioPlayer _player;

  /// Two triggers landing on the same voice in the same frame must not
  /// interleave their stop/volume/start calls, so they queue behind each
  /// other. A failed one is caught here, leaving the chain usable.
  Future<void> _queue = Future.value();

  @override
  Future<void> trigger(double amplitude) {
    return _queue = _queue
        .then((_) async {
          // Stopping first is load-bearing rather than tidy: while a stream is
          // still open, SoundPool's `start` resumes *that* stream instead of
          // triggering the clip again, so a retrigger would be inaudible.
          await _player.stop();
          await _player.setVolume(amplitude);
          await _player.resume();
        })
        .catchError((Object error) {
          logAudioFailure('playing at $amplitude', error);
        });
  }
}
