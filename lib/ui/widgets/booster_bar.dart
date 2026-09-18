import 'package:flutter/material.dart';

import '../../game/boosters/booster_run_state.dart';
import '../../models/theme_definition.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import 'booster_slot.dart';

/// The bottom row of the gameplay screen, directly under the board
/// (`boosters.md` §4.1).
///
/// It replaces the banner ad, which cost 50pt of play area on every phone on
/// every run for the lowest-value unit in the build; the boosters buy that
/// income back through rewarded video the player opts into.
///
/// The height is a fixed token for the same reason the HUD's is: the board's
/// vertical budget is computed before layout runs.
class BoosterBar extends StatelessWidget {
  const BoosterBar({
    super.key,
    required this.state,
    required this.theme,
    required this.onSlotTapped,
  });

  final BoosterRunState state;
  final ThemeDefinition theme;

  /// Called with the slot index. The bar itself never decides what a tap
  /// means — arming, firing and the refill offer are all the run's business.
  final ValueChanged<int> onSlotTapped;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final loadout = state.loadout;
        if (loadout == null) {
          return SizedBox(height: ui.px(Tokens.boosterBarHeight));
        }
        return SizedBox(
          height: ui.px(Tokens.boosterBarHeight),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < loadout.length; i++)
                BoosterSlotButton(
                  type: loadout[i],
                  state: state.stateAt(i),
                  charges: state.chargesAt(i),
                  aimProgress: state.armedIndex == i ? state.aimProgress : 0,
                  theme: theme,
                  onTap: () => onSlotTapped(i),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The first-use tip, and the aiming instruction under it (§4.8).
///
/// Sits above the bar and takes no height of its own — it floats over the
/// bottom of the board, so a tip can never push the board around mid-run.
class BoosterTipLine extends StatelessWidget {
  const BoosterTipLine({super.key, required this.state, required this.theme});

  final BoosterRunState state;
  final ThemeDefinition theme;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final text = state.tip ?? _armedHint;
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: text == null ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ui.spaceMd,
                vertical: ui.spaceXs,
              ),
              alignment: Alignment.center,
              child: Text(
                text ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Tokens.fontBody,
                  fontSize: ui.fontXs,
                  fontWeight: FontWeight.w600,
                  color: theme.text.withValues(alpha: 0.85),
                  shadows: const [
                    Shadow(color: Color(0xCC000000), blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? get _armedHint {
    final type = state.armedType;
    if (type == null) return null;
    return type.tip;
  }
}
