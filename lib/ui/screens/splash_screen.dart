import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/storage_service.dart';
import '../theme/tokens.dart';
import '../widgets/logo_mark.dart';
import '../widgets/logo_wordmark.dart';
import '../widgets/progress_bar.dart';
import 'main_menu_screen.dart';

/// Boot screen 1 (game.md §P.2 / Phase 8) — 1:1 port of splash.html.
/// The block mark falls into place under gravity (ease-in), lands with a
/// squash, then the wordmark and loader reveal. The loader fills while
/// assets precache in the background; the whole stage fades out once
/// both the animation and the real load are done, handing off to the
/// main menu.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _dropDuration = Duration(milliseconds: 550);
  static const _squashDuration = Duration(milliseconds: 400);
  static const _revealDuration = Duration(milliseconds: 400);
  static const _loaderFillDuration = Duration(milliseconds: 1800);
  static const _fadeOutDuration = Duration(milliseconds: 600);

  late final AnimationController _dropController;
  late final AnimationController _squashController;

  bool _landed = false;
  bool _revealed = false;
  bool _loaderStarted = false;
  bool _fadingOut = false;

  Future<void> _assetsReady = Future.value();
  bool _assetsPrecacheStarted = false;

  @override
  void initState() {
    super.initState();
    _dropController = AnimationController(
      vsync: this,
      duration: _dropDuration,
    );
    _squashController = AnimationController(
      vsync: this,
      duration: _squashDuration,
    );
    _runSequence();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (which precacheImage needs) isn't available until after
    // initState, so the real preload future is wired up here instead.
    if (_assetsPrecacheStarted) return;
    _assetsPrecacheStarted = true;
    _assetsReady = _preloadAssets();
  }

  Future<void> _preloadAssets() async {
    await precacheImage(
      const AssetImage('assets/images/textures/bg_wood.png'),
      context,
    );
  }

  Future<void> _runSequence() async {
    // 1. Tetromino falls into place.
    await _dropController.forward();
    if (!mounted) return;

    // 2. Landing squash + this is what triggers the rest of the reveal.
    setState(() {
      _landed = true;
      _revealed = true;
    });
    unawaited(_squashController.forward());

    // 3. Loading bar fills.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _loaderStarted = true);

    // 4. Load finishes -> fade out -> hand off to the real main menu.
    await Future.wait([Future.delayed(_loaderFillDuration), _assetsReady]);
    if (!mounted) return;
    setState(() => _fadingOut = true);

    await Future.delayed(_fadeOutDuration);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => MainMenuScreen(storage: widget.storage)));
  }

  @override
  void dispose() {
    _dropController.dispose();
    _squashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: AnimatedOpacity(
        opacity: _fadingOut ? 0 : 1,
        duration: _fadeOutDuration,
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _SplashDust(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DroppingLogo(
                      dropController: _dropController,
                      squashController: _squashController,
                      landed: _landed,
                    ),
                    const SizedBox(height: Tokens.spaceMd),
                    AnimatedSlide(
                      offset: _revealed ? Offset.zero : const Offset(0, 0.08),
                      duration: _revealDuration,
                      curve: Curves.easeOut,
                      child: AnimatedOpacity(
                        opacity: _revealed ? 1 : 0,
                        duration: _revealDuration,
                        curve: Curves.easeOut,
                        child: const LogoWordmark(),
                      ),
                    ),
                    const SizedBox(height: Tokens.spaceXl),
                    AnimatedOpacity(
                      opacity: _revealed ? 1 : 0,
                      duration: const Duration(milliseconds: 350),
                      child: SizedBox(
                        width: 220,
                        child: Column(
                          children: [
                            AppProgressBar(
                              value: _loaderStarted ? 1 : 0,
                              animationDuration: _loaderFillDuration,
                              curve: const Cubic(0.3, 0.6, 0.3, 1),
                            ),
                            const SizedBox(height: Tokens.spaceSm),
                            const Text(
                              'LOADING…',
                              style: TextStyle(
                                fontFamily: Tokens.fontBody,
                                fontSize: Tokens.fontSizeSm,
                                fontWeight: FontWeight.bold,
                                color: Tokens.colorTextMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DroppingLogo extends StatelessWidget {
  const _DroppingLogo({
    required this.dropController,
    required this.squashController,
    required this.landed,
  });

  final AnimationController dropController;
  final AnimationController squashController;
  final bool landed;

  static final Animatable<double> _scaleY = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.7), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.1), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 1.1, end: 0.96), weight: 23),
    TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.0), weight: 22),
  ]);

  static final Animatable<double> _scaleX = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.18, end: 0.94), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 0.94, end: 1.03), weight: 23),
    TweenSequenceItem(tween: Tween(begin: 1.03, end: 1.0), weight: 22),
  ]);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([dropController, squashController]),
      builder: (context, child) {
        final shadowProgress = Curves.ease.transform(dropController.value);
        final easedDrop = const Cubic(
          0.55,
          0,
          0.85,
          0.15,
        ).transform(dropController.value);
        final dropOffset = (1 - easedDrop) * -260;
        final shadowScaleX = 0.3 + 0.7 * shadowProgress;
        final shadowOpacity = shadowProgress;

        final squashT = squashController.value;
        final scaleY = landed ? _scaleY.transform(squashT) : 1.0;
        final scaleX = landed ? _scaleX.transform(squashT) : 1.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, dropOffset),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
                child: const LogoMark(),
              ),
            ),
            const SizedBox(height: 6),
            Opacity(
              opacity: shadowOpacity,
              child: Transform.scale(
                scaleX: shadowScaleX,
                scaleY: 1,
                child: Container(
                  width: 96,
                  height: 14,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x73000000), Colors.transparent],
                      stops: [0, 0.75],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 14 upward-drifting gold dust particles, matching splash.html's
/// `.dust-particle` keyframes: fade in over the first 10% of travel,
/// hold, then fade out over the last 10%, drifting 820px upward with a
/// small randomized horizontal wobble.
class _SplashDust extends StatefulWidget {
  const _SplashDust();

  @override
  State<_SplashDust> createState() => _SplashDustState();
}

class _SplashDustState extends State<_SplashDust>
    with TickerProviderStateMixin {
  static const _count = 14;
  late final List<_DustSpec> _specs;
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    final random = math.Random();
    _specs = List.generate(
      _count,
      (_) => _DustSpec(
        left: random.nextDouble(),
        driftX: random.nextDouble() * 40 - 20,
        duration: Duration(
          milliseconds: 4000 + random.nextInt(4000),
        ),
        delay: Duration(milliseconds: random.nextInt(6000)),
      ),
    );
    _controllers = [
      for (final spec in _specs) AnimationController(vsync: this, duration: spec.duration),
    ];
    for (var i = 0; i < _controllers.length; i++) {
      Future.delayed(_specs[i].delay, () {
        if (mounted) _controllers[i].repeat();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (var i = 0; i < _count; i++)
              AnimatedBuilder(
                animation: _controllers[i],
                builder: (context, child) {
                  final t = _controllers[i].value;
                  final opacity = t < 0.1
                      ? t / 0.1 * 0.7
                      : t < 0.9
                      ? 0.7 - (t - 0.1) / 0.8 * 0.3
                      : 0.4 * (1 - (t - 0.9) / 0.1);
                  return Positioned(
                    left: _specs[i].left * constraints.maxWidth,
                    bottom: -20 + t * 820,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(_specs[i].driftX * t, 0),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Tokens.colorGold,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _DustSpec {
  const _DustSpec({
    required this.left,
    required this.driftX,
    required this.duration,
    required this.delay,
  });

  final double left;
  final double driftX;
  final Duration duration;
  final Duration delay;
}
