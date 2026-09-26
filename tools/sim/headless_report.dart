// ignore_for_file: avoid_print
// Plays the endless game headlessly with the demo bot at three skill levels,
// Director on and off, and prints how the runs compare. Used to tune the
// Director before an experiment, and to check that it helps beginners without
// changing what experts experience.
//
//   dart run tools/sim/headless_report.dart [--runs 500] [--seed 1] [--v1]
//
// `--v1` runs the rescue-only Director instead of the full one.

import 'dart:math';

import 'package:tetrofall/game/ai/demo_bot.dart';
import 'package:tetrofall/game/config/run_config.dart';
import 'package:tetrofall/game/engine/events.dart';
import 'package:tetrofall/game/engine/game_engine.dart';

const _step = 1 / 60;

/// A run that lasts this long is counted as having survived to the cap.
const _capSeconds = 20 * 60.0;

class _Bot {
  const _Bot(
    this.name,
    this.policy,
    this.blunderRate,
    this.skill,
    this.secondsPerPiece,
  );

  final String name;
  final BotPolicy policy;
  final double blunderRate;

  /// What the Director is told about this player.
  final double skill;

  /// How long the bot "thinks" before committing a piece. Without it the bot
  /// drops twenty pieces a second and every run is over in seconds, which
  /// tells nothing about play at a human's pace.
  final double secondsPerPiece;
}

const _bots = [
  _Bot('casual', BotPolicy.blunder, 0.30, 0.2, 2.5),
  _Bot('normal', BotPolicy.blunder, 0.10, 0.5, 1.8),
  _Bot('expert', BotPolicy.skilled, 0.0, 0.9, 1.2),
];

class _Result {
  _Result(this.seconds, this.lines, this.rescues, this.comebacks, this.gifts);

  final double seconds;
  final int lines;
  final int rescues;
  final int comebacks;
  final int gifts;
}

_Result _play(
  _Bot bot, {
  required bool director,
  required bool v2,
  required int seed,
}) {
  final config = director
      ? RunConfig.endless(
          EndlessProfile(
            skill: bot.skill,
            directorV2: v2,
            gentleFirstRuns: false,
          ),
          random: Random(seed + 7),
        )
      : RunConfig.plain;
  final engine = GameEngine(random: Random(seed), config: config);
  final player = DemoBot(
    policy: bot.policy,
    blunderRate: bot.blunderRate,
    random: Random(seed + 13),
  );

  var sinceSpawn = 0.0;
  engine.addEventListener((event) {
    if (event is PieceSpawnedEvent) {
      sinceSpawn = 0;
      final piece = engine.pieceController.piece;
      if (piece != null) player.onPieceSpawned(engine.grid, piece.type);
    }
  });
  engine.start(config: config);

  var t = 0.0;
  while (engine.phase != GamePhase.gameOver && t < _capSeconds) {
    if (sinceSpawn >= bot.secondsPerPiece) player.tick(engine);
    engine.tick(_step);
    t += _step;
    sinceSpawn += _step;
  }

  final stats = engine.director.stats;
  return _Result(
    engine.riseController.elapsed,
    engine.scoring.totalLines,
    stats.rescues,
    stats.comebacks,
    stats.giftRows,
  );
}

double _percentile(List<double> sorted, double p) =>
    sorted[((sorted.length - 1) * p).round()];

void _report(String label, List<_Result> results) {
  final secs = results.map((r) => r.seconds).toList()..sort();
  final lines = results.fold<int>(0, (a, r) => a + r.lines);
  final minutes = secs.fold<double>(0, (a, b) => a + b) / 60;
  final rescues = results.fold<int>(0, (a, r) => a + r.rescues);
  final comebacks = results.fold<int>(0, (a, r) => a + r.comebacks);
  final gifts = results.fold<int>(0, (a, r) => a + r.gifts);
  final n = results.length;
  String f(double v) => v.toStringAsFixed(1).padLeft(6);
  print(
    '${label.padRight(16)} median ${f(_percentile(secs, 0.5))}s  '
    'p10 ${f(_percentile(secs, 0.1))}s  p90 ${f(_percentile(secs, 0.9))}s  '
    'lines/min ${f(lines / minutes)}  rescues/run ${f(rescues / n)}  '
    'comebacks/run ${f(comebacks / n)}  gifts/run ${f(gifts / n)}',
  );
}

void main(List<String> args) {
  int option(String name, int fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? int.parse(args[i + 1]) : fallback;
  }

  final runs = option('runs', 100);
  final seed = option('seed', 1);
  final v2 = !args.contains('--v1');

  print(
    'Director ${v2 ? 'full' : 'rescue-only'}, $runs runs per row, seed $seed\n',
  );
  for (final bot in _bots) {
    final off = [
      for (var i = 0; i < runs; i++)
        _play(bot, director: false, v2: v2, seed: seed + i),
    ];
    final on = [
      for (var i = 0; i < runs; i++)
        _play(bot, director: true, v2: v2, seed: seed + i),
    ];
    _report('${bot.name} off', off);
    _report('${bot.name} on', on);
    print('');
  }
}
