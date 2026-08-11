import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'audio_service.dart' show logAudioFailure, volumeToAmplitude;
import 'storage_service.dart';

/// The looping background tracks (game.md §P.7), relative to
/// `FlameAudio.audioCache.prefix`.
enum MusicTrack {
  menu('music/menu_loop.mp3'),
  gameplay('music/game_loop.mp3');

  const MusicTrack(this.asset);

  final String asset;
}

/// Owns the single looping background player behind the Settings "Music"
/// slider.
///
/// Mutable state is static like [AudioService]'s pools — there is only one
/// [FlameAudio.bgm] no matter how many screens ask it for a track, so a
/// screen can construct a handle on the spot. The slider is applied without
/// restarting the track; zero stops it, and the requested track is
/// remembered so raising it again starts back up.
class MusicService {
  MusicService(this._storage);

  final StorageService _storage;

  /// Tracks actually in the bundle. The loops are still an outstanding art
  /// asset, so until the mp3s land this stays empty and every request is a
  /// no-op rather than an exception per screen transition.
  static final Set<MusicTrack> _available = {};

  static Future<void>? _warmUpFuture;

  static MusicTrack? _wanted;
  static MusicTrack? _resolved;
  static MusicTrack? _playing;

  static double _volume = 0;

  /// `audioplayers` does not like `play` and `setVolume` racing, and
  /// dragging the slider fires a lot of them in a hurry.
  static Future<void> _queue = Future.value();

  /// Registers the lifecycle observer so music pauses when the app is
  /// backgrounded, and works out which loops exist. Safe to call twice.
  static Future<void> warmUp() => _warmUpFuture ??= _prepare();

  static Future<void> _prepare() async {
    try {
      await FlameAudio.bgm.initialize();
    } catch (error) {
      // A device that won't hand out a player must not take the boot down.
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
    // A screen that asked for a track before the probe finished is waiting.
    _sync();
  }

  /// Makes [track] the current music at the volume set in Settings. Already
  /// playing it is a no-op, so returning to the menu doesn't restart it.
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
        // Music is cosmetic; a failed player call must not break the run.
        logAudioFailure('applying the music state', error);
      }
    });
  }

  static Future<void> _apply() async {
    final wanted = _wanted;
    final volume = _volume;

    // Asking for a track that isn't bundled holds the previous one instead
    // of dropping to silence, so shipping only one loop still carries the
    // music across the menu/gameplay boundary.
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

    // The slider is a 0–1 loudness knob, not an amplitude — see
    // [volumeToAmplitude].
    final amplitude = volumeToAmplitude(volume);

    if (_playing == target) {
      await FlameAudio.bgm.audioPlayer.setVolume(amplitude);
      return;
    }

    _playing = target;
    await FlameAudio.bgm.play(target.asset, volume: amplitude);
  }
}
