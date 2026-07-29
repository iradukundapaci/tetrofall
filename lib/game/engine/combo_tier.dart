/// Blocks-destroyed banner tiers (§1.7). Thresholds are counted across a
/// single resolve — every chain link's destroyed blocks included, not just
/// the triggering clear.
enum ComboTier { good, awesome, incredible, unbelievable }

extension ComboTierInfo on ComboTier {
  // Scaled for the 21-column board (roughly ½ / 2 / 5 / 10 rows' worth of
  // blocks, same proportions the 10-column thresholds had).
  int get threshold => switch (this) {
    ComboTier.good => 11,
    ComboTier.awesome => 42,
    ComboTier.incredible => 105,
    ComboTier.unbelievable => 210,
  };

  String get label => switch (this) {
    ComboTier.good => 'GOOD!',
    ComboTier.awesome => 'AWESOME!',
    ComboTier.incredible => 'INCREDIBLE!',
    ComboTier.unbelievable => 'UNBELIEVABLE!',
  };
}
