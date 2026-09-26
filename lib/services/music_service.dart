import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'audio_service.dart' show logAudioFailure, volumeToAmplitude;
import 'storage_service.dart';

/// The looping background tracks, relative to `FlameAudio.audioCache.prefix`.
enum MusicTrack {
  menu('music/menu_loop.mp3'),
  gameplay('music/game_loop.mp3');

  const MusicTrack(this.asset);

  final String asset;
}

/// Owns the single looping background player behind the Music slider. State
/// is static because there is one [FlameAudio.bgm]; the slider applies without
/// restarting the track, zero stops it, and the requested track is remembered
/// so raising it starts it again.
class MusicService {
  MusicService(this._storage);

  final StorageService _storage;

  /// Tracks actually in the bundle; while empty, every request is a no-op.
  static final Set<MusicTrack> _available = {};

  /// Whether any loop shipped; Settings hides its Music control when false.
  /// Only meaningful once [warmUp] has completed.
  static bool get hasBundledTracks => _available.isNotEmpty;

  static Future<void>? _warmUpFuture;

  static MusicTrack? _wanted;
  static MusicTrack? _resolved;
  static MusicTrack? _playing;

  static double _volume = 0;

  /// Serialises player calls; `audioplayers` dislikes `play`/`setVolume`
  /// racing, and dragging the slider fires many.
  static Future<void> _queue = Future.value();

  /// Initialises the player (which pauses music when backgrounded) and works
  /// out which loops exist. Safe to call twice.
  static Future<void> warmUp() => _warmUpFuture ??= _prepare();

  static Future<void> _prepare() async {
    try {
      await FlameAudio.bgm.initialize();
    } catch (error) {
      // A device that won't hand out a player must not break boot.
      logAudioFailure('initializing the music player', error);
    }
    try {
      final bundled = (await AssetManifest.loadFromAssetBundle(
        rootBundle,
      )).listAssets().toSet();
      for (final track in MusicTrack.values) {
        if (bundled.contains('${FlameAudio.audioCache.prefix}${track.asset}')) {
          _available.add(track);
        }
      }
    } catch (error) {
      // No manifest, no music.
      logAudioFailure('probing the bundle for music', error);
    }
    // A screen may have asked for a track before the probe finished.
    _sync();
  }

  /// Makes [track] current at the Settings volume; a no-op if already playing.
  void play(MusicTrack track) {
    _wanted = track;
    _volume = _storage.musicVolume;
    _sync();
  }

  void stop() {
    _wanted = null;
    _sync();
  }

  void setVolume(double volume) {
    _volume = volume;
    _sync();
  }

  static void _sync() {
    _queue = _queue.then((_) async {
      try {
        await _apply();
      } catch (error) {
        // Music is cosmetic.
        logAudioFailure('applying the music state', error);
      }
    });
  }

  static Future<void> _apply() async {
    final wanted = _wanted;
    final volume = _volume;

    // An unbundled track holds the previous one rather than dropping to
    // silence.
    if (wanted == null) {
      _resolved = null;
    } else if (_available.contains(wanted)) {
      _resolved = wanted;
    }
    final target = _resolved;

    if (target == null || volume <= 0) {
      if (_playing != null) {
        _playing = null;
        await FlameAudio.bgm.stop();
      }
      return;
    }

    // The slider is loudness, not amplitude; see [volumeToAmplitude].
    final amplitude = volumeToAmplitude(volume);

    if (_playing == target) {
      await FlameAudio.bgm.audioPlayer.setVolume(amplitude);
      return;
    }

    _playing = target;
    await FlameAudio.bgm.play(target.asset, volume: amplitude);
  }
}
