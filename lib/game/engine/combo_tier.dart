/// Blocks-destroyed banner tiers (§1.7). Thresholds are counted across a
/// single resolve — every chain link's destroyed blocks included, not just
/// the triggering clear.
enum ComboTier { good, awesome, incredible, unbelievable }

extension ComboTierInfo on ComboTier {
  int get threshold => switch (this) {
    ComboTier.good => 5,
    ComboTier.awesome => 20,
    ComboTier.incredible => 50,
    ComboTier.unbelievable => 100,
  };

  String get label => switch (this) {
    ComboTier.good => 'GOOD!',
    ComboTier.awesome => 'AWESOME!',
    ComboTier.incredible => 'INCREDIBLE!',
    ComboTier.unbelievable => 'UNBELIEVABLE!',
  };
}
