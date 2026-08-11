import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/services/audio_service.dart';
import 'package:tetrofall/services/storage_service.dart';

/// The Settings "Sound Effects" slider stopped reaching the game: the old
/// `AudioPool` minted a native player per overlapping play and never disposed
/// the surplus, so working the slider — one preview per drag release, each
/// holding its player for the clip's full second — burned through Android's
/// process-wide ceiling and silenced every effect for the rest of the run.
/// These pin the ring that replaced it, and the level actually reaching it.
class _FakeVoice implements SfxVoice {
  final List<double> amplitudes = [];

  @override
  Future<void> trigger(double amplitude) async => amplitudes.add(amplitude);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Stands the ring up with [count] fakes for [sfx] and nothing else, so a
  /// play that goes anywhere unexpected shows up as a missing trigger.
  List<_FakeVoice> installVoices(Sfx sfx, {required int count}) {
    final voices = List.generate(count, (_) => _FakeVoice());
    AudioService.installVoicesForTest({sfx: voices});
    addTearDown(() => AudioService.installVoicesForTest({}));
    return voices;
  }

  Future<StorageService> storageWithSfxVolume(double volume) async {
    SharedPreferences.setMockInitialValues({'sfx_volume': volume});
    return StorageService.load();
  }

  test('the slider level reaches the player, curved', () async {
    final voices = installVoices(Sfx.blockSettle, count: 3);
    final audio = AudioService(await storageWithSfxVolume(0.5));

    audio.play(Sfx.blockSettle);

    // Halfway on a loudness knob is a quarter of the amplitude — a linear
    // pass-through is what made the slider feel like it did nothing.
    expect(voices.first.amplitudes, [0.25]);
  });

  test('zero plays nothing at all', () async {
    final voices = installVoices(Sfx.blockSettle, count: 3);
    final audio = AudioService(await storageWithSfxVolume(0));

    audio.play(Sfx.blockSettle);

    expect(voices.expand((v) => v.amplitudes), isEmpty);
  });

  test('the level is read per call, not captured at construction', () async {
    final voices = installVoices(Sfx.blockSettle, count: 3);
    SharedPreferences.setMockInitialValues({'sfx_volume': 0.0});
    final prefs = await SharedPreferences.getInstance();
    final audio = AudioService(StorageService(prefs));

    audio.play(Sfx.blockSettle);
    expect(voices.expand((v) => v.amplitudes), isEmpty);

    // Raising it from the pause menu has to land on the next lock.
    await prefs.setDouble('sfx_volume', 1);
    audio.play(Sfx.blockSettle);
    expect(voices.expand((v) => v.amplitudes), [1.0]);
  });

  test('the settings preview overrides the stored level', () async {
    final voices = installVoices(Sfx.blockSettle, count: 3);
    final audio = AudioService(await storageWithSfxVolume(0));

    // Muted in storage, but the slider is being dragged to 1 right now.
    audio.play(Sfx.blockSettle, volumeOverride: 1);

    expect(voices.first.amplitudes, [1.0]);
  });

  test('a burst of plays stays inside the ring', () async {
    final voices = installVoices(Sfx.blockSettle, count: 3);
    final audio = AudioService(await storageWithSfxVolume(1));

    // Far more plays than voices — the regression guard: this is the shape of
    // input (a worked slider, a cascade of clears) that used to allocate a
    // native player per play until the platform ran out.
    for (var i = 0; i < 30; i++) {
      audio.play(Sfx.blockSettle);
    }

    expect(
      voices.map((v) => v.amplitudes.length),
      [10, 10, 10],
      reason: 'round-robin over the fixed voices, and nothing beyond them',
    );
  });

  test('an effect with no voices is silent rather than fatal', () async {
    AudioService.installVoicesForTest({});
    final audio = AudioService(await storageWithSfxVolume(1));

    expect(() => audio.play(Sfx.woodCrush), returnsNormally);
  });

  test('the volume curve keeps the ends honest', () {
    expect(volumeToAmplitude(0), 0);
    expect(volumeToAmplitude(1), 1);
    expect(volumeToAmplitude(0.2), lessThan(0.2));
  });
}
