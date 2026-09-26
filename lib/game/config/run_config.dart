import 'dart:math' as math;

import '../director/adaptive_director.dart';
import '../director/director.dart';
import '../director/skill_model.dart';
import 'difficulty.dart';

/// How the floor rises: the [Difficulty] curve, optionally with a gentler
/// start.
class RiseConfig {
  const RiseConfig({this.introScale = 1.0, this.introFadeSeconds = 90});

  static const curve = RiseConfig();

  /// Multiplies the rise interval at the start of a run, fading back to 1.0
  /// over [introFadeSeconds].
  final double introScale;
  final double introFadeSeconds;

  double scaleAt(double elapsed) {
    if (introScale == 1.0) return 1.0;
    final t = (elapsed / introFadeSeconds).clamp(0.0, 1.0);
    return 1.0 + (introScale - 1.0) * (1.0 - t);
  }
}

/// What the game knows about the player. Plain data, so the engine layer
/// never imports storage.
class EndlessProfile {
  const EndlessProfile({
    this.bestScore = 0,
    this.skill = SkillModel.initial,
    this.runCount = 0,
    this.daysSinceInstall = 0,
    this.adaptiveStartOptIn = false,
    this.directorEnabled = true,
    this.directorV2 = true,
    this.gentleFirstRuns = true,
  });

  final int bestScore;
  final double skill;

  /// Endless runs started before this one.
  final int runCount;
  final int daysSinceInstall;

  /// The Settings toggle that starts a returning player partway up the curve.
  final bool adaptiveStartOptIn;

  final bool directorEnabled;
  final bool directorV2;
  final bool gentleFirstRuns;
}

/// Everything that distinguishes one run from another; the engine is handed
/// one and never learns which mode it is playing.
class RunConfig {
  const RunConfig({
    this.rise = RiseConfig.curve,
    this.director,
    this.initialElapsed = Duration.zero,
  });

  /// No adaptive systems.
  static const plain = RunConfig();

  final RiseConfig rise;

  /// Null means [NullDirector].
  final Director? director;

  /// Where the difficulty clock starts.
  final Duration initialElapsed;

  /// Adaptive start stays off for this long after install: session two must
  /// never be harder than session one.
  static const freshStartDays = 7;

  /// How many of a player's first runs get a gentler opening.
  static const gentleRuns = 3;

  /// Stretches the opening 22 s rise interval to about 30 s.
  static const _gentleIntroScale = 30 / 22;

  factory RunConfig.endless(EndlessProfile profile, {math.Random? random}) {
    final gentle = profile.gentleFirstRuns && profile.runCount < gentleRuns;
    final useAdaptiveStart =
        profile.adaptiveStartOptIn &&
        profile.daysSinceInstall >= freshStartDays;

    return RunConfig(
      rise: gentle
          ? const RiseConfig(introScale: _gentleIntroScale)
          : RiseConfig.curve,
      director: profile.directorEnabled
          ? AdaptiveDirector(
              skill: profile.skill,
              pacing: profile.directorV2,
              random: random,
            )
          : null,
      initialElapsed: useAdaptiveStart
          ? Difficulty.adaptiveStartElapsed(profile.bestScore)
          : Duration.zero,
    );
  }
}
