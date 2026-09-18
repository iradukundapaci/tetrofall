import 'booster_type.dart';

/// The four boosters a run is played with — one per slot (`boosters.md` §3).
class Loadout {
  const Loadout(this.boosters);

  /// In slot order: small, line, area, board. The order is what the roll
  /// screen and the bar both draw, left to right, and it is why neither of
  /// them needs to label a slot (§3.2).
  final List<BoosterType> boosters;

  BoosterType operator [](int index) => boosters[index];
  int get length => boosters.length;

  BoosterSlot slotAt(int index) => BoosterSlot.values[index];

  Loadout withAt(int index, BoosterType type) =>
      Loadout([...boosters]..[index] = type);

  /// The fixed loadout the first runs after the tutorial play with (§3.6).
  static const starterKit = Loadout([
    BoosterType.hammer,
    BoosterType.drill,
    BoosterType.lightning,
    BoosterType.earthquake,
  ]);

  String encode() => boosters.map((b) => b.name).join(',');

  /// Null on anything unrecognised — a booster dropped after the test, or a
  /// half-written key — so the caller rolls fresh instead of crashing (§3.8).
  static Loadout? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(',');
    if (parts.length != BoosterSlot.values.length) return null;
    final types = <BoosterType>[];
    for (var i = 0; i < parts.length; i++) {
      final type = BoosterType.byId(parts[i]);
      if (type == null || type.slot != BoosterSlot.values[i]) return null;
      types.add(type);
    }
    return Loadout(types);
  }
}
