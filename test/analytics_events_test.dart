import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/engine/events.dart';
import 'package:tetrofall/services/analytics_service.dart';
import 'package:tetrofall/services/run_tracker.dart';

/// One emitted design event, so assertions can read ids and values back.
class _Emitted {
  const _Emitted(this.id, this.value);
  final String id;
  final double? value;

  @override
  String toString() => value == null ? id : '$id=$value';
}

class _Recorder {
  final events = <_Emitted>[];
  int starts = 0;
  final failScores = <int>[];

  void design(String id, {double? value}) => events.add(_Emitted(id, value));
  void start() => starts++;
  void fail({required int score}) => failScores.add(score);

  RunTracker get tracker => RunTracker(
    design: design,
    progressionStart: start,
    progressionFail: fail,
  );

  List<String> get ids => [for (final e in events) e.id];
  double? valueOf(String id) =>
      events.firstWhere((e) => e.id == id, orElse: () => _Emitted(id, null)).value;
}

RowsClearedEvent _cleared(int rows) =>
    RowsClearedEvent(List.generate(rows, (i) => i), const []);

RowsClearedEvent _forcedClear(int row) =>
    RowsClearedEvent([row], const [], forced: true);

void main() {
  group('RunTracker', () {
    test('a run start opens a progression and reports its head start', () {
      final r = _Recorder();
      r.tracker.runStarted(initialElapsed: const Duration(seconds: 90));

      expect(r.starts, 1);
      expect(r.ids, ['run:start']);
      expect(r.valueOf('run:start'), 90);
    });

    test('line clears are bucketed by size and carry the chain length', () {
      final r = _Recorder();
      final tracker = r.tracker..runStarted();

      tracker.onEvent(_cleared(1));
      tracker.onEvent(const ChainAdvancedEvent(1));
      tracker.onEvent(_cleared(4));
      tracker.onEvent(const ChainAdvancedEvent(2));
      tracker.onEvent(_cleared(7));

      expect(r.ids, [
        'run:start',
        'clear:single',
        'clear:tetris',
        'clear:multi',
      ]);
      // The first clear opens the chain; each ChainAdvancedEvent arrives
      // after the clear it belongs to and sets the length for the next one.
      expect(r.valueOf('clear:single'), 1);
      expect(r.valueOf('clear:tetris'), 2);
      expect(r.valueOf('clear:multi'), 3);
    });

    test('the run summary counts what happened between the boundaries', () {
      final r = _Recorder();
      final tracker = r.tracker..runStarted();

      for (var i = 0; i < 5; i++) {
        tracker.onEvent(const PieceLockedEvent());
      }
      tracker.onEvent(const PlayerActionEvent(PlayerAction.hardDrop));
      tracker.onEvent(const PlayerActionEvent(PlayerAction.hardDrop));
      // Not a hard drop, and not counted as one.
      tracker.onEvent(const PlayerActionEvent(PlayerAction.rotate));
      tracker.onEvent(const RiseCommittedEvent());
      tracker.onEvent(_cleared(2));

      tracker.runEnded(
        reason: 'topout',
        elapsed: const Duration(minutes: 4),
        score: 4200,
        maxChain: 3,
        blocksDestroyed: 88,
      );

      expect(r.valueOf('run:end:topout'), 240);
      expect(r.valueOf('run:pieces'), 5);
      expect(r.valueOf('run:harddrops'), 2);
      expect(r.valueOf('run:lines'), 2);
      expect(r.valueOf('run:rises'), 1);
      expect(r.valueOf('run:blocks'), 88);
      expect(r.valueOf('chain:max'), 3);
      expect(r.failScores, [4200]);
      // 4 minutes sits in the 3-minute bracket, one below the 5-minute one.
      expect(r.valueOf('run:tier'), 3);
    });

    test('a camelCase game-over reason is normalised', () {
      final r = _Recorder();
      final tracker = r.tracker..runStarted();

      // What GameOverReason.blockOut.name hands over.
      tracker.runEnded(
        reason: 'blockOut',
        elapsed: const Duration(seconds: 45),
        score: 0,
        maxChain: 0,
        blocksDestroyed: 0,
      );

      expect(r.ids, contains('run:end:blockout'));
      expect(r.ids, isNot(contains('run:end:blockOut')));
    });

    test('ending a run twice reports it once', () {
      final r = _Recorder();
      final tracker = r.tracker..runStarted();

      void end(String reason) => tracker.runEnded(
        reason: reason,
        elapsed: Duration.zero,
        score: 10,
        maxChain: 1,
        blocksDestroyed: 0,
      );

      // What the game-over path and the Home button do in sequence.
      end('topout');
      end('quit');

      expect(r.ids.where((id) => id.startsWith('run:end')), ['run:end:topout']);
      expect(r.failScores, [10]);
    });

    test('events outside a run are ignored', () {
      final r = _Recorder();
      final tracker = r.tracker;

      // Flame starts the engine from `onLoad`, which lands after the screen's
      // initState — and the screen may never open a run at all, mid-tutorial.
      tracker.onEvent(const PieceLockedEvent());
      tracker.onEvent(_cleared(4));
      tracker.runEnded(
        reason: 'quit',
        elapsed: Duration.zero,
        score: 0,
        maxChain: 0,
        blocksDestroyed: 0,
      );

      expect(r.events, isEmpty);
      expect(r.starts, 0);
      expect(r.failScores, isEmpty);
    });

    test('a new best is reported once, at the end, with the final score', () {
      final r = _Recorder();
      final tracker = r.tracker..runStarted(bestBefore: 1000);

      tracker.onEvent(_cleared(1));
      tracker.onEvent(_cleared(1));
      tracker.runEnded(
        reason: 'blockout',
        elapsed: const Duration(seconds: 30),
        score: 2500,
        maxChain: 1,
        blocksDestroyed: 20,
      );

      expect(r.ids.where((id) => id == 'score:best'), hasLength(1));
      expect(r.valueOf('score:best'), 2500);
    });

    test('a run that falls short of the best reports no new best', () {
      final r = _Recorder();
      final tracker = r.tracker..runStarted(bestBefore: 5000);

      tracker.runEnded(
        reason: 'topout',
        elapsed: const Duration(seconds: 20),
        score: 400,
        maxChain: 1,
        blocksDestroyed: 4,
      );

      expect(r.ids, isNot(contains('score:best')));
    });

    test('the continue board wipe is not counted as line clears', () {
      final r = _Recorder();
      final tracker = r.tracker..runStarted();

      tracker.onEvent(_cleared(1));
      // What continueAfterAd's sweep emits: one per row, whole board.
      for (var row = 0; row < 32; row++) {
        tracker.onEvent(_forcedClear(row));
      }

      tracker.runEnded(
        reason: 'topout',
        elapsed: const Duration(seconds: 60),
        score: 100,
        maxChain: 1,
        blocksDestroyed: 10,
      );

      expect(r.ids.where((id) => id.startsWith('clear:')), ['clear:single']);
      expect(r.valueOf('run:lines'), 1);
    });

    test('a rewarded continue resumes without a second attempt', () {
      final r = _Recorder();
      final tracker = r.tracker..runStarted();

      tracker.runEnded(
        reason: 'topout',
        elapsed: const Duration(seconds: 60),
        score: 900,
        maxChain: 2,
        blocksDestroyed: 30,
      );
      tracker.runStarted(resumed: true);
      tracker.continueUsed();
      tracker.runEnded(
        reason: 'topout',
        elapsed: const Duration(seconds: 150),
        score: 2000,
        maxChain: 4,
        blocksDestroyed: 70,
      );

      expect(r.ids, contains('run:resume'));
      expect(r.valueOf('run:continues'), 1);
      // One Start for the run; the resume is not a fresh attempt, but each
      // life still ends in a Fail carrying the score it reached.
      expect(r.starts, 1);
      expect(r.failScores, [900, 2000]);
    });

    test('tier brackets follow the difficulty checkpoints', () {
      expect(RunTracker.tierFor(Duration.zero), 1);
      expect(RunTracker.tierFor(const Duration(seconds: 89)), 1);
      expect(RunTracker.tierFor(const Duration(seconds: 90)), 2);
      expect(RunTracker.tierFor(const Duration(minutes: 3)), 3);
      expect(RunTracker.tierFor(const Duration(minutes: 5)), 4);
      expect(RunTracker.tierFor(const Duration(minutes: 8)), 5);
      expect(RunTracker.tierFor(const Duration(minutes: 30)), 6);
    });
  });

  group('AnalyticsService', () {
    test('is inert without a platform behind it', () async {
      // The guard the whole rest of the suite depends on: no method channel is
      // registered under `flutter test`, so every one of these would throw
      // MissingPluginException if they were not gated on init.
      await AnalyticsService.init();
      expect(AnalyticsService.isReady, isFalse);

      AnalyticsService.design('screen:test', value: 1);
      AnalyticsService.progressionStart();
      AnalyticsService.progressionFail(score: 1);
      AnalyticsService.error('nothing happened');
      AnalyticsService.setAdaptiveDimension(true);
      AnalyticsService.setTutorialDimension(true);
      AnalyticsService.ad(
        outcome: AdOutcome.shown,
        kind: AdKind.banner,
        placement: 'banner',
      );
    });
  });
}
