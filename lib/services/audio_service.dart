import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

import 'storage_service.dart';

/// The gameplay sound effects shipped in `assets/audio/sfx/`.
///
/// [maxPlayers] is how many copies of the clip may overlap. Spawns are one at
/// a time, settles can double up when a cascade lands, and a multi-row clear
/// fires several crushes within a few frames.
enum Sfx {
  blockSpawn('sfx/block_spawn.wav', maxPlayers: 2),
  blockSettle('sfx/block_settle.wav', maxPlayers: 3),
  woodCrush('sfx/wood_crush.wav', maxPlayers: 4);

  const Sfx(this.asset, {required this.maxPlayers});

  final String asset;
  final int maxPlayers;
}

/// Plays one-shot sound effects at the volume the player set in Settings.
///
/// The pools are static and shared: they are per-asset, and the app can have
/// more than one game alive at once. Pool creation decodes the clip and warms
/// a player per voice, which is the expensive part, so it happens once at
/// startup via [warmUp] rather than on the first clear.
class AudioService {
  AudioService(this._storage);

  final StorageService _storage;

  static final Map<Sfx, AudioPool> _pools = {};
  static Future<void>? _warmUpFuture;

  /// Loads every effect. Safe to call more than once — the work runs once.
  static Future<void> warmUp() => _warmUpFuture ??= _createPools();

  static Future<void> _createPools() async {
    for (final sfx in Sfx.values) {
      try {
        _pools[sfx] = await FlameAudio.createPool(
          sfx.asset,
          maxPlayers: sfx.maxPlayers,
        );
      } catch (_) {
        // A device that refuses to open an audio player, or a missing asset,
        // must not take gameplay down with it — that effect just stays silent.
      }
    }
  }

  /// Fires [sfx] if it is loaded and the SFX slider is above zero. Never
  /// throws and never blocks the frame.
  ///
  /// [volumeOverride] is for the Settings screen previewing the level the
  /// player just dragged to.
  void play(Sfx sfx, {double? volumeOverride}) {
    final volume = volumeOverride ?? _storage.sfxVolume;
    if (volume <= 0) return;
    final pool = _pools[sfx];
    if (pool == null) return;
    unawaited(_start(pool, volume));
  }

  static Future<void> _start(AudioPool pool, double volume) async {
    try {
      await pool.start(volume: volume);
    } catch (_) {
      // Playback failures are cosmetic.
    }
  }
}
