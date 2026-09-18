import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/ai/demo_bot.dart';
import '../../game/engine/events.dart';
import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/music_service.dart';
import '../../services/storage_service.dart';
import '../../services/economy.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/coin_balance_pill.dart';
import '../widgets/counter_pill.dart';
import '../widgets/icon_button.dart';
import '../widgets/primary_button.dart';
import 'gameplay_screen.dart';
import 'coin_vault_screen.dart';
import 'daily_reward_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'themes_screen.dart';

/// 1:1 port of main-menu.html — plus a live, self-playing game running
/// full-bleed behind the menu in place of main-menu.html's empty
/// `.menu-video-slot` (there's no gameplay clip to drop in, so the real
/// engine stands in for one). It's purely decorative: a separate
/// throwaway `TetrofallGame` that never touches saved best score or
/// settings, autoplaying itself and restarting whenever it tops out —
/// tuned to actively hunt for line clears so the shatter/cascade "juice"
/// (the whole point of the game) actually shows up on the menu instead
/// of just watching pieces stack.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({
    super.key,
    required this.storage,
    required this.ads,
    required this.economy,
  });

  final StorageService storage;
  final AdsService ads;
  final Economy economy;

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  /// Nullable (rather than the live-forever `late final` this started as)
  /// so the demo can be fully torn down while a real run is in progress:
  /// dropping the reference lets the GameWidget unmount, which makes Flame
  /// release the demo's component tree and stop ticking it in the
  /// background instead of burning memory/CPU behind the gameplay screen.
  TetrofallGame? _demoGame;
  Timer? _autoplayTimer;
  Timer? _restartTimer;
  DemoBot _bot = DemoBot();

  late final MusicService _music = MusicService(widget.storage);

  @override
  void initState() {
    super.initState();
    AnalyticsService.design('screen:menu');
    _startDemo();
    _music.play(MusicTrack.menu);
  }

  @override
  void dispose() {
    _stopDemo();
    super.dispose();
  }

  void _startDemo() {
    // Deliberately no `clearSkies`: the demo is decoration, and Flame ticks
    // it for as long as the menu is open. Handing it the balance would drain
    // paid-for ad-free time while nobody is playing.
    final game = TetrofallGame(
      storage: widget.storage,
      // The menu shows off whatever the player has equipped, so a theme
      // bought in the shop is on screen the moment they back out of it.
      theme: widget.economy.wallet.equippedTheme,
      feedbackEnabled: false,
    );
    _demoGame = game;
    _bot = DemoBot();
    game.engine.addEventListener(_onDemoEvent);
    _autoplayTimer = Timer.periodic(
      const Duration(milliseconds: 220),
      (_) => _tickAutoplay(),
    );
  }

  void _stopDemo() {
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    _restartTimer?.cancel();
    _restartTimer = null;
    _demoGame?.engine.removeEventListener(_onDemoEvent);
    _demoGame = null;
  }

  Future<void> _openGameplay() async {
    setState(_stopDemo);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameplayScreen(
          storage: widget.storage,
          ads: widget.ads,
          economy: widget.economy,
          startTutorial: !widget.storage.tutorialSeen,
        ),
      ),
    );
    if (mounted) {
      setState(_startDemo);
      _music.play(MusicTrack.menu);
    }
  }

  /// Opens a menu destination the same way [_openGameplay] does: the demo is
  /// stopped underneath and rebuilt on return, which is also what puts a
  /// newly equipped theme on the menu board straight away.
  Future<void> _openScreen(WidgetBuilder builder) async {
    setState(_stopDemo);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
    if (mounted) setState(_startDemo);
  }

  Widget _navRow(UiScale ui) {
    Widget item(
      String label,
      Widget icon,
      WidgetBuilder builder, {
      bool dot = false,
    }) => Padding(
      padding: EdgeInsets.symmetric(horizontal: ui.spaceMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Badge(
            isLabelVisible: dot,
            backgroundColor: Tokens.colorRed,
            smallSize: ui.px(10),
            child: CircleIconButton(
              tooltip: label,
              icon: icon,
              onPressed: () => _openScreen(builder),
            ),
          ),
          SizedBox(height: ui.spaceXs),
          Text(
            label,
            style: TextStyle(
              fontFamily: Tokens.fontBody,
              fontSize: ui.fontXs,
              fontWeight: FontWeight.w700,
              color: Tokens.colorTextMuted,
            ),
          ),
        ],
      ),
    );
    final economy = widget.economy;
    return AnimatedBuilder(
      animation: economy.daily,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          item(
            'Daily',
            Icon(Icons.card_giftcard, color: Tokens.colorText, size: ui.iconMd),
            (_) => DailyRewardScreen(ads: widget.ads, economy: economy),
            // The zero-ad income has to be found to be collected.
            dot: economy.daily.hasSomethingToClaim,
          ),
          item(
            'Shop',
            Icon(
              Icons.storefront_outlined,
              color: Tokens.colorText,
              size: ui.iconMd,
            ),
            (_) => ShopScreen(ads: widget.ads, economy: economy),
          ),
          item(
            'Themes',
            SvgPicture.asset(
              AppIcons.palette,
              width: ui.iconMd,
              height: ui.iconMd,
              colorFilter: const ColorFilter.mode(
                Tokens.colorText,
                BlendMode.srcIn,
              ),
            ),
            (_) => ThemesScreen(ads: widget.ads, economy: economy),
          ),
        ],
      ),
    );
  }

  void _onDemoEvent(GameEvent event) {
    final game = _demoGame;
    if (game == null) return;
    if (event is PieceSpawnedEvent) {
      final piece = game.engine.pieceController.piece;
      if (piece != null) {
        _bot.onPieceSpawned(game.engine.grid, piece.type);
      }
    } else if (event is GameOverEvent) {
      _restartTimer = Timer(const Duration(seconds: 2), () {
        _demoGame?.restart();
      });
    }
  }

  void _tickAutoplay() {
    final engine = _demoGame?.engine;
    if (engine != null) _bot.tick(engine);
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: _demoGame == null
                  ? const ColoredBox(color: Tokens.colorBg)
                  : ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                      child: GameWidget(game: _demoGame!),
                    ),
            ),
          ),
          const Positioned.fill(child: _MenuScrim()),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                ui.spaceLg,
                ui.spaceLg,
                ui.spaceLg,
                ui.spaceXl,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CounterPill(
                        label: 'BEST',
                        value: _formatScore(widget.storage.bestScore),
                        icon: SvgPicture.asset(
                          AppIcons.trophy,
                          colorFilter: const ColorFilter.mode(
                            Tokens.colorGold,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const Spacer(),
                      CoinBalancePill(
                        wallet: widget.economy.wallet,
                        onTap: () => _openScreen(
                          (_) => CoinVaultScreen(
                            ads: widget.ads,
                            wallet: widget.economy.wallet,
                          ),
                        ),
                      ),
                      SizedBox(width: ui.spaceSm),
                      CircleIconButton(
                        tooltip: 'Settings',
                        icon: SvgPicture.asset(
                          AppIcons.settings,
                          width: ui.iconMd,
                          height: ui.iconMd,
                          colorFilter: const ColorFilter.mode(
                            Tokens.colorText,
                            BlendMode.srcIn,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SettingsScreen(
                                  storage: widget.storage,
                                  ads: widget.ads,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: ui.px(Tokens.menuPlayWidth),
                            child: PrimaryButton(
                              label: 'PLAY',
                              fontSize: ui.fontMd,
                              onPressed: _openGameplay,
                            ),
                          ),
                          SizedBox(height: ui.spaceLg),
                          _navRow(ui),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Darkens the live demo board so the topbar and buttons on top of it
/// stay readable, lighter in the middle so the board is still visible.
class _MenuScrim extends StatelessWidget {
  const _MenuScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.black.withValues(alpha: 0.32),
            Colors.black.withValues(alpha: 0.65),
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }
}

String _formatScore(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
