import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/theme/tokens.dart';
import '../engine/booster_engine.dart';
import '../engine/game_engine.dart';
import '../tetrofall_game.dart';

/// The four HUD booster slots (§1.9) — a minimal functional version for
/// Phase 8. `gameplay.html`'s pixel-perfect bottom panel is a Phase 10
/// port; this just needs to actually work: tap a slot to arm it (pausing
/// gravity, not the rise), tap again to disarm, charge badge per slot.
class BoosterHud extends StatefulWidget {
  const BoosterHud({super.key, required this.game});

  final TetrofallGame game;

  @override
  State<BoosterHud> createState() => _BoosterHudState();
}

class _BoosterHudState extends State<BoosterHud> {
  static const _slots = [
    (BoosterType.hammer, Icons.gavel),
    (BoosterType.bomb, Icons.circle),
    (BoosterType.drill, Icons.vertical_align_bottom),
    (BoosterType.lightning, Icons.bolt),
  ];

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Charges/armed state can change from outside a tap on this widget
    // (a commit resolving, the debug "give charges" button) — keep the
    // badges and armed highlight live either way.
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.game.engine;
    // A flow widget, not a `Positioned` overlay (R4) — sized by the
    // enclosing `Column`, which is what lets the board above it claim
    // exactly the vertical space this panel doesn't need.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.spaceMd,
          vertical: Tokens.spaceSm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (final slot in _slots) _slotButton(engine, slot.$1, slot.$2)],
        ),
      ),
    );
  }

  Widget _slotButton(GameEngine engine, BoosterType type, IconData icon) {
    final charges = engine.boosterEngine.charges[type] ?? 0;
    final armed = engine.boosterEngine.armed == type;
    return GestureDetector(
      onTap: () => setState(() {
        if (armed) {
          engine.disarmBooster();
        } else {
          engine.armBooster(type);
        }
      }),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: armed
              ? Tokens.colorGold.withValues(alpha: 0.35)
              : Tokens.colorPanel,
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          border: Border.all(
            color: armed ? Tokens.colorGold : Tokens.colorPanelBorder,
            width: armed ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                icon,
                color: charges > 0 ? Tokens.colorText : Tokens.colorTextMuted,
              ),
            ),
            Positioned(
              right: 4,
              bottom: 2,
              child: Text(
                '$charges',
                style: const TextStyle(
                  color: Tokens.colorGold,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
