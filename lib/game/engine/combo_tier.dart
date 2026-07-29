/// Blocks-destroyed banner tiers (§1.7). Thresholds are counted across a
/// single resolve — every chain link's destroyed blocks included, not just
/// the triggering clear.
enum ComboTier { good, awesome, incredible, unbelievable }

extension ComboTierInfo on ComboTier {
  // Scaled for the 18-column board (roughly ½ / 2 / 5 / 10 rows' worth of
  // blocks, same proportions the 10-column thresholds had).
  int get threshold => switch (this) {
    ComboTier.good => 9,
    ComboTier.awesome => 36,
    ComboTier.incredible => 90,
    ComboTier.unbelievable => 180,
  };

  String get label => switch (this) {
    ComboTier.good => 'GOOD!',
    ComboTier.awesome => 'AWESOME!',
    ComboTier.incredible => 'INCREDIBLE!',
    ComboTier.unbelievable => 'UNBELIEVABLE!',
  };
}
