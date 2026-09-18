import 'dart:math';

import 'booster_type.dart';
import 'loadout.dart';

/// Picks a run's four boosters (`boosters.md` §3.3).
///
/// **The randomness is deliberately its own.** The engine's seeded source
/// deals pieces and rising rows; if the roll drew from it, a re-spin would
/// shift every piece that followed and a seed would stop reproducing a run.
/// It is also the prerequisite for a fair Daily Challenge later (§10.3).
class LoadoutRoller {
  LoadoutRoller({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Weights are equal for the test build — every booster needs data before
  /// rarity tiers mean anything (§3.3 rule 2).
  Loadout roll() => Loadout([
    for (final slot in BoosterSlot.values) _pick(slot, exclude: null),
  ]);

  /// One slot, re-rolled. Never lands on what the slot already shows, which
  /// is the whole point of spending a re-spin on it (§3.3 rule 3).
  BoosterType respin(BoosterSlot slot, BoosterType current) =>
      _pick(slot, exclude: current);

  BoosterType _pick(BoosterSlot slot, {required BoosterType? exclude}) {
    final pool = [
      for (final t in BoosterType.pool(slot))
        if (t != exclude) t,
    ];
    return pool[_random.nextInt(pool.length)];
  }
}
