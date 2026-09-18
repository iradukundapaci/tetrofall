import '../../ui/theme/app_icons.dart';

/// How much of the board a booster touches. Slots are what the loadout rolls
/// against: one booster per slot, three candidates each (`boosters.md` §2).
enum BoosterSlot { small, line, area, board }

/// What a booster does to blocks. Shapes the pools and the effect language —
/// and never reaches the UI (§2). The player only ever sees icon and name.
enum BoosterClass { breaker, mover, builder }

/// What the player has to give the booster before it can fire.
enum BoosterInput {
  aimCell,
  aimRow,
  aimColumn,
  aimRowSwipe,
  swipeDirection,
  instant,
}

enum BoosterType {
  hammer(BoosterSlot.small, BoosterClass.breaker, BoosterInput.aimCell),
  bomb(BoosterSlot.small, BoosterClass.breaker, BoosterInput.aimCell),
  patch(BoosterSlot.small, BoosterClass.builder, BoosterInput.aimCell),
  drill(BoosterSlot.line, BoosterClass.breaker, BoosterInput.aimRow),
  slide(BoosterSlot.line, BoosterClass.mover, BoosterInput.aimRowSwipe),
  pillar(BoosterSlot.line, BoosterClass.builder, BoosterInput.aimColumn),
  sweep(BoosterSlot.area, BoosterClass.breaker, BoosterInput.instant),
  lightning(BoosterSlot.area, BoosterClass.builder, BoosterInput.instant),
  mortar(BoosterSlot.area, BoosterClass.builder, BoosterInput.instant),
  earthquake(BoosterSlot.board, BoosterClass.mover, BoosterInput.instant),
  tilt(BoosterSlot.board, BoosterClass.mover, BoosterInput.swipeDirection),
  wildfire(BoosterSlot.board, BoosterClass.breaker, BoosterInput.aimCell);

  const BoosterType(this.slot, this.boosterClass, this.input);

  final BoosterSlot slot;
  final BoosterClass boosterClass;
  final BoosterInput input;

  bool get isInstant =>
      input == BoosterInput.instant || input == BoosterInput.swipeDirection;

  /// The only string the player ever sees for a booster (§3.2, §9.4).
  String get displayName => switch (this) {
    BoosterType.hammer => 'Hammer',
    BoosterType.bomb => 'Bomb',
    BoosterType.patch => 'Patch',
    BoosterType.drill => 'Drill',
    BoosterType.slide => 'Slide',
    BoosterType.pillar => 'Pillar',
    BoosterType.sweep => 'Sweep',
    BoosterType.lightning => 'Lightning',
    BoosterType.mortar => 'Mortar',
    BoosterType.earthquake => 'Earthquake',
    BoosterType.tilt => 'Tilt',
    BoosterType.wildfire => 'Wildfire',
  };

  /// One line, shown the first time this booster is armed or fired (§4.8).
  String get tip => switch (this) {
    BoosterType.hammer => 'Tap a block to smash it',
    BoosterType.bomb => 'Tap to blast everything around that spot',
    BoosterType.patch => 'Tap an empty gap to plug it',
    BoosterType.drill => 'Tap a row to bore it out',
    BoosterType.slide => 'Hold a row, swipe to shift it',
    BoosterType.pillar => 'Tap a column to fill its holes',
    BoosterType.sweep => 'Clears the top of your stack',
    BoosterType.lightning => 'Fills the rows closest to done',
    BoosterType.mortar => 'Seals holes under overhangs',
    BoosterType.earthquake => 'Everything falls into place',
    BoosterType.tilt => 'Swipe left or right to tilt the board',
    BoosterType.wildfire => 'Start the fire in a big pile',
  };

  /// Lucide glyph, one per booster (§9.6).
  String get icon => switch (this) {
    BoosterType.hammer => AppIcons.hammer,
    BoosterType.bomb => AppIcons.bomb,
    BoosterType.patch => AppIcons.patch,
    BoosterType.drill => AppIcons.drill,
    BoosterType.slide => AppIcons.slide,
    BoosterType.pillar => AppIcons.pillar,
    BoosterType.sweep => AppIcons.sweep,
    BoosterType.lightning => AppIcons.lightning,
    BoosterType.mortar => AppIcons.mortar,
    BoosterType.earthquake => AppIcons.earthquake,
    BoosterType.tilt => AppIcons.tilt,
    BoosterType.wildfire => AppIcons.wildfire,
  };

  static BoosterType? byId(String id) {
    for (final t in BoosterType.values) {
      if (t.name == id) return t;
    }
    return null;
  }

  /// The three candidates a slot can roll (§2). Order is the roster's.
  static List<BoosterType> pool(BoosterSlot slot) => [
    for (final t in BoosterType.values)
      if (t.slot == slot) t,
  ];
}
