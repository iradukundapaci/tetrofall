enum ComboTier { good, awesome, incredible, unbelievable }

extension ComboTierInfo on ComboTier {
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
