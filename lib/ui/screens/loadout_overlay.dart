import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/boosters/booster_type.dart';
import '../../game/boosters/loadout.dart';
import '../../game/boosters/loadout_roller.dart';
import '../../game/config/booster_tuning.dart';
import '../../game/config/motion.dart';
import '../../models/theme_definition.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../../game/config/economy_tuning.dart';
import '../../services/wallet_service.dart';
import '../widgets/booster_coin_sheet.dart';
import '../widgets/modal_overlay.dart';
import '../widgets/panel.dart';
import '../widgets/primary_button.dart';

/// The pre-run roll (`boosters.md` §3).
///
/// Four wooden reels spin and stop one by one over the board the player is
/// about to play in, which is why this is an overlay on the gameplay screen
/// rather than a screen of its own: `engine.start()` is called only when it
/// closes.
class LoadoutOverlay extends StatefulWidget {
  const LoadoutOverlay({
    super.key,
    required this.theme,
    required this.previousLoadout,
    required this.useStarterKit,
    required this.wallet,
    required this.onEarnCoins,
    required this.onStart,
  });

  final ThemeDefinition theme;

  /// Offered as "Same boosters" on a replay (§3.7). Null on a fresh run.
  final Loadout? previousLoadout;

  /// The first runs after the tutorial play a fixed loadout, so the four
  /// simplest boosters are the ones a new player meets (§3.6).
  final bool useStarterKit;

  /// Coins pay for re-spins past the free one (§3.5). Watched so the offer
  /// line and the sheet stay honest about what the player can afford.
  final WalletService wallet;

  /// Opens the earn screen. Reached only from an empty wallet, so a re-spin
  /// the player cannot afford is still never a dead end.
  final VoidCallback onEarnCoins;

  final ValueChanged<Loadout> onStart;

  @override
  State<LoadoutOverlay> createState() => _LoadoutOverlayState();
}

class _LoadoutOverlayState extends State<LoadoutOverlay>
    with TickerProviderStateMixin {
  final LoadoutRoller _roller = LoadoutRoller();

  late Loadout _loadout;

  /// Which reels have come to rest. The result is decided before the
  /// animation starts; the animation only reveals it (§3.4).
  late List<bool> _landed;

  int _respins = BoosterTuning.freeRespinsPerRun;

  /// Bought re-spins left this run. Still capped even though they are paid
  /// for: price sets the pace, but the cap is what keeps a rich player from
  /// rolling until the board is a sandbox.
  int _paidRespins = BoosterTuning.adRespinsPerRun;

  int? _pendingPaidSlot;
  bool _spinning = false;

  bool get _isReplay => widget.previousLoadout != null;

  @override
  void initState() {
    super.initState();
    if (_isReplay) {
      // A replay opens with the previous loadout already in the reels, no
      // spin, and a fresh free re-spin behind "Spin" (§3.7).
      _loadout = widget.previousLoadout!;
      _landed = List.filled(_loadout.length, true);
    } else {
      _loadout = widget.useStarterKit ? Loadout.starterKit : _roller.roll();
      _landed = List.filled(_loadout.length, false);
      _runSpin();
    }
  }

  void _runSpin() {
    _spinning = true;
    for (var i = 0; i < _loadout.length; i++) {
      final delay = Motion.boosterReelSpin + Motion.boosterReelStagger * i;
      Future.delayed(delay, () {
        if (!mounted) return;
        setState(() {
          _landed[i] = true;
          if (_landed.every((l) => l)) _spinning = false;
        });
      });
    }
  }

  /// Tapping anywhere during the spin stops every reel on the result it had
  /// already been given. The roll must never feel like a gate in front of
  /// "one more run" (§3.4).
  void _revealAll() {
    if (!_spinning) return;
    setState(() {
      _landed = List.filled(_loadout.length, true);
      _spinning = false;
    });
  }

  void _tapReel(int index) {
    if (_spinning || widget.useStarterKit || _isReplay) return;
    if (_respins > 0) {
      setState(() {
        _respins--;
        _respinSlot(index);
      });
      return;
    }
    if (_canSellRespin) setState(() => _pendingPaidSlot = index);
  }

  bool get _canSellRespin =>
      BoosterTuning.tokenRespinEnabled && _paidRespins > 0;

  void _respinSlot(int index) {
    final slot = _loadout.slotAt(index);
    _loadout = _loadout.withAt(index, _roller.respin(slot, _loadout[index]));
    _landed[index] = false;
    Future.delayed(Motion.boosterRespinSpin, () {
      if (!mounted) return;
      setState(() => _landed[index] = true);
    });
  }

  Future<void> _buyRespin() async {
    final index = _pendingPaidSlot;
    if (index == null) return;
    if (!await widget.wallet.trySpend(EconomyTuning.respinPrice)) return;
    if (!mounted) return;
    setState(() {
      _paidRespins--;
      _pendingPaidSlot = null;
      _respinSlot(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final pending = _pendingPaidSlot;
    if (pending != null) {
      return BoosterCoinSheet(
        title: 'Re-spin the ${_slotLabel(_loadout.slotAt(pending))} slot?',
        message:
            'This slot rolls again. '
            '$_paidRespins left before this run.',
        price: EconomyTuning.respinPrice,
        balance: widget.wallet.coins,
        onSpend: _buyRespin,
        onEarn: widget.onEarnCoins,
        onDecline: () => setState(() => _pendingPaidSlot = null),
      );
    }

    return Positioned.fill(
      child: GestureDetector(
        onTap: _revealAll,
        behavior: HitTestBehavior.opaque,
        child: ModalOverlayBody(
          child: AppPanel(
            padding: EdgeInsets.all(ui.spaceMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.useStarterKit ? 'STARTER KIT' : 'YOUR BOOSTERS',
                  style: TextStyle(
                    fontFamily: Tokens.fontDisplay,
                    fontSize: ui.fontLg,
                    fontWeight: FontWeight.w800,
                    color: Tokens.colorText,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: ui.spaceMd),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _loadout.length; i++)
                      Expanded(
                        child: _Reel(
                          type: _loadout[i],
                          landed: _landed[i],
                          theme: widget.theme,
                          onTap: () => _tapReel(i),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: ui.spaceMd),
                _respinLine(ui),
                SizedBox(height: ui.spaceMd),
                if (_isReplay) ...[
                  PrimaryButton(
                    label: 'Same boosters',
                    onPressed: () => widget.onStart(_loadout),
                  ),
                  SizedBox(height: ui.spaceSm),
                  SecondaryButton(
                    label: 'Spin',
                    onPressed: () => setState(() {
                      _loadout = _roller.roll();
                      _landed = List.filled(_loadout.length, false);
                      _respins = BoosterTuning.freeRespinsPerRun;
                      _runSpin();
                    }),
                  ),
                ] else
                  PrimaryButton(
                    label: 'START',
                    onPressed: _spinning
                        ? null
                        : () => widget.onStart(_loadout),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The line under the reels is the whole re-spin state machine, and it only
  /// ever shows one offer (§3.5).
  Widget _respinLine(UiScale ui) {
    if (widget.useStarterKit) {
      return _lineText(
        ui,
        'Fixed loadout — rolls start at run ${BoosterTuning.starterKitRuns + 1}',
        muted: true,
      );
    }
    if (_isReplay) return SizedBox(height: ui.fontSm);
    if (_respins > 0) {
      return _lineText(ui, '↻ Tap a booster to re-spin ($_respins left)');
    }
    if (_canSellRespin) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            AppIcons.coin,
            width: ui.iconSm,
            height: ui.iconSm,
            colorFilter: ColorFilter.mode(widget.theme.accent, BlendMode.srcIn),
          ),
          SizedBox(width: ui.spaceXs),
          Flexible(
            child: Text(
              '${EconomyTuning.respinPrice} to re-spin '
              '($_paidRespins left)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Tokens.fontBody,
                fontSize: ui.fontSm,
                fontWeight: FontWeight.w700,
                color: widget.theme.accent,
              ),
            ),
          ),
        ],
      );
    }
    return _lineText(ui, 'No re-spins left', muted: true);
  }

  Widget _lineText(UiScale ui, String text, {bool muted = false}) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontFamily: Tokens.fontBody,
      fontSize: ui.fontSm,
      color: muted
          ? Tokens.colorTextMuted.withValues(alpha: 0.45)
          : Tokens.colorTextMuted,
    ),
  );

  static String _slotLabel(BoosterSlot slot) => switch (slot) {
    BoosterSlot.small => 'Small',
    BoosterSlot.line => 'Line',
    BoosterSlot.area => 'Area',
    BoosterSlot.board => 'Board',
  };
}

/// One reel window: a recessed wooden drum with icons rolling over it, and
/// the booster's name underneath. Nothing else — no slot label, no class
/// mark (§9.4).
class _Reel extends StatefulWidget {
  const _Reel({
    required this.type,
    required this.landed,
    required this.theme,
    required this.onTap,
  });

  final BoosterType type;
  final bool landed;
  final ThemeDefinition theme;
  final VoidCallback onTap;

  @override
  State<_Reel> createState() => _ReelState();
}

class _ReelState extends State<_Reel> with TickerProviderStateMixin {
  /// One second per cycle, read as [_reelIconsPerSecond] icons of travel —
  /// so the drum scrolls at the speed §3.4 asks for without needing a second
  /// clock.
  late final AnimationController _scroll = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  /// The stop flash: a gold rim for 180ms as the drum settles (§3.4).
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.landed) _scroll.repeat();
  }

  @override
  void didUpdateWidget(_Reel old) {
    super.didUpdateWidget(old);
    if (widget.landed && !old.landed) {
      _scroll.stop();
      _flash.forward(from: 0);
    } else if (!widget.landed && old.landed) {
      _scroll.repeat();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final window = ui.px(56);
    final glyph = ui.px(26);

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: ui.px(3)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_scroll, _flash]),
              builder: (context, _) => Container(
                height: window,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [widget.theme.frameDark, widget.theme.boardBg],
                  ),
                  borderRadius: BorderRadius.circular(ui.radiusSm),
                  border: Border.all(
                    color: Color.lerp(
                      widget.theme.boosterRim.withValues(alpha: 0.35),
                      widget.theme.accent,
                      _flash.isAnimating ? 1 - _flash.value : 0,
                    )!,
                    width: ui.px(1.5),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: widget.landed
                    ? Center(child: _glyph(widget.type, glyph, 1))
                    : _drum(glyph, window),
              ),
            ),
            SizedBox(height: ui.spaceXs),
            Text(
              widget.landed ? widget.type.displayName : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Tokens.fontDisplay,
                fontSize: ui.font(11),
                fontWeight: FontWeight.w700,
                color: widget.theme.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Icons streaming downward, with the top and bottom fading into the panel
  /// so they appear to roll over a drum.
  Widget _drum(double glyph, double window) {
    final pool = BoosterType.pool(widget.type.slot);
    final travelled = _scroll.value * _reelIconsPerSecond;
    final offset = (travelled % 1) * window;
    final base = travelled.floor();

    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0, 0.2, 0.8, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // One row above the window and one below it, so the strip is never
          // seen to end.
          for (var i = -1; i < 2; i++)
            Positioned(
              left: 0,
              right: 0,
              top: (i * window) + offset + (window - glyph) / 2,
              child: Center(
                child: _glyph(pool[(base - i) % pool.length], glyph, 0.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _glyph(BoosterType type, double size, double alpha) =>
      SvgPicture.asset(
        type.icon,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(
          alpha >= 1
              ? widget.theme.boosterGlyph
              : widget.theme.boosterGlyphMuted.withValues(alpha: alpha),
          BlendMode.srcIn,
        ),
      );
}

/// The reel's scroll speed (§3.4), kept next to the drum it drives so the
/// two can never drift apart.
const _reelIconsPerSecond = 14.0;
