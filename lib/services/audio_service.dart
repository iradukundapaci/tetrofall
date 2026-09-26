import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// The gameplay sound effects in `assets/audio/sfx/`. [voices] is how many
/// copies may overlap, and the hard ceiling on players the effect ever owns.
enum Sfx {
  blockSpawn('sfx/block_spawn.wav', voices: 2),
  blockSettle('sfx/block_settle.wav', voices: 3),
  woodCrush('sfx/wood_crush.wav', voices: 4);

  const Sfx(this.asset, {required this.voices});

  final String asset;
  final int voices;
}

/// Maps the 0–1 Settings slider onto amplitude. Loudness is roughly
/// logarithmic in amplitude, so squaring spreads the audible change across the
/// slider's travel.
double volumeToAmplitude(double slider) => slider * slider;

/// Audio must never take gameplay down, so player calls are wrapped, but
/// every swallowed failure is logged in debug builds.
void logAudioFailure(String what, Object error) {
  if (kDebugMode) {
    debugPrint('[audio] $what failed: $error');
  }
}

/// One playback voice, retriggerable at a given amplitude; exists so tests can
/// watch the [AudioService] ring.
@visibleForTesting
abstract class SfxVoice {
  Future<void> trigger(double amplitude);
}

/// Plays one-shot effects at the Settings volume. Each effect owns a fixed
/// ring of pre-loaded players allocated once by [warmUp]; nothing is allocated
/// at play time, so bursts can't exhaust Android's `MediaPlayer` ceiling the
/// way `AudioPool` did. Players are static and shared across games.
class AudioService {
  AudioService(this._storage);

  final StorageService _storage;

  static final Map<Sfx, _VoiceRing> _rings = {};
  static Future<void>? _warmUpFuture;

  /// Matches `FlameAudio`'s default so players share its SoundPool.
  static final AudioContext _context = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  /// Loads every effect; the work runs once.
  static Future<void> warmUp() => _warmUpFuture ??= _createVoices();

  static Future<void> _createVoices() async {
    for (final sfx in Sfx.values) {
      final voices = <SfxVoice>[];
      for (var i = 0; i < sfx.voices; i++) {
        try {
          voices.add(_PlayerVoice(await _createPlayer(sfx)));
        } catch (error) {
          // That effect stays silent; one failure means the rest would fail
          // the same way.
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
    // Low latency is `SoundPool` on Android: decoded once, and a trigger costs
    // a stream rather than a `MediaPlayer`.
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setAudioContext(_context);
    await player.setSource(AssetSource(sfx.asset));
    await player.setReleaseMode(ReleaseMode.stop);
    return player;
  }

  /// Fires [sfx] if loaded and the slider is above zero; never throws or
  /// blocks. [volumeOverride] is for Settings previewing a dragged level.
  void play(Sfx sfx, {double? volumeOverride}) {
    final volume = volumeOverride ?? _storage.sfxVolume;
    if (volume <= 0) return;
    _rings[sfx]?.trigger(volumeToAmplitude(volume));
  }

  /// Swaps the players for fakes; `{}` silences every effect.
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

/// The voices for one effect, handed out round-robin.
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

  /// Triggers on one voice queue so their stop/volume/start calls don't
  /// interleave; a failure is caught here so the chain stays usable.
  Future<void> _queue = Future.value();

  @override
  Future<void> trigger(double amplitude) {
    return _queue = _queue
        .then((_) async {
          // Stop first: while a stream is open, SoundPool's `start` resumes it
          // instead of retriggering.
          await _player.stop();
          await _player.setVolume(amplitude);
          await _player.resume();
        })
        .catchError((Object error) {
          logAudioFailure('playing at $amplitude', error);
        });
  }
}
