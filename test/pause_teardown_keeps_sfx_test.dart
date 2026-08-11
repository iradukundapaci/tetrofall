import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/game/tetrofall_game.dart';
import 'package:tetrofall/services/audio_service.dart';
import 'package:tetrofall/services/storage_service.dart';

/// Pausing a run used to deafen it permanently.
///
/// The paused frame wrapped the gameplay body in a blur, which changed the
/// widget *shape* below it and so reinflated the `GameWidget`; the discarded
/// one ran Flame's `onRemove` on the game that was still mid-run, and that
/// unhooked the engine listener every sound effect and buzz travels on. The
/// listener was only ever registered in the constructor, so nothing put it
/// back — the rest of the run played in silence, and only a brand new game
/// brought sound back. It surfaced as "the Sound Effects slider does nothing
/// unless I quit and start again", because reaching Settings means pausing.
///
/// This pins the game side of it: a widget teardown must not cost a live run
/// its audio.
class _FakeVoice implements SfxVoice {
  final List<double> amplitudes = [];

  @override
  Future<void> trigger(double amplitude) async => amplitudes.add(amplitude);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a GameWidget teardown leaves a live run still audible', () async {
    final voices = List.generate(2, (_) => _FakeVoice());
    AudioService.installVoicesForTest({Sfx.blockSpawn: voices});
    addTearDown(() => AudioService.installVoicesForTest({}));

    SharedPreferences.setMockInitialValues({'sfx_volume': 1.0});
    final game = TetrofallGame(storage: await StorageService.load());

    // Starting the engine spawns a piece, which is one of the events the
    // game turns into a sound.
    game.engine.start();
    expect(
      voices.expand((v) => v.amplitudes),
      hasLength(1),
      reason: 'the spawn should be audible before anything is torn down',
    );

    // What Flame does to the game when the pause overlay swaps the widget
    // tree out from under it. The game object itself lives on.
    game.onRemove();

    game.engine.start();
    expect(
      voices.expand((v) => v.amplitudes),
      hasLength(2),
      reason: 'the run kept playing, so it must have kept its sound',
    );
  });
}
